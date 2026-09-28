-- Recálculo automático de comisiones al cambiar el contrato (28-sep-2026, owner).
--
-- «Si hay cambio en el contrato hay cambio en las comisiones.» Decisiones del owner ese día:
--   · lo pendiente se recalcula en sitio; lo aprobado/pagado NO se toca: se genera una
--     línea de diferencia ± (comisiones_diferencias, DIF-00001…).
--   · la base (precio_total) cuenta SOLO contratos FIRMADOS (bloqueado) y no liberados —
--     también en el motor: un borrador no genera comisión (cierra que un agente infle la
--     suya subiendo el precio de un borrador, hallazgo de Seguridad en la revisión previa).
--
-- Revisión previa (Administración, Seguridad, Datos) plegada aquí:
--   · el reconciliador corre DIFERIDO (constraint trigger, al commit): una transacción que
--     mueve varias filas de la misma venta ve el estado final y no deja diferencias fantasma.
--   · la transición de solicitudes_pago revertía en silencio el importe de una automática si
--     quien guarda no es admin → marca de transacción app.via_recalculo_comision.
--   · casos que no se restan solos → diferencia en «revisar» (la decide un admin): la venta
--     ya no es raíz (traspaso LAW-51 / liberada), moneda distinta, importe tocado a mano,
--     comisión en disputa, solicitud rechazada/anulada/inexistente, importe nuevo ≤ 0, y una
--     subida a favor de quien provocó el cambio.
--   · solo se vigilan CONTRATOS: las 6 condiciones activas calculan sobre precio_total; la
--     lista de parcelas es la lista viva y no debe mover comisiones vendidas.
--   · nace APAGADO (comisiones_interruptor): el owner ve antes la simulación
--     (comisiones_reconciliar(raiz, true)) y lo enciende él.
--   · permisos cerrados: tabla SELECT solo authenticated/lw_lector por RLS; funciones internas
--     revocadas; dos RPC con llamador con nombre (/intranet/v4/comisiones y /v4/reparto).

-- ───────────────────────── 1. Interruptor ─────────────────────────
create table if not exists public.comisiones_interruptor (
  id             boolean primary key default true check (id),
  recalculo_auto boolean not null default false,
  cambiado_por   text,
  cambiado_en    timestamptz not null default now(),
  nota           text,
  ultimo_error   text,
  ultimo_error_en timestamptz
);
insert into public.comisiones_interruptor (id, recalculo_auto, cambiado_por, nota)
values (true, false, 'migracion 20260928210000', 'apagado hasta que el owner vea la simulación')
on conflict (id) do nothing;
alter table public.comisiones_interruptor enable row level security;
revoke all on public.comisiones_interruptor from public, anon, authenticated;

-- ───────────────────────── 2. Diferencias ─────────────────────────
create sequence if not exists public.comisiones_diferencias_seq;
revoke all on sequence public.comisiones_diferencias_seq from public, anon, authenticated;

create table if not exists public.comisiones_diferencias (
  id              uuid primary key default gen_random_uuid(),
  numero          text not null unique
                  default 'DIF-' || lpad(nextval('public.comisiones_diferencias_seq')::text, 5, '0'),
  devengo_id      uuid not null references public.comisiones_devengadas(id) on delete cascade,
  importe         numeric,          -- con signo; null solo en «revisar» sin importe calculable
  importe_vigente numeric,          -- lo que valía la comisión (más diferencias vivas) antes
  importe_nuevo   numeric,          -- lo que vale hoy con la base nueva
  base_antes      numeric,
  base_despues    numeric,
  motivo          text not null check (btrim(motivo) <> ''),
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente', 'pagada', 'compensada', 'anulada', 'revisar')),
  origen          jsonb not null default '{}'::jsonb,   -- qué contrato/campo cambió, de qué a qué
  provocado_por   text,
  solicitud_id    uuid references public.solicitudes_pago(id),
  resuelto_por    text,
  resuelto_en     timestamptz,
  resolucion_motivo text,
  created_at      timestamptz not null default now(),
  constraint dif_importe_no_cero check (importe is null or importe <> 0),
  constraint dif_importe_salvo_revisar check (estado in ('revisar', 'anulada') or importe is not null)
);
create unique index if not exists comisiones_diferencias_una_revisar
  on public.comisiones_diferencias (devengo_id) where estado = 'revisar';
create index if not exists comisiones_diferencias_devengo on public.comisiones_diferencias (devengo_id);
create index if not exists comisiones_diferencias_solicitud on public.comisiones_diferencias (solicitud_id);

alter table public.comisiones_diferencias enable row level security;
revoke all on public.comisiones_diferencias from public, anon, authenticated;
grant select on public.comisiones_diferencias to authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    execute 'grant select on public.comisiones_diferencias to lw_lector';
  end if;
end $$;
-- se ve la diferencia de una comisión que se ve (la subconsulta pasa por la RLS de devengadas)
drop policy if exists "comisiones_diferencias: leer" on public.comisiones_diferencias;
create policy "comisiones_diferencias: leer" on public.comisiones_diferencias
  for select using (exists (select 1 from public.comisiones_devengadas d where d.id = devengo_id));

-- identidad inmutable
create or replace function public._trg_comision_diferencia_fija()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.numero := old.numero; new.devengo_id := old.devengo_id; new.created_at := old.created_at;
  new.provocado_por := old.provocado_por;
  return new;
end $$;
drop trigger if exists trg_comision_diferencia_fija on public.comisiones_diferencias;
create trigger trg_comision_diferencia_fija before update on public.comisiones_diferencias
  for each row execute function public._trg_comision_diferencia_fija();

-- una diferencia viva no se borra (tampoco en cascada desde comision_recalcular / borrar_operacion)
create or replace function public._trg_comision_diferencia_no_borrar_viva()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.estado in ('pendiente', 'pagada', 'compensada') then
    raise exception 'la comisión tiene una diferencia % (%) viva: resuélvela o anúlala antes de borrar', old.numero, old.estado
      using errcode = '23503';
  end if;
  return old;
end $$;
drop trigger if exists trg_comision_diferencia_no_borrar_viva on public.comisiones_diferencias;
create trigger trg_comision_diferencia_no_borrar_viva before delete on public.comisiones_diferencias
  for each row execute function public._trg_comision_diferencia_no_borrar_viva();
drop trigger if exists trg_guarda_antes_de_borrar on public.comisiones_diferencias;
create trigger trg_guarda_antes_de_borrar before delete on public.comisiones_diferencias
  for each row execute function public.trg_guarda_antes_de_borrar();

-- el log acepta las acciones y la tabla nuevas
alter table public.comisiones_ajustes_log drop constraint if exists comisiones_ajustes_log_accion_check;
alter table public.comisiones_ajustes_log add constraint comisiones_ajustes_log_accion_check
  check (accion = any (array['editar_importe', 'anular', 'recalcular', 'recalculo_auto', 'diferencia', 'resolver_diferencia']));
alter table public.comisiones_ajustes_log drop constraint if exists comisiones_ajustes_log_tabla_check;
alter table public.comisiones_ajustes_log add constraint comisiones_ajustes_log_tabla_check
  check (tabla = any (array['solicitudes_pago', 'comisiones_devengadas', 'comisiones_diferencias']));

-- ───────────────────────── 3. Base: solo firmados ─────────────────────────
-- Fuente única de la base precio_total de una venta: la usan el motor y el reconciliador.
-- La Carta de Reserva hija ya vale suelo + obra: no se suma otra vez (24-sep-2026).
create or replace function public._comisiones_precio_total(p_raiz uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(sum(x.precio_total), 0)
    from public.contratos x
   where (x.id = p_raiz or x.contrato_padre_id = p_raiz)
     and coalesce(x.bloqueado, false)
     and x.liberado_en is null
     and not (x.contrato_padre_id is not null and x.tipo like 'carta_reserva%');
$$;
revoke execute on function public._comisiones_precio_total(uuid) from public, anon, authenticated;

-- el motor pasa a leerla (parche sobre la definición viva: el repo no es su verdad)
do $$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure);
  if position('_comisiones_precio_total(v_raiz_id)' in v_def) > 0 then
    return;  -- ya aplicado
  end if;
  v_new := regexp_replace(v_def,
    'select\s+coalesce\(sum\(x\.precio_total\),\s*0\)\s+into\s+v_precio_total\s+from\s+public\.contratos\s+x\s+where\s+\(x\.id\s*=\s*v_raiz_id\s+or\s+x\.contrato_padre_id\s*=\s*v_raiz_id\)\s+and\s+not\s+\(x\.contrato_padre_id\s+is\s+not\s+null\s+and\s+x\.tipo\s+like\s+''carta_reserva%''\);',
    'v_precio_total := public._comisiones_precio_total(v_raiz_id);');
  if v_new = v_def then
    raise exception 'comisiones_evaluar_contrato: no encuentro el bloque de la base para parchearlo';
  end if;
  execute v_new;
end $$;

-- ───────────────────────── 4. Transición de solicitudes ─────────────────────────
-- Igual que la viva (md5 a632f2e4… el 28-sep) más tres cosas:
--   · con app.via_recalculo_comision el reconciliador cambia importe y concepto de una
--     automática pendiente sin que cuente como edición humana (sin importe_editado_por,
--     sin importe_ajustado en el devengo, sin log de edición — el suyo lo escribe él).
--   · anular una solicitud anula también su diferencia pendiente.
--   · pagar una solicitud marca pagada su diferencia.
create or replace function public._trg_solicitud_pago_transicion()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_yo      text := lower(coalesce(auth.email(), ''));
  v_benef   boolean := old.beneficiario_email is not null and lower(old.beneficiario_email) = v_yo;
  v_motivo  text := case when new.motivo_ajuste is distinct from old.motivo_ajuste then nullif(btrim(coalesce(new.motivo_ajuste, '')), '') end;
  v_recalc  boolean := coalesce(current_setting('app.via_recalculo_comision', true), '') = 'on';
begin
  new.numero := old.numero;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.origen := old.origen;
  new.beneficiario_email := old.beneficiario_email;

  if old.estado = 'pendiente' then
    if new.estado = 'pendiente' then
      new.resuelto_por := null; new.resuelto_en := null;
      new.pagado_por := null;   new.pagado_en := null;
      new.pago_referencia := null; new.motivo_rechazo := null;
      new.concepto := btrim(new.concepto);
      if old.origen = 'comision_automatica' then
        if v_recalc then
          new.contrato_id := old.contrato_id; new.moneda := old.moneda;
          new.importe_editado_por := old.importe_editado_por;
          return new;
        end if;
        new.contrato_id := old.contrato_id; new.concepto := old.concepto;
        new.moneda := old.moneda;
        if new.importe is distinct from old.importe then
          if not public.es_admin() or v_benef then
            new.importe := old.importe;
          elsif v_motivo is null then
            raise exception 'cambiar el importe de una comisión automática exige un motivo' using errcode = '22023';
          end if;
        end if;
      end if;
      if new.importe is distinct from old.importe and old.creado_por is distinct from auth.uid() and v_motivo is null then
        raise exception 'cambiar el importe de la solicitud de otra persona exige un motivo' using errcode = '22023';
      end if;
      if new.importe is distinct from old.importe then
        new.importe_editado_por := auth.uid();
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
        values ('solicitudes_pago', old.id, 'editar_importe', old.importe, new.importe, old.estado, new.estado,
                coalesce(v_motivo, 'edición por quien la creó'));
        update public.comisiones_devengadas
           set importe_ajustado = new.importe, ajuste_motivo = coalesce(v_motivo, 'edición por quien la creó'),
               ajustado_por = auth.uid(), ajustado_en = now()
         where solicitud_id = old.id;
      else
        new.importe_editado_por := old.importe_editado_por;
      end if;
      return new;
    elsif new.estado in ('aprobada','rechazada') then
      if not public.es_admin() then
        raise exception 'solo un administrador resuelve una solicitud' using errcode = '42501';
      end if;
      if new.estado = 'aprobada' and v_benef then
        raise exception 'nadie aprueba una solicitud de pago a su propio nombre' using errcode = '42501';
      end if;
      if new.estado = 'aprobada' and old.importe_editado_por is not null and old.importe_editado_por = auth.uid() then
        raise exception 'quien cambió el importe no puede aprobarla: la aprueba otro administrador' using errcode = '42501';
      end if;
    elsif new.estado = 'anulada' then
      if coalesce(current_setting('app.via_venta_propia', true), '') <> 'on'
         and not v_recalc
         and (old.origen = 'comision_automatica' or old.creado_por is distinct from auth.uid()) then
        if not public.es_admin() or v_benef then
          raise exception 'solo quien creó la solicitud, o un administrador que no la cobra, puede anularla' using errcode = '42501';
        end if;
        if v_motivo is null then
          raise exception 'anular la solicitud de otra persona exige un motivo' using errcode = '22023';
        end if;
      end if;
    else
      raise exception 'desde pendiente solo se puede aprobar, rechazar o anular' using errcode = '22023';
    end if;
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.importe_editado_por := old.importe_editado_por;
    new.pagado_por := null; new.pagado_en := null; new.pago_referencia := null;
    new.resuelto_por := auth.uid();
    new.resuelto_en := now();
    if new.estado = 'anulada' then
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
      values ('solicitudes_pago', old.id, 'anular', old.importe, old.importe, old.estado, 'anulada',
              coalesce(v_motivo, 'anulada por quien la creó'));
      update public.comisiones_devengadas
         set estado = 'anulada', anulado_motivo = coalesce(v_motivo, 'anulada por quien la creó'),
             anulado_por = auth.uid(), anulado_en = now()
       where solicitud_id = old.id and estado = 'pendiente';
      update public.comisiones_diferencias
         set estado = 'anulada', resolucion_motivo = 'su solicitud de pago se anuló: ' || coalesce(v_motivo, 'anulada por quien la creó'),
             resuelto_por = auth.email(), resuelto_en = now()
       where solicitud_id = old.id and estado = 'pendiente';
    end if;
    return new;

  elsif old.estado = 'aprobada' and new.estado = 'pagada' then
    if not public.es_admin() then
      raise exception 'solo un administrador marca una solicitud como pagada' using errcode = '42501';
    end if;
    if v_benef then
      raise exception 'nadie marca como pagada una solicitud a su propio nombre' using errcode = '42501';
    end if;
    if old.importe_editado_por is not null and old.importe_editado_por = auth.uid() then
      raise exception 'quien cambió el importe no puede marcarla pagada: la paga otro administrador' using errcode = '42501';
    end if;
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.motivo_rechazo := old.motivo_rechazo;
    new.importe_editado_por := old.importe_editado_por;
    new.resuelto_por := old.resuelto_por; new.resuelto_en := old.resuelto_en;
    new.pagado_por := auth.uid();
    new.pagado_en := now();
    update public.comisiones_diferencias
       set estado = 'pagada', resuelto_por = auth.email(), resuelto_en = now(),
           resolucion_motivo = 'pagada con su solicitud de pago'
     where solicitud_id = old.id and estado = 'pendiente';
    return new;

  elsif old.estado = 'aprobada' and new.estado = 'anulada' then
    if not public.es_admin() or v_benef then
      raise exception 'solo un administrador que no la cobra anula una solicitud aprobada' using errcode = '42501';
    end if;
    if v_motivo is null then
      raise exception 'anular una solicitud aprobada exige un motivo' using errcode = '22023';
    end if;
    if old.pago_referencia is not null or old.pagado_en is not null then
      raise exception 'esta solicitud ya tiene un pago registrado: no se anula' using errcode = '22023';
    end if;
    new.contrato_id := old.contrato_id; new.concepto := old.concepto;
    new.importe := old.importe;         new.moneda := old.moneda;
    new.vence_el := old.vence_el;       new.nota := old.nota;
    new.importe_editado_por := old.importe_editado_por;
    new.pagado_por := null; new.pagado_en := null; new.pago_referencia := null;
    new.resuelto_por := auth.uid();
    new.resuelto_en := now();
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
    values ('solicitudes_pago', old.id, 'anular', old.importe, old.importe, 'aprobada', 'anulada', v_motivo);
    update public.comisiones_devengadas
       set estado = 'anulada', anulado_motivo = v_motivo, anulado_por = auth.uid(), anulado_en = now()
     where solicitud_id = old.id and estado = 'pendiente';
    update public.comisiones_diferencias
       set estado = 'anulada', resolucion_motivo = 'su solicitud de pago se anuló: ' || v_motivo,
           resuelto_por = auth.email(), resuelto_en = now()
     where solicitud_id = old.id and estado = 'pendiente';
    return new;
  end if;

  raise exception 'una solicitud % no se puede editar', old.estado using errcode = '22023';
end
$function$;

-- ───────────────────────── 5. Solicitud de una diferencia positiva de Lawang ─────────────────────────
create or replace function public._comision_diferencia_solicitud(p_dif uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare x public.comisiones_diferencias; d public.comisiones_devengadas; v_num text; v_por uuid; v_sp uuid;
begin
  select * into x from public.comisiones_diferencias where id = p_dif;
  select * into d from public.comisiones_devengadas where id = x.devengo_id;
  if x.importe is null or x.importe <= 0 or d.nivel not in ('manager', 'estandar', 'propia') or x.solicitud_id is not null then
    return x.solicitud_id;
  end if;
  select numero into v_num from public.contratos where id = d.contrato_raiz_id;
  v_por := coalesce(
    auth.uid(),
    (select u.user_id from public.usuarios u where lower(u.email) = lower(d.beneficiario_email) and u.activo limit 1),
    (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1));
  insert into public.solicitudes_pago (contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por)
  values (d.contrato_raiz_id,
          'Diferencia ' || x.numero || ' por cambio de contrato — comisión '
            || case d.nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end
            || ' de la venta ' || coalesce(v_num, '?') || ': base ' || coalesce(round(x.base_antes, 2)::text, '?')
            || ' → ' || coalesce(round(x.base_despues, 2)::text, '?') || ' ' || d.moneda
            || ' — importe BRUTO (retención al pagar)',
          x.importe, d.moneda, 'comision_automatica', d.beneficiario_email, v_por)
  returning id into v_sp;
  update public.comisiones_diferencias set solicitud_id = v_sp where id = x.id;
  return v_sp;
end $$;
revoke execute on function public._comision_diferencia_solicitud(uuid) from public, anon, authenticated;

-- ───────────────────────── 6. Reconciliador ─────────────────────────
-- p_simular = true (por defecto): no escribe nada, devuelve lo que haría.
create or replace function public.comisiones_reconciliar(p_raiz uuid, p_simular boolean default true, p_origen jsonb default '{}'::jsonb)
returns table (devengo_id uuid, venta text, beneficiario text, nivel text, estado_devengo text,
               base_antes numeric, base_despues numeric, vigente numeric, nuevo numeric, delta numeric,
               accion text, motivo text)
language plpgsql security definer set search_path = '' as $$
declare
  r record; v_sp public.solicitudes_pago;
  v_es_raiz boolean; v_moneda text; v_num text; v_base numeric;
  v_vig numeric; v_nuevo numeric; v_delta numeric; v_base_antes numeric;
  v_lawang boolean; v_manual boolean; v_accion text; v_motivo text;
  v_yo text := lower(coalesce(auth.email(), ''));
  v_dif public.comisiones_diferencias; v_dif_id uuid;
  v_hoy text := to_char(now() at time zone 'Asia/Makassar', 'DD-MM-YYYY');
begin
  if p_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select (c.contrato_padre_id is null and c.liberado_en is null), c.moneda, c.numero
    into v_es_raiz, v_moneda, v_num
    from public.contratos c where c.id = p_raiz;
  v_base := public._comisiones_precio_total(p_raiz);

  for r in
    select d.*, c.base_calculo, c.pct_comision, c.importe_fijo, t.pct_tramo
      from public.comisiones_devengadas d
      join public.condiciones_comision c on c.id = d.condicion_id
      join public.condicion_tramos t on t.id = d.tramo_id
     where d.contrato_raiz_id = p_raiz and d.estado <> 'anulada'
     order by d.created_at, d.id
  loop
    -- solo la base precio_total se reconcilia: importe fijo no depende del contrato, y las
    -- bases de parcela salen de la lista viva de unidades
    continue when r.base_calculo <> 'precio_total';

    v_lawang := r.nivel in ('manager', 'estandar', 'propia');
    v_sp := null;
    if r.solicitud_id is not null then
      select * into v_sp from public.solicitudes_pago sp where sp.id = r.solicitud_id;
    end if;
    select * into v_dif from public.comisiones_diferencias x where x.devengo_id = r.id and x.estado = 'revisar';

    v_base_antes := coalesce(
      (select x.base_despues from public.comisiones_diferencias x
        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')
        order by x.created_at desc limit 1),
      nullif(r.disparado_por_snapshot->>'base_valor', '')::numeric);
    v_vig := (case when v_lawang and v_sp.id is not null then v_sp.importe
                   else coalesce(r.importe_ajustado, r.importe) end)
           + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')), 0);
    v_nuevo := round((r.pct_comision / 100) * v_base * (r.pct_tramo / 100), 2);
    v_delta := round(v_nuevo - v_vig, 2);
    v_manual := r.importe_ajustado is not null or (v_sp.id is not null and v_sp.importe_editado_por is not null);

    v_accion := null; v_motivo := null;
    if not coalesce(v_es_raiz, false) then
      v_accion := 'revisar'; v_motivo := 'la venta ' || coalesce(v_num, '?') || ' ya no es una venta viva (traspasada a otro contrato o liberada)';
      v_delta := null;
    elsif v_moneda is distinct from r.moneda then
      v_accion := 'revisar'; v_motivo := 'la venta está ahora en ' || coalesce(v_moneda, '?') || ' y la comisión en ' || r.moneda;
      v_delta := null;
    elsif abs(v_delta) < 0.01 then
      v_accion := 'nada';
    elsif v_nuevo <= 0 then
      v_accion := 'revisar'; v_motivo := 'sin contratos firmados en la venta la comisión bajaría a 0';
    elsif v_manual then
      v_accion := 'revisar'; v_motivo := 'el importe se había ajustado a mano';
    elsif r.estado = 'en_disputa' then
      v_accion := 'revisar'; v_motivo := 'la comisión está en disputa';
    elsif v_lawang and (v_sp.id is null or v_sp.estado in ('rechazada', 'anulada')) then
      v_accion := 'revisar'; v_motivo := 'su solicitud de pago está ' || coalesce(v_sp.estado, 'sin crear');
    elsif v_delta > 0 and lower(r.beneficiario_email) = v_yo then
      v_accion := 'revisar'; v_motivo := 'la subida la provoca quien cobra la comisión';
    elsif r.estado = 'pendiente' and (not v_lawang or v_sp.estado = 'pendiente')
          and not exists (select 1 from public.comisiones_diferencias x
                           where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')) then
      v_accion := 'actualizar';
    else
      v_accion := 'diferencia';
      v_motivo := 'la comisión ya estaba '
                  || case when r.estado = 'pagada' or v_sp.estado = 'pagada' then 'pagada' else 'aprobada' end
                  || case when v_delta > 0 then ': se paga la diferencia' else ': la diferencia se descuenta de un pago siguiente' end;
    end if;

    -- un «revisar» ya descartado por un admin para este mismo importe no se vuelve a abrir
    if v_accion = 'revisar' and exists (
         select 1 from public.comisiones_diferencias x
          where x.devengo_id = r.id and x.estado = 'anulada' and x.importe_nuevo is not distinct from v_nuevo
            and x.resuelto_por is not null and x.resuelto_por <> 'sistema') then
      v_accion := 'descartada';
    end if;

    if v_accion <> 'nada' or v_dif.id is not null then
      devengo_id := r.id; venta := v_num; beneficiario := r.beneficiario_email; nivel := r.nivel;
      estado_devengo := r.estado; base_antes := v_base_antes; base_despues := v_base;
      vigente := v_vig; nuevo := v_nuevo; delta := v_delta;
      accion := case when v_accion = 'nada' then 'cierra_revisar' else v_accion end;
      motivo := v_motivo;
      return next;
    end if;
    continue when p_simular;

    perform set_config('app.via_recalculo_comision', 'on', true);

    if v_accion = 'nada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'la comisión vuelve a cuadrar sola con la base de hoy'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'actualizar' then
      update public.comisiones_devengadas d
         set importe = v_nuevo,
             disparado_por_snapshot = d.disparado_por_snapshot
               || jsonb_build_object('base_valor', v_base, 'precio_total', v_base,
                                     'recalculado_en', now(), 'recalculo_origen', p_origen,
                                     'importe_motor_original', coalesce(d.disparado_por_snapshot->'importe_motor_original', to_jsonb(r.importe)),
                                     'base_original', coalesce(d.disparado_por_snapshot->'base_original', d.disparado_por_snapshot->'base_valor'))
       where d.id = r.id;
      if v_sp.id is not null then
        update public.solicitudes_pago sp
           set importe = v_nuevo,
               concepto = case
                 when sp.concepto ~ '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}'
                   then regexp_replace(sp.concepto, '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}',
                                       'recalculada el ' || v_hoy || ': ' || round(v_base, 2) || ' ' || sp.moneda)
                 else sp.concepto || ' — recalculada el ' || v_hoy || ' sobre ' || round(v_base, 2) || ' ' || sp.moneda
               end
         where sp.id = v_sp.id;
      end if;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_devengadas', r.id, 'recalculo_auto', v_vig, v_nuevo, r.estado, r.estado,
              'cambio en el contrato: base ' || coalesce(round(v_base_antes, 2)::text, '?') || ' → ' || round(v_base, 2) || ' ' || r.moneda,
              jsonb_build_object('origen', p_origen, 'solicitud_id', v_sp.id));

    elsif v_accion = 'revisar' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set importe = v_delta, importe_vigente = v_vig, importe_nuevo = v_nuevo,
               base_despues = v_base, motivo = v_motivo, origen = p_origen
         where id = v_dif.id;
      else
        insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                   motivo, estado, origen, provocado_por)
        values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'revisar', p_origen, nullif(v_yo, ''))
        returning id into v_dif_id;
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
        values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'revisar', v_motivo, jsonb_build_object('origen', p_origen));
      end if;

    elsif v_accion = 'diferencia' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'sustituida por una diferencia automática'
         where id = v_dif.id;
      end if;
      insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                 motivo, estado, origen, provocado_por)
      values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'pendiente', p_origen, nullif(v_yo, ''))
      returning id into v_dif_id;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'pendiente', v_motivo, jsonb_build_object('origen', p_origen));
      perform public._comision_diferencia_solicitud(v_dif_id);
    end if;

    perform set_config('app.via_recalculo_comision', 'off', true);
  end loop;
end $$;
revoke execute on function public.comisiones_reconciliar(uuid, boolean, jsonb) from public, anon, authenticated;

-- ───────────────────────── 7. Disparador diferido en contratos ─────────────────────────
create or replace function public._trg_comisiones_reconcilia_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_raices uuid[]; v_r uuid; v_origen jsonb;
begin
  if not coalesce((select i.recalculo_auto from public.comisiones_interruptor i where i.id), false) then
    return null;
  end if;
  v_origen := jsonb_build_object(
    'tabla', 'contratos', 'op', tg_op, 'contrato_id', new.id, 'numero', new.numero, 'en', now(),
    'quien', auth.email(),
    'precio_total', jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.precio_total end, 'despues', new.precio_total),
    'firmado',      jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.bloqueado end,    'despues', new.bloqueado),
    'padre',        jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.contrato_padre_id end, 'despues', new.contrato_padre_id),
    'tipo',         jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.tipo end,         'despues', new.tipo),
    'liberado',     jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.liberado_en end,  'despues', new.liberado_en),
    'moneda',       jsonb_build_object('antes', case when tg_op = 'UPDATE' then old.moneda end,       'despues', new.moneda));
  v_raices := array[new.id, coalesce(new.contrato_padre_id, new.id)];
  if tg_op = 'UPDATE' then
    v_raices := v_raices || coalesce(old.contrato_padre_id, old.id);
  end if;
  begin
    for v_r in select distinct u from unnest(v_raices) u where u is not null loop
      perform public.comisiones_reconciliar(v_r, false, v_origen);
      perform public.comisiones_evaluar_contrato(v_r);
    end loop;
  exception when others then
    -- una comisión nunca impide guardar un contrato: queda anotado para el vigilante
    update public.comisiones_interruptor
       set ultimo_error = sqlerrm || ' (contrato ' || coalesce(new.numero, new.id::text) || ')', ultimo_error_en = now()
     where id;
    raise warning 'recalculo de comisiones fallido para %: %', new.numero, sqlerrm;
  end;
  return null;
end $$;
revoke execute on function public._trg_comisiones_reconcilia_contrato() from public, anon, authenticated;

drop trigger if exists zz_comisiones_reconcilia_alta on public.contratos;
create constraint trigger zz_comisiones_reconcilia_alta
  after insert on public.contratos
  deferrable initially deferred
  for each row execute function public._trg_comisiones_reconcilia_contrato();

drop trigger if exists zz_comisiones_reconcilia_cambio on public.contratos;
create constraint trigger zz_comisiones_reconcilia_cambio
  after update on public.contratos
  deferrable initially deferred
  for each row
  when (old.precio_total is distinct from new.precio_total
        or old.bloqueado is distinct from new.bloqueado
        or old.contrato_padre_id is distinct from new.contrato_padre_id
        or old.tipo is distinct from new.tipo
        or old.liberado_en is distinct from new.liberado_en
        or old.moneda is distinct from new.moneda)
  execute function public._trg_comisiones_reconcilia_contrato();

-- ───────────────────────── 8. RPC: resolver una diferencia ─────────────────────────
-- Llamador: /intranet/v4/comisiones y /intranet/v4/reparto (botones de la trazabilidad).
create or replace function public.comision_diferencia_resolver(p_id uuid, p_accion text, p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  x public.comisiones_diferencias; d public.comisiones_devengadas; v_sp public.solicitudes_pago;
  v_yo text := lower(coalesce(auth.email(), '')); v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_lawang boolean; v_nuevo text;
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_motivo is null then raise exception 'resolver una diferencia exige un motivo' using errcode = '22023'; end if;
  select * into x from public.comisiones_diferencias where id = p_id for update;
  if not found then raise exception 'no existe esa diferencia' using errcode = 'P0002'; end if;
  select * into d from public.comisiones_devengadas where id = x.devengo_id;
  v_lawang := d.nivel in ('manager', 'estandar', 'propia');
  if v_lawang then
    if not public.es_admin() then
      raise exception 'esta diferencia la paga Lawang: la resuelve un administrador' using errcode = '42501';
    end if;
  elsif not ((public.es_admin() and public.puede('comisiones_reparto'))
             or public.es_manager_de_equipo(public._equipo_de_condicion_comision(d.condicion_id))) then
    raise exception 'la resuelve el manager que la paga o un administrador' using errcode = '42501';
  end if;
  if lower(d.beneficiario_email) = v_yo then
    raise exception 'nadie resuelve una diferencia a su propio nombre' using errcode = '42501';
  end if;
  if x.provocado_por is not null and lower(x.provocado_por) = v_yo then
    raise exception 'quien provocó el cambio no resuelve su diferencia: la resuelve otra persona' using errcode = '42501';
  end if;

  if p_accion = 'aplicar' then
    if x.estado <> 'revisar' then raise exception 'solo se aplica una diferencia en revisión' using errcode = '22023'; end if;
    if x.importe is null then raise exception 'esta diferencia no tiene importe calculable: anúlala y ajusta la comisión a mano' using errcode = '22023'; end if;
    v_nuevo := 'pendiente';
  elsif p_accion = 'pagada' then
    if x.estado <> 'pendiente' or x.importe <= 0 or v_lawang then
      raise exception 'solo se marca pagada una diferencia pendiente a favor del closer (la de Lawang se paga con su solicitud)' using errcode = '22023';
    end if;
    v_nuevo := 'pagada';
  elsif p_accion = 'compensada' then
    if x.estado <> 'pendiente' or x.importe >= 0 then
      raise exception 'solo se compensa una diferencia pendiente a descontar' using errcode = '22023';
    end if;
    v_nuevo := 'compensada';
  elsif p_accion = 'anular' then
    if x.estado not in ('revisar', 'pendiente') then
      raise exception 'solo se anula una diferencia en revisión o pendiente' using errcode = '22023';
    end if;
    if x.solicitud_id is not null then
      select * into v_sp from public.solicitudes_pago where id = x.solicitud_id;
      if v_sp.estado <> 'pendiente' and v_sp.estado <> 'anulada' then
        raise exception 'su solicitud de pago ya está %: anúlala desde la solicitud', v_sp.estado using errcode = '22023';
      end if;
    end if;
    v_nuevo := 'anulada';
  else
    raise exception 'acción desconocida: %', p_accion using errcode = '22023';
  end if;

  update public.comisiones_diferencias
     set estado = v_nuevo, resuelto_por = v_yo, resuelto_en = now(), resolucion_motivo = v_motivo
   where id = x.id;
  insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
  values ('comisiones_diferencias', x.id, 'resolver_diferencia', x.importe, x.importe, x.estado, v_nuevo, v_motivo);

  if v_nuevo = 'pendiente' then
    perform public._comision_diferencia_solicitud(x.id);
  elsif v_nuevo = 'anulada' and v_sp.id is not null and v_sp.estado = 'pendiente' then
    perform set_config('app.via_recalculo_comision', 'on', true);
    update public.solicitudes_pago set estado = 'anulada', motivo_ajuste = 'Diferencia anulada: ' || v_motivo where id = v_sp.id;
    perform set_config('app.via_recalculo_comision', 'off', true);
  end if;
end $$;
revoke execute on function public.comision_diferencia_resolver(uuid, text, text) from public, anon;
grant execute on function public.comision_diferencia_resolver(uuid, text, text) to authenticated;

-- ───────────────────────── 9. RPC: trazabilidad de una comisión ─────────────────────────
-- Llamador: /intranet/v4/reparto y /intranet/v4/comisiones (ficha de la fila). Lectura:
-- operación (contratos de la venta y si cuentan en la base), parcelas, historial y diferencias.
create or replace function public.comision_trazabilidad(p_devengo uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), ''));
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- mismo criterio que la policy de lectura de comisiones_devengadas
  if not found or not (
       (public.es_admin() and public.puede('comisiones_reparto'))
       or lower(d.beneficiario_email) = v_yo
       or (d.nivel in ('closer', 'setter', 'team_lead')
           and public.es_manager_de_equipo(public._equipo_de_condicion_comision(d.condicion_id)))) then
    raise exception 'No encuentro esa comisión entre las que puedes ver' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'venta', d.contrato_raiz_id,
    'base_hoy', public._comisiones_precio_total(d.contrato_raiz_id),
    'operacion', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'numero', c.numero, 'tipo', c.tipo, 'precio_total', c.precio_total, 'moneda', c.moneda,
               'firmado', coalesce(c.bloqueado, false), 'fecha_firma', c.fecha_firma,
               'liberado', c.liberado_en is not null, 'es_raiz', c.id = d.contrato_raiz_id,
               'cuenta_en_base', coalesce(c.bloqueado, false) and c.liberado_en is null
                                 and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%'))
             order by (c.id = d.contrato_raiz_id) desc, c.created_at), '[]'::jsonb)
        from public.contratos c
       where c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id),
    'parcelas', (
      select coalesce(jsonb_agg(jsonb_build_object('codigo', u.codigo, 'proyecto', u.proyecto) order by u.codigo_orden, u.codigo), '[]'::jsonb)
        from public.unidades u where u.contrato_id = d.contrato_raiz_id),
    'solicitud', (
      select jsonb_build_object('numero', sp.numero, 'estado', sp.estado, 'importe', sp.importe, 'moneda', sp.moneda)
        from public.solicitudes_pago sp where sp.id = d.solicitud_id),
    'diferencias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', x.id, 'numero', x.numero, 'importe', x.importe, 'estado', x.estado, 'motivo', x.motivo,
               'base_antes', x.base_antes, 'base_despues', x.base_despues, 'vigente', x.importe_vigente,
               'nuevo', x.importe_nuevo, 'origen', x.origen, 'provocado_por', x.provocado_por,
               'resuelto_por', x.resuelto_por, 'resuelto_en', x.resuelto_en, 'resolucion_motivo', x.resolucion_motivo,
               'solicitud', (select jsonb_build_object('numero', sp.numero, 'estado', sp.estado)
                               from public.solicitudes_pago sp where sp.id = x.solicitud_id),
               'creada', x.created_at) order by x.created_at), '[]'::jsonb)
        from public.comisiones_diferencias x where x.devengo_id = d.id),
    'historial', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'en', l.creado_en, 'tabla', l.tabla, 'accion', l.accion, 'antes', l.importe_antes, 'despues', l.importe_despues,
               'estado_antes', l.estado_antes, 'estado_despues', l.estado_despues, 'motivo', l.motivo, 'quien', l.actor_email)
             order by l.creado_en), '[]'::jsonb)
        from public.comisiones_ajustes_log l
       where (l.tabla = 'comisiones_devengadas' and l.fila_id = d.id)
          or (l.tabla = 'solicitudes_pago' and l.fila_id = d.solicitud_id)
          or (l.tabla = 'comisiones_diferencias' and l.fila_id in (select x.id from public.comisiones_diferencias x where x.devengo_id = d.id)))
  );
end $$;
revoke execute on function public.comision_trazabilidad(uuid) from public, anon;
grant execute on function public.comision_trazabilidad(uuid) to authenticated;
