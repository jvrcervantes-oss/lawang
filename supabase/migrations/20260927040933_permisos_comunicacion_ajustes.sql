-- Permisos v4 al día (27-sep-2026, encargos/20260927_lawang_permisos_v4_documentacion.md,
-- revisión previa #129 de Seguridad). Dos claves reales nuevas en `usuarios.herramientas`:
--   · `comunicacion` — Comunicados al equipo (/intranet/v4/comunicacion/). Lee la PII de los
--     destinatarios (`comunicado_envios.email/nombre`) y manda correo a todo el equipo.
--   · `ajustes` — Ajustes (/intranet/v4/ajustes/): cerrar la intranet y pausar los envíos.
-- Hasta hoy las dos se abrían solo por ROL (admin): una casilla que no decidiera nada en el
-- servidor sería cosmética, así que el rol SE QUEDA y se AÑADE `puede('<clave>')` en las RPC
-- y en las dos policies de lectura. `mantenimiento_envios` acepta ajustes O comunicacion: lo
-- llama también el botón «Pausar envíos» de Comunicados (assets/mantenimiento.js).
-- `parametro_set` no se toca: ya exige super admin.
-- Sin clave, a propósito (revisión #129): Sociedades y Comisión de administración (todo exige
-- es_super_admin() y puede() da true al super) y Finanzas (sin RPC propia).
--
-- destructivo-ok: el único DELETE es el cuerpo de comunicado_borra, que se RECREA idéntico salvo
-- la puerta (rol + clave); la migración no borra ninguna fila ni objeto.
--
-- Backfill SIN PÉRDIDAS: los 4 admins activos reciben las dos claves (los super admin pasan
-- `puede()` sin tenerlas). Mismo patrón que 20260923180500 y 20260924114729: se ejecuta como el
-- super_admin owner porque el trigger usuarios_bloquea_cambio_rol_herramientas solo deja a un
-- super_admin tocar herramientas — nunca una excepción en el trigger ni `disable trigger`.
-- El bloque del final RECALCULA por usuario activo «abre Comunicados / abre Ajustes» con la
-- regla vieja (rol) y la nueva (rol + clave) y aborta la migración entera si difieren.

select set_config('request.jwt.claims', json_build_object('sub',
  (select user_id from public.usuarios where email = 'jvr.cervantes@gmail.com' and rol = 'super_admin'),
  'role', 'authenticated')::text, true);

-- foto de ANTES (regla vieja: data-rol="admin" → admin o super_admin activos)
create temp table _antes on commit drop as
  select u.user_id, u.rol, coalesce(u.herramientas, '{}'::text[]) as herr,
         (u.activo and u.rol in ('admin', 'super_admin')) as abre
    from public.usuarios u;

update public.usuarios u
   set herramientas = coalesce(u.herramientas, '{}'::text[])
                      || array(select x from unnest(array['comunicacion', 'ajustes']) x
                                where not x = any (coalesce(u.herramientas, '{}'::text[])))   -- añade, sin reordenar
 where u.rol = 'admin' and u.activo
   and not (coalesce(u.herramientas, '{}'::text[]) @> array['comunicacion', 'ajustes']);

-- ── RPC: rol + clave ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.comunicado_borra(p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (public.es_admin() and public.puede('comunicacion')) then raise exception 'Los comunicados son de administración con la herramienta «Comunicación»' using errcode = '42501'; end if;
  delete from public.comunicados where id = p_id;
  if not found then raise exception 'Ese comunicado ya no existe: recarga' using errcode = '22023'; end if;
  return p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.comunicado_encolar(p_comunicado uuid, p_user_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int;
begin
  if not (public.es_admin() and public.puede('comunicacion')) then
    raise exception 'Enviar un comunicado exige ser admin con la herramienta «Comunicación».' using errcode = '42501';
  end if;
  if public.envios_pausados() then
    raise exception 'Los envíos de correo están en pausa (modo mantenimiento). Reanúdalos en Ajustes para enviar.' using errcode = '55000';
  end if;
  if p_user_ids is null or cardinality(p_user_ids) = 0 then
    raise exception 'Elige al menos un destinatario.' using errcode = '22023';
  end if;
  if cardinality(p_user_ids) > 200 then
    raise exception 'Demasiados destinatarios de una vez (máximo 200).' using errcode = '22023';
  end if;
  perform 1 from public.comunicados where id = p_comunicado for update;
  if not found then
    raise exception 'Ese comunicado no existe.' using errcode = 'P0002';
  end if;

  update public.comunicados set enviado_en = coalesce(enviado_en, now()) where id = p_comunicado;

  with reservados as (
    insert into public.comunicado_envios (comunicado_id, user_id, email, nombre, encolado_por)
    select p_comunicado, u.user_id, u.email, u.nombre, (select auth.uid())
      from public.usuarios u
     where u.user_id = any (p_user_ids) and u.activo and u.email is not null
    on conflict (comunicado_id, user_id) where not es_prueba
    do update set estado = 'pendiente', intentos = 0, error = null, reclamado_en = null,
                  email = excluded.email, nombre = excluded.nombre,
                  encolado_por = excluded.encolado_por, encolado_en = now()
      where public.comunicado_envios.estado = 'error'
    returning 1)
  select count(*) into n from reservados;

  if n > 0 then perform public._comunicados_despierta(); end if;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.comunicado_guarda(p_id uuid, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.comunicados%rowtype; k text;
begin
  if not (public.es_admin() and public.puede('comunicacion')) then raise exception 'Los comunicados son de administración con la herramienta «Comunicación»' using errcode = '42501'; end if;
  if jsonb_typeof(p_datos) is distinct from 'object' then raise exception 'Datos del comunicado no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_datos) loop
    if k not in ('asunto', 'encabezado', 'cuerpo', 'cta_url', 'cta_texto') then
      raise exception 'Ese dato del comunicado no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  if p_id is not null then
    select * into v from public.comunicados c where c.id = p_id for update;
    if not found then raise exception 'Ese comunicado ya no existe: recarga' using errcode = '22023'; end if;
  end if;
  if p_datos ? 'asunto' then v.asunto := p_datos->>'asunto'; end if;
  if p_datos ? 'encabezado' then v.encabezado := nullif(btrim(coalesce(p_datos->>'encabezado', '')), ''); end if;
  if p_datos ? 'cuerpo' then v.cuerpo := p_datos->>'cuerpo'; end if;
  if p_datos ? 'cta_url' then v.cta_url := nullif(btrim(coalesce(p_datos->>'cta_url', '')), ''); end if;
  if p_datos ? 'cta_texto' then v.cta_texto := nullif(btrim(coalesce(p_datos->>'cta_texto', '')), ''); end if;
  if p_id is null then
    insert into public.comunicados (asunto, encabezado, cuerpo, cta_url, cta_texto, creado_por)
    values (v.asunto, v.encabezado, v.cuerpo, v.cta_url, v.cta_texto, (select auth.uid()))
    returning * into v;
  else
    update public.comunicados set asunto = v.asunto, encabezado = v.encabezado, cuerpo = v.cuerpo,
           cta_url = v.cta_url, cta_texto = v.cta_texto
     where id = p_id returning * into v;
  end if;
  return to_jsonb(v);
end $function$;

CREATE OR REPLACE FUNCTION public.comunicado_prueba(p_comunicado uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_email text; v_nombre text;
begin
  if not (public.es_admin() and public.puede('comunicacion')) then
    raise exception 'Enviar una prueba exige ser admin con la herramienta «Comunicación».' using errcode = '42501';
  end if;
  if public.envios_pausados() then
    raise exception 'Los envíos de correo están en pausa (modo mantenimiento). Reanúdalos en Ajustes para enviar.' using errcode = '55000';
  end if;
  perform 1 from public.comunicados where id = p_comunicado;
  if not found then
    raise exception 'Guarda el comunicado antes de probarlo.' using errcode = 'P0002';
  end if;
  select u.email, u.nombre into v_email, v_nombre
    from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
  if v_email is null then
    raise exception 'Tu usuario no tiene email en la intranet.' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.comunicado_envios
              where comunicado_id = p_comunicado and es_prueba and user_id = (select auth.uid())
                and estado in ('pendiente','enviando')) then
    raise exception 'Ya hay una prueba en camino: espera a que llegue.' using errcode = '22023';
  end if;
  insert into public.comunicado_envios (comunicado_id, user_id, email, nombre, es_prueba, encolado_por)
  values (p_comunicado, (select auth.uid()), v_email, v_nombre, true, (select auth.uid()));
  perform public._comunicados_despierta();
  return v_email;
end $function$;

CREATE OR REPLACE FUNCTION public.mantenimiento_envios(p_pausar boolean, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- ajustes O comunicacion: el botón «Pausar envíos» está en las dos pantallas (mantenimiento.js)
  if not (public.es_admin() and (public.puede('ajustes') or public.puede('comunicacion'))) then
    raise exception 'Pausar o reanudar los envíos exige ser admin con «Ajustes» o «Comunicación».' using errcode = '42501';
  end if;
  if p_pausar is null then
    raise exception 'Falta indicar si se pausa o se reanuda.' using errcode = '22023';
  end if;
  insert into public.mantenimiento (id, envios_pausados, motivo, cambiado_por, cambiado_en)
  values (1, p_pausar, nullif(btrim(p_motivo), ''), (select auth.uid()), now())
  on conflict (id) do update set envios_pausados = excluded.envios_pausados, motivo = excluded.motivo,
                                 cambiado_por = excluded.cambiado_por, cambiado_en = excluded.cambiado_en;
  if not p_pausar then perform public._comunicados_despierta(); end if;
end $function$;

CREATE OR REPLACE FUNCTION public.mantenimiento_intranet(p_cerrar boolean, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not (public.es_admin() and public.puede('ajustes')) then
    raise exception 'Cerrar o reabrir la intranet exige ser admin con la herramienta «Ajustes».' using errcode = '42501';
  end if;
  if p_cerrar is null then
    raise exception 'Falta indicar si se cierra o se reabre.' using errcode = '22023';
  end if;
  if p_cerrar and nullif(btrim(p_motivo), '') is null then
    raise exception 'Escribe el motivo: es lo que verá el equipo.' using errcode = '22023';
  end if;
  update public.mantenimiento
     set intranet_cerrada      = p_cerrar,
         intranet_motivo       = case when p_cerrar then btrim(p_motivo) else null end,
         intranet_cambiado_por = (select auth.uid()),
         intranet_cambiado_en  = now()
   where id = 1;
  if not found then
    raise exception 'Falta la fila de mantenimiento (id = 1).' using errcode = 'P0002';
  end if;
end $function$;

-- Reducir la exposición: la RPC la llama la sesión (authenticated) y nadie más.
revoke all on function public.comunicado_borra(uuid) from public, anon;
revoke all on function public.comunicado_encolar(uuid, uuid[]) from public, anon;
revoke all on function public.comunicado_guarda(uuid, jsonb) from public, anon;
revoke all on function public.comunicado_prueba(uuid) from public, anon;
revoke all on function public.mantenimiento_envios(boolean, text) from public, anon;
revoke all on function public.mantenimiento_intranet(boolean, text) from public, anon;
grant execute on function public.comunicado_borra(uuid) to authenticated, service_role;
grant execute on function public.comunicado_encolar(uuid, uuid[]) to authenticated, service_role;
grant execute on function public.comunicado_guarda(uuid, jsonb) to authenticated, service_role;
grant execute on function public.comunicado_prueba(uuid) to authenticated, service_role;
grant execute on function public.mantenimiento_envios(boolean, text) to authenticated, service_role;
grant execute on function public.mantenimiento_intranet(boolean, text) to authenticated, service_role;

-- ── Lectura: los comunicados y sus destinatarios (PII) piden la clave ────────────
-- ALTER y no drop+create: la policy no desaparece ni un instante y conserva sus roles
-- ({authenticated, lw_lector}).
alter policy comunicados_admin_select on public.comunicados
  using (public.es_admin() and public.puede('comunicacion'));
alter policy comunicado_envios_admin_select on public.comunicado_envios
  using (public.es_admin() and public.puede('comunicacion'));

-- ── Medida: misma gente antes y después ──────────────────────────────────────
do $$
declare
  v_distintos int; v_nuevos int; v_admins int; v_con int; v_sin_doc int;
begin
  select count(*) into v_distintos
    from _antes a join public.usuarios u using (user_id)
   where a.abre is distinct from
         (u.activo and u.rol in ('admin', 'super_admin')
          and (u.rol = 'super_admin' or coalesce(u.herramientas, '{}') @> array['comunicacion']))
      or a.abre is distinct from
         (u.activo and u.rol in ('admin', 'super_admin')
          and (u.rol = 'super_admin' or coalesce(u.herramientas, '{}') @> array['ajustes']));
  if v_distintos > 0 then
    raise exception 'Backfill: % usuarios abrirían Comunicados/Ajustes distinto que antes', v_distintos;
  end if;
  -- la clave solo la gana quien ya pasaba la puerta, y nada más cambia en su lista
  select count(*) into v_nuevos
    from _antes a join public.usuarios u using (user_id)
   where coalesce(u.herramientas, '{}') is distinct from a.herr
     and not (a.abre and a.rol = 'admin'
              and (select array_agg(distinct h order by h) from unnest(coalesce(u.herramientas, '{}')) h)
                  = (select array_agg(distinct h order by h) from unnest(a.herr || array['comunicacion', 'ajustes']) h));
  if v_nuevos > 0 then
    raise exception 'Backfill: % usuarios cambian de herramientas fuera de lo previsto', v_nuevos;
  end if;
  select count(*) into v_admins from public.usuarios where rol = 'admin' and activo;
  select count(*) into v_con from public.usuarios where rol = 'admin' and activo
     and herramientas @> array['comunicacion', 'ajustes'];
  if v_con <> v_admins then
    raise exception 'Backfill: % de % admins activos con las dos claves', v_con, v_admins;
  end if;
  select count(*) into v_sin_doc from public.usuarios where rol = 'admin' and activo
     and not coalesce(herramientas, '{}') @> array['documentacion'];
  raise notice 'Backfill OK: % admins activos con comunicacion+ajustes; % admin(s) sin documentacion (no se toca: sería ampliar acceso)', v_con, v_sin_doc;
end $$;
;
