-- LAW-338 L2 (pantallas de un solo lector) — B10a a la par con el maestro.
-- erp-ok: B10 a la par (decisión del owner 27-sep: cada *_datos nace en las dos bases con el mismo cuerpo)
-- Encargos: encargos/20260927_lawang_law338_lecturas_bloques.md (L2) · encargos/20260927_erp_b10_lecturas_a_la_par.md.
-- Pareja: maestro erp/migraciones/20260928130000_b10a_l2_pantallas.sql (dueño erp_lector). Cuerpo de las siete *_datos
-- IDÉNTICO en las dos bases (md5 de prosrc); solo cambia el rol lector dueño.
-- Qué sustituye (cada pantalla deja de leer tablas por PostgREST y pide UNA `*_datos` por window.lwDatos):
--   · intranet/v4/assets/mantenimiento.js (franja + ajustes)   mantenimiento                       → mantenimiento_datos()
--   · intranet/v4/assets/comunicacion.js (lista + destinatarios) comunicados, comunicado_envios, usuarios → comunicacion_datos(p_limit, p_despues)
--   · intranet/v4/assets/comunicacion.js (abrir + registro)    comunicados, comunicado_envios       → comunicado_datos(p_id)
--   · intranet/v4/usuarios/solicitudes.js (altas)              solicitudes_colaborador, proyectos   → solicitudes_alta_datos(p_limit, p_despues)
--   · intranet/v4/usuarios/solicitudes.js (referidos)          referidos_contactos                  → referidos_datos(p_limit, p_despues)
--   · contracts/assets/autoria.js (reasignar autor)            usuarios, correcciones_datos         → autoria_datos(p_tabla, p_fila)
--   · contracts/assets/documento_diseno.js                     contratos_diseno                     → contrato_diseno_datos(p_slug)
--
-- Por qué así (reglas de LAW-338 L0/L1 y de la revisión previa #136):
--  · SECURITY DEFINER con dueño LECTOR (NOBYPASSRLS): la RLS se evalúa como el lector con las claims del usuario ⇒ mismas
--    filas que la lectura directa de hoy; la regla vive solo en la policy. Sin `auth.*` en el cuerpo (uid_sesion()),
--    search_path '', stable, columnas explícitas, 42501 sin sesión.
--  · Comunicados exige `es_admin() and puede('comunicacion')` (el gate de sus RPC de escritura, 20260927040933) y lo dice
--    en voz alta (42501) en vez de devolver una lista vacía.
--  · mantenimiento_datos: la franja de envíos la ve todo el equipo (lo de hoy); el estado del interruptor de la
--    intranet solo admin con «Ajustes» (antes cualquier sesión leía la fila entera: exposición reducida a propósito).
--  · Listas con `p_limit` (tope 500) + cursor `p_despues` = id del último de la página → `siguiente`; las listas de
--    catálogo (usuarios, proyectos, envíos de un comunicado) llevan tope fijo y `recortado` si lo tocan.
--  · La lista de comunicados trae su recuento de envíos (ok/total sin pruebas) calculado aquí: el navegador ya no baja
--    el registro entero de todos los comunicados para contarlo.
--  · Aditiva: solo create function + dueño + grants. NINGÚN revoke de tabla (van en por_aplicar/, con OK del owner).
--  · Además (solo Lawang): dossier_datos (27-sep, anterior a LAW-338) deja de ser de postgres (BYPASSRLS) y pasa a
--    lw_lector; su único llamador es intranet/dossier/builder.html. Sin service_role. El maestro no la tiene.
--  · Paridad medida ANTES de aplicar (28-sep), en transacción revertida: 65/65 usuarios de auth.users, 3.073 llamadas,
--    0 distintas (count+md5 por lista contra la lectura directa como authenticated); dossier_datos dueño postgres vs
--    copia dueño lw_lector: 4 usuarios con permiso × 29 proyectos, 0 distintas.

-- ── Las siete RPC (cuerpo IDÉNTICO en Lawang y en el maestro; solo cambia el rol lector dueño) ─────────────────────

-- Franja «envíos en pausa» (todas las pantallas que cargan mantenimiento.js) + interruptor de /v4/ajustes/.
create or replace function public.mantenimiento_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  m record;
  v_ajustes boolean;
begin
  if public.uid_sesion() is null then
    raise exception 'mantenimiento_datos: sin sesión' using errcode = '42501';
  end if;
  -- La franja de envíos la ve todo el equipo (lo mismo que dejaba la policy `mantenimiento_leer`). El estado del
  -- interruptor de la intranet, solo quien lo maneja: admin con «Ajustes», el mismo gate que mantenimiento_intranet().
  v_ajustes := public.es_admin() and public.puede('ajustes');
  select t.envios_pausados, t.motivo, t.cambiado_en, t.intranet_cerrada, t.intranet_motivo, t.intranet_cambiado_en
    into m from public.mantenimiento t where t.id = 1;
  return jsonb_build_object(
    'envios_pausados',      coalesce(m.envios_pausados, false),
    'motivo',               m.motivo,
    'cambiado_en',          m.cambiado_en,
    'intranet_cerrada',     case when v_ajustes then coalesce(m.intranet_cerrada, false) end,
    'intranet_motivo',      case when v_ajustes then m.intranet_motivo end,
    'intranet_cambiado_en', case when v_ajustes then m.intranet_cambiado_en end);
end $$;

-- Lista de comunicados (con su recuento de envíos reales) + destinatarios posibles. /v4/comunicacion/.
create or replace function public.comunicacion_datos(p_limit int default 100, p_despues uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_ts timestamptz;
  v_lista jsonb; v_n int; v_ult uuid;
  v_usu jsonb; v_nusu int;
begin
  if public.uid_sesion() is null then
    raise exception 'comunicacion_datos: sin sesión' using errcode = '42501';
  end if;
  if not (public.es_admin() and public.puede('comunicacion')) then
    raise exception 'Los comunicados son de administración con la herramienta «Comunicación»' using errcode = '42501';
  end if;
  if p_despues is not null then
    select c.actualizado_en into v_ts from public.comunicados c where c.id = p_despues;
    if v_ts is null then
      raise exception 'comunicacion_datos: cursor desconocido' using errcode = '22023';
    end if;
  end if;
  -- orden de la pantalla (actualizado_en desc) con el id de desempate: el cursor es (actualizado_en, id)
  with pag as (
    select c.id, c.asunto, c.encabezado, c.cuerpo, c.cta_url, c.cta_texto, c.creado_en, c.actualizado_en, c.enviado_en
      from public.comunicados c
     where p_despues is null or (c.actualizado_en, c.id) < (v_ts, p_despues)
     order by c.actualizado_en desc, c.id desc
     limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'asunto', p.asunto, 'encabezado', p.encabezado, 'cuerpo', p.cuerpo, 'cta_url', p.cta_url,
           'cta_texto', p.cta_texto, 'creado_en', p.creado_en, 'actualizado_en', p.actualizado_en, 'enviado_en', p.enviado_en,
           'envios_ok', e.ok, 'envios_total', e.total) order by p.actualizado_en desc, p.id desc), '[]'::jsonb),
         count(*)::int,
         (array_agg(p.id order by p.actualizado_en, p.id))[1]
    into v_lista, v_n, v_ult
    from pag p
    cross join lateral (select count(*) filter (where x.estado = 'ok')::int as ok, count(*)::int as total
                          from public.comunicado_envios x
                         where x.comunicado_id = p.id and x.es_prueba = false) e;
  -- destinatarios: usuarios activos con email (el navegador filtraba los sin email); tope de 1000
  select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'nombre', u.nombre, 'email', u.email, 'rol', u.rol)
                            order by u.nombre, u.user_id), '[]'::jsonb), count(*)::int
    into v_usu, v_nusu
    from (select x.user_id, x.nombre, x.email, x.rol from public.usuarios x
           where x.activo = true and coalesce(x.email, '') <> ''
           order by x.nombre, x.user_id limit 1000) u;
  return jsonb_build_object(
    'comunicados', v_lista,
    'siguiente',   case when v_n = v_lim then v_ult end,
    'usuarios',    v_usu,
    'recortado',   case when v_nusu = 1000 then '["usuarios"]'::jsonb else '[]'::jsonb end);
end $$;

-- Un comunicado abierto y su registro de envíos (también el sondeo de 4-20 s mientras hay algo en camino).
create or replace function public.comunicado_datos(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_com jsonb;
  v_env jsonb; v_nenv int;
begin
  if public.uid_sesion() is null then
    raise exception 'comunicado_datos: sin sesión' using errcode = '42501';
  end if;
  if not (public.es_admin() and public.puede('comunicacion')) then
    raise exception 'Los comunicados son de administración con la herramienta «Comunicación»' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'comunicado_datos: falta el comunicado' using errcode = '22023';
  end if;
  select jsonb_build_object('id', c.id, 'asunto', c.asunto, 'encabezado', c.encabezado, 'cuerpo', c.cuerpo,
                            'cta_url', c.cta_url, 'cta_texto', c.cta_texto, 'creado_en', c.creado_en,
                            'actualizado_en', c.actualizado_en, 'enviado_en', c.enviado_en)
    into v_com from public.comunicados c where c.id = p_id;
  -- una fila por destinatario y reintento: tope de 2000 (hoy el mayor tiene 31)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'user_id', e.user_id, 'email', e.email, 'nombre', e.nombre, 'es_prueba', e.es_prueba,
           'estado', e.estado, 'intentos', e.intentos, 'error', e.error, 'encolado_en', e.encolado_en,
           'enviado_en', e.enviado_en) order by e.encolado_en desc, e.id desc), '[]'::jsonb), count(*)::int
    into v_env, v_nenv
    from (select x.id, x.user_id, x.email, x.nombre, x.es_prueba, x.estado, x.intentos, x.error, x.encolado_en,
                 x.enviado_en
            from public.comunicado_envios x where x.comunicado_id = p_id
           order by x.encolado_en desc, x.id desc limit 2000) e;
  return jsonb_build_object(
    'comunicado', v_com,
    'envios',     case when v_com is null then '[]'::jsonb else v_env end,
    'recortado',  case when v_com is not null and v_nenv = 2000 then '["envios"]'::jsonb else '[]'::jsonb end);
end $$;

-- Solicitudes de alta de comerciales + proyectos activos para activarlas. /v4/usuarios/ (solicitudes.js).
create or replace function public.solicitudes_alta_datos(p_limit int default 60, p_despues uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 60), 1), 500);
  v_ts timestamptz;
  v_lista jsonb; v_n int; v_ult uuid;
  v_pro jsonb; v_npro int;
begin
  if public.uid_sesion() is null then
    raise exception 'solicitudes_alta_datos: sin sesión' using errcode = '42501';
  end if;
  if p_despues is not null then
    select s.creado_at into v_ts from public.solicitudes_colaborador s where s.id = p_despues;
    if v_ts is null then
      raise exception 'solicitudes_alta_datos: cursor desconocido' using errcode = '22023';
    end if;
  end if;
  with pag as (
    select s.id, s.email, s.nombre, s.telefono, s.pais, s.mensaje, s.estado, s.revisado_por, s.revisado_en, s.creado_at
      from public.solicitudes_colaborador s
     where p_despues is null or (s.creado_at, s.id) < (v_ts, p_despues)
     order by s.creado_at desc, s.id desc
     limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'email', p.email, 'nombre', p.nombre, 'telefono', p.telefono, 'pais', p.pais,
           'mensaje', p.mensaje, 'estado', p.estado, 'revisado_por', p.revisado_por, 'revisado_en', p.revisado_en,
           'creado_at', p.creado_at) order by p.creado_at desc, p.id desc), '[]'::jsonb),
         count(*)::int,
         (array_agg(p.id order by p.creado_at, p.id))[1]
    into v_lista, v_n, v_ult
    from pag p;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre) order by x.nombre, x.id), '[]'::jsonb),
         count(*)::int
    into v_pro, v_npro
    from (select p.id, p.nombre from public.proyectos p where p.activo = true order by p.nombre, p.id limit 1000) x;
  return jsonb_build_object(
    'solicitudes', v_lista,
    'siguiente',   case when v_n = v_lim then v_ult end,
    'proyectos',   v_pro,
    'recortado',   case when v_npro = 1000 then '["proyectos"]'::jsonb else '[]'::jsonb end);
end $$;

-- Contactos que traen los referidos. /v4/usuarios/ (solicitudes.js).
create or replace function public.referidos_datos(p_limit int default 100, p_despues uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_ts timestamptz;
  v_lista jsonb; v_n int; v_ult uuid;
begin
  if public.uid_sesion() is null then
    raise exception 'referidos_datos: sin sesión' using errcode = '42501';
  end if;
  if p_despues is not null then
    select r.creado_at into v_ts from public.referidos_contactos r where r.id = p_despues;
    if v_ts is null then
      raise exception 'referidos_datos: cursor desconocido' using errcode = '22023';
    end if;
  end if;
  with pag as (
    select r.id, r.referido_email, r.referido_nombre, r.referido_telefono, r.cliente_nombre, r.cliente_email,
           r.cliente_telefono, r.cliente_pais, r.interes, r.estado, r.creado_at
      from public.referidos_contactos r
     where p_despues is null or (r.creado_at, r.id) < (v_ts, p_despues)
     order by r.creado_at desc, r.id desc
     limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'referido_email', p.referido_email, 'referido_nombre', p.referido_nombre,
           'referido_telefono', p.referido_telefono, 'cliente_nombre', p.cliente_nombre, 'cliente_email', p.cliente_email,
           'cliente_telefono', p.cliente_telefono, 'cliente_pais', p.cliente_pais, 'interes', p.interes,
           'estado', p.estado, 'creado_at', p.creado_at) order by p.creado_at desc, p.id desc), '[]'::jsonb),
         count(*)::int,
         (array_agg(p.id order by p.creado_at, p.id))[1]
    into v_lista, v_n, v_ult
    from pag p;
  return jsonb_build_object(
    'referidos', v_lista,
    'siguiente', case when v_n = v_lim then v_ult end);
end $$;

-- Reasignar autor (contracts/assets/autoria.js, super admin): equipo activo + último cambio de autor de esa fila.
create or replace function public.autoria_datos(p_tabla text, p_fila uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_eq jsonb; v_neq int;
  v_ult jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'autoria_datos: sin sesión' using errcode = '42501';
  end if;
  if p_tabla is null or p_fila is null then
    raise exception 'autoria_datos: falta la tabla o la fila' using errcode = '22023';
  end if;
  -- solo activos: reasigna_autor rechaza una cuenta desactivada
  select coalesce(jsonb_agg(jsonb_build_object('email', x.email, 'nombre', x.nombre, 'activo', x.activo)
                            order by x.email, x.user_id), '[]'::jsonb), count(*)::int
    into v_eq, v_neq
    from (select u.user_id, u.email, u.nombre, u.activo from public.usuarios u where u.activo = true
           order by u.email, u.user_id limit 1000) x;
  select jsonb_build_object('valor_anterior', c.valor_anterior, 'valor_nuevo', c.valor_nuevo, 'motivo', c.motivo,
                            'corregido_en', c.corregido_en, 'corregido_por', c.corregido_por)
    into v_ult
    from public.correcciones_datos c
   where c.tabla = p_tabla and c.fila_id = p_fila and c.campo = 'creado_por'
   order by c.corregido_en desc, c.id desc
   limit 1;
  return jsonb_build_object(
    'equipo',    v_eq,
    'ultimo',    v_ult,
    'recortado', case when v_neq = 1000 then '["equipo"]'::jsonb else '[]'::jsonb end);
end $$;

-- Diseño compartido de una plantilla de contrato (contracts/assets/documento_diseno.js).
create or replace function public.contrato_diseno_datos(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_d jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'contrato_diseno_datos: sin sesión' using errcode = '42501';
  end if;
  if p_slug is null or btrim(p_slug) = '' then
    raise exception 'contrato_diseno_datos: falta la plantilla' using errcode = '22023';
  end if;
  select d.design into v_d from public.contratos_diseno d where d.slug = p_slug;
  return jsonb_build_object('design', v_d);
end $$;

-- ── Dueño lector, permisos y comprobación en la misma migración ──────────────────────────────────────────────

grant create on schema public to lw_lector;
alter function public.mantenimiento_datos() owner to lw_lector;
alter function public.comunicacion_datos(integer,uuid) owner to lw_lector;
alter function public.comunicado_datos(uuid) owner to lw_lector;
alter function public.solicitudes_alta_datos(integer,uuid) owner to lw_lector;
alter function public.referidos_datos(integer,uuid) owner to lw_lector;
alter function public.autoria_datos(text,uuid) owner to lw_lector;
alter function public.contrato_diseno_datos(text) owner to lw_lector;
-- dossier_datos (27-sep, anterior a LAW-338) nació con dueño postgres = BYPASSRLS: pasa al lector. Único llamador:
-- intranet/dossier/builder.html (navegador). Ninguna edge, cron ni PHP la llama: fuera service_role.
alter function public.dossier_datos(uuid,uuid[]) owner to lw_lector;
revoke create on schema public from lw_lector;

revoke all on function public.mantenimiento_datos() from public, anon, service_role;
revoke all on function public.comunicacion_datos(integer,uuid) from public, anon, service_role;
revoke all on function public.comunicado_datos(uuid) from public, anon, service_role;
revoke all on function public.solicitudes_alta_datos(integer,uuid) from public, anon, service_role;
revoke all on function public.referidos_datos(integer,uuid) from public, anon, service_role;
revoke all on function public.autoria_datos(text,uuid) from public, anon, service_role;
revoke all on function public.contrato_diseno_datos(text) from public, anon, service_role;
revoke all on function public.dossier_datos(uuid,uuid[]) from public, anon, service_role;
grant execute on function public.mantenimiento_datos() to authenticated;
grant execute on function public.comunicacion_datos(integer,uuid) to authenticated;
grant execute on function public.comunicado_datos(uuid) to authenticated;
grant execute on function public.solicitudes_alta_datos(integer,uuid) to authenticated;
grant execute on function public.referidos_datos(integer,uuid) to authenticated;
grant execute on function public.autoria_datos(text,uuid) to authenticated;
grant execute on function public.contrato_diseno_datos(text) to authenticated;
grant execute on function public.dossier_datos(uuid,uuid[]) to authenticated;

-- si el dueño, el proacl o el CREATE no cuadran, la migración no se aplica
do $chk$
declare f text; v_acl text; v_dueno text;
begin
  foreach f in array array['public.mantenimiento_datos()', 'public.comunicacion_datos(integer,uuid)', 'public.comunicado_datos(uuid)', 'public.solicitudes_alta_datos(integer,uuid)', 'public.referidos_datos(integer,uuid)', 'public.autoria_datos(text,uuid)', 'public.contrato_diseno_datos(text)', 'public.dossier_datos(uuid,uuid[])'] loop
    select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno from pg_proc p where p.oid = f::regprocedure;
    if v_dueno <> 'lw_lector' then raise exception '%: dueño % (esperado lw_lector)', f, v_dueno; end if;
    if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
      raise exception '%: proacl % (esperado lw_lector + authenticated)', f, v_acl;
    end if;
  end loop;
  if has_schema_privilege('lw_lector', 'public', 'create') then raise exception 'lw_lector conserva CREATE en public'; end if;
end $chk$;
