-- LAW-338 L2 — ajustes de revisión a 20260927232020_law338_l2_pantallas. A la par con el maestro.
-- erp-ok: B10 a la par (decisión del owner 27-sep: cada *_datos nace en las dos bases con el mismo cuerpo)
-- Pareja: maestro erp/migraciones/20260928131000_b10a_l2_ajustes.sql (dueño erp_lector). Cuerpos IDÉNTICOS.
-- Encargo: encargos/20260927_erp_b10_lecturas_a_la_par.md (Bitácora 28-sep, L2). Hallazgos de code-review sobre la
-- primera migración de L2, antes de aterrizar (el front que llama a estas RPC aún no está en producción):
--  · autoria_datos nacía abierta a cualquier sesión: ahora super_admin y solo contratos/facturas (como reasigna_autor).
--  · solicitudes_alta_datos y referidos_datos devolvían lista vacía sin permiso: ahora 42501 en voz alta, con el mismo
--    gate que su policy (es_admin() and puede('usuarios')).
--  · comunicacion_datos: su cursor relee el actualizado_en de la fila (inestable si se edita entre páginas). NO se
--    arregla aquí: cambia la firma y el drop es parada del owner; ninguna pantalla pagina esa lista. Fila en pendientes.
--  · `siguiente` solo cuando de verdad hay otra página (se pide una fila de más).

-- ── Cuerpos corregidos (IDÉNTICOS en Lawang y en el maestro) ──────────────────────────────────────────────────────

-- comunicacion_datos: `siguiente` solo cuando hay otra página. OJO (pendiente, no arreglado aquí): el cursor relee el
-- actualizado_en de su fila; si esa fila se edita entre páginas, la paginación vuelve arriba, y si se borra da 22023.
-- Arreglarlo cambia la firma (drop = parada del owner); hoy ninguna pantalla pagina esta lista (enseña las 100 últimas).
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
  v_lista jsonb; v_mas boolean; v_ult uuid;
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
  -- orden de la pantalla (actualizado_en desc) con el id de desempate; se pide una fila de más para saber si hay otra
  -- página (sin ella, una página justa de v_lim anunciaba una siguiente vacía)
  with pag as (
    select c.id, c.asunto, c.encabezado, c.cuerpo, c.cta_url, c.cta_texto, c.creado_en, c.actualizado_en, c.enviado_en,
           row_number() over (order by c.actualizado_en desc, c.id desc) as rn
      from public.comunicados c
     where p_despues is null or (c.actualizado_en, c.id) < (v_ts, p_despues)
     order by c.actualizado_en desc, c.id desc
     limit v_lim + 1)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'asunto', p.asunto, 'encabezado', p.encabezado, 'cuerpo', p.cuerpo, 'cta_url', p.cta_url,
           'cta_texto', p.cta_texto, 'creado_en', p.creado_en, 'actualizado_en', p.actualizado_en, 'enviado_en', p.enviado_en,
           'envios_ok', e.ok, 'envios_total', e.total) order by p.rn) filter (where p.rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(p.rn > v_lim), false),
         (array_agg(p.id order by p.rn desc) filter (where p.rn <= v_lim))[1]
    into v_lista, v_mas, v_ult
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
    'siguiente',   case when v_mas then v_ult end,
    'usuarios',    v_usu,
    'recortado',   case when v_nusu = 1000 then '["usuarios"]'::jsonb else '[]'::jsonb end);
end $$;

-- Solicitudes de alta: ahora exige lo mismo que su policy y lo dice en voz alta (42501), en vez de una lista vacía que
-- esconde solicitudes esperando; y `siguiente` solo si de verdad hay otra página.
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
  v_lista jsonb; v_mas boolean; v_ult uuid;
  v_pro jsonb; v_npro int;
begin
  if public.uid_sesion() is null then
    raise exception 'solicitudes_alta_datos: sin sesión' using errcode = '42501';
  end if;
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'Las solicitudes de alta son de administración con la herramienta «Usuarios»' using errcode = '42501';
  end if;
  if p_despues is not null then
    -- creado_at no cambia nunca: releerlo es estable
    select s.creado_at into v_ts from public.solicitudes_colaborador s where s.id = p_despues;
    if v_ts is null then
      raise exception 'solicitudes_alta_datos: cursor desconocido' using errcode = '22023';
    end if;
  end if;
  with pag as (
    select s.id, s.email, s.nombre, s.telefono, s.pais, s.mensaje, s.estado, s.revisado_por, s.revisado_en, s.creado_at,
           row_number() over (order by s.creado_at desc, s.id desc) as rn
      from public.solicitudes_colaborador s
     where p_despues is null or (s.creado_at, s.id) < (v_ts, p_despues)
     order by s.creado_at desc, s.id desc
     limit v_lim + 1)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'email', p.email, 'nombre', p.nombre, 'telefono', p.telefono, 'pais', p.pais,
           'mensaje', p.mensaje, 'estado', p.estado, 'revisado_por', p.revisado_por, 'revisado_en', p.revisado_en,
           'creado_at', p.creado_at) order by p.rn) filter (where p.rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(p.rn > v_lim), false),
         (array_agg(p.id order by p.rn desc) filter (where p.rn <= v_lim))[1]
    into v_lista, v_mas, v_ult
    from pag p;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre) order by x.nombre, x.id), '[]'::jsonb),
         count(*)::int
    into v_pro, v_npro
    from (select p.id, p.nombre from public.proyectos p where p.activo = true order by p.nombre, p.id limit 1000) x;
  return jsonb_build_object(
    'solicitudes', v_lista,
    'siguiente',   case when v_mas then v_ult end,
    'proyectos',   v_pro,
    'recortado',   case when v_npro = 1000 then '["proyectos"]'::jsonb else '[]'::jsonb end);
end $$;

-- Referidos: mismo gate que su policy, en voz alta; `siguiente` solo si hay otra página.
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
  v_lista jsonb; v_mas boolean; v_ult uuid;
begin
  if public.uid_sesion() is null then
    raise exception 'referidos_datos: sin sesión' using errcode = '42501';
  end if;
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'Los contactos de referidos son de administración con la herramienta «Usuarios»' using errcode = '42501';
  end if;
  if p_despues is not null then
    select r.creado_at into v_ts from public.referidos_contactos r where r.id = p_despues;
    if v_ts is null then
      raise exception 'referidos_datos: cursor desconocido' using errcode = '22023';
    end if;
  end if;
  with pag as (
    select r.id, r.referido_email, r.referido_nombre, r.referido_telefono, r.cliente_nombre, r.cliente_email,
           r.cliente_telefono, r.cliente_pais, r.interes, r.estado, r.creado_at,
           row_number() over (order by r.creado_at desc, r.id desc) as rn
      from public.referidos_contactos r
     where p_despues is null or (r.creado_at, r.id) < (v_ts, p_despues)
     order by r.creado_at desc, r.id desc
     limit v_lim + 1)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'referido_email', p.referido_email, 'referido_nombre', p.referido_nombre,
           'referido_telefono', p.referido_telefono, 'cliente_nombre', p.cliente_nombre, 'cliente_email', p.cliente_email,
           'cliente_telefono', p.cliente_telefono, 'cliente_pais', p.cliente_pais, 'interes', p.interes,
           'estado', p.estado, 'creado_at', p.creado_at) order by p.rn) filter (where p.rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(p.rn > v_lim), false),
         (array_agg(p.id order by p.rn desc) filter (where p.rn <= v_lim))[1]
    into v_lista, v_mas, v_ult
    from pag p;
  return jsonb_build_object(
    'referidos', v_lista,
    'siguiente', case when v_mas then v_ult end);
end $$;

-- Reasignar autor: nace cerrada como su única escritura (reasigna_autor): super_admin y solo contratos/facturas.
-- Antes cualquier sesión podía pedir el equipo activo entero y el rastro de cualquier tabla que su RLS le dejara ver.
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
  if not public.es_super_admin() then
    raise exception 'Reasignar el autor es solo de super admin' using errcode = '42501';
  end if;
  if p_tabla is null or p_tabla not in ('contratos', 'facturas') or p_fila is null then
    raise exception 'autoria_datos: solo contratos o facturas, con su fila' using errcode = '22023';
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

-- ── create or replace conserva dueño y permisos: se comprueba ─────────────────────────────────────────────────
do $chk$
declare f text; v_acl text; v_dueno text;
begin
  foreach f in array array['public.comunicacion_datos(integer,uuid)', 'public.solicitudes_alta_datos(integer,uuid)', 'public.referidos_datos(integer,uuid)', 'public.autoria_datos(text,uuid)'] loop
    select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno from pg_proc p where p.oid = f::regprocedure;
    if v_dueno <> 'lw_lector' then raise exception '%: dueño % (esperado lw_lector)', f, v_dueno; end if;
    if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
      raise exception '%: proacl % (esperado lw_lector + authenticated)', f, v_acl;
    end if;
  end loop;
  if has_schema_privilege('lw_lector', 'public', 'create') then raise exception 'lw_lector conserva CREATE en public'; end if;
end $chk$;
