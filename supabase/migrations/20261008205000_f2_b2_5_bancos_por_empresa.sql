-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 5 (8-oct-2026): BANCOS (extractos y conciliacion) POR EMPRESA.
--   La empresa de un movimiento, de su perfil de importacion y de sus lineas de conciliacion es la de SU CUENTA (cuentas_bancarias.empresa, 2B). Una cuenta propia sin empresa
--   (sandalwoods_dbs, sandalwoods_dbs_sg, suite_sumbahills, sw_ltd_lux) y las de terceros: extractos solo para admin/super global. Las tablas de bancos estan vacias.
--   Un rol restringido (admin_empresa con la casilla Bancos, super_admin_empresa sin casilla) importa, concilia, ignora y ve SOLO movimientos de las cuentas de su empresa,
--   y solo puede conciliar un movimiento contra documentos (recibi, gasto, retencion, comision, traspaso) de esa misma empresa.
--   panel_bancos_datos / bancos_resumen devuelven solo lo de su empresa en todas sus listas (movimientos, perfiles, cuentas, recibis, gastos, comisiones).
--   _bancos_puerta() sigue siendo la puerta GRUESA (admin con la casilla; ahora tambien rol de empresa); la FINA por cuenta es _bancos_puerta_de(empresa), que se llama tras leer el movimiento/cuenta.
--   Los 34 de hoy: sin cambio (orden de errores igual que antes; lo prueba f2_foto_b2.sql).
--   panel_bancos_datos (como gastos_panel_datos) es propiedad de lw_lector: usa solo envoltorios con EXECUTE para lw_lector (bancos_acceso, banco_comision_visible, banco_cuenta_visible, gasto_visible).
-- destructivo-ok: create or replace de funciones, funciones nuevas, alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql

create or replace function public._bancos_puerta() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public._puede_herr_admin('bancos') then
    raise exception 'Hace falta ser admin y tener «Bancos» marcado en Usuarios.' using errcode = '42501';
  end if;
end $$;

create or replace function public._bancos_puerta_de(p_empresa text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public._puede_admin_de(p_empresa, 'bancos') then
    raise exception 'Hace falta ser admin y tener «Bancos» marcado en Usuarios.' using errcode = '42501';
  end if;
end $$;

create or replace function public._banco_ref_empresa(p_tipo text, p_ref uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case p_tipo
    when 'recibi'   then (select public._empresa_doc(f.proyecto_id, f.contrato_id) from public.facturas f where f.id = p_ref)
    when 'gasto'    then (select public._empresa_gasto(g.sociedad, g.proyecto_id) from public.gastos g where g.id = p_ref)
    when 'pph'      then (select public._empresa_gasto(g.sociedad, g.proyecto_id) from public.gastos g where g.id = p_ref)
    when 'comision' then public._empresa_comision(p_ref)
    when 'traspaso' then public._empresa_movimiento(p_ref)
  end $$;

revoke all on function public._bancos_puerta_de(text) from public, anon, authenticated, lw_lector;
revoke all on function public._banco_ref_empresa(text, uuid) from public, anon, authenticated, lw_lector;

-- panel_bancos_datos es propiedad de lw_lector (como las demas *_datos): corre con los permisos del lector y su RLS, y solo puede llamar a funciones con EXECUTE para lw_lector.
create or replace function public.bancos_acceso() returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_herr_admin('bancos') $$;

create or replace function public.banco_comision_visible(p_devengo uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin_de(public._empresa_comision(p_devengo)) $$;

revoke all on function public.bancos_acceso() from public, anon, authenticated, lw_lector;
revoke all on function public.banco_comision_visible(uuid) from public, anon, authenticated, lw_lector;
grant execute on function public.bancos_acceso() to lw_lector;
grant execute on function public.banco_comision_visible(uuid) to lw_lector;

create or replace function public.bancos_importar(p_cuenta text, p_fichero text, p_filas jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_imp uuid; v_leidas int; v_nuevas int;
begin
  perform public._bancos_puerta();
  perform public._bancos_puerta_de(public._empresa_cuenta(p_cuenta));
  perform public._bancos_cuenta_valida(p_cuenta);
  if jsonb_typeof(p_filas) <> 'array' then raise exception 'filas no es una lista' using errcode = '22023'; end if;
  v_leidas := jsonb_array_length(p_filas);
  if v_leidas = 0 then raise exception 'El extracto no trae movimientos.' using errcode = '22023'; end if;
  if v_leidas > 5000 then raise exception 'Máximo 5.000 movimientos por importación: divide el extracto por meses.' using errcode = '22023'; end if;
  insert into public.bancos_importaciones (cuenta_clave, fichero, filas_leidas, creado_por)
  values (p_cuenta, left(p_fichero, 200), v_leidas, (select auth.uid())) returning id into v_imp;
  with ins as (
    insert into public.bancos_movimientos (cuenta_clave, fecha, fecha_valor, concepto, referencia, importe, moneda, saldo, orden, huella, importacion_id)
    select p_cuenta, f.fecha, f.fecha_valor, left(f.concepto, 500), left(f.referencia, 200), f.importe, upper(f.moneda), f.saldo, coalesce(f.orden, 0),
           p_cuenta || ':' || f.huella, v_imp
      from jsonb_to_recordset(p_filas) as f(fecha date, fecha_valor date, concepto text, referencia text, importe numeric, moneda text, saldo numeric, orden int, huella text)
     where f.importe is not null and f.importe <> 0 and f.fecha is not null and f.huella is not null
    on conflict (huella) do nothing
    returning fecha
  )
  select count(*) into v_nuevas from ins;
  update public.bancos_importaciones i
     set nuevas = v_nuevas, duplicadas = v_leidas - v_nuevas,
         desde = (select min(m.fecha) from public.bancos_movimientos m where m.importacion_id = v_imp),
         hasta = (select max(m.fecha) from public.bancos_movimientos m where m.importacion_id = v_imp)
   where i.id = v_imp;
  return jsonb_build_object('importacion_id', v_imp, 'leidas', v_leidas, 'nuevas', v_nuevas, 'duplicadas', v_leidas - v_nuevas);
end $function$;

create or replace function public.bancos_conciliar(p_mov uuid, p_lineas jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare m record; l record; v_ya numeric; v_tope numeric; v_doc_ya numeric; v_mon text; v_estado text; v_otro record;
        v_rest boolean := public.alcance_restringido() and not public.es_admin(); v_emp text;
begin
  perform public._bancos_puerta();
  select * into m from public.bancos_movimientos where id = p_mov for update;
  if m.id is null then raise exception 'Movimiento no encontrado.' using errcode = 'P0002'; end if;
  v_emp := public._empresa_cuenta(m.cuenta_clave);
  perform public._bancos_puerta_de(v_emp);
  if m.ignorado_en is not null then raise exception 'Este movimiento está marcado como ignorado: quítale la marca antes de conciliarlo.' using errcode = '23514'; end if;
  for l in select * from jsonb_to_recordset(p_lineas) as x(tipo text, ref_id uuid, importe_mov numeric, importe_doc numeric, naturaleza text, nota text) loop
    if l.importe_mov is null or l.importe_mov = 0 or sign(l.importe_mov) <> sign(m.importe) then
      raise exception 'Cada línea lleva el mismo signo que el movimiento (entrada + / salida −).' using errcode = '23514';
    end if;
    select coalesce(sum(importe_mov), 0) into v_ya from public.bancos_conciliacion where movimiento_id = p_mov and anulado_en is null;
    if abs(v_ya + l.importe_mov) > abs(m.importe) + 0.005 then
      raise exception 'Las líneas suman más que el movimiento.' using errcode = '23514';
    end if;
    -- un rol restringido solo concilia contra documentos de la empresa de la cuenta
    if v_rest and l.tipo in ('recibi','gasto','pph','comision','traspaso')
       and public._banco_ref_empresa(l.tipo, l.ref_id) is distinct from v_emp then
      raise exception 'Ese documento no es de la empresa de esta cuenta.' using errcode = '42501';
    end if;
    v_tope := null; v_mon := null;
    if l.tipo = 'recibi' then
      if m.importe < 0 then raise exception 'Un recibí solo explica una ENTRADA.' using errcode = '23514'; end if;
      select total, coalesce(moneda, 'EUR') into v_tope, v_mon from public.facturas where id = l.ref_id and tipo = 'recibi' and not coalesce(anulada, false);
    elsif l.tipo = 'gasto' then
      if m.importe > 0 then raise exception 'Un gasto solo explica una SALIDA.' using errcode = '23514'; end if;
      select total - pph_retenido, moneda into v_tope, v_mon from public.gastos where id = l.ref_id and estado = 'pagado';
    elsif l.tipo = 'pph' then
      if m.importe > 0 then raise exception 'Una retención ingresada solo explica una SALIDA.' using errcode = '23514'; end if;
      select pph_retenido, moneda into v_tope, v_mon from public.gastos where id = l.ref_id and pph_retenido > 0 and pph_ingresado_el is not null and estado <> 'anulado';
    elsif l.tipo = 'comision' then
      if m.importe > 0 then raise exception 'Una comisión pagada solo explica una SALIDA.' using errcode = '23514'; end if;
      select coalesce(importe_ajustado, importe), moneda into v_tope, v_mon from public.comisiones_devengadas where id = l.ref_id and estado = 'pagada';
    elsif l.tipo = 'traspaso' then
      select * into v_otro from public.bancos_movimientos where id = l.ref_id;
      if v_otro.id is null or v_otro.cuenta_clave = m.cuenta_clave or sign(v_otro.importe) = sign(m.importe) then
        raise exception 'Un traspaso enlaza con un movimiento de SIGNO CONTRARIO en OTRA cuenta propia.' using errcode = '23514';
      end if;
      v_tope := abs(v_otro.importe); v_mon := v_otro.moneda;
    end if;
    if l.tipo in ('recibi','gasto','pph','comision','traspaso') then
      if v_tope is null then raise exception 'El documento % no existe o no está en el estado que se puede conciliar.', l.ref_id using errcode = '23514'; end if;
      select coalesce(sum(abs(coalesce(importe_doc, importe_mov))), 0) into v_doc_ya from public.bancos_conciliacion
       where tipo = l.tipo and ref_id = l.ref_id and anulado_en is null;
      if v_doc_ya + abs(coalesce(l.importe_doc, case when v_mon = m.moneda then l.importe_mov end, 0)) > v_tope + 0.005 then
        raise exception 'Ese documento ya está conciliado del todo (o esta línea lo supera).' using errcode = '23514';
      end if;
      if v_mon <> m.moneda and l.importe_doc is null then
        raise exception 'Moneda distinta (% en el banco, % en el documento): indica el importe en la moneda del documento.', m.moneda, v_mon using errcode = '23514';
      end if;
    end if;
    insert into public.bancos_conciliacion (movimiento_id, tipo, ref_id, importe_mov, importe_doc, moneda_doc, tipo_cambio, naturaleza, nota, creado_por)
    values (p_mov, l.tipo, l.ref_id, l.importe_mov,
            coalesce(l.importe_doc, case when v_mon = m.moneda then abs(l.importe_mov) end),
            coalesce(v_mon, m.moneda),
            case when v_mon is not null and v_mon <> m.moneda and l.importe_doc is not null and l.importe_doc <> 0 then round(abs(l.importe_mov) / abs(l.importe_doc), 8) end,
            case when l.tipo = 'traspaso' then coalesce(l.naturaleza, 'interno') end,
            left(l.nota, 500), (select auth.uid()));
  end loop;
  perform public._bancos_recalcula(p_mov);
  select estado into v_estado from public.bancos_movimientos where id = p_mov;
  return jsonb_build_object('estado', v_estado);
end $function$;

create or replace function public.bancos_desconciliar(p_linea bigint) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_mov uuid;
begin
  perform public._bancos_puerta();
  select c.movimiento_id into v_mov from public.bancos_conciliacion c where c.id = p_linea and c.anulado_en is null;
  if v_mov is not null then perform public._bancos_puerta_de(public._empresa_movimiento(v_mov)); end if;
  update public.bancos_conciliacion set anulado_en = now(), anulado_por = (select auth.uid())
   where id = p_linea and anulado_en is null returning movimiento_id into v_mov;
  if v_mov is null then raise exception 'Esa línea no existe o ya estaba deshecha.' using errcode = 'P0002'; end if;
  perform public._bancos_recalcula(v_mov);
  return jsonb_build_object('ok', true);
end $function$;

create or replace function public.bancos_designorar(p_mov uuid) returns jsonb
language plpgsql security definer set search_path = '' as $function$
begin
  perform public._bancos_puerta();
  if exists (select 1 from public.bancos_movimientos m where m.id = p_mov) then
    perform public._bancos_puerta_de(public._empresa_movimiento(p_mov));
  end if;
  update public.bancos_movimientos set ignorado_en = null, ignorado_por = null, ignorado_motivo = null where id = p_mov;
  perform public._bancos_recalcula(p_mov);
  return jsonb_build_object('ok', true);
end $function$;

create or replace function public.bancos_ignorar(p_mov uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
begin
  perform public._bancos_puerta();
  if exists (select 1 from public.bancos_movimientos m where m.id = p_mov) then
    perform public._bancos_puerta_de(public._empresa_movimiento(p_mov));
  end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'Hace falta un motivo.' using errcode = '23514'; end if;
  if exists (select 1 from public.bancos_conciliacion where movimiento_id = p_mov and anulado_en is null) then
    raise exception 'Tiene líneas de conciliación vivas: deshazlas antes de ignorarlo.' using errcode = '23514';
  end if;
  update public.bancos_movimientos set ignorado_en = now(), ignorado_por = (select auth.uid()), ignorado_motivo = left(p_motivo, 300) where id = p_mov;
  perform public._bancos_recalcula(p_mov);
  return jsonb_build_object('ok', true);
end $function$;

create or replace function public.banco_perfil_guarda(p_cuenta text, p_mapeo jsonb) returns text
language plpgsql security definer set search_path = '' as $function$
declare k text; val jsonb;
begin
  perform public._bancos_puerta();
  perform public._bancos_puerta_de(public._empresa_cuenta(p_cuenta));
  if jsonb_typeof(p_mapeo) is distinct from 'object' then raise exception 'Columnas del extracto no válidas' using errcode = '22023'; end if;
  for k, val in select * from jsonb_each(p_mapeo) loop
    if k not in ('cabecera', 'fecha', 'fechaValor', 'concepto', 'referencia', 'importe', 'cargo', 'abono', 'saldo', 'moneda', 'formatoFecha', 'monedaFija') then
      raise exception 'Columna del extracto desconocida: %', k using errcode = '22023';
    end if;
    if jsonb_typeof(val) = 'null' then continue; end if;
    if k in ('formatoFecha', 'monedaFija') then
      if jsonb_typeof(val) <> 'string' or char_length(val #>> '{}') > 20 then raise exception 'Valor no válido para %', k using errcode = '22023'; end if;
    elsif jsonb_typeof(val) <> 'number' or (val #>> '{}')::numeric < 0 or (val #>> '{}')::numeric > 1000
          or (val #>> '{}')::numeric <> trunc((val #>> '{}')::numeric) then
      raise exception 'Valor no válido para %', k using errcode = '22023';
    end if;
  end loop;
  insert into public.bancos_perfiles (cuenta_clave, mapeo) values (p_cuenta, p_mapeo)
  on conflict (cuenta_clave) do update set mapeo = excluded.mapeo;
  return p_cuenta;
end $function$;

create or replace function public.bancos_resumen(p_anio integer default (extract(year from current_date))::integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare r jsonb; v_all boolean := public.es_admin();
begin
  if not public._puede_herr_admin('bancos') then return null; end if;
  with ult as (
    select distinct on (cuenta_clave, moneda) cuenta_clave, moneda, saldo, fecha
      from public.bancos_movimientos
     where saldo is not null and (v_all or public.banco_cuenta_visible(cuenta_clave))
     order by cuenta_clave, moneda, fecha desc, orden desc, creado_en desc
  ), por as (
    select m.cuenta_clave, m.moneda, max(m.fecha) ultimo, count(*) n,
           count(*) filter (where m.estado in ('pendiente','parcial')) pendientes,
           sum(m.importe) filter (where m.importe > 0 and extract(year from m.fecha) = p_anio) entradas,
           sum(m.importe) filter (where m.importe < 0 and extract(year from m.fecha) = p_anio) salidas,
           coalesce(sum(t.traspaso) filter (where m.importe > 0 and extract(year from m.fecha) = p_anio), 0) traspaso_in,
           coalesce(sum(t.traspaso) filter (where m.importe < 0 and extract(year from m.fecha) = p_anio), 0) traspaso_out
      from public.bancos_movimientos m
      left join lateral (select sum(c.importe_mov) traspaso from public.bancos_conciliacion c
                          where c.movimiento_id = m.id and c.anulado_en is null and c.tipo = 'traspaso') t on true
     where v_all or public.banco_cuenta_visible(m.cuenta_clave)
     group by 1, 2
  )
  select jsonb_agg(jsonb_build_object('cuenta', p.cuenta_clave, 'label', cb.label, 'moneda', p.moneda, 'ultimo', p.ultimo, 'movimientos', p.n,
           'pendientes', p.pendientes, 'saldo', u.saldo, 'saldo_fecha', u.fecha,
           'entradas', coalesce(p.entradas, 0) - p.traspaso_in, 'salidas', coalesce(p.salidas, 0) - p.traspaso_out,
           'traspasos_in', p.traspaso_in, 'traspasos_out', p.traspaso_out) order by cb.orden, p.moneda)
    into r
    from por p join public.cuentas_bancarias cb on cb.clave = p.cuenta_clave
    left join ult u on u.cuenta_clave = p.cuenta_clave and u.moneda = p.moneda;
  return coalesce(r, '[]'::jsonb);
end $function$;

create or replace function public.panel_bancos_datos(p_anio integer default null, p_limit integer default 1000, p_despues uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare
  v_lim  int := least(greatest(coalesce(p_limit, 1000), 1), 1000);
  v_tope int := 5000;
  v_anio int := coalesce(p_anio, extract(year from current_date)::int);
  v_all  boolean := public.es_admin();
  v_ids  uuid[];
  v_movs jsonb;
  v_res  jsonb;
  v_rec  text[] := '{}';
  v_cuentas jsonb; v_perfiles jsonb; v_recibis jsonb; v_gastos jsonb; v_comis jsonb;
  v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'panel_bancos_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.bancos_acceso() then
    raise exception 'panel_bancos_datos: hace falta ser admin con Bancos' using errcode = '42501';
  end if;

  select coalesce(array_agg(m.id order by m.id), '{}'),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'cuenta_clave', m.cuenta_clave, 'fecha', m.fecha, 'fecha_valor', m.fecha_valor,
           'concepto', m.concepto, 'referencia', m.referencia, 'importe', m.importe, 'moneda', m.moneda,
           'saldo', m.saldo, 'orden', m.orden, 'conciliado', m.conciliado, 'estado', m.estado,
           'ignorado_motivo', m.ignorado_motivo) order by m.id), '[]'::jsonb)
    into v_ids, v_movs
    from (select b.id, b.cuenta_clave, b.fecha, b.fecha_valor, b.concepto, b.referencia, b.importe, b.moneda,
                 b.saldo, b.orden, b.conciliado, b.estado, b.ignorado_motivo
            from public.bancos_movimientos b
           where (p_despues is null or b.id > p_despues)
             and (v_all or public.banco_cuenta_visible(b.cuenta_clave))
           order by b.id limit v_lim) m;

  v_res := jsonb_build_object(
    'movimientos', v_movs,
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', c.id, 'movimiento_id', c.movimiento_id, 'tipo', c.tipo, 'ref_id', c.ref_id,
                 'importe_mov', c.importe_mov, 'importe_doc', c.importe_doc, 'moneda_doc', c.moneda_doc,
                 'tipo_cambio', c.tipo_cambio, 'naturaleza', c.naturaleza, 'nota', c.nota) order by c.id), '[]'::jsonb)
                 from public.bancos_conciliacion c
                where c.anulado_en is null and c.movimiento_id = any(v_ids)),
    'siguiente', case when cardinality(v_ids) = v_lim then v_ids[v_lim] end);

  if p_despues is not null then
    return v_res;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'clave', cb.clave, 'label', cb.label, 'banco', cb.banco, 'es_escrow', cb.es_escrow,
           'es_propia', cb.es_propia, 'activa', cb.activa, 'orden', cb.orden) order by cb.orden, cb.clave), '[]'::jsonb),
         count(*)
    into v_cuentas, v_n
    from (select x.clave, x.label, x.banco, x.es_escrow, x.es_propia, x.activa, x.orden
            from public.cuentas_bancarias x
           where v_all or public.es_admin_de(x.empresa)
           order by orden, clave limit v_tope) cb;
  if v_n = v_tope then v_rec := v_rec || 'cuentas'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('cuenta_clave', p.cuenta_clave, 'mapeo', p.mapeo) order by p.cuenta_clave), '[]'::jsonb),
         count(*)
    into v_perfiles, v_n
    from (select x.cuenta_clave, x.mapeo from public.bancos_perfiles x
           where v_all or public.banco_cuenta_visible(x.cuenta_clave)
           order by cuenta_clave limit v_tope) p;
  if v_n = v_tope then v_rec := v_rec || 'perfiles'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'numero', f.numero, 'total', f.total, 'moneda', f.moneda,
           'fecha_emision', f.fecha_emision, 'created_at', f.created_at, 'proyecto_nombre', f.proyecto_nombre) order by f.id), '[]'::jsonb),
         count(*)
    into v_recibis, v_n
    from (select x.id, x.numero, x.total, x.moneda, x.fecha_emision, x.created_at, x.proyecto_nombre
            from public.facturas x
           where x.tipo = 'recibi' and x.anulada is not true
             and (v_all or x.proyecto_id = any (public.mis_proyectos_admin_empresa()))
           order by x.id limit v_tope) f;
  if v_n = v_tope then v_rec := v_rec || 'recibis'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id, 'concepto', g.concepto, 'referencia', g.referencia, 'total', g.total,
           'pph_retenido', g.pph_retenido, 'pph_ingresado_el', g.pph_ingresado_el, 'moneda', g.moneda,
           'estado', g.estado, 'pagado_el', g.pagado_el) order by g.id), '[]'::jsonb),
         count(*)
    into v_gastos, v_n
    from (select x.id, x.concepto, x.referencia, x.total, x.pph_retenido, x.pph_ingresado_el, x.moneda, x.estado, x.pagado_el
            from public.gastos x
           where x.estado <> 'anulado' and (v_all or public.gasto_visible(x.sociedad, x.proyecto_id))
           order by x.id limit v_tope) g;
  if v_n = v_tope then v_rec := v_rec || 'gastos'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'importe', d.importe, 'importe_ajustado', d.importe_ajustado,
           'moneda', d.moneda, 'pagado_en', d.pagado_en) order by d.id), '[]'::jsonb),
         count(*)
    into v_comis, v_n
    from (select x.id, x.importe, x.importe_ajustado, x.moneda, x.pagado_en
            from public.comisiones_devengadas x
           where x.estado = 'pagada' and (v_all or public.banco_comision_visible(x.id))
           order by x.id limit v_tope) d;
  if v_n = v_tope then v_rec := v_rec || 'comisiones'; end if;

  return v_res || jsonb_build_object(
    'cuentas', v_cuentas,
    'perfiles', v_perfiles,
    'resumen', public.bancos_resumen(v_anio),
    'recibis', v_recibis,
    'gastos', v_gastos,
    'comisiones', v_comis,
    'recortado', to_jsonb(v_rec));
end $function$;

-- Policies de lectura (solo las usa lw_lector; el panel va por las funciones de arriba).
alter policy "bancos_movimientos: leer" on public.bancos_movimientos
  using (public.banco_cuenta_visible(cuenta_clave));
alter policy "bancos_perfiles: leer" on public.bancos_perfiles
  using (public.banco_cuenta_visible(cuenta_clave));
alter policy "bancos_conciliacion: leer" on public.bancos_conciliacion
  using (public.banco_movimiento_visible(movimiento_id));
