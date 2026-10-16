-- MCP de Lawang · F1-P4 · lo que piden las tres pantallas (16-oct-2026, sesión mcp-lawang).
-- Encargo: encargos/20261015_erp_mcp.md (agencia), fila «Lawang F1-P4». Va después de 20261016110000 (P1) y 20261016120000 (P2).
--
-- QUÉ CONSTRUYE (solo construye; no toca Auth, ni anon, ni nada existente fuera de ia_*):
--   1. public.ia_peticion_datos(peticion)  · authenticated · la página /intranet/ia/conectar/: qué asistente pide entrar y si
--      esta persona puede conectarlo (no gasta la petición; la gasta ia_conexion_autoriza). Su EXECUTE no se da aquí: va con la
--      página y la edge en supabase/propuestas/20261016140000_mcp_f1_abre_conexion.sql (OK del owner; Seguridad, 16-oct).
--   2. public.ia_mis_conexiones()          · authenticated · «apps conectadas»: las conexiones de la propia persona.
--   3. public.ia_ajustes_datos()           · super admin   · Ajustes › IA: interruptor, tope, clientes, quién y conexiones vivas.
--   4. public.ia_ajustes_guarda(datos)     · super admin   · encender/apagar, tope diario, duración y máximo de conexiones.
--   5. public.ia_cliente_guarda(...)       · super admin   · un cliente por asistente, con sus direcciones de vuelta exactas.
--   6. public.ia_permiso_guarda(uid, bool) · super admin   · quién puede conectar; quitarlo revoca sus conexiones EN EL ACTO.
-- Quién: el super admin, como fijó el plan revisado (encargo, «Las acciones de Ajustes › IA … el super admin»): decide qué datos
-- de Lawang salen hacia un asistente externo, no es gestión del negocio. Llamador con nombre de cada una: su pantalla (arriba).
--
-- NO TE CREAS EL FRONTEND: cada cifra se valida aquí (rangos de ia_ajustes), el asistente es una lista cerrada, las direcciones
-- de vuelta solo valen https y en el dominio de su asistente (una dirección ajena = robo del código), y el permiso se concede
-- solo a un usuario ACTIVO por su id. Encender sin tope (0) se rechaza: el tope lo fija el super admin, no el estudio.
-- Ninguna de estas funciones se puede llamar desde dentro de una llamada del asistente (axw.ia_conexion fijado).
--
-- VUELTA ATRÁS: drop de las 6 funciones (supabase/reversion_mcp/vuelta_atras_p4.sql). No crea tablas ni datos.

set lock_timeout = '5s';

grant create on schema public to ia_puente_rol;
grant create on schema privado to ia_puente_rol;

-- ── 0. Ayudantes ──────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Sesión de una persona de la intranet, nunca la de una llamada del asistente.
create or replace function privado.ia_pantalla_uid()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_uid uuid := public.uid_sesion();
begin
  if v_uid is null then raise exception 'Sin sesión' using errcode = '42501'; end if;
  if nullif(current_setting('axw.ia_conexion', true), '') is not null then
    raise exception 'No disponible' using errcode = '42501';
  end if;
  return v_uid;
end $$;

create or replace function privado.ia_gestor_uid()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_uid uuid := privado.ia_pantalla_uid();
begin
  if not public.es_super_admin() then
    raise exception 'Solo el super admin gestiona la IA' using errcode = '42501';
  end if;
  return v_uid;
end $$;

-- El equipo activo para Ajustes › IA (id, nombre y rol). ia_puente_rol no lee public.usuarios (no tiene grant y la tabla tiene RLS):
-- como en P1 (ia_auth_usuario), lo que necesita de fuera de ia_* se lo da un ayudante de postgres, estrecho y solo de lectura.
create or replace function privado.ia_equipo()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'nombre', u.nombre, 'rol', u.rol) order by u.nombre), '[]'::jsonb)
    from public.usuarios u
   where u.activo
$$;
alter function privado.ia_equipo() owner to postgres;
revoke all on function privado.ia_equipo() from public, anon, authenticated, service_role;
grant execute on function privado.ia_equipo() to ia_puente_rol;

-- ── 1. Página de conexión ─────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.ia_peticion_datos(p_peticion text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
end $$;

-- ── 2. «Apps conectadas» ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.ia_mis_conexiones()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'encendido', coalesce((select encendido from public.ia_ajustes where id), false),
    'permiso', exists (select 1 from public.ia_permisos x where x.usuario_id = privado.ia_pantalla_uid() and x.quitado_en is null),
    'conexiones', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'asistente', k.asistente, 'nombre', k.nombre, 'creada_en', c.creada_en, 'expira_en', c.expira_en,
               'viva', c.revocada_en is null and c.expira_en > now(), 'revocada_en', c.revocada_en,
               'revocada_motivo', c.revocada_motivo,
               'ultima_llamada', (select max(l.creado_en) from public.ia_llamadas l where l.conexion_id = c.id),
               'llamadas', (select count(*) from public.ia_llamadas l where l.conexion_id = c.id and l.resultado = 'ok'))
             order by c.creada_en desc)
        from public.ia_conexiones c join public.ia_clientes k on k.id = c.cliente_id
       where c.usuario_id = privado.ia_pantalla_uid() and c.creada_en > now() - interval '30 days'), '[]'::jsonb));
$$;

-- ── 3. Ajustes › IA: lectura ──────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.ia_ajustes_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
end $$;

-- ── 4. Ajustes › IA: interruptor y topes ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.ia_ajustes_guarda(p_datos jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_uid uuid := privado.ia_gestor_uid(); a public.ia_ajustes; k text;
        v_enc boolean; v_tope integer; v_dur integer; v_max integer;
begin
  if jsonb_typeof(p_datos) is distinct from 'object' then return jsonb_build_object('error', 'datos_invalidos'); end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('encendido', 'tope_dia', 'duracion_dias', 'max_conexiones') then
      return jsonb_build_object('error', 'campo_desconocido', 'campo', k);
    end if;
  end loop;
  select * into a from public.ia_ajustes where id for update;
  begin
    v_enc  := coalesce((p_datos ->> 'encendido')::boolean, a.encendido);
    v_tope := coalesce((p_datos ->> 'tope_dia')::integer, a.tope_dia);
    v_dur  := coalesce((p_datos ->> 'duracion_dias')::integer, a.duracion_dias);
    v_max  := coalesce((p_datos ->> 'max_conexiones')::integer, a.max_conexiones);
  exception when others then
    return jsonb_build_object('error', 'datos_invalidos');
  end;
  if v_tope not between 0 and 5000 or v_dur not between 1 and 30 or v_max not between 1 and 10 then
    return jsonb_build_object('error', 'fuera_de_rango');
  end if;
  if v_enc and v_tope = 0 then return jsonb_build_object('error', 'falta_tope'); end if;
  update public.ia_ajustes
     set encendido = v_enc, tope_dia = v_tope, duracion_dias = v_dur, max_conexiones = v_max,
         actualizado_por = v_uid, actualizado_en = now()
   where id;
  return jsonb_build_object('ok', true);
end $$;

-- ── 5. Clientes por asistente ─────────────────────────────────────────────────────────────────────────────────────────────
-- Dirección de vuelta: https, sin puerto, ni usuario, ni consulta, ni fragmento, y en el dominio de SU asistente.
create or replace function privado.ia_redirect_valida(p_asistente text, p_uri text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_uri is not null and length(p_uri) <= 200 and case p_asistente
    when 'claude'  then p_uri ~ '^https://(claude\.ai|claude\.com)/[A-Za-z0-9/_.-]*$'
    when 'chatgpt' then p_uri ~ '^https://(chatgpt\.com|chat\.openai\.com)/[A-Za-z0-9/_.-]*$'
    else false end
$$;

create or replace function public.ia_cliente_guarda(p_id uuid, p_asistente text, p_nombre text, p_redirect_uris text[],
                                                    p_activo boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_uid uuid := privado.ia_gestor_uid(); v_id uuid; v_nombre text := btrim(coalesce(p_nombre, '')); x text; c uuid;
begin
  if p_asistente is null or p_asistente not in ('claude', 'chatgpt') then return jsonb_build_object('error', 'asistente'); end if;
  if length(v_nombre) not between 1 and 60 then return jsonb_build_object('error', 'nombre'); end if;
  if p_redirect_uris is null or cardinality(p_redirect_uris) not between 1 and 3 then
    return jsonb_build_object('error', 'redirect_uris');
  end if;
  foreach x in array p_redirect_uris loop
    if not privado.ia_redirect_valida(p_asistente, x) then return jsonb_build_object('error', 'redirect_uri', 'uri', left(x, 200)); end if;
  end loop;
  if p_id is null then
    insert into public.ia_clientes (asistente, nombre, redirect_uris, activo, creado_por)
    values (p_asistente, v_nombre, p_redirect_uris, coalesce(p_activo, false), v_uid)
    returning id into v_id;
  else
    update public.ia_clientes
       set asistente = p_asistente, nombre = v_nombre, redirect_uris = p_redirect_uris, activo = coalesce(p_activo, activo)
     where id = p_id
    returning id into v_id;
    if v_id is null then return jsonb_build_object('error', 'no_existe'); end if;
    -- apagado: sus conexiones se cortan YA, no en la siguiente llamada
    if not (select activo from public.ia_clientes where id = v_id) then
      for c in select x3.id from public.ia_conexiones x3 where x3.cliente_id = v_id and x3.revocada_en is null loop
        perform privado.ia_revoca(c, 'cliente');
      end loop;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ── 6. Quién puede conectar ───────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.ia_permiso_guarda(p_usuario uuid, p_concede boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_uid uuid := privado.ia_gestor_uid(); c uuid;
begin
  if p_usuario is null or p_concede is null then return jsonb_build_object('error', 'datos_invalidos'); end if;
  if p_concede then
    -- activo = public.usuarios.activo, leído por el ayudante de P1 (ia_puente_rol no lee usuarios)
    if not coalesce((privado.ia_auth_usuario(p_usuario) ->> 'activo')::boolean, false) then
      return jsonb_build_object('error', 'usuario_inactivo');
    end if;
    -- volver a conceder uno quitado: la fila revive con quién y cuándo nuevos (un permiso vivo no se toca)
    insert into public.ia_permisos (usuario_id, concedido_por) values (p_usuario, v_uid)
    on conflict (usuario_id) do update set concedido_por = excluded.concedido_por, concedido_en = now(),
                                           quitado_en = null, quitado_por = null
     where public.ia_permisos.quitado_en is not null;
  else
    -- quitar no borra: queda quién y cuándo (sin DELETE en la base de un cliente, 16-oct)
    update public.ia_permisos set quitado_en = now(), quitado_por = v_uid
     where usuario_id = p_usuario and quitado_en is null;
    for c in select x.id from public.ia_conexiones x where x.usuario_id = p_usuario and x.revocada_en is null loop
      perform privado.ia_revoca(c, 'permiso');
    end loop;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ── 7. Dueños y permisos (default-deny: cada EXECUTE con su llamador) ──────────────────────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array['privado.ia_pantalla_uid()', 'privado.ia_gestor_uid()', 'privado.ia_redirect_valida(text,text)',
                           'public.ia_peticion_datos(text)', 'public.ia_mis_conexiones()', 'public.ia_ajustes_datos()',
                           'public.ia_ajustes_guarda(jsonb)', 'public.ia_cliente_guarda(uuid,text,text,text[],boolean)',
                           'public.ia_permiso_guarda(uuid,boolean)'] loop
    execute format('alter function %s owner to ia_puente_rol', f);
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
-- las pantallas de la intranet (la sesión de la persona; el super admin lo comprueba cada función por dentro).
-- public.ia_peticion_datos: sin grant aquí (propuestas/20261016140000, con la página de conexión).
grant execute on function public.ia_mis_conexiones() to authenticated;
grant execute on function public.ia_ajustes_datos() to authenticated;
grant execute on function public.ia_ajustes_guarda(jsonb) to authenticated;
grant execute on function public.ia_cliente_guarda(uuid, text, text, text[], boolean) to authenticated;
grant execute on function public.ia_permiso_guarda(uuid, boolean) to authenticated;

revoke create on schema public from ia_puente_rol;
revoke create on schema privado from ia_puente_rol;
