-- LAW-338 L2, tanda 2 — lecturas por el servidor de 3 pantallas (entities.js, panel de gastos, creatividades).
-- erp-ok: B10 a la par (Lawang independiente, owner 28-sep)
-- Pareja de contrato: maestro erp/migraciones/20260928190000_b10a_l2_tanda2.sql (dueño erp_lector), con apoderados_datos,
-- firmantes_datos, gastos_panel_datos y gasto_historial_datos de cuerpo IDÉNTICO. creatividades_datos, creatividad_datos y
-- bloque_legal_datos son «solo Lawang» (el maestro no tiene esas tablas) y así se declaran en FORMAS_DATOS.
-- Encargo: encargos/20260927_erp_b10_lecturas_a_la_par.md (Bitácora 28-sep, L2 tanda 2).
--  · Aditiva: create function + dueño + grants. NINGÚN revoke de tabla: van en su propia migración cuando producción
--    sirva el front que llama a estas RPC (orden seguro: RPC → front → curl del asset servido → revoke).
--  · Paridad medida ANTES de aplicar, en transacción revertida, con los usuarios de auth.users: count+md5 por lista de la
--    RPC (como lw_lector) contra la lectura directa como authenticated.
--    Medido el 28-sep: 66 usuarios, 1.875 llamadas, 0 distintas (incluye cursores recorridos de 7 en 7 y de 3 en 3 == lista
--    entera, creatividad_datos de las 20 filas también las que la policy esconde → null, bloque legal es/en/fr). Gastos:
--    42501 en 63 usuarios, todos con 0 filas directas en gastos/proveedores/categorías/log. Sin sesión: 42501 en las 7.
-- ── Cuerpos A LA PAR (idénticos en Lawang y en el maestro; el dueño lo pone cada migración) ────────────────────────

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
                            order by a.orden, a.clave), '[]'::jsonb), count(*)::int
    into v_lista, v_n
    from (select x.clave, x.edad, x.ocupacion, x.direccion, x.nik, x.ktp, x.orden
            from public.apoderados_hak_sewa x
           where x.activo = true
           order by x.orden, x.clave limit 200) a;
  return jsonb_build_object('apoderados', v_lista,
                            'recortado', case when v_n = 200 then '["apoderados"]'::jsonb else '[]'::jsonb end);
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
                            order by f.nombre), '[]'::jsonb), count(*)::int
    into v_lista, v_n
    from (select x.nombre, x.rep_npwp, x.cred_es, x.cred_en, x.cred_id
            from public.firmantes_cred x order by x.nombre limit 200) f;
  return jsonb_build_object('firmantes', v_lista,
                            'recortado', case when v_n = 200 then '["firmantes"]'::jsonb else '[]'::jsonb end);
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
                                               'notas', x.notas, 'activo', x.activo) order by x.nombre, x.id), '[]'::jsonb),
         count(*)::int
    into v_prov, v_nprov
    from (select p.id, p.nombre, p.tipo, p.npwp, p.contacto, p.email, p.telefono, p.notas, p.activo
            from public.proveedores p order by p.nombre, p.id limit 2000) x;
  select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo, 'orden', x.orden,
                                               'activa', x.activa) order by x.orden, x.clave), '[]'::jsonb), count(*)::int
    into v_cat, v_ncat
    from (select c.clave, c.nombre, c.grupo, c.orden, c.activa
            from public.gasto_categorias c order by c.orden, c.clave limit 500) x;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre, 'activo', x.activo)
                            order by x.nombre, x.id), '[]'::jsonb), count(*)::int
    into v_pro, v_npro
    from (select p.id, p.nombre, p.activo from public.proyectos p order by p.nombre, p.id limit 1000) x;
  select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'label', x.label, 'banco', x.banco, 'titular', x.titular,
                                               'es_escrow', x.es_escrow, 'es_propia', x.es_propia, 'activa', x.activa)
                            order by x.orden, x.clave), '[]'::jsonb), count(*)::int
    into v_cue, v_ncue
    from (select c.clave, c.label, c.banco, c.titular, c.es_escrow, c.es_propia, c.activa, c.orden
            from public.cuentas_bancarias c order by c.orden, c.clave limit 200) x;
  -- nombres para el historial (quién hizo cada cambio); la RLS de usuarios decide a quién ve
  select coalesce(jsonb_agg(jsonb_build_object('user_id', x.user_id, 'nombre', x.nombre, 'email', x.email)
                            order by x.nombre, x.user_id), '[]'::jsonb), count(*)::int
    into v_usu, v_nusu
    from (select u.user_id, u.nombre, u.email from public.usuarios u order by u.nombre, u.user_id limit 2000) x;
  if v_nprov = 2000 then v_rec := v_rec || '["proveedores"]'::jsonb; end if;
  if v_ncat = 500 then v_rec := v_rec || '["categorias"]'::jsonb; end if;
  if v_npro = 1000 then v_rec := v_rec || '["proyectos"]'::jsonb; end if;
  if v_ncue = 200 then v_rec := v_rec || '["cuentas"]'::jsonb; end if;
  if v_nusu = 2000 then v_rec := v_rec || '["usuarios"]'::jsonb; end if;
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

-- Historial de un gasto (cajón de la ficha). Mismo gate que el panel, en voz alta.
create or replace function public.gasto_historial_datos(p_gasto uuid, p_limit int default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 8), 1), 50);
  v_lista jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'gasto_historial_datos: sin sesión' using errcode = '42501';
  end if;
  if not (public.es_admin() and public.puede('gastos')) then
    raise exception 'Los gastos son de administración con la herramienta «Gastos»' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('accion', x.accion, 'quien', x.quien, 'cuando', x.cuando,
                                               'antes', x.antes, 'despues', x.despues) order by x.cuando desc, x.id desc),
                  '[]'::jsonb)
    into v_lista
    from (select l.id, l.accion, l.quien, l.cuando, l.antes, l.despues
            from public.gastos_log l where l.gasto_id = p_gasto
           order by l.cuando desc, l.id desc limit v_lim) x;
  return jsonb_build_object('historial', v_lista);
end $$;
-- ── Solo Lawang (el maestro no tiene creatividades ni bloques_legales): se declaran «solo Lawang» en FORMAS_DATOS ──

-- Biblioteca de creatividades (/v4/creatividades/, creatividades.js → listar). La visibilidad la decide la policy
-- (creatividad_puede_ver), que el dueño lector hereda. `creado_en` no cambia nunca: releerlo en el cursor es estable.
create or replace function public.creatividades_datos(p_tipo text default null, p_estado text default null,
                                                      p_proyecto_id uuid default null, p_limit int default 500,
                                                      p_despues uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim int := least(greatest(coalesce(p_limit, 500), 1), 500);
  v_ts timestamptz;
  v_lista jsonb; v_mas boolean; v_ult uuid;
begin
  if public.uid_sesion() is null then
    raise exception 'creatividades_datos: sin sesión' using errcode = '42501';
  end if;
  if p_despues is not null then
    select c.creado_en into v_ts from public.creatividades c where c.id = p_despues;
    if v_ts is null then
      raise exception 'creatividades_datos: cursor desconocido' using errcode = '22023';
    end if;
  end if;
  with pag as (
    select c.id, c.tipo, c.titulo, c.proyecto_id, c.formato, c.arquetipo, c.estado, c.path, c.estado_path, c.portada_path,
           c.lleva_render, c.precios_a, c.origen, c.creado_por, c.creado_en, c.actualizado_en, c.enviada_por, c.enviada_en,
           c.aprobada_en, c.publicada_en, c.archivada_en,
           row_number() over (order by c.creado_en desc, c.id desc) as rn
      from public.creatividades c
     where (p_tipo is null or c.tipo = p_tipo)
       and (p_estado is null or c.estado = p_estado)
       and (p_proyecto_id is null or c.proyecto_id = p_proyecto_id)
       and (p_despues is null or (c.creado_en, c.id) < (v_ts, p_despues))
     order by c.creado_en desc, c.id desc
     limit v_lim + 1)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'tipo', p.tipo, 'titulo', p.titulo, 'proyecto_id', p.proyecto_id, 'formato', p.formato,
           'arquetipo', p.arquetipo, 'estado', p.estado, 'path', p.path, 'estado_path', p.estado_path,
           'portada_path', p.portada_path, 'lleva_render', p.lleva_render, 'precios_a', p.precios_a, 'origen', p.origen,
           'creado_por', p.creado_por, 'creado_en', p.creado_en, 'actualizado_en', p.actualizado_en,
           'enviada_por', p.enviada_por, 'enviada_en', p.enviada_en, 'aprobada_en', p.aprobada_en,
           'publicada_en', p.publicada_en, 'archivada_en', p.archivada_en) order by p.rn) filter (where p.rn <= v_lim),
           '[]'::jsonb),
         coalesce(bool_or(p.rn > v_lim), false),
         (array_agg(p.id order by p.rn desc) filter (where p.rn <= v_lim))[1]
    into v_lista, v_mas, v_ult
    from pag p;
  return jsonb_build_object('creatividades', v_lista, 'siguiente', case when v_mas then v_ult end);
end $$;

-- Una creatividad (abrir en el editor de redes o en el dossier). null = no existe o la policy no te la deja ver: la
-- pantalla lo dice (antes `.single()` daba el mismo error para los dos casos).
create or replace function public.creatividad_datos(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'creatividad_datos: sin sesión' using errcode = '42501';
  end if;
  select jsonb_build_object(
           'id', c.id, 'tipo', c.tipo, 'titulo', c.titulo, 'proyecto_id', c.proyecto_id, 'formato', c.formato,
           'arquetipo', c.arquetipo, 'estado', c.estado, 'path', c.path, 'estado_path', c.estado_path,
           'portada_path', c.portada_path, 'lleva_render', c.lleva_render, 'precios_a', c.precios_a, 'origen', c.origen,
           'creado_por', c.creado_por, 'creado_en', c.creado_en, 'actualizado_en', c.actualizado_en,
           'enviada_por', c.enviada_por, 'enviada_en', c.enviada_en, 'aprobada_en', c.aprobada_en,
           'publicada_en', c.publicada_en, 'archivada_en', c.archivada_en)
    into v
    from public.creatividades c where c.id = p_id;
  return jsonb_build_object('creatividad', v);
end $$;

-- Bloque fijo de Legal (p. ej. «Cómo se compra» del dossier): la última versión en ese idioma. null = no hay.
create or replace function public.bloque_legal_datos(p_clave text, p_idioma text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'bloque_legal_datos: sin sesión' using errcode = '42501';
  end if;
  select jsonb_build_object('texto', b.texto, 'version', b.version, 'estado', b.estado)
    into v
    from public.bloques_legales b
   where b.clave = p_clave and b.idioma = case when p_idioma = 'es' then 'es' else 'en' end
   order by b.version desc limit 1;
  return jsonb_build_object('bloque', v);
end $$;

-- ── Dueño lector (hereda la RLS de quien llama: nunca postgres), fuera PUBLIC/anon/service_role, EXECUTE authenticated ─
-- Llamadores con nombre (§1.ter): apoderados/firmantes → contracts/assets/entities.js (navegador); gastos_panel/
-- gasto_historial → intranet/v4/assets/panel-gastos.js; creatividades/creatividad/bloque_legal → contracts/assets/
-- creatividades.js (v4/creatividades, creatividades/redes, dossier/builder). Ninguna edge, cron ni PHP: fuera service_role.
grant create on schema public to lw_lector;
alter function public.apoderados_datos() owner to lw_lector;
alter function public.firmantes_datos() owner to lw_lector;
alter function public.gastos_panel_datos(integer,date,uuid) owner to lw_lector;
alter function public.gasto_historial_datos(uuid,integer) owner to lw_lector;
alter function public.creatividades_datos(text,text,uuid,integer,uuid) owner to lw_lector;
alter function public.creatividad_datos(uuid) owner to lw_lector;
alter function public.bloque_legal_datos(text,text) owner to lw_lector;
revoke create on schema public from lw_lector;

revoke all on function public.apoderados_datos() from public, anon, service_role;
revoke all on function public.firmantes_datos() from public, anon, service_role;
revoke all on function public.gastos_panel_datos(integer,date,uuid) from public, anon, service_role;
revoke all on function public.gasto_historial_datos(uuid,integer) from public, anon, service_role;
revoke all on function public.creatividades_datos(text,text,uuid,integer,uuid) from public, anon, service_role;
revoke all on function public.creatividad_datos(uuid) from public, anon, service_role;
revoke all on function public.bloque_legal_datos(text,text) from public, anon, service_role;
grant execute on function public.apoderados_datos() to authenticated;
grant execute on function public.firmantes_datos() to authenticated;
grant execute on function public.gastos_panel_datos(integer,date,uuid) to authenticated;
grant execute on function public.gasto_historial_datos(uuid,integer) to authenticated;
grant execute on function public.creatividades_datos(text,text,uuid,integer,uuid) to authenticated;
grant execute on function public.creatividad_datos(uuid) to authenticated;
grant execute on function public.bloque_legal_datos(text,text) to authenticated;

-- si el dueño, el proacl o el CREATE no cuadran, la migración no se aplica
do $chk$
declare f text; v_acl text; v_dueno text;
begin
  foreach f in array array['public.apoderados_datos()', 'public.firmantes_datos()', 'public.gastos_panel_datos(integer,date,uuid)', 'public.gasto_historial_datos(uuid,integer)', 'public.creatividades_datos(text,text,uuid,integer,uuid)', 'public.creatividad_datos(uuid)', 'public.bloque_legal_datos(text,text)'] loop
    select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno from pg_proc p where p.oid = f::regprocedure;
    if v_dueno <> 'lw_lector' then raise exception '%: dueño % (esperado lw_lector)', f, v_dueno; end if;
    if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
      raise exception '%: proacl % (esperado lw_lector + authenticated)', f, v_acl;
    end if;
  end loop;
  if has_schema_privilege('lw_lector', 'public', 'create') then raise exception 'lw_lector conserva CREATE en public'; end if;
end $chk$;
