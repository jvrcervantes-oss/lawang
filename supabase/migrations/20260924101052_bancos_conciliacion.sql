-- ═══════════════════════════════════════════════════════════════════════════
-- BANCOS Y CONCILIACIÓN (24-sep-2026) — módulo `bancos` del AxisWorks ERP.
-- Owner: «Hazlo. Usan Statrys, bancos de Hong Kong y Singapur». Revisión previa
-- #67 (Administración, Datos, Seguridad), plegada aquí:
--  · Puerta = es_admin() AND puede('bancos'): casilla NUEVA, nace para nadie.
--  · El navegador SOLO LEE estas tablas. Importar, conciliar, deshacer e ignorar
--    van por funciones SECURITY DEFINER que comprueban la puerta: así el estado
--    «conciliado» y la autoría no los puede escribir el cliente (Seguridad, Datos).
--  · El estado lo DERIVA la base de las líneas vivas de conciliación.
--  · Conciliación N↔N validada por los DOS lados: ni el movimiento ni el
--    documento (recibí, gasto, PPh, comisión) pueden quedar sobreconciliados.
--  · Traspasos entre cuentas propias con su naturaleza (interno / capital /
--    préstamo / pago) y tipo de cambio; no cuentan como entrada ni salida de caja.
--  · Solo cuentas es_propia IS TRUE AND es_escrow IS NOT TRUE.
--  · Nada de datos reales en este fichero: el repo es público.
-- ═══════════════════════════════════════════════════════════════════════════

create table public.bancos_perfiles (
  cuenta_clave    text primary key references public.cuentas_bancarias(clave),
  mapeo           jsonb not null check (jsonb_typeof(mapeo) = 'object'),
  actualizado_por uuid,
  actualizado_en  timestamptz not null default now()
);

create table public.bancos_importaciones (
  id            uuid primary key default gen_random_uuid(),
  cuenta_clave  text not null references public.cuentas_bancarias(clave),
  fichero       text,
  filas_leidas  int not null default 0,
  nuevas        int not null default 0,
  duplicadas    int not null default 0,
  desde         date,
  hasta         date,
  creado_por    uuid,
  creado_en     timestamptz not null default now()
);

create table public.bancos_movimientos (
  id              uuid primary key default gen_random_uuid(),
  cuenta_clave    text not null references public.cuentas_bancarias(clave),
  fecha           date not null,
  fecha_valor     date,
  concepto        text,
  referencia      text,
  importe         numeric(18,2) not null check (importe <> 0),
  moneda          text not null check (moneda ~ '^[A-Z]{3}$'),
  saldo           numeric(18,2),
  orden           int not null default 0,
  huella          text not null unique,
  importacion_id  uuid references public.bancos_importaciones(id),
  conciliado      numeric(18,2) not null default 0,
  estado          text not null default 'pendiente' check (estado in ('pendiente','parcial','conciliado','ignorado')),
  ignorado_motivo text,
  ignorado_por    uuid,
  ignorado_en     timestamptz,
  creado_en       timestamptz not null default now()
);
create index bancos_mov_cuenta_fecha on public.bancos_movimientos (cuenta_clave, fecha desc, orden desc);
create index bancos_mov_estado on public.bancos_movimientos (estado);

create table public.bancos_conciliacion (
  id            bigint generated always as identity primary key,
  movimiento_id uuid not null references public.bancos_movimientos(id),
  tipo          text not null check (tipo in ('recibi','gasto','pph','comision','traspaso','comision_bancaria','retencion_sufrida','otro')),
  ref_id        uuid,
  importe_mov   numeric(18,2) not null check (importe_mov <> 0),
  importe_doc   numeric(18,2),
  moneda_doc    text check (moneda_doc is null or moneda_doc ~ '^[A-Z]{3}$'),
  tipo_cambio   numeric(18,8),
  naturaleza    text check (naturaleza in ('interno','capital','prestamo','pago')),
  nota          text,
  creado_por    uuid,
  creado_en     timestamptz not null default now(),
  anulado_en    timestamptz,
  anulado_por   uuid,
  constraint bancos_conc_ref check (tipo in ('comision_bancaria','retencion_sufrida','otro') or ref_id is not null),
  constraint bancos_conc_naturaleza check (tipo <> 'traspaso' or naturaleza is not null),
  constraint bancos_conc_nota check (tipo <> 'otro' or nullif(btrim(nota), '') is not null)
);
create index bancos_conc_mov on public.bancos_conciliacion (movimiento_id) where anulado_en is null;
create index bancos_conc_ref on public.bancos_conciliacion (tipo, ref_id) where anulado_en is null;

-- ── la puerta, una sola vez ───────────────────────────────────────────────
create or replace function public._bancos_puerta()
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.es_admin() and public.puede('bancos')) then
    raise exception 'Hace falta ser admin y tener «Bancos» marcado en Usuarios.' using errcode = '42501';
  end if;
end $$;

create or replace function public._bancos_cuenta_valida(p_cuenta text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.cuentas_bancarias c
                  where c.clave = p_cuenta and c.es_propia is true and c.es_escrow is not true) then
    raise exception 'Solo se importan extractos de cuentas marcadas como propias de la sociedad (y nunca escrow).' using errcode = '23514';
  end if;
end $$;

-- ── estado derivado ───────────────────────────────────────────────────────
create or replace function public._bancos_recalcula(p_mov uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_imp numeric; v_con numeric; v_ign timestamptz;
begin
  select importe, ignorado_en into v_imp, v_ign from public.bancos_movimientos where id = p_mov for update;
  select coalesce(sum(importe_mov), 0) into v_con from public.bancos_conciliacion where movimiento_id = p_mov and anulado_en is null;
  update public.bancos_movimientos
     set conciliado = v_con,
         estado = case when v_ign is not null and v_con = 0 then 'ignorado'
                       when abs(v_con - v_imp) < 0.005 then 'conciliado'
                       when v_con <> 0 then 'parcial' else 'pendiente' end
   where id = p_mov;
end $$;

-- ── importar un extracto (atómico) ────────────────────────────────────────
create or replace function public.bancos_importar(p_cuenta text, p_fichero text, p_filas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_imp uuid; v_leidas int; v_nuevas int;
begin
  perform public._bancos_puerta();
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
end $$;

-- ── conciliar: líneas que explican un movimiento ──────────────────────────
create or replace function public.bancos_conciliar(p_mov uuid, p_lineas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m record; l record; v_ya numeric; v_tope numeric; v_doc_ya numeric; v_mon text; v_estado text; v_otro record;
begin
  perform public._bancos_puerta();
  select * into m from public.bancos_movimientos where id = p_mov for update;
  if m.id is null then raise exception 'Movimiento no encontrado.' using errcode = 'P0002'; end if;
  if m.ignorado_en is not null then raise exception 'Este movimiento está marcado como ignorado: quítale la marca antes de conciliarlo.' using errcode = '23514'; end if;
  for l in select * from jsonb_to_recordset(p_lineas) as x(tipo text, ref_id uuid, importe_mov numeric, importe_doc numeric, naturaleza text, nota text) loop
    if l.importe_mov is null or l.importe_mov = 0 or sign(l.importe_mov) <> sign(m.importe) then
      raise exception 'Cada línea lleva el mismo signo que el movimiento (entrada + / salida −).' using errcode = '23514';
    end if;
    select coalesce(sum(importe_mov), 0) into v_ya from public.bancos_conciliacion where movimiento_id = p_mov and anulado_en is null;
    if abs(v_ya + l.importe_mov) > abs(m.importe) + 0.005 then
      raise exception 'Las líneas suman más que el movimiento.' using errcode = '23514';
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
      -- por el lado del documento: nunca más de lo que vale (misma moneda que el documento)
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
            -- tipo de cambio SOLO si las monedas difieren; con la misma moneda, importe_doc ≠ importe_mov
            -- es la comisión del banco (SWIFT recortada) y se lee como diferencia, no como cambio
            case when v_mon is not null and v_mon <> m.moneda and l.importe_doc is not null and l.importe_doc <> 0 then round(abs(l.importe_mov) / abs(l.importe_doc), 8) end,
            case when l.tipo = 'traspaso' then coalesce(l.naturaleza, 'interno') end,
            left(l.nota, 500), (select auth.uid()));
  end loop;
  perform public._bancos_recalcula(p_mov);
  select estado into v_estado from public.bancos_movimientos where id = p_mov;
  return jsonb_build_object('estado', v_estado);
end $$;

create or replace function public.bancos_desconciliar(p_linea bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_mov uuid;
begin
  perform public._bancos_puerta();
  update public.bancos_conciliacion set anulado_en = now(), anulado_por = (select auth.uid())
   where id = p_linea and anulado_en is null returning movimiento_id into v_mov;
  if v_mov is null then raise exception 'Esa línea no existe o ya estaba deshecha.' using errcode = 'P0002'; end if;
  perform public._bancos_recalcula(v_mov);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bancos_ignorar(p_mov uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public._bancos_puerta();
  if nullif(btrim(p_motivo), '') is null then raise exception 'Hace falta un motivo.' using errcode = '23514'; end if;
  if exists (select 1 from public.bancos_conciliacion where movimiento_id = p_mov and anulado_en is null) then
    raise exception 'Tiene líneas de conciliación vivas: deshazlas antes de ignorarlo.' using errcode = '23514';
  end if;
  update public.bancos_movimientos set ignorado_en = now(), ignorado_por = (select auth.uid()), ignorado_motivo = left(p_motivo, 300) where id = p_mov;
  perform public._bancos_recalcula(p_mov);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.bancos_designorar(p_mov uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public._bancos_puerta();
  update public.bancos_movimientos set ignorado_en = null, ignorado_por = null, ignorado_motivo = null where id = p_mov;
  perform public._bancos_recalcula(p_mov);
  return jsonb_build_object('ok', true);
end $$;

-- ── resumen para Finanzas (null sin permiso: nunca 0 en silencio) ─────────
create or replace function public.bancos_resumen(p_anio int default extract(year from current_date)::int)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if not (public.es_admin() and public.puede('bancos')) then return null; end if;
  with ult as (
    select distinct on (cuenta_clave, moneda) cuenta_clave, moneda, saldo, fecha
      from public.bancos_movimientos where saldo is not null
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
end $$;

-- ── permisos ──────────────────────────────────────────────────────────────
alter table public.bancos_perfiles      enable row level security;
alter table public.bancos_importaciones enable row level security;
alter table public.bancos_movimientos   enable row level security;
alter table public.bancos_conciliacion  enable row level security;
create policy "bancos_perfiles: leer"      on public.bancos_perfiles      for select to authenticated using ((select public.es_admin()) and (select public.puede('bancos')));
create policy "bancos_perfiles: crear"     on public.bancos_perfiles      for insert to authenticated with check ((select public.es_admin()) and (select public.puede('bancos')));
create policy "bancos_perfiles: editar"    on public.bancos_perfiles      for update to authenticated using ((select public.es_admin()) and (select public.puede('bancos'))) with check ((select public.es_admin()) and (select public.puede('bancos')));
create policy "bancos_importaciones: leer" on public.bancos_importaciones for select to authenticated using ((select public.es_admin()) and (select public.puede('bancos')));
create policy "bancos_movimientos: leer"   on public.bancos_movimientos   for select to authenticated using ((select public.es_admin()) and (select public.puede('bancos')));
create policy "bancos_conciliacion: leer"  on public.bancos_conciliacion  for select to authenticated using ((select public.es_admin()) and (select public.puede('bancos')));

revoke all on public.bancos_perfiles, public.bancos_importaciones, public.bancos_movimientos, public.bancos_conciliacion from anon, authenticated;
grant select on public.bancos_perfiles, public.bancos_importaciones, public.bancos_movimientos, public.bancos_conciliacion to authenticated;
grant insert (cuenta_clave, mapeo) on public.bancos_perfiles to authenticated;
grant update (mapeo) on public.bancos_perfiles to authenticated;

create or replace function public._bancos_perfil_autoria()
returns trigger language plpgsql set search_path = '' as $$
begin
  perform public._bancos_cuenta_valida(new.cuenta_clave);
  new.actualizado_por := (select auth.uid()); new.actualizado_en := now();
  return new;
end $$;
create trigger bancos_perfil_autoria before insert or update on public.bancos_perfiles
  for each row execute function public._bancos_perfil_autoria();

revoke all on function public._bancos_puerta(), public._bancos_cuenta_valida(text), public._bancos_recalcula(uuid) from public, anon, authenticated;
revoke all on function public.bancos_importar(text, text, jsonb), public.bancos_conciliar(uuid, jsonb), public.bancos_desconciliar(bigint),
                       public.bancos_ignorar(uuid, text), public.bancos_designorar(uuid), public.bancos_resumen(int) from public, anon;
grant execute on function public.bancos_importar(text, text, jsonb), public.bancos_conciliar(uuid, jsonb), public.bancos_desconciliar(bigint),
                          public.bancos_ignorar(uuid, text), public.bancos_designorar(uuid), public.bancos_resumen(int) to authenticated;
-- el trigger de perfiles llama a _bancos_cuenta_valida como invoker: necesita poder ejecutarla
grant execute on function public._bancos_cuenta_valida(text) to authenticated;
