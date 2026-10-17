-- MCP de Lawang · el conector, para TODO el equipo activo: fuera el permiso por persona (17-oct-2026, sesión mcp-ventana).
-- Decisión del owner, 17-oct 12:15: «activa el mcp a todos. Quita lo de dar permiso porque se tienen que loguear, es redundante».
-- Encargo: encargos/20261015_erp_mcp.md (Decisiones, 17-oct). Va DESPUÉS de 20261017015111, 20261017015135 y 20261017015203.
--
-- QUÉ CAMBIA (solo construye: create or replace de 5 funciones que ya existen y un revoke; no crea tablas ni toca filas):
--   · public.ia_conexion_autoriza  ya no devuelve 'sin_permiso': conecta quien tenga sesión con contraseña de hace ≤ 2 min, IA
--                                  encendida, usuario ACTIVO de public.usuarios y sin bloqueo, 2.º factor si lo tiene, cliente
--                                  activo y menos de max_conexiones vivas. Todo eso sigue igual.
--   · privado.ia_conexion_motivo   ya no corta con 'permiso'. Siguen: revocada, caducada, sin_aviso, apagado, cliente,
--                                  usuario_inactivo (baja o bloqueo) y contrasena (cambió contraseña, correo, bloqueo, baja o 2FA).
--   · public.ia_peticion_ver       en vez de «sin_permiso», «usuario_inactivo» (baja o bloqueo), la misma puerta que autoriza:
--                                  la pantalla de «Conectar» no dice «puedes» a quien no podrá.
--   · public.ia_mis_conexiones     `permiso` pasa a significar «puede conectar» (activo y sin bloqueo, de privado.ia_auth_usuario,
--                                  la misma regla que las dos de arriba): así la web de hoy (aviso-ia.js, ia-conexiones.js) y la
--                                  nueva funcionan las dos, en cualquier orden de publicación.
--   · public.ia_ajustes_ver        `usuarios` sigue siendo el equipo activo con sus consultas de hoy; `permiso` va a true para la
--                                  web anterior, que deja de leerlo en esta misma tanda (ajustes-ia.js sin «Dar permiso»).
--   · revoke execute on public.ia_permiso_guarda from authenticated: se queda sin llamador (Ajustes › IA ya no tiene el
--                                  interruptor por persona); reducir la exposición (CLAUDE.md, §1.ter). Su dueño la conserva.
--
-- QUÉ NO CAMBIA: la tabla public.ia_permisos se queda con sus filas (no se borra ni se actualiza nada: es el histórico de quién
-- tuvo permiso). Cada herramienta sigue mirando el permiso del ROL de la persona (public.puede('<módulo>') y los accesos de
-- gastos y bancos) dentro de privado.mcp_<herramienta>: el asistente ve solo lo que esa persona ve en la intranet. El portal de
-- clientes no entra: sus usuarios no tienen fila activa en public.usuarios (ia_auth_usuario → activo false).
--
-- Dueño y permisos: CREATE OR REPLACE conserva dueño (ia_puente_rol) y EXECUTE (authenticated en las 4 públicas); postgres puede
-- reemplazarlas porque es miembro de ia_puente_rol (20261016073011). El cuerpo es el de la viva del 17-oct (pg_get_functiondef,
-- md5 en la vuelta atrás) con SOLO lo de arriba quitado o cambiado; la comprobación del final para si alguna sigue leyendo ia_permisos.
-- Prueba: supabase/pruebas/mcp_f1_p1_base.sql (C2, I3), mcp_f1_p4_ajustes.sql (C7, E, F4, G1, G2) y mcp_f1_p6_aviso_conexion.sql.
-- VUELTA ATRÁS (no destruye nada): supabase/reversion_mcp_todos/vuelta_atras.sql — vuelve a dejar las 5 con el texto vivo del 17-oct
-- (y lo comprueba por md5) y devuelve el EXECUTE de ia_permiso_guarda a authenticated. Con ella, solo vuelve a poder conectar
-- quien tenga fila viva en ia_permisos (hoy, el owner); las conexiones de los demás se cortan en su siguiente uso ('permiso').
begin;
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION privado.ia_conexion_motivo(p_conexion uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.ia_conexiones; a public.ia_ajustes; u jsonb; h integer;
begin
  select * into c from public.ia_conexiones where id = p_conexion;
  if c.id is null then return 'sin_conexion'; end if;
  if c.revocada_en is not null then return 'revocada'; end if;
  if c.expira_en <= now() then return 'caducada'; end if;
  if c.avisada_en is null then
    -- sin la regla de la clave (una redefinición futura que la pierda) se corta: sin tope no hay aviso que esperar (Seguridad, 2.ª vuelta)
    select r.tope_horas into h from public._correo_cola_regla('aviso_ia_conexion') r;
    if h is null or c.creada_en < now() - make_interval(hours => h) then
      perform privado.ia_revoca(c.id, 'sin_aviso'); return 'sin_aviso';
    end if;
  end if;
  select * into a from public.ia_ajustes where id;
  if not coalesce(a.encendido, false) then return 'apagado'; end if;
  if not exists (select 1 from public.ia_clientes k where k.id = c.cliente_id and k.activo) then
    perform privado.ia_revoca(c.id, 'cliente'); return 'cliente';
  end if;
  u := privado.ia_auth_usuario(c.usuario_id);
  if u is null or not coalesce((u ->> 'activo')::boolean, false) or coalesce((u ->> 'baneado')::boolean, true) then
    perform privado.ia_revoca(c.id, 'usuario_inactivo'); return 'usuario_inactivo';
  end if;
  if (u ->> 'huella') is distinct from c.huella then
    perform privado.ia_revoca(c.id, 'contrasena'); return 'contrasena';
  end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.ia_conexion_autoriza(p_peticion text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  cl jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  v_uid uuid := public.uid_sesion(); a public.ia_ajustes; p public.ia_peticiones; u jsonb; v_ts numeric;
  v_con uuid; v_cod text; v_vivas integer;
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  if nullif(current_setting('axw.ia_conexion', true), '') is not null then
    raise exception 'No disponible' using errcode = '42501';
  end if;
  -- Frescura por el método `password` del amr (no por iat: un refresh lo renueva sin contraseña; #395).
  select max((x ->> 'timestamp')::numeric) into v_ts
    from jsonb_array_elements(case when jsonb_typeof(cl -> 'amr') = 'array' then cl -> 'amr' else '[]'::jsonb end) x
   where x ->> 'method' = 'password';
  if v_ts is null or v_ts < extract(epoch from now()) - 120 then
    return jsonb_build_object('error', 'contrasena_no_reciente');
  end if;
  select * into a from public.ia_ajustes where id;
  if not coalesce(a.encendido, false) then return jsonb_build_object('error', 'apagado'); end if;
  u := privado.ia_auth_usuario(v_uid);
  if u is null or not coalesce((u ->> 'activo')::boolean, false) or coalesce((u ->> 'baneado')::boolean, true) then
    return jsonb_build_object('error', 'usuario_inactivo');
  end if;
  if coalesce((u ->> 'factores')::integer, 0) > 0 and coalesce(cl ->> 'aal', '') <> 'aal2' then
    return jsonb_build_object('error', 'falta_segundo_factor');
  end if;
  select * into p from public.ia_peticiones where id_hash = privado.ia_hash(p_peticion) for update;
  if p.id_hash is null or p.usada_en is not null or p.caduca_en <= now() then
    return jsonb_build_object('error', 'peticion_invalida');
  end if;
  if not exists (select 1 from public.ia_clientes k where k.id = p.cliente_id and k.activo) then
    return jsonb_build_object('error', 'cliente');
  end if;
  select count(*) into v_vivas from public.ia_conexiones x
   where x.usuario_id = v_uid and x.revocada_en is null and x.expira_en > now();
  if v_vivas >= a.max_conexiones then return jsonb_build_object('error', 'demasiadas_conexiones'); end if;
  update public.ia_peticiones set usada_en = now() where id_hash = p.id_hash;
  insert into public.ia_conexiones (usuario_id, cliente_id, recurso, huella, aal, expira_en)
  values (v_uid, p.cliente_id, p.recurso, u ->> 'huella', case when cl ->> 'aal' = 'aal2' then 'aal2' else 'aal1' end,
          now() + make_interval(days => a.duracion_dias))
  returning id into v_con;
  v_cod := privado.ia_token_nuevo(v_con, 'codigo', now() + interval '60 seconds', p.code_challenge, p.redirect_uri);
  return jsonb_build_object('redirect_uri', p.redirect_uri, 'code', v_cod, 'state', p.estado);
end $function$;

CREATE OR REPLACE FUNCTION public.ia_peticion_ver(p_peticion text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := privado.ia_pantalla_uid(); p public.ia_peticiones; k public.ia_clientes; a public.ia_ajustes;
        v_motivo text; v_vivas integer;
begin
  if p_peticion is null or p_peticion !~ '^[A-Za-z0-9_-]{43}$' then return jsonb_build_object('error', 'peticion_invalida'); end if;
  select * into p from public.ia_peticiones where id_hash = privado.ia_hash(p_peticion);
  if p.id_hash is null or p.usada_en is not null or p.caduca_en <= now() then
    return jsonb_build_object('error', 'peticion_invalida');
  end if;
  select * into k from public.ia_clientes where id = p.cliente_id;
  select * into a from public.ia_ajustes where id;
  select count(*) into v_vivas from public.ia_conexiones x
   where x.usuario_id = v_uid and x.revocada_en is null and x.expira_en > now();
  v_motivo := case
    when not coalesce(a.encendido, false) then 'apagado'
    when not coalesce(k.activo, false) then 'cliente'
    -- la misma puerta que ia_conexion_autoriza (17-oct, sin permiso por persona): la pantalla no dice «puedes» a quien no podrá
    when not exists (select 1 from (select privado.ia_auth_usuario(v_uid) as j) u
                      where coalesce((u.j ->> 'activo')::boolean, false) and not coalesce((u.j ->> 'baneado')::boolean, true))
      then 'usuario_inactivo'
    when v_vivas >= a.max_conexiones then 'demasiadas_conexiones'
  end;
  -- destino: el dominio al que volverá el código (la pantalla de consentimiento lo enseña); quedan_s: segundos de vida de la
  -- petición medidos con el reloj de la base (el del navegador no es de fiar)
  return jsonb_build_object('asistente', k.asistente, 'nombre', k.nombre, 'caduca_en', p.caduca_en,
                            'quedan_s', greatest(0, floor(extract(epoch from p.caduca_en - now())))::integer,
                            'destino', substring(p.redirect_uri from '^https://([^/]+)/'),
                            'duracion_dias', a.duracion_dias, 'puede', v_motivo is null, 'motivo', v_motivo);
end $function$;

CREATE OR REPLACE FUNCTION public.ia_mis_conexiones()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with yo as (
    select privado.ia_pantalla_uid() as uid,
           coalesce((select encendido from public.ia_ajustes where id), false) as encendido,
           (select duracion_dias from public.ia_ajustes where id) as duracion_dias,
           (select r.tope_horas from public._correo_cola_regla('aviso_ia_conexion') r) as tope_aviso
  ), puede as (
    -- «permiso» = puede conectar: usuario activo del equipo y sin bloqueo (17-oct-2026, owner: ya no hay permiso por persona;
    -- la misma regla que ia_conexion_autoriza y privado.ia_conexion_motivo, de privado.ia_auth_usuario)
    select y.*, coalesce((u.j ->> 'activo')::boolean, false) and not coalesce((u.j ->> 'baneado')::boolean, true) as permiso
      from yo y cross join lateral (select privado.ia_auth_usuario(y.uid) as j) u
  )
  select jsonb_build_object(
    'encendido', p.encendido,
    'permiso', p.permiso,
    'duracion_dias', p.duracion_dias,
    -- con qué se conecta: solo a quien puede conectar ahora mismo, y solo los asistentes activos
    'clientes', case when p.encendido and p.permiso then coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'asistente', k.asistente, 'nombre', k.nombre) order by k.asistente, k.nombre)
        from public.ia_clientes k where k.activo), '[]'::jsonb) else '[]'::jsonb end,
    'conexiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'asistente', k.asistente, 'nombre', k.nombre, 'creada_en', c.creada_en, 'expira_en', c.expira_en,
               'viva', c.revocada_en is null and c.expira_en > now() and not m.sin_aviso,
               'revocada_en', coalesce(c.revocada_en, case when m.sin_aviso then c.creada_en + make_interval(hours => coalesce(p.tope_aviso, 0)) end),
               'revocada_motivo', coalesce(c.revocada_motivo, case when m.sin_aviso then 'sin_aviso' end),
               'ultima_llamada', (select max(l.creado_en) from public.ia_llamadas l where l.conexion_id = c.id),
               'llamadas', (select count(*) from public.ia_llamadas l where l.conexion_id = c.id and l.resultado = 'ok'))
             order by c.creada_en desc)
        from public.ia_conexiones c join public.ia_clientes k on k.id = c.cliente_id
             -- la misma regla y el mismo orden que privado.ia_conexion_motivo (P6 §7b; caducada va antes): sin aviso pasadas tope_horas (o sin regla) ya no puede
             -- consultar y su siguiente uso la corta; aquí se enseña ya cortada, sin escribir (esta lectura es STABLE)
             cross join lateral (select c.revocada_en is null and c.expira_en > now() and c.avisada_en is null
                                        and (p.tope_aviso is null or c.creada_en < now() - make_interval(hours => p.tope_aviso)) as sin_aviso) m
       where c.usuario_id = p.uid and c.creada_en > now() - interval '30 days'), '[]'::jsonb))
    from puede p;
$function$;

CREATE OR REPLACE FUNCTION public.ia_ajustes_ver()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := privado.ia_gestor_uid(); v_dia date := (now() at time zone 'Asia/Makassar')::date;
begin
  return jsonb_build_object(
    'ajustes', (select jsonb_build_object('encendido', a.encendido, 'tope_dia', a.tope_dia, 'duracion_dias', a.duracion_dias,
                                          'max_conexiones', a.max_conexiones, 'actualizado_en', a.actualizado_en,
                                          'actualizado_por', a.actualizado_por)
                  from public.ia_ajustes a where a.id),
    'clientes', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'asistente', k.asistente, 'nombre', k.nombre,
                                                               'redirect_uris', to_jsonb(k.redirect_uris), 'activo', k.activo)
                                            order by k.asistente, k.creado_en)
                            from public.ia_clientes k), '[]'::jsonb),
    -- el equipo activo y sus consultas de hoy (nombre y rol: lo que ya ve el super admin en Usuarios). Desde el 17-oct puede
    -- conectar todo el equipo activo; `permiso` queda en true para la web anterior hasta que se publique la nueva
    'usuarios', coalesce((select jsonb_agg(e || jsonb_build_object('permiso', true, 'uso_hoy', coalesce(s.n, 0))
                                            order by e ->> 'nombre')
                            from jsonb_array_elements(privado.ia_equipo()) e
                            left join public.ia_uso s on s.usuario_id = (e ->> 'user_id')::uuid and s.dia = v_dia), '[]'::jsonb),
    'conexiones', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'usuario_id', c.usuario_id, 'cliente_id', c.cliente_id,
                                                                 'creada_en', c.creada_en, 'expira_en', c.expira_en, 'aal', c.aal)
                                              order by c.creada_en desc)
                              from public.ia_conexiones c where c.revocada_en is null and c.expira_en > now()), '[]'::jsonb));
end $function$;

revoke execute on function public.ia_permiso_guarda(uuid, boolean) from authenticated;

do $c$
declare f text;
begin
  foreach f in array array['privado.ia_conexion_motivo(uuid)', 'public.ia_conexion_autoriza(text)', 'public.ia_peticion_ver(text)',
                           'public.ia_mis_conexiones()', 'public.ia_ajustes_ver()'] loop
    if pg_get_functiondef(f::regprocedure) ~ 'ia_permisos' then
      raise exception 'mcp_todos: % sigue leyendo ia_permisos; no se aplica nada', f;
    end if;
    if pg_get_userbyid((select proowner from pg_proc where oid = f::regprocedure)) <> 'ia_puente_rol' then
      raise exception 'mcp_todos: % ya no es de ia_puente_rol; no se aplica nada', f;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.ia_permiso_guarda(uuid,boolean)', 'execute') then
    raise exception 'mcp_todos: ia_permiso_guarda sigue abierta a authenticated; no se aplica nada';
  end if;
end $c$;
commit;
