-- ═══════════════════════════════════════════════════════════════════════════
-- RETENCIÓN PPh EN LOS PAGOS DE COMISIÓN (30-sep-2026) — LAW-306 (a), F0 del encargo
-- encargos/20260930_lawang_equipos_venta_asistente.md (agencia).
--
-- Qué guarda: por cada solicitud de pago PAGADA, la retención que Lawang practica al
-- perceptor — identidad fiscal congelada (persona/empresa, NPWP/NIK, residente, nombre
-- fiscal), bruto, base, tipo de PPh, importe retenido, nº de bukti potong, fecha de
-- ingreso en la DJP y referencia del justificante de ese ingreso. Patrón: columnas pph_*
-- de `gastos` (20260924075945_gastos_proveedores.sql).
--
-- Decisiones (y su porqué):
--  · TABLA APARTE 1:1 y no columnas en `solicitudes_pago`: `_trg_solicitud_pago_transicion`
--    rechaza cualquier UPDATE de una solicitud `pagada`, y el bukti potong, el ingreso en la
--    DJP y su justificante llegan DESPUÉS del pago. Meterlo ahí obligaba a parchear un
--    trigger vivo de dinero; aparte, las columnas viejas no se tocan (huella idéntica).
--  · Solo sobre solicitudes `pagada`: la retención se practica al pagar, y `borrar_operacion`
--    ya se niega a purgar una venta con solicitud pagada, así que la FK (sin cascada) nunca
--    choca con esa purga. Un registro fiscal no se borra: sin DELETE para nadie.
--  · Vale para cualquier origen (`comision_automatica` y `manual`: una comisión también se
--    pide a mano), pero exige beneficiario: una solicitud sin `beneficiario_email` no tiene
--    perceptor al que retener, y se rechaza con mensaje.
--  · El perceptor lo pone el SERVIDOR desde la solicitud (email + user_id: copia congelada
--    con el id de su dueño); bruto y moneda también. Del navegador solo llega lo que el
--    servidor no puede saber: identidad fiscal, base, tipo, retenido y los datos del ingreso.
--  · Identidad fiscal SIN fuente viva todavía: no se crea un almacén de NIK/NPWP sin llamador
--    (reducir la exposición). La trae F8 (identidad fiscal de los SM, pendiente del owner);
--    entonces la RPC rellenará esta copia desde esa fuente en vez de desde el formulario.
--  · Tipos de PPh como LISTA (pph21/pph23/pph26), SIN porcentajes ni reglas de base en
--    código: están pendientes del gestor indonesio. El admin teclea base y retenido.
--  · Congelado = cuando se numera el bukti potong: ese es el documento que recibe el
--    perceptor y debe seguir diciendo lo mismo. Antes se puede corregir (queda en el log);
--    después, identidad e importes son inmutables y los datos del ingreso en la DJP se
--    rellenan una sola vez. Candado en trigger de la tabla, no solo en la RPC.
--  · Escribe solo admin con casilla `comisiones` y que NO sea el perceptor, por RPC DEFINER.
--    `authenticated` solo lee: admin con casilla todas; el perceptor la suya (la necesita
--    para su bukti potong). Sin la cláusula `creado_por` de la policy de solicitudes: si
--    alguna vez creador ≠ perceptor, vería un NIK ajeno.
--  · Esta tabla expone el importe de la comisión → entra en el inventario de salidas de
--    `comision_visible` (F4). Paridad con el ERP maestro → F9.
--  · Nada de datos reales en este fichero: el repo es público.
-- ═══════════════════════════════════════════════════════════════════════════

create table public.solicitudes_pago_retencion (
  solicitud_id          uuid primary key references public.solicitudes_pago(id),
  -- perceptor: copia congelada (valor + id del dueño), la pone el servidor
  perceptor_user_id     uuid references public.usuarios(user_id),
  perceptor_email       text not null check (btrim(perceptor_email) <> ''),
  perceptor_tipo        text not null check (perceptor_tipo in ('persona','empresa')),
  perceptor_nombre_fiscal text not null check (btrim(perceptor_nombre_fiscal) <> ''),
  perceptor_npwp        text check (perceptor_npwp ~ '^[0-9]{15,16}$'),
  perceptor_nik         text check (perceptor_nik ~ '^[0-9]{16}$'),
  perceptor_residente   boolean not null,
  -- importes
  moneda                text not null check (moneda ~ '^[A-Z]{3}$'),
  bruto                 numeric(18,2) not null check (bruto > 0),
  base                  numeric(18,2) not null check (base >= 0),
  pph_tipo              text not null check (pph_tipo in ('pph21','pph23','pph26')),
  pph_retenido          numeric(18,2) not null default 0 check (pph_retenido >= 0),
  -- documento y liquidación con la DJP
  bukti_potong_numero   text check (btrim(bukti_potong_numero) <> ''),
  bukti_potong_en       timestamptz,          -- cuándo se numeró: desde ahí, congelado
  djp_ingresado_el      date,
  djp_justificante_ref  text check (btrim(djp_justificante_ref) <> ''),
  -- autoría (la pone la base)
  creado_por            uuid,
  creado_en             timestamptz not null default now(),
  actualizado_por       uuid,
  actualizado_en        timestamptz,
  constraint retencion_base_no_supera   check (base <= bruto),
  constraint retencion_pph_no_supera    check (pph_retenido <= base),
  constraint retencion_nik_solo_persona check (perceptor_nik is null or perceptor_tipo = 'persona'),
  constraint retencion_residente_identificado check (
    not perceptor_residente
    or perceptor_npwp is not null
    or (perceptor_tipo = 'persona' and perceptor_nik is not null)),
  constraint retencion_bukti_con_fecha  check ((bukti_potong_numero is null) = (bukti_potong_en is null)),
  constraint retencion_justificante_con_ingreso check (djp_justificante_ref is null or djp_ingresado_el is not null)
);
create unique index solicitudes_pago_retencion_bukti_unico
  on public.solicitudes_pago_retencion (lower(btrim(bukti_potong_numero))) where bukti_potong_numero is not null;
create index solicitudes_pago_retencion_perceptor_idx on public.solicitudes_pago_retencion (lower(perceptor_email));

-- ── log append-only (calca gastos_log) ────────────────────────────────────
create table public.solicitudes_pago_retencion_log (
  id            bigint generated always as identity primary key,
  solicitud_id  uuid not null,
  accion        text not null,            -- insert | update
  antes         jsonb,
  despues       jsonb not null,
  quien         uuid,
  cuando        timestamptz not null default now()
);
create index solicitudes_pago_retencion_log_idx on public.solicitudes_pago_retencion_log (solicitud_id, cuando desc);

-- ── candado y autoría ─────────────────────────────────────────────────────
create or replace function public._retencion_antes()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.solicitud_id := old.solicitud_id;
    new.perceptor_user_id := old.perceptor_user_id;
    new.perceptor_email := old.perceptor_email;
    new.moneda := old.moneda;
    new.bruto := old.bruto;
    new.creado_por := old.creado_por;
    new.creado_en := old.creado_en;
    if old.bukti_potong_numero is not null then
      if (new.perceptor_tipo, new.perceptor_nombre_fiscal, new.perceptor_npwp, new.perceptor_nik,
          new.perceptor_residente, new.base, new.pph_tipo, new.pph_retenido,
          new.bukti_potong_numero, new.bukti_potong_en)
         is distinct from
         (old.perceptor_tipo, old.perceptor_nombre_fiscal, old.perceptor_npwp, old.perceptor_nik,
          old.perceptor_residente, old.base, old.pph_tipo, old.pph_retenido,
          old.bukti_potong_numero, old.bukti_potong_en) then
        raise exception 'El bukti potong % ya está emitido: su retención no se modifica (se corrige con un bukti potong de rectificación)', old.bukti_potong_numero using errcode = '23514';
      end if;
    end if;
    if old.djp_ingresado_el is not null and new.djp_ingresado_el is distinct from old.djp_ingresado_el then
      raise exception 'La fecha de ingreso en la DJP ya está registrada: no se cambia' using errcode = '23514';
    end if;
    if old.djp_justificante_ref is not null and new.djp_justificante_ref is distinct from old.djp_justificante_ref then
      raise exception 'El justificante del ingreso en la DJP ya está registrado: no se cambia' using errcode = '23514';
    end if;
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
  else
    new.creado_por := (select auth.uid());
    new.creado_en  := now();
    new.actualizado_por := null;
    new.actualizado_en  := null;
  end if;
  if new.bukti_potong_numero is not null and new.bukti_potong_en is null then
    new.bukti_potong_en := now();
  end if;
  return new;
end $$;

create or replace function public._retencion_log()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.solicitudes_pago_retencion_log (solicitud_id, accion, antes, despues, quien)
  values (new.solicitud_id, lower(tg_op),
          case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new), (select auth.uid()));
  return null;
end $$;

create trigger trg_retencion_antes before insert or update on public.solicitudes_pago_retencion
  for each row execute function public._retencion_antes();
create trigger trg_retencion_log after insert or update on public.solicitudes_pago_retencion
  for each row execute function public._retencion_log();
revoke all on function public._retencion_antes(), public._retencion_log() from public, anon, authenticated;

-- ── RPC única de escritura ────────────────────────────────────────────────
-- p_datos: perceptor_tipo, perceptor_nombre_fiscal, perceptor_npwp, perceptor_nik,
-- perceptor_residente, base, pph_tipo, pph_retenido, bukti_potong_numero,
-- djp_ingresado_el, djp_justificante_ref. Clave ausente = se conserva lo guardado.
-- Llamador previsto: /intranet/v4/comisiones/ (pantalla pendiente, siguiente paso de F0).
create or replace function public.solicitud_pago_retencion_guarda(p_solicitud uuid, p_datos jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s     public.solicitudes_pago%rowtype;
  o     public.solicitudes_pago_retencion%rowtype;
  v_yo  text := lower(coalesce((select auth.email()), ''));
  v_uid uuid;
  d     jsonb := coalesce(p_datos, '{}'::jsonb);
  v_tipo text; v_nombre text; v_npwp text; v_nik text; v_res boolean;
  v_base numeric; v_pph text; v_ret numeric; v_bukti text; v_ing date; v_just text;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('comisiones')) then
    raise exception 'Solo un administrador con la casilla Comisiones registra retenciones' using errcode = '42501';
  end if;
  select * into s from public.solicitudes_pago sp where sp.id = p_solicitud for update;
  if not found then raise exception 'Esa solicitud ya no existe' using errcode = 'P0002'; end if;
  if s.estado <> 'pagada' then
    raise exception 'La retención se registra sobre una solicitud pagada (esta está %)', s.estado using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(s.beneficiario_email, '')), '') is null then
    raise exception 'Esta solicitud no tiene beneficiario: no hay perceptor al que retener' using errcode = '22023';
  end if;
  if lower(btrim(s.beneficiario_email)) = v_yo then
    raise exception 'Nadie registra la retención de un pago a su propio nombre' using errcode = '42501';
  end if;
  select u.user_id into v_uid from public.usuarios u where lower(u.email) = lower(btrim(s.beneficiario_email)) limit 1;
  select * into o from public.solicitudes_pago_retencion r where r.solicitud_id = p_solicitud;

  v_tipo   := case when d ? 'perceptor_tipo' then nullif(btrim(d->>'perceptor_tipo'), '') else o.perceptor_tipo end;
  v_nombre := case when d ? 'perceptor_nombre_fiscal' then nullif(btrim(d->>'perceptor_nombre_fiscal'), '') else o.perceptor_nombre_fiscal end;
  v_npwp   := case when d ? 'perceptor_npwp' then nullif(regexp_replace(coalesce(d->>'perceptor_npwp', ''), '[^0-9]', '', 'g'), '') else o.perceptor_npwp end;
  v_nik    := case when d ? 'perceptor_nik' then nullif(regexp_replace(coalesce(d->>'perceptor_nik', ''), '[^0-9]', '', 'g'), '') else o.perceptor_nik end;
  v_res    := case when d ? 'perceptor_residente' then (d->>'perceptor_residente')::boolean else o.perceptor_residente end;
  v_base   := case when d ? 'base' then public.lw_parse_importe(d->>'base') else o.base end;
  v_pph    := case when d ? 'pph_tipo' then nullif(btrim(lower(d->>'pph_tipo')), '') else o.pph_tipo end;
  v_ret    := case when d ? 'pph_retenido' then coalesce(public.lw_parse_importe(d->>'pph_retenido'), 0) else coalesce(o.pph_retenido, 0) end;
  v_bukti  := case when d ? 'bukti_potong_numero' then nullif(btrim(d->>'bukti_potong_numero'), '') else o.bukti_potong_numero end;
  v_ing    := case when d ? 'djp_ingresado_el' then nullif(btrim(d->>'djp_ingresado_el'), '')::date else o.djp_ingresado_el end;
  v_just   := case when d ? 'djp_justificante_ref' then nullif(btrim(d->>'djp_justificante_ref'), '') else o.djp_justificante_ref end;

  if v_tipo is null or v_nombre is null or v_res is null or v_base is null or v_pph is null then
    raise exception 'Faltan datos: tipo de perceptor, nombre fiscal, residencia, base y tipo de PPh son obligatorios' using errcode = '22023';
  end if;
  if v_base > s.importe then
    raise exception 'La base (%) no puede superar el bruto pagado (%)', v_base, s.importe using errcode = '22023';
  end if;
  if v_ret > v_base then
    raise exception 'El importe retenido (%) no puede superar la base (%)', v_ret, v_base using errcode = '22023';
  end if;

  if o.solicitud_id is null then
    insert into public.solicitudes_pago_retencion (
      solicitud_id, perceptor_user_id, perceptor_email, perceptor_tipo, perceptor_nombre_fiscal,
      perceptor_npwp, perceptor_nik, perceptor_residente, moneda, bruto, base, pph_tipo, pph_retenido,
      bukti_potong_numero, djp_ingresado_el, djp_justificante_ref)
    values (s.id, v_uid, lower(btrim(s.beneficiario_email)), v_tipo, v_nombre,
      v_npwp, v_nik, v_res, s.moneda, s.importe, v_base, v_pph, v_ret,
      v_bukti, v_ing, v_just);
  else
    update public.solicitudes_pago_retencion r set
      perceptor_tipo = v_tipo, perceptor_nombre_fiscal = v_nombre, perceptor_npwp = v_npwp,
      perceptor_nik = v_nik, perceptor_residente = v_res, base = v_base, pph_tipo = v_pph,
      pph_retenido = v_ret, bukti_potong_numero = v_bukti, djp_ingresado_el = v_ing,
      djp_justificante_ref = v_just
    where r.solicitud_id = p_solicitud;
  end if;
end $$;
revoke all on function public.solicitud_pago_retencion_guarda(uuid, jsonb) from public, anon;
grant execute on function public.solicitud_pago_retencion_guarda(uuid, jsonb) to authenticated;

-- ── RLS y permisos: authenticated solo lee ────────────────────────────────
alter table public.solicitudes_pago_retencion enable row level security;
alter table public.solicitudes_pago_retencion_log enable row level security;
revoke all on public.solicitudes_pago_retencion, public.solicitudes_pago_retencion_log from public, anon, authenticated;
grant select on public.solicitudes_pago_retencion to authenticated;

create policy "retencion: admin con casilla todas, el perceptor la suya"
  on public.solicitudes_pago_retencion for select to authenticated
  using ((public.es_admin() and public.puede('comisiones'))
         or lower(perceptor_email) = lower((select auth.email())));
-- solicitudes_pago_retencion_log: sin policy ni grant — nace cerrado (sin llamador en la app).
