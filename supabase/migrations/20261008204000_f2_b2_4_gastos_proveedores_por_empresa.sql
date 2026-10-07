-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 4 (8-oct-2026): GASTOS Y PROVEEDORES POR EMPRESA.
--   Un gasto no tiene proyecto ni contrato obligatorios: su empresa sale de su proyecto si lo tiene, y si no, de la empresa cuya sociedad es la del gasto (empresas.sociedad_clave).
--   Una sociedad sin empresa (sandal_woods_ltd) o un gasto sin ninguna de las dos = sin empresa = solo admin/super global. Las tablas gastos, proveedores y bancos estan VACIAS: no hay nada que rellenar.
--   proveedores.empresa (migracion 1): un rol de empresa crea siempre el proveedor en su empresa (en el servidor; con dos empresas elige una de las suyas) y no toca los de otra ni los globales.
--   Un rol restringido solo registra gastos con la sociedad de su empresa, sobre proyectos de su empresa, con proveedores de esa empresa y pagados desde cuentas de esa empresa.
--   Coherencia con los 34 de hoy: la puerta GRUESA (_gasto_puede) sigue siendo «admin con la casilla Gastos» para ellos, y todas las funciones conservan el orden de errores de antes
--   (gate -> existe? -> estado) para que el sqlstate de cada llamada no cambie; la puerta FINA por empresa va despues de leer la fila.
--   Policies: gastos, gastos_log, proveedores, gasto_categorias (catalogo compartido, sin RPC de escritura: se lee con la casilla) y el bucket de justificantes `gastos`.
--   La lista de proveedores/proyectos/cuentas que devuelve gastos_panel_datos tambien se filtra por empresa.
-- destructivo-ok: create or replace de funciones y alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql

create or replace function public._gasto_puede() returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_herr_admin('gastos')
$$;

create or replace function public.gasto_guarda(p_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $function$
declare
  v_id uuid; v_estado text;
  v_base numeric := public._gasto_importe(p_datos->'base');
  v_imp numeric := coalesce(public._gasto_importe(p_datos->'impuesto'), 0);
  v_pph numeric := coalesce(public._gasto_importe(p_datos->'pph_retenido'), 0);
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_soc text := p_datos->>'sociedad';
  v_proy uuid := nullif(p_datos->>'proyecto_id', '')::uuid;
  v_prov uuid := nullif(p_datos->>'proveedor_id', '')::uuid;
  v_emp text; v_old public.gastos%rowtype; v_cuenta text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if v_base is null then raise exception 'La base no es un importe válido' using errcode = '22023'; end if;
  v_emp := public._empresa_gasto(v_soc, v_proy);
  if p_id is not null then
    select * into v_old from public.gastos g where g.id = p_id;
    if found and not public._puede_admin_de(public._empresa_gasto(v_old.sociedad, v_old.proyecto_id), 'gastos') then
      raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
    end if;
  end if;
  if not public._puede_admin_de(v_emp, 'gastos') then
    raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if v_rest then
    -- sociedad de SU empresa, proveedor de SU empresa, y (si ya se paga) cuenta de SU empresa
    if v_emp is null or not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = v_soc) then
      raise exception 'El gasto tiene que ir con la sociedad de la empresa del proyecto (o de tu empresa, si no lleva proyecto)' using errcode = '42501';
    end if;
    if v_prov is not null and not exists (select 1 from public.proveedores pv where pv.id = v_prov and pv.empresa = v_emp) then
      raise exception 'Ese proveedor no es de la empresa del gasto' using errcode = '42501';
    end if;
    v_cuenta := nullif(p_datos->>'cuenta_pago', '');
    if p_id is null and p_datos->>'estado' = 'pagado' and v_cuenta is not null and public._empresa_cuenta(v_cuenta) is distinct from v_emp then
      raise exception 'Esa cuenta no es de la empresa del gasto' using errcode = '42501';
    end if;
  end if;
  if p_id is null then
    v_estado := case when p_datos->>'estado' = 'pagado' then 'pagado' else 'pendiente' end;
    insert into public.gastos as g (sociedad, proyecto_id, proveedor_id, categoria, concepto, referencia, moneda,
        fecha, vence_el, base, impuesto, pph_tipo, pph_retenido, notas, estado, pagado_el, cuenta_pago)
    values (p_datos->>'sociedad', nullif(p_datos->>'proyecto_id', '')::uuid, nullif(p_datos->>'proveedor_id', '')::uuid,
        p_datos->>'categoria', p_datos->>'concepto', nullif(p_datos->>'referencia', ''), coalesce(nullif(p_datos->>'moneda', ''), 'EUR'),
        nullif(p_datos->>'fecha', '')::date, nullif(p_datos->>'vence_el', '')::date, v_base, v_imp,
        nullif(p_datos->>'pph_tipo', ''), v_pph, nullif(p_datos->>'notas', ''), v_estado,
        case when v_estado = 'pagado' then coalesce(nullif(p_datos->>'pagado_el', '')::date, current_date) end,
        case when v_estado = 'pagado' then nullif(p_datos->>'cuenta_pago', '') end)
    returning g.id into v_id;
    return v_id;
  end if;
  -- Edición: los datos del gasto; NUNCA estado, pago, justificantes ni anulación (tienen su RPC).
  update public.gastos g set
    sociedad = p_datos->>'sociedad', proyecto_id = nullif(p_datos->>'proyecto_id', '')::uuid,
    proveedor_id = nullif(p_datos->>'proveedor_id', '')::uuid, categoria = p_datos->>'categoria',
    concepto = p_datos->>'concepto', referencia = nullif(p_datos->>'referencia', ''),
    moneda = coalesce(nullif(p_datos->>'moneda', ''), 'EUR'), fecha = nullif(p_datos->>'fecha', '')::date,
    vence_el = nullif(p_datos->>'vence_el', '')::date, base = v_base, impuesto = v_imp,
    pph_tipo = nullif(p_datos->>'pph_tipo', ''), pph_retenido = v_pph, notas = nullif(p_datos->>'notas', '')
  where g.id = p_id
  returning g.id into v_id;
  if v_id is null then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
  return v_id;
end $function$;

create or replace function public.gasto_anula(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $function$
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then raise exception 'Anular un gasto exige un motivo' using errcode = '22023'; end if;
  if exists (select 1 from public.gastos g where g.id = p_id) and not public.gasto_id_visible(p_id) then
    raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
  end if;
  update public.gastos set estado = 'anulado', anulado_motivo = btrim(p_motivo) where id = p_id;
  if not found then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
end $function$;

create or replace function public.gasto_marca_pagado(p_id uuid, p_pagado_el date, p_cuenta text) returns void
language plpgsql security definer set search_path = '' as $function$
declare v_estado text; v_soc text; v_proy uuid; v_emp text;
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  select estado, sociedad, proyecto_id into v_estado, v_soc, v_proy from public.gastos where id = p_id for update;
  if not found then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
  v_emp := public._empresa_gasto(v_soc, v_proy);
  if not public._puede_admin_de(v_emp, 'gastos') then
    raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if v_estado <> 'pendiente' then raise exception 'Solo se marca pagado un gasto pendiente (este está %)', v_estado using errcode = '22023'; end if;
  if p_pagado_el is null then raise exception 'Falta la fecha de pago' using errcode = '22023'; end if;
  if public.alcance_restringido() and not public.es_admin()
     and nullif(btrim(coalesce(p_cuenta, '')), '') is not null
     and public._empresa_cuenta(nullif(btrim(coalesce(p_cuenta, '')), '')) is distinct from v_emp then
    raise exception 'Esa cuenta no es de la empresa del gasto' using errcode = '42501';
  end if;
  update public.gastos set estado = 'pagado', pagado_el = p_pagado_el, cuenta_pago = nullif(btrim(coalesce(p_cuenta, '')), '') where id = p_id;
end $function$;

create or replace function public.gasto_pph_ingresado(p_id uuid, p_fecha date) returns void
language plpgsql security definer set search_path = '' as $function$
declare v_pph numeric; v_soc text; v_proy uuid;
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  select pph_retenido, sociedad, proyecto_id into v_pph, v_soc, v_proy from public.gastos where id = p_id for update;
  if not found then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
  if not public._puede_admin_de(public._empresa_gasto(v_soc, v_proy), 'gastos') then
    raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if coalesce(v_pph, 0) <= 0 then raise exception 'Este gasto no tiene retención que ingresar' using errcode = '22023'; end if;
  if p_fecha is null then raise exception 'Falta la fecha del ingreso' using errcode = '22023'; end if;
  update public.gastos set pph_ingresado_el = p_fecha where id = p_id;
end $function$;

create or replace function public.gasto_anade_justificante(p_id uuid, p_ruta text, p_nombre text) returns void
language plpgsql security definer set search_path = '' as $function$
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if p_ruta is null or split_part(p_ruta, '/', 1) <> p_id::text then
    raise exception 'Ese justificante no es de este gasto' using errcode = '42501';
  end if;
  if exists (select 1 from public.gastos g where g.id = p_id) and not public.gasto_id_visible(p_id) then
    raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'gastos' and o.name = p_ruta) then
    raise exception 'El fichero no se ha subido: vuelve a intentarlo' using errcode = 'P0002';
  end if;
  update public.gastos g set justificantes = g.justificantes || jsonb_build_array(jsonb_build_object(
      'path', p_ruta, 'nombre', left(coalesce(nullif(btrim(p_nombre), ''), split_part(p_ruta, '/', 2)), 200), 'subido_en', now()))
  where g.id = p_id and not (g.justificantes @> jsonb_build_array(jsonb_build_object('path', p_ruta)));
end $function$;

create or replace function public.gasto_justificante_registra(p_uid uuid, p_gasto uuid, p_path text, p_nombre text) returns uuid
language plpgsql security definer set search_path = '' as $function$
declare v_estado text; v_soc text; v_proy uuid;
begin
  perform public._actua_como(p_uid);
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  select g.estado, g.sociedad, g.proyecto_id into v_estado, v_soc, v_proy from public.gastos g where g.id = p_gasto for update;
  if v_estado is null then raise exception 'Ese gasto ya no existe: recarga' using errcode = '22023'; end if;
  if not public._puede_admin_de(public._empresa_gasto(v_soc, v_proy), 'gastos') then
    raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if v_estado = 'anulado' then raise exception 'Ese gasto está anulado: no admite justificantes' using errcode = '22023'; end if;
  if p_path is null or p_path !~ ('^' || p_gasto::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp)$') then
    raise exception 'Ruta de justificante no válida' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'gastos' and o.name = p_path) then
    raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023';
  end if;
  update public.gastos g set justificantes = g.justificantes || jsonb_build_array(jsonb_build_object(
      'path', p_path, 'nombre', left(coalesce(nullif(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g')), ''), 'Justificante'), 200),
      'subido_en', now()))
   where g.id = p_gasto and not (g.justificantes @> jsonb_build_array(jsonb_build_object('path', p_path)));
  return p_gasto;
end $function$;

create or replace function public.gasto_historial_datos(p_gasto uuid, p_limit integer default 8) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_lim int := least(greatest(coalesce(p_limit, 8), 1), 50);
  v_lista jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'gasto_historial_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.gastos_acceso() then
    raise exception 'Los gastos son de administración con la herramienta «Gastos»' using errcode = '42501';
  end if;
  if exists (select 1 from public.gastos g where g.id = p_gasto) and not public.gasto_id_visible(p_gasto) then
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
end $function$;

create or replace function public.proveedor_guarda(p_id uuid, p_datos jsonb) returns uuid
language plpgsql security definer set search_path = '' as $function$
declare
  v_id uuid;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_mis text[]; v_emp text; v_old text; v_hay boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public._gasto_puede() then raise exception 'Proveedores exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if p_id is null then
    -- la empresa del proveedor nueva: la fija el servidor (la unica de quien tiene una; si tiene dos, una de las suyas). Un global puede dejarla vacia (proveedor global).
    if v_rest then
      select u.empresas into v_mis from public.usuarios u where u.user_id = (select auth.uid());
      v_emp := case when cardinality(v_mis) = 1 then v_mis[1] else nullif(btrim(coalesce(p_datos->>'empresa', '')), '') end;
      if v_emp is null or not (v_emp = any (v_mis)) then
        raise exception 'Elige la empresa del proveedor (una de las tuyas)' using errcode = '42501';
      end if;
    else
      v_emp := nullif(btrim(coalesce(p_datos->>'empresa', '')), '');
    end if;
    if not public._puede_admin_de(v_emp, 'gastos') then
      raise exception 'Proveedores exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
    end if;
    insert into public.proveedores as p (nombre, tipo, npwp, contacto, telefono, email, notas, empresa)
    values (btrim(coalesce(p_datos->>'nombre', '')), coalesce(nullif(p_datos->>'tipo', ''), 'proveedor'),
            nullif(btrim(coalesce(p_datos->>'npwp', '')), ''), nullif(btrim(coalesce(p_datos->>'contacto', '')), ''),
            nullif(btrim(coalesce(p_datos->>'telefono', '')), ''), nullif(btrim(coalesce(p_datos->>'email', '')), ''),
            nullif(btrim(coalesce(p_datos->>'notas', '')), ''), v_emp)
    returning p.id into v_id;
  else
    select pv.empresa, true into v_old, v_hay from public.proveedores pv where pv.id = p_id;
    if coalesce(v_hay, false) and not public._puede_admin_de(v_old, 'gastos') then
      raise exception 'Proveedores exige ser administrador con la herramienta «Gastos»' using errcode = '42501';
    end if;
    update public.proveedores p set
      nombre = btrim(coalesce(p_datos->>'nombre', '')), tipo = coalesce(nullif(p_datos->>'tipo', ''), p.tipo),
      npwp = nullif(btrim(coalesce(p_datos->>'npwp', '')), ''), contacto = nullif(btrim(coalesce(p_datos->>'contacto', '')), ''),
      telefono = nullif(btrim(coalesce(p_datos->>'telefono', '')), ''), email = nullif(btrim(coalesce(p_datos->>'email', '')), ''),
      notas = nullif(btrim(coalesce(p_datos->>'notas', '')), ''),
      activo = case when p_datos ? 'activo' then coalesce((p_datos->>'activo')::boolean, p.activo) else p.activo end
    where p.id = p_id returning p.id into v_id;
    if v_id is null then raise exception 'Ese proveedor ya no existe' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end $function$;

create or replace function public.gastos_panel_datos(p_limit integer default 1000, p_despues_fecha date default null, p_despues uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_lim int := least(greatest(coalesce(p_limit, 1000), 1), 5000);
  v_all boolean := public.es_admin();
  v_gastos jsonb; v_mas boolean; v_ult_f date; v_ult_id uuid;
  v_prov jsonb; v_nprov int; v_cat jsonb; v_ncat int; v_pro jsonb; v_npro int;
  v_cue jsonb; v_ncue int; v_usu jsonb; v_nusu int; v_rec jsonb := '[]'::jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'gastos_panel_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.gastos_acceso() then
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
     where (p_despues is null or (g.fecha, g.id) < (p_despues_fecha, p_despues))
       and (v_all or public.gasto_visible(g.sociedad, g.proyecto_id))
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
            from public.proveedores p
           where v_all or public.proveedor_visible(p.empresa)
           order by p.nombre, p.id limit 2001) x;
  select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'nombre', x.nombre, 'grupo', x.grupo, 'orden', x.orden,
                                               'activa', x.activa) order by x.orden, x.clave) filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
    into v_cat, v_ncat
    from (select c.clave, c.nombre, c.grupo, c.orden, c.activa, row_number() over (order by c.orden, c.clave) as rn
            from public.gasto_categorias c order by c.orden, c.clave limit 501) x;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'nombre', x.nombre, 'activo', x.activo)
                            order by x.nombre, x.id) filter (where x.rn <= 1000), '[]'::jsonb), count(*)::int
    into v_pro, v_npro
    from (select p.id, p.nombre, p.activo, row_number() over (order by p.nombre, p.id) as rn
            from public.proyectos p
           where v_all or p.id = any (public.mis_proyectos_admin_empresa())
           order by p.nombre, p.id limit 1001) x;
  select coalesce(jsonb_agg(jsonb_build_object('clave', x.clave, 'label', x.label, 'banco', x.banco, 'titular', x.titular,
                                               'es_escrow', x.es_escrow, 'es_propia', x.es_propia, 'activa', x.activa)
                            order by x.orden, x.clave) filter (where x.rn <= 200), '[]'::jsonb), count(*)::int
    into v_cue, v_ncue
    from (select c.clave, c.label, c.banco, c.titular, c.es_escrow, c.es_propia, c.activa, c.orden,
                 row_number() over (order by c.orden, c.clave) as rn
            from public.cuentas_bancarias c
           where v_all or public.es_admin_de(c.empresa)
           order by c.orden, c.clave limit 201) x;
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
end $function$;

-- NOTA (hallazgo del A/B de la foto): gasto_historial_datos y gastos_panel_datos son propiedad de lw_lector (como todas las *_datos): corren con los permisos del lector y su RLS, y solo
--   pueden llamar a funciones con EXECUTE para lw_lector. Por eso usan el envoltorio gastos_acceso() y no la puerta privada _gasto_puede().
-- Policies de lectura. Para el admin global con la casilla son identicas a las de antes; el rol de empresa ve lo de su empresa.
alter policy "gastos: leer" on public.gastos
  using (public.gasto_visible(sociedad, proyecto_id));
alter policy "gastos_log: leer" on public.gastos_log
  using (public.gasto_id_visible(gasto_id));
alter policy "proveedores: leer" on public.proveedores
  using (public.proveedor_visible(empresa));
alter policy "categorias: leer" on public.gasto_categorias
  using (public.gastos_acceso());
alter policy "gastos: leer justificantes" on storage.objects
  using ((bucket_id = 'gastos'::text)
         and ((((select public.es_admin()) and (select public.puede('gastos'::text)))) or public.gasto_ruta_visible(name)));
