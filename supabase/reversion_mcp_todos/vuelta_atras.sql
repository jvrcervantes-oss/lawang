-- VUELTA ATRÁS de la migración «mcp_todos» (17-oct-2026, sesión mcp-ventana): vuelve el permiso por persona.
-- Deja las 5 funciones EXACTAMENTE como estaban en la viva el 17-oct antes del cambio (pg_get_functiondef; md5 al final: si no
-- casa, no se aplica nada) y devuelve el EXECUTE de public.ia_permiso_guarda a authenticated. No destruye nada: ia_permisos no se
-- tocó. Efecto: solo conecta quien tenga fila viva en ia_permisos; las conexiones de los demás se cortan en su siguiente uso.
-- La web de Ajustes › IA sin el interruptor por persona no lo puede dar: se revierte también su commit de Lawang.
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
  if not exists (select 1 from public.ia_permisos p where p.usuario_id = c.usuario_id and p.quitado_en is null) then
    perform privado.ia_revoca(c.id, 'permiso'); return 'permiso';
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
  if not exists (select 1 from public.ia_permisos x where x.usuario_id = v_uid and x.quitado_en is null) then
    return jsonb_build_object('error', 'sin_permiso');
  end if;
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
    when not exists (select 1 from public.ia_permisos x where x.usuario_id = v_uid and x.quitado_en is null) then 'sin_permiso'
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
    select y.*, exists (select 1 from public.ia_permisos x where x.usuario_id = y.uid and x.quitado_en is null) as permiso
      from yo y
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
    -- el equipo activo, para elegir quién puede conectar (nombre y rol: lo que ya ve el super admin en Usuarios)
    'usuarios', coalesce((select jsonb_agg(e || jsonb_build_object('permiso', p.usuario_id is not null, 'uso_hoy', coalesce(s.n, 0))
                                            order by p.usuario_id is null, e ->> 'nombre')
                            from jsonb_array_elements(privado.ia_equipo()) e
                            left join public.ia_permisos p on p.usuario_id = (e ->> 'user_id')::uuid and p.quitado_en is null
                            left join public.ia_uso s on s.usuario_id = (e ->> 'user_id')::uuid and s.dia = v_dia), '[]'::jsonb),
    'conexiones', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'usuario_id', c.usuario_id, 'cliente_id', c.cliente_id,
                                                                 'creada_en', c.creada_en, 'expira_en', c.expira_en, 'aal', c.aal)
                                              order by c.creada_en desc)
                              from public.ia_conexiones c where c.revocada_en is null and c.expira_en > now()), '[]'::jsonb));
end $function$;

grant execute on function public.ia_permiso_guarda(uuid, boolean) to authenticated;

do $c$
begin
  if md5(pg_get_functiondef('privado.ia_conexion_motivo(uuid)'::regprocedure)) <> '79cdd648f15072106cd9dcad0c42c264' then
    raise exception 'vuelta_atras mcp_todos: privado.ia_conexion_motivo(uuid) no es la del 17-oct; no se aplica nada';
  end if;
  if md5(pg_get_functiondef('public.ia_conexion_autoriza(text)'::regprocedure)) <> 'c32880807118c6c405d6d7c946c705af' then
    raise exception 'vuelta_atras mcp_todos: public.ia_conexion_autoriza(text) no es la del 17-oct; no se aplica nada';
  end if;
  if md5(pg_get_functiondef('public.ia_peticion_ver(text)'::regprocedure)) <> '40aa2461219a53c81bf97c7ce694a597' then
    raise exception 'vuelta_atras mcp_todos: public.ia_peticion_ver(text) no es la del 17-oct; no se aplica nada';
  end if;
  if md5(pg_get_functiondef('public.ia_mis_conexiones()'::regprocedure)) <> 'c969b1574ab64832ea49c01c305100ae' then
    raise exception 'vuelta_atras mcp_todos: public.ia_mis_conexiones() no es la del 17-oct; no se aplica nada';
  end if;
  if md5(pg_get_functiondef('public.ia_ajustes_ver()'::regprocedure)) <> '456120fc5c391de01163d2d34a782ae9' then
    raise exception 'vuelta_atras mcp_todos: public.ia_ajustes_ver() no es la del 17-oct; no se aplica nada';
  end if;
  -- el permiso de ia_permiso_guarda, el medido en la viva el 17-oct antes del cambio (Backend, consulta de deploy)
  if (select proacl::text from pg_proc where oid = 'public.ia_permiso_guarda(uuid, boolean)'::regprocedure)
     <> '{ia_puente_rol=X/ia_puente_rol,authenticated=X/ia_puente_rol}' then
    raise exception 'vuelta_atras mcp_todos: el permiso de public.ia_permiso_guarda no queda como el del 17-oct; no se aplica nada';
  end if;
end $c$;
commit;
