-- Comision de administracion: % sobre TODO EL DINERO QUE ENTRA por la intranet
-- (17-sep-2026, encargo del owner)
-- ============================================================================
-- Encargo, textual: «Desde la intranet voy a empezar a cargar 0,5% de comision
-- a todo el dinero que entra [...] es de administracion [...] no es equipo de
-- ventas [...] que ese campo sea editable por si a futuro quiero editarlo».
--
-- «Dinero que entra» = cada RECIBI (facturas.tipo='recibi'). No las facturas ni
-- las proformas: una factura es lo que se PIDE, un recibi es lo que se COBRO.
-- Gravar las dos seria cobrar dos veces el mismo dinero -- y `contrato_cobrado()`
-- ya usa ese mismo criterio, asi que no se inventa vocabulario nuevo.
-- Verificado el 17-sep: 0 facturas vivas con justificante sin aplicacion de
-- recibi, o sea que hoy TODO el dinero que entra pasa por un recibi.
--
-- NO se toca nada de la comision de VENTAS (equipos_venta, condiciones_comision,
-- condicion_tramos, comisiones_devengadas). Son dos hechos distintos: aquella la
-- cobra un comercial por vender, esta la cobra administracion por el uso de la
-- intranet. Mezclarlas en una tabla haria imposible contestar «cuanto se llevo
-- el equipo» sin restar a mano.
--
-- destructivo-ok: los "drop policy/trigger if exists" son el patron estandar del
-- repo para poder reejecutar la migracion. Los nombres son NUEVOS (las dos
-- tablas y los dos triggers nacen aqui), asi que hoy no quitan nada. No hay
-- ningun otro DROP/DELETE/UPDATE-sin-WHERE en este SQL.
--
-- Revision previa 17-sep-2026 (Seguridad + Administracion). Lo que cambiaron del
-- plan original va marcado abajo como [SEG-n] / [ADM-n].

-- ── 1. Tarifas: historial, NUNCA una celda que se sobrescribe ────────────────
-- El % es editable, pero editarlo no puede reescribir el pasado: hay que poder
-- decir que tarifa regia el dia que entro cada euro. Por eso una fila por cambio
-- y ningun UPDATE: la vigente es la ultima con efectivo_desde <= hoy.
create table if not exists public.comision_admin_tarifas (
  id              uuid primary key default gen_random_uuid(),
  -- [ADM-5] numeric(7,4) y nunca float: 0,5% es 0.5000 exacto. Un float
  -- arrastra 0.49999999 y el redondeo final deja de ser reproducible.
  pct             numeric(7,4) not null check (pct >= 0 and pct <= 100),
  efectivo_desde  date    not null,
  nota            text,
  -- [SEG-5] default auth.email() y ademas forzado en el WITH CHECK de la policy:
  -- un "creado_por" que teclea el navegador es un log de auditoria que rellena
  -- el propio auditado. Mismo patron que facturas.creado_por.
  creado_por      text default auth.email(),
  created_at      timestamptz not null default now(),
  unique (efectivo_desde)
);

comment on table public.comision_admin_tarifas is
  'Historial del % de comision de administracion (0,5% al arrancar, 17-sep-2026). APPEND-ONLY a proposito: la vigente es la ultima fila con efectivo_desde <= current_date, y cada linea ya devengada guarda su propio pct congelado. Sin esto, subir la tarifa manana reescribiria lo cobrado ayer.';
comment on column public.comision_admin_tarifas.efectivo_desde is
  'Desde que dia rige. La primera fila nace el 17-sep-2026 para que la comision NO sea retroactiva: ningun recibi dado de alta antes de esa fecha genera linea.';

-- ── 2. El libro: una linea por hecho, y los hechos no se reescriben ──────────
-- [ADM-2] El plan original tenia UNA fila por recibi que se mutaba al anular o
-- al corregir el importe. Eso hace que un mes ya cerrado cambie solo. Aqui el
-- libro es append-only en lo que importa: el devengo original no se toca una vez
-- facturado; una anulacion genera ABONO (importe negativo) y una correccion
-- posterior genera AJUSTE (la diferencia). Mientras la linea sigue `pendiente`
-- y nadie la ha facturado todavia, si se corrige en sitio: no hay historia que
-- preservar y una linea de ajuste sobre algo que nadie ha visto es ruido.
create table if not exists public.comision_admin_lineas (
  id              uuid primary key default gen_random_uuid(),
  tipo_linea      text not null default 'devengo'
                    check (tipo_linea in ('devengo','ajuste','abono')),
  linea_origen_id uuid references public.comision_admin_lineas(id) on delete set null,

  -- [SEG-2] on delete set null y NO cascade: un recibi se puede borrar de verdad
  -- (policy "borrar facturas": super_admin siempre; admin si no esta anulada y
  -- no tiene aplicaciones). Con cascade, borrar el recibi borraria en silencio
  -- la comision devengada sobre el. Asi queda la linea con recibi_id null +
  -- recibi_numero, que es la senal de «el recibi desaparecio, miralo».
  recibi_id       uuid references public.facturas(id) on delete set null,
  recibi_numero   text not null,
  -- [ADM-4] La sociedad emisora del recibi. Hay DOS (tepi_sungai y
  -- san_dal_woods) y cada una es un deudor distinto de esta comision: sin esta
  -- columna no hay conciliacion ni factura por entidad, y no se puede rellenar
  -- despues sobre lineas ya congeladas.
  sociedad        text,
  contrato_id     uuid references public.contratos(id) on delete set null,
  proyecto_id     uuid references public.proyectos(id) on delete set null,

  -- [SEG-2 + ADM-2] LA FECHA QUE MANDA es la del ALTA en la intranet, no la
  -- `fecha_emision` que teclea quien registra el recibi. Dos motivos que empujan
  -- en la misma direccion:
  --   · Seguridad: `fecha_emision` la escribe el agente autor del recibi (su
  --     policy de UPDATE se lo permite). Si la elegibilidad dependiera de ella,
  --     poner 16-sep dejaria el recibi fuera del corte para siempre y nada se
  --     quejaria.
  --   · Administracion: si un UPDATE pudiera crear linea, adjuntar manana un
  --     justificante a un recibi de marzo lo volveria elegible de golpe.
  -- La regla que cierra las dos: SOLO el INSERT crea linea, y lo hace con
  -- current_date. El hecho que se grava es registrar el cobro en la intranet
  -- --que es literalmente lo que se cobra: «0,5% por usar la intranet»--, y eso
  -- pasa el dia del alta.
  devengado_el    date not null default current_date,
  fecha_recibi    date,

  -- [ADM-1] La base es el SUBTOTAL del recibi, no su total. Hoy son iguales (los
  -- 97 recibis llevan datos.totales.pct = 0), pero el emisor permite meter PPN:
  -- el dia que alguien marque un 11%, un 0,5% sobre el total cobraria comision
  -- sobre dinero del fisco indonesio, y el importe dejaria de ser comparable
  -- entre meses segun quien marco el impuesto. Se elige bien AHORA porque
  -- despues las lineas ya estan congeladas.
  base_total      numeric not null,
  moneda          text not null,
  pct_aplicado    numeric(7,4) not null,
  importe         numeric not null,
  tarifa_id       uuid references public.comision_admin_tarifas(id),

  anulada         boolean not null default false,
  revisar         boolean not null default false,
  estado          text not null default 'pendiente'
                    check (estado in ('pendiente','facturada','cobrada','exenta')),
  nota            text,
  snapshot        jsonb,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

-- Un solo DEVENGO por recibi; los ajustes y abonos son filas adicionales del
-- mismo recibi a proposito. Indice parcial y no `unique(recibi_id)` de tabla
-- justo por eso -- y el trigger no usa ON CONFLICT (busca la linea y decide),
-- que es lo unico fiable con un indice parcial.
create unique index if not exists comision_admin_lineas_devengo_uk
  on public.comision_admin_lineas (recibi_id)
  where tipo_linea = 'devengo' and recibi_id is not null;
create index if not exists comision_admin_lineas_devengado_idx on public.comision_admin_lineas (devengado_el desc);
create index if not exists comision_admin_lineas_proyecto_idx  on public.comision_admin_lineas (proyecto_id);
create index if not exists comision_admin_lineas_estado_idx    on public.comision_admin_lineas (estado);
create index if not exists comision_admin_lineas_origen_idx    on public.comision_admin_lineas (linea_origen_id);

comment on table public.comision_admin_lineas is
  'Libro de la comision de administracion: una linea por hecho (devengo de un recibi, ajuste por correccion posterior, abono por anulacion). La escribe SOLO el trigger; el navegador unicamente mueve estado/nota/revisar (grant POR COLUMNA -- el grant manda antes que la policy). pct_aplicado queda congelado: cambiar la tarifa no reescribe lo ya devengado.';
comment on column public.comision_admin_lineas.pct_aplicado is
  'El % vigente el dia del alta del recibi, copiado aqui. Congelado: si manana la tarifa sube al 1%, esta linea sigue al 0,5%.';
comment on column public.comision_admin_lineas.importe is
  'round(base_total * pct_aplicado / 100, N) con N = 0 en IDR y 2 en el resto. La rupia no tiene centimos y ninguna factura indonesia puede emitir 12.345,67 IDR (UU 7/2011). Un solo redondeo, al final.';
comment on column public.comision_admin_lineas.revisar is
  'Bandera para una persona: el recibi cambio despues de que la comision dejara de estar pendiente, o resucito de una anulacion. No la baja ningun automatismo -- y bajarla a mano no esconde nada, porque el descuadre lo recalcula comision_admin_descuadres() desde base_total/pct/importe.';
comment on column public.comision_admin_lineas.estado is
  'Ciclo de cobro de ESTA comision. `exenta` es la salida para el dinero que entra pero no es una venta: aporte de capital, traspaso entre las dos PT, devolucion. Sin esa salida, mover fondos propios pagaria comision (hallazgo de Administracion).';
comment on column public.comision_admin_lineas.snapshot is
  'Lista CERRADA de campos del recibi: numero, sociedad, total, subtotal, impuesto, moneda, fecha_emision, tarifa. NUNCA facturas.datos -- ese jsonb lleva el contenido del documento (PII del comprador y blobs) y copiarlo aqui seria duplicar datos fuera de su dueno y engordar el libro.';

-- ── 3. Alta del devengo: solo el INSERT de un recibi crea linea ──────────────
create or replace function public._comision_admin_alta_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_tarifa    record;
  v_base      numeric;
  v_decimales integer;
begin
  if coalesce(new.tipo, '') <> 'recibi' then
    return new;
  end if;

  -- Tarifa vigente HOY (dia del alta). Sin tarifa vigente no hay comision, y no
  -- es un fallo: es exactamente lo que hace que el arranque no sea retroactivo.
  select * into v_tarifa
    from public.comision_admin_tarifas t
   where t.efectivo_desde <= current_date
   order by t.efectivo_desde desc
   limit 1;

  if v_tarifa.id is null then
    return new;
  end if;

  if exists (select 1 from public.comision_admin_lineas l
              where l.recibi_id = new.id and l.tipo_linea = 'devengo') then
    return new;  -- defensivo: ya tiene devengo
  end if;

  v_base      := coalesce((new.datos -> 'totales' ->> 'subtotal')::numeric, new.total, 0);
  v_decimales := case when upper(coalesce(new.moneda, '')) = 'IDR' then 0 else 2 end;

  insert into public.comision_admin_lineas (
    tipo_linea, recibi_id, recibi_numero, sociedad, contrato_id, proyecto_id,
    devengado_el, fecha_recibi, base_total, moneda, pct_aplicado, importe,
    tarifa_id, anulada, snapshot
  ) values (
    'devengo', new.id, coalesce(new.numero, '(sin numero)'), new.sociedad,
    new.contrato_id, new.proyecto_id,
    current_date, new.fecha_emision, v_base, coalesce(new.moneda, 'EUR'),
    v_tarifa.pct, round(v_base * v_tarifa.pct / 100, v_decimales),
    v_tarifa.id, coalesce(new.anulada, false),
    jsonb_build_object(
      'numero', new.numero, 'sociedad', new.sociedad,
      'total', new.total, 'subtotal', v_base,
      'impuesto', (new.datos -> 'totales' ->> 'impuesto'),
      'moneda', new.moneda, 'fecha_emision', new.fecha_emision,
      'tarifa_pct', v_tarifa.pct, 'tarifa_desde', v_tarifa.efectivo_desde,
      'calculado_en', now())
  );

  return new;
exception when others then
  -- MUDO PARA EL RECIBI, RUIDOSO EN EL LOG: un fallo calculando la comision no
  -- puede impedir que se registre el dinero que entra. Mismo criterio que
  -- _trg_comisiones_desde_recibi_aplicaciones. Y para que el silencio no se
  -- coma dinero, comision_admin_descuadres() cuenta los recibis sin linea.
  raise warning 'comision_admin alta (recibi %): %', new.id, sqlerrm;
  return new;
end;
$function$;

-- ── 4. Cambios posteriores: ajustan o abonan, NUNCA dan de alta ──────────────
create or replace function public._comision_admin_cambio_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea     record;
  v_base      numeric;
  v_decimales integer;
  v_nuevo     numeric;
begin
  if coalesce(new.tipo, '') <> 'recibi' and coalesce(old.tipo, '') <> 'recibi' then
    return new;
  end if;

  select * into v_linea
    from public.comision_admin_lineas l
   where l.recibi_id = new.id and l.tipo_linea = 'devengo'
   limit 1;

  -- Un recibi sin devengo (anterior al corte, o que acaba de cambiar de tipo)
  -- NO nace de un UPDATE. Si el flip factura->recibi fuera legitimo, saldra como
  -- «recibi vivo sin linea» en comision_admin_descuadres(), que es un descuadre
  -- visible en vez de un alta automatica por la puerta de atras.
  if v_linea.id is null then
    return new;
  end if;

  v_decimales := case when upper(coalesce(new.moneda, '')) = 'IDR' then 0 else 2 end;
  v_base      := coalesce((new.datos -> 'totales' ->> 'subtotal')::numeric, new.total, 0);

  -- (a) el recibi se anula -> ABONO por el importe devengado, una sola vez
  if coalesce(new.anulada, false) and not v_linea.anulada then
    insert into public.comision_admin_lineas (
      tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
      contrato_id, proyecto_id, devengado_el, fecha_recibi,
      base_total, moneda, pct_aplicado, importe, tarifa_id, nota, snapshot
    ) values (
      'abono', v_linea.id, new.id, v_linea.recibi_numero, v_linea.sociedad,
      v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
      - v_linea.base_total, v_linea.moneda, v_linea.pct_aplicado,
      - v_linea.importe, v_linea.tarifa_id,
      'Abono automatico: el recibi se anulo.',
      jsonb_build_object('motivo', 'recibi_anulado', 'devengo_id', v_linea.id, 'en', now())
    );
    update public.comision_admin_lineas
       set anulada = true, actualizado_en = now()
     where id = v_linea.id;
    return new;
  end if;

  -- (b) un recibi anulado vuelve a la vida: no se reabre el devengo solo
  if not coalesce(new.anulada, false) and v_linea.anulada then
    update public.comision_admin_lineas
       set revisar = true, actualizado_en = now(),
           nota = coalesce(nota || ' · ', '') || 'El recibi se desanulo: revisar si procede reponer el devengo.'
     where id = v_linea.id;
    return new;
  end if;

  -- (c) cambia la base
  if v_base is distinct from v_linea.base_total and not v_linea.anulada then
    v_nuevo := round(v_base * v_linea.pct_aplicado / 100, v_decimales);

    if v_linea.estado = 'pendiente'
       and not exists (select 1 from public.comision_admin_lineas a
                        where a.linea_origen_id = v_linea.id) then
      -- nadie la ha facturado todavia y no cuelga nada de ella: se corrige en
      -- sitio, con SU pct congelado (nunca el de hoy)
      update public.comision_admin_lineas
         set base_total = v_base, importe = v_nuevo,
             moneda = coalesce(new.moneda, moneda),
             recibi_numero = coalesce(new.numero, recibi_numero),
             contrato_id = new.contrato_id, proyecto_id = new.proyecto_id,
             fecha_recibi = new.fecha_emision, actualizado_en = now()
       where id = v_linea.id;
    else
      -- ya facturada/cobrada: el dinero emitido no se toca, se anota la
      -- DIFERENCIA como linea de ajuste
      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
        contrato_id, proyecto_id, devengado_el, fecha_recibi,
        base_total, moneda, pct_aplicado, importe, tarifa_id, revisar, nota, snapshot
      ) values (
        'ajuste', v_linea.id, new.id, coalesce(new.numero, v_linea.recibi_numero), v_linea.sociedad,
        new.contrato_id, new.proyecto_id, current_date, new.fecha_emision,
        v_base - v_linea.base_total, v_linea.moneda, v_linea.pct_aplicado,
        v_nuevo - v_linea.importe, v_linea.tarifa_id, true,
        'Ajuste automatico: el recibi cambio de importe despues de que la comision dejara de estar pendiente.',
        jsonb_build_object('motivo', 'base_corregida', 'devengo_id', v_linea.id,
                           'base_antes', v_linea.base_total, 'base_despues', v_base, 'en', now())
      );
      update public.comision_admin_lineas set revisar = true, actualizado_en = now() where id = v_linea.id;
    end if;
  end if;

  return new;
exception when others then
  raise warning 'comision_admin cambio (recibi %): %', new.id, sqlerrm;
  return new;
end;
$function$;

-- ── 5. Borrado del recibi: la linea sobrevive y lo dice ──────────────────────
-- BEFORE DELETE y no AFTER: el `on delete set null` de la FK ya habria borrado
-- el rastro de a que recibi pertenecia la linea.
create or replace function public._comision_admin_borrado_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea record;
begin
  if coalesce(old.tipo, '') <> 'recibi' then
    return old;
  end if;

  select * into v_linea
    from public.comision_admin_lineas l
   where l.recibi_id = old.id and l.tipo_linea = 'devengo'
   limit 1;

  if v_linea.id is null then
    return old;
  end if;

  if not v_linea.anulada then
    insert into public.comision_admin_lineas (
      tipo_linea, linea_origen_id, recibi_numero, sociedad, contrato_id, proyecto_id,
      devengado_el, fecha_recibi, base_total, moneda, pct_aplicado, importe,
      tarifa_id, revisar, nota, snapshot
    ) values (
      'abono', v_linea.id, v_linea.recibi_numero, v_linea.sociedad,
      v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
      - v_linea.base_total, v_linea.moneda, v_linea.pct_aplicado, - v_linea.importe,
      v_linea.tarifa_id, true,
      'Abono automatico: el recibi se BORRO de la base.',
      jsonb_build_object('motivo', 'recibi_borrado', 'devengo_id', v_linea.id, 'en', now())
    );
  end if;

  update public.comision_admin_lineas
     set anulada = true, revisar = true, actualizado_en = now(),
         nota = coalesce(nota || ' · ', '') || 'El recibi ya no existe en la base.'
   where id = v_linea.id;

  return old;
exception when others then
  raise warning 'comision_admin borrado (recibi %): %', old.id, sqlerrm;
  return old;
end;
$function$;

-- [SEG-1] Las tres son SECURITY DEFINER: EXECUTE explicitamente revocado, sin
-- fiarse del default. Son funciones de trigger, nadie las llama por RPC.
revoke all on function public._comision_admin_alta_recibi()     from public, anon, authenticated;
revoke all on function public._comision_admin_cambio_recibi()   from public, anon, authenticated;
revoke all on function public._comision_admin_borrado_recibi()  from public, anon, authenticated;

-- [SEG-2] SIN lista de columnas en el UPDATE: el filtro por `tipo` va dentro de
-- la funcion. Con `update of total, anulada` se colaban `tipo`, `moneda` y
-- `fecha_emision`, que son justo las que deciden si la linea cuenta y por cuanto.
drop trigger if exists trg_comision_admin_alta     on public.facturas;
drop trigger if exists trg_comision_admin_cambio   on public.facturas;
drop trigger if exists trg_comision_admin_borrado  on public.facturas;

create trigger trg_comision_admin_alta
  after insert on public.facturas
  for each row execute function public._comision_admin_alta_recibi();

create trigger trg_comision_admin_cambio
  after update on public.facturas
  for each row execute function public._comision_admin_cambio_recibi();

create trigger trg_comision_admin_borrado
  before delete on public.facturas
  for each row execute function public._comision_admin_borrado_recibi();

-- ── 6. Reconciliacion: el silencio del trigger tiene que verse ───────────────
-- [SEG-3] El `exception when others` de arriba es correcto, pero si el unico
-- rastro fuese un raise warning que nadie lee, lo que se perderia en silencio es
-- dinero sin facturar. Esto lo cuenta, y de paso caza el flip de tipo, el
-- borrado manual de una linea y cualquier importe tocado por fuera.
create or replace function public.comision_admin_descuadres()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_desde date;
  v_sin_linea integer;
  v_mal_calculadas integer;
  v_sin_base integer;
begin
  if not public.es_admin() then
    raise exception 'comision_admin_descuadres: solo administracion';
  end if;

  select min(efectivo_desde) into v_desde from public.comision_admin_tarifas;
  if v_desde is null then
    return jsonb_build_object('sin_tarifa', true);
  end if;

  select count(*) into v_sin_linea
    from public.facturas f
   where f.tipo = 'recibi'
     and not coalesce(f.anulada, false)
     and f.created_at::date >= v_desde
     and not exists (select 1 from public.comision_admin_lineas l
                      where l.recibi_id = f.id and l.tipo_linea = 'devengo');

  select count(*) into v_mal_calculadas
    from public.comision_admin_lineas l
   where l.importe is distinct from
         round(l.base_total * l.pct_aplicado / 100,
               case when upper(l.moneda) = 'IDR' then 0 else 2 end);

  select count(*) into v_sin_base
    from public.comision_admin_lineas l
   where l.tipo_linea = 'devengo' and l.base_total = 0 and not l.anulada;

  return jsonb_build_object(
    'desde', v_desde,
    'recibis_sin_linea', v_sin_linea,
    'lineas_mal_calculadas', v_mal_calculadas,
    'devengos_con_base_cero', v_sin_base,
    'para_revisar', (select count(*) from public.comision_admin_lineas where revisar)
  );
end;
$function$;

revoke all on function public.comision_admin_descuadres() from public, anon, authenticated;
grant execute on function public.comision_admin_descuadres() to authenticated;

-- ── 7. Permisos ─────────────────────────────────────────────────────────────
-- [SEG-1] El GRANT manda ANTES que la policy, y en este proyecto una tabla nueva
-- nace con insert/update/delete concedidos a anon y authenticated. Sin este
-- revoke, una policy `for all using es_admin()` dejaria el libro reescribible
-- desde DevTools con la publishable key: cambiar el `importe` de una linea ya
-- emitida seria un PATCH. Un libro que el auditado puede reescribir no es libro.
alter table public.comision_admin_tarifas enable row level security;
alter table public.comision_admin_lineas  enable row level security;

revoke all on public.comision_admin_tarifas from anon, authenticated;
revoke all on public.comision_admin_lineas  from anon, authenticated;

-- La tarifa se da de alta, nunca se edita ni se borra: el historial es el punto.
grant select, insert on public.comision_admin_tarifas to authenticated;
-- Del libro, el navegador solo mueve el ciclo de cobro. Ni inserta, ni borra, ni
-- puede tocar importe/base/pct -- eso lo pone el trigger, que escribe como owner
-- y no necesita grant. El grant POR COLUMNA es el candado: la policy no limita
-- columnas.
grant select on public.comision_admin_lineas to authenticated;
grant update (estado, nota, revisar) on public.comision_admin_lineas to authenticated;

drop policy if exists "comision_admin_tarifas: leer" on public.comision_admin_tarifas;
drop policy if exists "comision_admin_tarifas: alta" on public.comision_admin_tarifas;
create policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas
  for select to authenticated using (public.es_admin());
-- [SEG-5] Cambiar la tarifa es la perilla del dinero: super_admin, como el alta
-- de una cuenta de cobro. Y tres cosas mas que valida la propia policy:
--   · efectivo_desde >= hoy -- una tarifa retroactiva haria mentir a la tarjeta
--     «que % regia el dia X» (las lineas viejas no cambian, porque el pct va
--     congelado, pero el historial dejaria de cuadrar con ellas).
--   · creado_por = quien esta escribiendo, no lo que diga el navegador.
--   · el CHECK 0..100 de la tabla para el 0,5 tecleado como 50.
create policy "comision_admin_tarifas: alta" on public.comision_admin_tarifas
  for insert to authenticated
  with check (
    public.es_super_admin()
    and efectivo_desde >= current_date
    and creado_por = (select auth.email())
  );

drop policy if exists "comision_admin_lineas: leer"   on public.comision_admin_lineas;
drop policy if exists "comision_admin_lineas: estado" on public.comision_admin_lineas;
create policy "comision_admin_lineas: leer" on public.comision_admin_lineas
  for select to authenticated using (public.es_admin());
create policy "comision_admin_lineas: estado" on public.comision_admin_lineas
  for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- ── 8. La tarifa de arranque ────────────────────────────────────────────────
-- 0,5% desde HOY. No retroactivo por construccion: el alta busca la tarifa
-- vigente el dia del alta, y ningun recibi anterior vuelve a pasar por el INSERT.
insert into public.comision_admin_tarifas (pct, efectivo_desde, nota, creado_por)
values (0.5000, date '2026-09-17',
        'Tarifa de arranque: 0,5% por el uso de la intranet sobre todo el dinero que entra (encargo del owner, 17-sep-2026).',
        'sistema')
on conflict (efectivo_desde) do nothing;
