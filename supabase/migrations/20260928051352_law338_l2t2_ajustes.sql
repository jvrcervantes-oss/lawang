-- LAW-338 L2, tanda 2 — ajuste de code-review a 20260928045443_law338_l2_tanda2 (antes de publicar el front).
-- Pareja: maestro erp/migraciones/20260928196000_b10a_l2t2_ajustes.sql (dueño erp_lector). Cuerpos IDÉNTICOS.
--  · `recortado` se marcaba con EXACTAMENTE el tope (200 apoderados/firmantes, o 2000/500/1000/200/2000 en los catálogos
--    del panel de gastos), aunque no faltara nada; entities.js trata un catálogo recortado como error y el generador no
--    habría cargado. Ahora se pide una fila de más y solo se marca si de verdad existía.
-- ── Cuerpos corregidos A LA PAR (idénticos en Lawang y en el maestro) ─────────────────────────────────────────────

-- Apoderados del contrato Hak Sewa (entities.js → cargarApoderadosHakSewa). Datos personales de un particular (NIK, KTP):
-- la regla sigue en la policy (es_agente()), que el dueño lector hereda. Catálogo corto: tope fijo + `recortado`.
create or replace function public.apoderados_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lista jsonb; v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'apoderados_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('clave', a.clave, 'edad', a.edad, 'ocupacion', a.ocupacion,
                                               'direccion', a.direccion, 'nik', a.nik, 'ktp', a.ktp)
                            order by a.orden, a.clave) filter (where a.rn <= 200), '[]'::jsonb), count(*)::int
    into v_lista, v_n
    from (select x.clave, x.edad, x.ocupacion, x.direccion, x.nik, x.ktp, x.orden,
                 row_number() over (order by x.orden, x.clave) as rn
            from public.apoderados_hak_sewa x
           where x.activo = true
           order by x.orden, x.clave limit 201) a;
  return jsonb_build_object('apoderados', v_lista,
                            'recortado', case when v_n > 200 then '["apoderados"]'::jsonb else '[]'::jsonb end);
end $$;

-- Credenciales de los firmantes (entities.js → cargarFirmantesCred): el documento del representante que se imprime
-- en el contrato. Misma regla que la tabla (es_agente()).
create or replace function public.firmantes_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lista jsonb; v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'firmantes_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('nombre', f.nombre, 'rep_npwp', f.rep_npwp, 'cred_es', f.cred_es,
                                               'cred_en', f.cred_en, 'cred_id', f.cred_id)
                            order by f.nombre) filter (where f.rn <= 200), '[]'::jsonb), count(*)::int
    into v_lista, v_n
    from (select x.nombre, x.rep_npwp, x.cred_es, x.cred_en, x.cred_id, row_number() over (order by x.nombre) as rn
            from public.firmantes_cred x order by x.nombre limit 201) f;
  return jsonb_build_object('firmantes', v_lista,
                            'recortado', case when v_n > 200 then '["firmantes"]'::jsonb else '[]'::jsonb end);
end $$;

-- Panel de gastos (/v4/gastos/, panel-gastos.js): la carga entera en una llamada. Exige lo mismo que las policies de
-- gastos/proveedores/categorías (admin + herramienta «Gastos») y lo dice en voz alta (42501): la pantalla no puede
-- confundir «sin permiso» con «no hay gastos».
-- Cursor COMPUESTO (fecha, id), no un id que se relee: `fecha` se edita (gasto_guarda) y releerla haría la paginación
-- inestable (el defecto de LAW-397). Los catálogos solo viajan en la primera página.
create or replace function public.gastos_panel_datos(p_limit int default 1000, p_despues_fecha date default null,
                                                     p_despues uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 1000), 1), 5000);
  v_gastos jsonb; v_mas boolean; v_ult_f date; v_ult_id uuid;
  v_prov jsonb; v_nprov int; v_cat jsonb; v_ncat int; v_pro jsonb; v_npro int;
  v_cue jsonb; v_ncue int; v_usu jsonb; v_nusu int; v_rec jsonb := '[]'::jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'gastos_panel_datos: sin sesión' using errcode = '42501';
  end if;
  if not (public.es_admin() and public.puede('gastos')) then
    raise exception 'Los gastos son de administración con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if (p_despues is null) <> (p_despues_fecha is null) then
    raise exception 'gastos_panel_datos: el cursor lleva fecha e id juntos' using errcode = '22023';
  end if;
  with pag as (
    select g.id, g.sociedad, g.proyecto_id, g.proveedor_id, g.categoria, g.concepto, g.referencia, g.fecha, g.vence_el,
           g.base, g.impuesto, g.total, g.pph_retenido, g.pph_tipo, g.pph_ingresado_el, g.moneda, g.estado, g.pagado_el,
           g.cuenta_pago, g.justificantes, g.anulado_motivo, g.notas, g.creado_por, g.creado_en, g.actualizado_en,
           row_number() over (order by g.fecha desc, g.id desc) as rn
      from public.gastos g
     where p_despues is null or (g.fecha, g.id) < (p_despues_fecha, p_despues)
     order by g.fecha desc, g.id desc
     limit v_lim + 1)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'sociedad', p.sociedad, 'proyecto_id', p.proyecto_id, 'proveedor_id', p.proveedor_id,
           'categoria', p.categoria, 'concepto', p.concepto, 'referencia', p.referencia, 'fecha', p.fecha,
           'vence_el', p.vence_el, 'base', p.base, 'impuesto', p.impuesto, 'total', p.total,
           'pph_retenido', p.pph_retenido, 'pph_tipo', p.pph_tipo, 'pph_ingresado_el', p.pph_ingresado_el,
           'moneda', p.moneda, 'estado', p.estado, 'pagado_el', p.pagado_el, 'cuenta_pago', p.cuenta_pago,
           'justificantes', p.justificantes, 'anulado_motivo', p.anulado_motivo, 'notas', p.notas,
           'creado_por', p.creado_por, 'creado_en', p.creado_en, 'actualizado_en', p.actualizado_en)
           order by p.rn) filter (where p.rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(p.rn > v_lim), false),
         (array_agg(p.fecha order by p.rn desc) filter (where p.rn <= v_lim))[1],
         (array_agg(p.id order by p.rn desc) filter (where p.rn <= v_lim))[1]
    into v_gastos, v_mas, v_ult_f, v_ult_id
    from pag p;
  if p_despues is not null then
    return jsonb_build_object('gastos', v_gastos,
                              'siguiente', case when v_mas then jsonb_build_object('fecha', v_ult_f, 'id', v_ult_id) end);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre, 'tipo', x.tipo, 'npwp', x.npwp,
                                               'contacto', x.contacto, 'email', x.email, 'telefono', x.telefono,
                                               'notas', x.notas, 'activo', x.activo) order by x.nombre, x.id) filter (where x.rn <= 2000), '[]'::jsonb),
         count(*)::int
    into v_prov, v_nprov
    from (select p.id, p.nombre, p.tipo, p.npwp, p.contacto, p.email, p.telefono, p.notas, p.activo,
                 row_number() over (order by p.nombre, p.id) as rn
            from public.proveedores p order by p.nombre, p.id limit 2001) x;
  select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo, 'orden', x.orden,
                                               'activa', x.activa) order by x.orden, x.clave) filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
    into v_cat, v_ncat
    from (select c.clave, c.nombre, c.grupo, c.orden, c.activa, row_number() over (order by c.orden, c.clave) as rn
            from public.gasto_categorias c order by c.orden, c.clave limit 501) x;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre, 'activo', x.activo)
                            order by x.nombre, x.id) filter (where x.rn <= 1000), '[]'::jsonb), count(*)::int
    into v_pro, v_npro
    from (select p.id, p.nombre, p.activo, row_number() over (order by p.nombre, p.id) as rn
            from public.proyectos p order by p.nombre, p.id limit 1001) x;
  select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'label', x.label, 'banco', x.banco, 'titular', x.titular,
                                               'es_escrow', x.es_escrow, 'es_propia', x.es_propia, 'activa', x.activa)
                            order by x.orden, x.clave) filter (where x.rn <= 200), '[]'::jsonb), count(*)::int
    into v_cue, v_ncue
    from (select c.clave, c.label, c.banco, c.titular, c.es_escrow, c.es_propia, c.activa, c.orden,
                 row_number() over (order by c.orden, c.clave) as rn
            from public.cuentas_bancarias c order by c.orden, c.clave limit 201) x;
  -- nombres para el historial (quién hizo cada cambio); la RLS de usuarios decide a quién ve
  select coalesce(jsonb_agg(jsonb_build_object('user_id', x.user_id, 'nombre', x.nombre, 'email', x.email)
                            order by x.nombre, x.user_id) filter (where x.rn <= 2000), '[]'::jsonb), count(*)::int
    into v_usu, v_nusu
    from (select u.user_id, u.nombre, u.email, row_number() over (order by u.nombre, u.user_id) as rn
            from public.usuarios u order by u.nombre, u.user_id limit 2001) x;
  if v_nprov > 2000 then v_rec := v_rec || '["proveedores"]'::jsonb; end if;
  if v_ncat > 500 then v_rec := v_rec || '["categorias"]'::jsonb; end if;
  if v_npro > 1000 then v_rec := v_rec || '["proyectos"]'::jsonb; end if;
  if v_ncue > 200 then v_rec := v_rec || '["cuentas"]'::jsonb; end if;
  if v_nusu > 2000 then v_rec := v_rec || '["usuarios"]'::jsonb; end if;
  return jsonb_build_object(
    'gastos',      v_gastos,
    'siguiente',   case when v_mas then jsonb_build_object('fecha', v_ult_f, 'id', v_ult_id) end,
    'proveedores', v_prov,
    'categorias',  v_cat,
    'proyectos',   v_pro,
    'cuentas',     v_cue,
    'usuarios',    v_usu,
    'recortado',   v_rec);
end $$;


-- create or replace conserva dueño y grants; se comprueban igual (si no cuadran, no se aplica)
do $chk$
declare f text; v_acl text; v_dueno text;
begin
  foreach f in array array['public.apoderados_datos()', 'public.firmantes_datos()', 'public.gastos_panel_datos(integer,date,uuid)'] loop
    select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno from pg_proc p where p.oid = f::regprocedure;
    if v_dueno <> 'lw_lector' then raise exception '%: dueño % (esperado lw_lector)', f, v_dueno; end if;
    if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
      raise exception '%: proacl % (esperado lw_lector + authenticated)', f, v_acl;
    end if;
  end loop;
end $chk$;
