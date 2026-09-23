-- destructivo-ok: ningún dato se borra al aplicar — DROP CONSTRAINT/POLICY/TRIGGER sustituyen por su versión nueva (CHECK ampliado con 'anulada'), TRUNCATE es un REVOKE que QUITA ese permiso, y el DELETE vive dentro de comision_recalcular (solo super_admin, pedido por el owner 23-sep, con copia al log).
-- Comisiones: el owner puede SIEMPRE editar o borrar (23-sep-2026, «siempre permíteme
-- editar o borrar»). Revisión previa #51 (Seguridad + Administración, ÁMBAR ambas):
--   · borrar = ANULAR con motivo (queda rastro y el motor no la regenera), nunca DELETE
--     de algo pagado ni aprobado;
--   · el devengo NO se sobrescribe: `importe` es lo que calculó el motor y el ajuste
--     humano va aparte (`importe_ajustado` + motivo + quién + cuándo);
--   · quien edita el importe no puede aprobarlo ni pagarlo (colusión entre admins);
--   · el beneficiario nunca toca lo suyo;
--   · log de solo añadir, escrito únicamente por funciones DEFINER;
--   · «Borrar y recalcular» solo super_admin, solo sobre pendientes/anuladas/rechazadas.
-- Nunca importes negativos: corregir una pagada es otra solicitud (Administración #1).
--
-- De paso: `authenticated` no tenía GRANT UPDATE sobre comisiones_devengadas, así que el
-- «Marcar pagada» del manager en «Reparto de equipo» fallaba siempre (el GRANT manda
-- antes que la policy). Se da UPDATE SOLO en las columnas de ese cierre.

-- ───────────────────────── log de ajustes ─────────────────────────
create table if not exists public.comisiones_ajustes_log (
  id            bigint generated always as identity primary key,
  tabla         text not null check (tabla in ('solicitudes_pago','comisiones_devengadas')),
  fila_id       uuid not null,
  accion        text not null check (accion in ('editar_importe','anular','recalcular')),
  actor         uuid default auth.uid(),
  actor_email   text default auth.email(),
  importe_antes numeric,
  importe_despues numeric,
  estado_antes  text,
  estado_despues text,
  motivo        text not null check (btrim(motivo) <> ''),
  copia         jsonb,
  creado_en     timestamptz not null default now()
);
alter table public.comisiones_ajustes_log enable row level security;
revoke all on public.comisiones_ajustes_log from anon, authenticated;
grant select on public.comisiones_ajustes_log to authenticated;
drop policy if exists "comisiones_ajustes_log: admin lee" on public.comisiones_ajustes_log;
create policy "comisiones_ajustes_log: admin lee" on public.comisiones_ajustes_log
  for select to authenticated using (public.es_admin());
create index if not exists comisiones_ajustes_log_fila on public.comisiones_ajustes_log (fila_id);

-- ───────────────────────── columnas nuevas ─────────────────────────
alter table public.solicitudes_pago
  add column if not exists importe_editado_por uuid references public.usuarios(user_id),
  add column if not exists motivo_ajuste text;

alter table public.comisiones_devengadas
  add column if not exists importe_ajustado numeric check (importe_ajustado is null or importe_ajustado > 0),
  add column if not exists ajuste_motivo text,
  add column if not exists ajustado_por uuid,
  add column if not exists ajustado_en timestamptz,
  add column if not exists anulado_motivo text,
  add column if not exists anulado_por uuid,
  add column if not exists anulado_en timestamptz;

alter table public.comisiones_devengadas drop constraint if exists comisiones_devengadas_estado_check;
alter table public.comisiones_devengadas add constraint comisiones_devengadas_estado_check
  check (estado in ('pendiente','pagada','en_disputa','anulada'));

-- higiene: la API nunca trunca ni crea triggers
revoke truncate, trigger, references on public.solicitudes_pago from authenticated, anon;

-- ───────────── devengo: el cierre del manager, y solo eso, por la API ─────────────
grant update (estado, pagado_por, pagado_en) on public.comisiones_devengadas to authenticated;

-- INVOKER a propósito: en una función DEFINER `current_user` sería siempre su dueño
-- y el candado no saltaría nunca. Así `current_user` es quien ejecuta el UPDATE.
create or replace function public._trg_comision_devengo_guarda()
returns trigger language plpgsql security invoker set search_path to '' as $$
begin
  -- Las funciones DEFINER del estudio (motor, disputa, ajustes, borrar_operacion)
  -- corren como su dueño: pasan. Por la API (authenticated) solo el cierre
  -- pendiente→pagada, sellado por la base y nunca sobre lo propio.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if not (old.estado = 'pendiente' and new.estado = 'pagada') then
    raise exception 'por aquí solo se marca pagada una comisión pendiente' using errcode = '22023';
  end if;
  if lower(old.beneficiario_email) = lower(coalesce(auth.email(), '')) then
    raise exception 'nadie marca como pagada una comisión a su propio nombre' using errcode = '42501';
  end if;
  new.pagado_por := auth.email();
  new.pagado_en := now();
  return new;
end $$;
drop trigger if exists trg_comision_devengo_guarda on public.comisiones_devengadas;
create trigger trg_comision_devengo_guarda before update on public.comisiones_devengadas
  for each row execute function public._trg_comision_devengo_guarda();

-- ───────────── solicitudes: transición con editar/anular de admin ─────────────
create or replace function public._trg_solicitud_pago_transicion()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_yo      text := lower(coalesce(auth.email(), ''));
  v_benef   boolean := old.beneficiario_email is not null and lower(old.beneficiario_email) = v_yo;
  v_motivo  text := nullif(btrim(coalesce(new.motivo_ajuste, '')), '');
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
        -- concepto, venta y moneda salen del motor: siempre congelados
        new.contrato_id := old.contrato_id; new.concepto := old.concepto;
        new.moneda := old.moneda;
        if new.importe is distinct from old.importe then
          -- el importe, solo un admin que NO cobra esta comisión, y con motivo
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
        -- el devengo guarda el cálculo del motor intacto; el ajuste va aparte
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
      -- en una automática `creado_por` no significa nada (quien registró el recibí,
      -- o el propio beneficiario): siempre por la vía de admin, con motivo
      if old.origen = 'comision_automatica' or old.creado_por is distinct from auth.uid() then
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
    return new;

  elsif old.estado = 'aprobada' and new.estado = 'anulada' then
    -- puede haber una transferencia en curso: solo admin que no cobra, con motivo,
    -- y nunca si ya consta referencia de pago
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
    return new;
  end if;

  raise exception 'una solicitud % no se puede editar', old.estado using errcode = '22023';
end
$function$;

-- ───────────── reparto de equipo (nivel closer, sin solicitud) ─────────────
-- Admin ajusta o anula el devengo de un closer. Nunca el que lo cobra ni el
-- manager de ese equipo (es su propio dinero el que paga).
create or replace function public._comision_devengo_admin_puede(p_id uuid)
returns public.comisiones_devengadas language plpgsql security definer set search_path to '' as $$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), ''));
begin
  if not public.es_admin() then
    raise exception 'solo un administrador ajusta una comisión' using errcode = '42501';
  end if;
  select * into d from public.comisiones_devengadas where id = p_id for update;
  if not found then raise exception 'no existe esa comisión' using errcode = 'P0002'; end if;
  if d.nivel <> 'closer' then
    raise exception 'esta comisión la paga Lawang: se ajusta desde su solicitud de pago' using errcode = '22023';
  end if;
  if d.estado <> 'pendiente' then
    raise exception 'solo se ajusta una comisión pendiente (esta está %)', d.estado using errcode = '22023';
  end if;
  if lower(d.beneficiario_email) = v_yo or exists (
       select 1 from public.equipos_venta ev
        where ev.id = public._equipo_de_condicion_comision(d.condicion_id)
          and lower(ev.manager_email) = v_yo) then
    raise exception 'no puedes ajustar una comisión que cobras o que pagas tú' using errcode = '42501';
  end if;
  return d;
end $$;

create or replace function public.comision_devengo_ajustar(p_id uuid, p_importe numeric, p_motivo text)
returns void language plpgsql security definer set search_path to '' as $$
declare d public.comisiones_devengadas;
begin
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'el ajuste exige un motivo' using errcode = '22023';
  end if;
  if p_importe is null or p_importe <= 0 then
    raise exception 'el importe tiene que ser mayor que cero' using errcode = '22023';
  end if;
  d := public._comision_devengo_admin_puede(p_id);
  insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
  values ('comisiones_devengadas', d.id, 'editar_importe', coalesce(d.importe_ajustado, d.importe), p_importe, d.estado, d.estado, btrim(p_motivo));
  update public.comisiones_devengadas
     set importe_ajustado = p_importe, ajuste_motivo = btrim(p_motivo), ajustado_por = auth.uid(), ajustado_en = now()
   where id = d.id;
end $$;

create or replace function public.comision_devengo_anular(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path to '' as $$
declare d public.comisiones_devengadas;
begin
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'anular exige un motivo' using errcode = '22023';
  end if;
  d := public._comision_devengo_admin_puede(p_id);
  insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo)
  values ('comisiones_devengadas', d.id, 'anular', coalesce(d.importe_ajustado, d.importe), coalesce(d.importe_ajustado, d.importe), d.estado, 'anulada', btrim(p_motivo));
  update public.comisiones_devengadas
     set estado = 'anulada', anulado_motivo = btrim(p_motivo), anulado_por = auth.uid(), anulado_en = now()
   where id = d.id;
end $$;

-- ───────────── borrar y recalcular (solo super_admin) ─────────────
-- Para cuando se corrigió una condición: tira los devengos de la venta y lo que
-- colgaba de ellos, y vuelve a pasar el motor. Las solicitudes vivas se ANULAN
-- (quedan de rastro), los devengos se borran con copia en el log (el unique por
-- tramo impediría regenerar). Se niega si algo de esa venta está aprobado,
-- pagado o en disputa: ahí ya puede haber dinero moviéndose.
create or replace function public.comision_recalcular(p_raiz uuid, p_motivo text)
returns integer language plpgsql security definer set search_path to '' as $$
declare v_motivo text := nullif(btrim(coalesce(p_motivo, '')), ''); d record; n integer;
begin
  if not public.es_super_admin() then
    raise exception 'solo un super admin recalcula comisiones' using errcode = '42501';
  end if;
  if v_motivo is null then
    raise exception 'recalcular exige un motivo' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  if exists (
       select 1 from public.comisiones_devengadas cd
         left join public.solicitudes_pago sp on sp.id = cd.solicitud_id
        where cd.contrato_raiz_id = p_raiz
          and (cd.estado in ('pagada','en_disputa') or sp.estado in ('aprobada','pagada'))) then
    raise exception 'hay comisiones de esta venta aprobadas, pagadas o en disputa: no se recalcula' using errcode = '22023';
  end if;
  if exists (
       select 1 from public.comisiones_devengadas cd
         join public.solicitudes_pago sp on sp.id = cd.solicitud_id
        where cd.contrato_raiz_id = p_raiz and lower(sp.beneficiario_email) = lower(coalesce(auth.email(), ''))) then
    raise exception 'esta venta tiene una comisión a tu nombre: la recalcula otro super admin' using errcode = '42501';
  end if;

  -- 1. anular las solicitudes vivas (el trigger deja su propio rastro)
  update public.solicitudes_pago sp
     set estado = 'anulada', motivo_ajuste = 'Recálculo: ' || v_motivo
   where sp.estado = 'pendiente'
     and sp.id in (select solicitud_id from public.comisiones_devengadas where contrato_raiz_id = p_raiz and solicitud_id is not null);

  -- 2. copia de cada devengo al log y fuera
  for d in select * from public.comisiones_devengadas where contrato_raiz_id = p_raiz loop
    insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
    values ('comisiones_devengadas', d.id, 'recalcular', coalesce(d.importe_ajustado, d.importe), null, d.estado, null, v_motivo, to_jsonb(d));
  end loop;
  delete from public.comisiones_devengadas where contrato_raiz_id = p_raiz;

  -- 3. el motor, con las condiciones de hoy
  n := public.comisiones_evaluar_contrato(p_raiz);
  return coalesce(n, 0);
end $$;

revoke all on function public._comision_devengo_admin_puede(uuid) from public, anon, authenticated;
revoke all on function public.comision_devengo_ajustar(uuid, numeric, text) from public, anon;
revoke all on function public.comision_devengo_anular(uuid, text) from public, anon;
revoke all on function public.comision_recalcular(uuid, text) from public, anon;
grant execute on function public.comision_devengo_ajustar(uuid, numeric, text) to authenticated;
grant execute on function public.comision_devengo_anular(uuid, text) to authenticated;
grant execute on function public.comision_recalcular(uuid, text) to authenticated;
