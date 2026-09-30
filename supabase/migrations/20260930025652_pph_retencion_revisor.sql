-- destructivo-ok: tabla vacía (0 filas verificado), sin llamador, rediseño pedido por Seg/Admin/Legal en consulta de deploy
-- ═══════════════════════════════════════════════════════════════════════════
-- RETENCIÓN PPh — rediseño tras el revisor de código y la consulta de deploy (Seguridad,
-- Administración, Legal) sobre 20260930022612 (30-sep-2026). Migración de SEGUIMIENTO: la
-- anterior ya está aplicada y no se reescribe. Las dos tablas estaban vacías y sin llamador,
-- así que se rehacen enteras (el 0 se comprueba en esta misma transacción, abajo).
--
-- Revisor de código
--  R1. Importe o número con texto que no se entiende → 22023; nunca se convierte en 0.
--  R2. Reducir la exposición: sin llamador todavía, `authenticated` no tiene SELECT de la
--      tabla ni EXECUTE de las RPC; quedan postgres y service_role.
--      SE CONCEDE CUANDO EXISTA LA PANTALLA DE /intranet/v4/comisiones/:
--        grant select on public.solicitudes_pago_retencion to authenticated;
--        grant execute on function public.solicitud_pago_retencion_guarda(uuid, jsonb),
--          public.solicitud_pago_retencion_rectifica(uuid, text, text) to authenticated;
--      La policy de lectura queda puesta para ese día.
--  R3. El bukti potong y el ingreso en la DJP van en IDR: bruto_idr, base_idr y
--      pph_retenido_idr los calcula la base desde tipo_cambio_idr (que teclea el admin:
--      ningún tipo de cambio en código). Obligatorios antes de numerar si moneda <> 'IDR';
--      en IDR el cambio es 1. Se congelan con el resto al numerar.
--  R5. djp_ingresado_el y retencion_fecha no pueden ser futuras (hoy en Asia/Makassar).
-- Seguridad
--  S1. El perceptor se reconoce SOLO por perceptor_user_id: la lectura y el candado «nadie
--      registra la suya». La RPC se niega si el beneficiario no tiene usuario.
--  S2. El usuario se busca por lower(email) y se exige exactamente uno (solicitudes_pago no
--      guarda el uid del beneficiario, solo su email).
--  S3. Booleanos y fechas se validan con 22023, sin casts que den 22P02.
--  S4. _retencion_antes sin SECURITY DEFINER: solo toca NEW.
--  S5. El log no guarda el id fiscal ni el TIN en claro: últimos 4.
-- Legal
--  L1. Un solo perceptor_id_fiscal: persona residente = NIK/NPWP16 (16 dígitos); empresa
--      residente = NPWP (15 o 16); no residente (pph26) = vacío + perceptor_pais +
--      perceptor_tin_extranjero. PPh 26 ⇔ no residente.
-- Administración
--  A1. retencion_fecha (no futura) y masa_pajak (AAAA-MM, lo calcula la base).
--  A2. tarifa_pct y kode_objek_pajak como DATOS que teclea el admin (el gestor aún no ha
--      confirmado tipos: nada fijo en código). pph_retenido lo calcula la base = base ×
--      tarifa; check de ±1 IDR. Retenido 0 o tarifa reducida (casilla del admin) exigen
--      exencion_motivo + exencion_documento_ref.
--  A3. Rectificación: varias filas por solicitud (version, estado normal|pembetulan|batal,
--      sustituye_a). Cada corrección es una FILA NUEVA y la anterior se marca `sustituida`
--      (lo único que cambia de una fila congelada, y solo por la RPC de rectificar). Índice
--      único: una vigente por solicitud (estado <> 'batal' y no sustituida).
--  A4. pemotong_entidad: la sociedad que retiene (FK a sociedades), congelada.
--  A5. tipo_cambio_fuente en lista ('kurs_pajak_kmk'); tipo_cambio_fecha entre
--      retencion_fecha − 7 y retencion_fecha (la semana del KMK).
--
-- PENDIENTE DE DECISIÓN DEL OWNER: el invariante «bruto − retenido = transferido» NO se
-- impone. Depende de si `solicitudes_pago.importe` es el bruto de la comisión o el neto que
-- se transfiere; hasta que el owner lo decida, bruto = importe de la solicitud.
-- Paridad con el ERP maestro → F9. La tabla expone el importe de comisión → inventario de
-- `comision_visible` (F4). Nada de datos reales en este fichero: el repo es público.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if (select count(*) from public.solicitudes_pago_retencion) + (select count(*) from public.solicitudes_pago_retencion_log) > 0 then
    raise exception 'Las tablas de retención ya tienen filas: este rediseño las borraría. Parar.';
  end if;
end $$;
drop table public.solicitudes_pago_retencion_log;
drop table public.solicitudes_pago_retencion;
-- la RPC vieja devolvía void y la nueva devuelve el id: `create or replace` no cambia el tipo de
-- retorno, así que se borra antes (sin llamador en la app; es de estas mismas tablas).
drop function if exists public.solicitud_pago_retencion_guarda(uuid, jsonb);

create table public.solicitudes_pago_retencion (
  id                      uuid primary key default gen_random_uuid(),
  solicitud_id            uuid not null references public.solicitudes_pago(id),
  version                 int  not null check (version >= 1),
  estado                  text not null default 'normal' check (estado in ('normal','pembetulan','batal')),
  sustituye_a             uuid references public.solicitudes_pago_retencion(id),
  sustituida              boolean not null default false,
  motivo                  text,
  pemotong_entidad        text not null references public.sociedades(clave),
  -- perceptor: copia congelada (valor + id del dueño), la pone el servidor
  perceptor_user_id       uuid not null references public.usuarios(user_id),
  perceptor_email         text not null check (btrim(perceptor_email) <> ''),
  perceptor_tipo          text not null check (perceptor_tipo in ('persona','empresa')),
  perceptor_nombre_fiscal text not null check (btrim(perceptor_nombre_fiscal) <> ''),
  perceptor_residente     boolean not null,
  perceptor_id_fiscal     text check (perceptor_id_fiscal ~ '^[0-9]{15,16}$'),
  perceptor_pais          text check (perceptor_pais ~ '^[A-Z]{2}$'),
  perceptor_tin_extranjero text check (btrim(perceptor_tin_extranjero) <> ''),
  -- importes en la moneda de la solicitud
  moneda                  text not null check (moneda ~ '^[A-Z]{3}$'),
  bruto                   numeric(18,2) not null check (bruto > 0),
  base                    numeric(18,2) not null check (base >= 0),
  pph_tipo                text not null check (pph_tipo in ('pph21','pph23','pph26')),
  kode_objek_pajak        text check (kode_objek_pajak ~ '^[0-9]{2}-[0-9]{3}-[0-9]{2}$'),
  tarifa_pct              numeric(7,4) not null check (tarifa_pct >= 0 and tarifa_pct <= 100),
  tarifa_reducida         boolean not null default false,
  pph_retenido            numeric(18,2) not null check (pph_retenido >= 0),   -- lo calcula la base
  exencion_motivo         text check (btrim(exencion_motivo) <> ''),
  exencion_documento_ref  text check (btrim(exencion_documento_ref) <> ''),
  retencion_fecha         date not null,
  masa_pajak              text not null check (masa_pajak ~ '^[0-9]{4}-[0-9]{2}$'),  -- la calcula la base
  -- en IDR (el bukti potong y el ingreso van en rupias)
  tipo_cambio_idr         numeric(18,6) check (tipo_cambio_idr > 0),
  tipo_cambio_fuente      text check (tipo_cambio_fuente in ('kurs_pajak_kmk')),
  tipo_cambio_fecha       date,
  bruto_idr               numeric(18,0),
  base_idr                numeric(18,0),
  pph_retenido_idr        numeric(18,0),
  -- documento y liquidación con la DJP
  bukti_potong_numero     text check (btrim(bukti_potong_numero) <> ''),
  bukti_potong_en         timestamptz,
  djp_ingresado_el        date,
  djp_justificante_ref    text check (btrim(djp_justificante_ref) <> ''),
  creado_por              uuid,
  creado_en               timestamptz not null default now(),
  actualizado_por         uuid,
  actualizado_en          timestamptz,
  constraint retencion_version_unica     unique (solicitud_id, version),
  constraint retencion_base_no_supera    check (base <= bruto),
  constraint retencion_pph_no_supera     check (pph_retenido <= base),
  constraint retencion_motivo_correccion check (estado = 'normal' or nullif(btrim(motivo), '') is not null),
  constraint retencion_correccion_enlazada check (estado = 'normal' or sustituye_a is not null),
  constraint retencion_pph26_no_residente check ((pph_tipo = 'pph26') = (not perceptor_residente)),
  constraint retencion_id_residente check (
    not perceptor_residente
    or (perceptor_pais is null and perceptor_tin_extranjero is null
        and (   (perceptor_tipo = 'persona' and perceptor_id_fiscal ~ '^[0-9]{16}$')
             or (perceptor_tipo = 'empresa' and perceptor_id_fiscal is not null)))),
  constraint retencion_id_no_residente check (
    perceptor_residente
    or (perceptor_id_fiscal is null and perceptor_pais is not null and perceptor_tin_extranjero is not null)),
  constraint retencion_exencion check (
    (pph_retenido > 0 and not tarifa_reducida)
    or (exencion_motivo is not null and exencion_documento_ref is not null)),
  constraint retencion_tarifa_idr check (
    pph_retenido_idr is null or base_idr is null
    or abs(pph_retenido_idr - round(base_idr * tarifa_pct / 100, 0)) <= 1),
  constraint retencion_cambio_semana check (
    tipo_cambio_fecha is null
    or (tipo_cambio_fecha <= retencion_fecha and tipo_cambio_fecha >= retencion_fecha - 7)),
  constraint retencion_idr_misma_moneda check (moneda <> 'IDR' or tipo_cambio_idr = 1),
  constraint retencion_lista_para_bukti check (
    bukti_potong_numero is null
    or (kode_objek_pajak is not null
        and bruto_idr is not null and base_idr is not null and pph_retenido_idr is not null
        and (moneda = 'IDR' or (tipo_cambio_fuente is not null and tipo_cambio_fecha is not null)))),
  constraint retencion_bukti_con_fecha   check ((bukti_potong_numero is null) = (bukti_potong_en is null)),
  constraint retencion_justificante_con_ingreso check (djp_justificante_ref is null or djp_ingresado_el is not null)
);
create unique index solicitudes_pago_retencion_una_vigente
  on public.solicitudes_pago_retencion (solicitud_id) where estado <> 'batal' and not sustituida;
create unique index solicitudes_pago_retencion_bukti_vigente
  on public.solicitudes_pago_retencion (lower(btrim(bukti_potong_numero)))
  where bukti_potong_numero is not null and estado <> 'batal' and not sustituida;
create index solicitudes_pago_retencion_perceptor_idx on public.solicitudes_pago_retencion (perceptor_user_id);
create index solicitudes_pago_retencion_masa_idx on public.solicitudes_pago_retencion (pemotong_entidad, masa_pajak);

create table public.solicitudes_pago_retencion_log (
  id            bigint generated always as identity primary key,
  retencion_id  uuid not null,
  solicitud_id  uuid not null,
  accion        text not null,            -- insert | update
  antes         jsonb,                    -- id fiscal y TIN enmascarados (S5)
  despues       jsonb not null,
  quien         uuid,
  cuando        timestamptz not null default now()
);
create index solicitudes_pago_retencion_log_idx on public.solicitudes_pago_retencion_log (solicitud_id, cuando desc);

-- ── helpers de lectura del JSON (22023, nunca 22P02) ─────────────────────
create or replace function public._ret_fecha(p text, p_campo text)
returns date language plpgsql immutable set search_path = '' as $$
begin
  if nullif(btrim(coalesce(p, '')), '') is null then return null; end if;
  if btrim(p) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception '% no es una fecha válida (AAAA-MM-DD)', p_campo using errcode = '22023';
  end if;
  begin
    return btrim(p)::date;
  exception when others then
    raise exception '% no es una fecha válida (AAAA-MM-DD)', p_campo using errcode = '22023';
  end;
end $$;
create or replace function public._ret_bool(p text, p_campo text)
returns boolean language plpgsql immutable set search_path = '' as $$
begin
  if nullif(btrim(coalesce(p, '')), '') is null then return null; end if;
  if lower(btrim(p)) in ('true','t','1','si','sí') then return true; end if;
  if lower(btrim(p)) in ('false','f','0','no') then return false; end if;
  raise exception '% debe ser sí o no', p_campo using errcode = '22023';
end $$;
revoke all on function public._ret_fecha(text, text), public._ret_bool(text, text) from public, anon, authenticated;

-- ── cálculos, candado y autoría (S4: sin DEFINER, solo toca NEW) ──────────
create or replace function public._retencion_antes()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_libres constant text[] := array['djp_ingresado_el','djp_justificante_ref','sustituida','actualizado_por','actualizado_en'];
begin
  if tg_op = 'UPDATE' then
    new.id := old.id; new.solicitud_id := old.solicitud_id; new.version := old.version;
    new.estado := old.estado; new.sustituye_a := old.sustituye_a;
    new.perceptor_user_id := old.perceptor_user_id; new.perceptor_email := old.perceptor_email;
    new.moneda := old.moneda; new.bruto := old.bruto;
    new.creado_por := old.creado_por; new.creado_en := old.creado_en;
    if old.sustituida and new.sustituida is distinct from old.sustituida then
      raise exception 'Esta retención ya está sustituida' using errcode = '23514';
    end if;
    if new.sustituida and not old.sustituida
       and coalesce(current_setting('app.via_retencion_rectifica', true), '') <> 'on' then
      raise exception 'Una retención solo se sustituye con la rectificación' using errcode = '23514';
    end if;
  end if;

  -- cálculos del servidor: retenido, masa pajak e importes en IDR
  new.pph_retenido := round(new.base * new.tarifa_pct / 100, 2);
  new.masa_pajak := to_char(new.retencion_fecha, 'YYYY-MM');
  if new.moneda = 'IDR' then new.tipo_cambio_idr := 1; end if;
  if new.tipo_cambio_idr is not null then
    new.bruto_idr := round(new.bruto * new.tipo_cambio_idr, 0);
    new.base_idr := round(new.base * new.tipo_cambio_idr, 0);
    new.pph_retenido_idr := round(new.base_idr * new.tarifa_pct / 100, 0);
  else
    new.bruto_idr := null; new.base_idr := null; new.pph_retenido_idr := null;
  end if;
  if new.retencion_fecha > v_hoy then
    raise exception 'La fecha de retención no puede ser futura' using errcode = '22023';
  end if;
  if new.djp_ingresado_el is not null and new.djp_ingresado_el > v_hoy then
    raise exception 'La fecha de ingreso en la DJP no puede ser futura' using errcode = '22023';
  end if;
  if new.bukti_potong_numero is not null and new.bukti_potong_en is null then
    new.bukti_potong_en := now();
  end if;

  if tg_op = 'UPDATE' then
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
    if old.bukti_potong_numero is not null
       and (to_jsonb(new) - v_libres) is distinct from (to_jsonb(old) - v_libres) then
      raise exception 'El bukti potong % ya está emitido: no se modifica; se emite una rectificación (pembetulan) o se anula (batal)', old.bukti_potong_numero using errcode = '23514';
    end if;
    if old.djp_ingresado_el is not null and new.djp_ingresado_el is distinct from old.djp_ingresado_el then
      raise exception 'La fecha de ingreso en la DJP ya está registrada: no se cambia' using errcode = '23514';
    end if;
    if old.djp_justificante_ref is not null and new.djp_justificante_ref is distinct from old.djp_justificante_ref then
      raise exception 'El justificante del ingreso en la DJP ya está registrado: no se cambia' using errcode = '23514';
    end if;
  else
    new.creado_por := (select auth.uid());
    new.creado_en  := now();
    new.actualizado_por := null;
    new.actualizado_en  := null;
  end if;
  return new;
end $$;

create or replace function public._retencion_log()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_nuevo jsonb := to_jsonb(new);
  v_viejo jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
begin
  v_nuevo := v_nuevo || jsonb_build_object(
    'perceptor_id_fiscal', case when new.perceptor_id_fiscal is not null then '…' || right(new.perceptor_id_fiscal, 4) end,
    'perceptor_tin_extranjero', case when new.perceptor_tin_extranjero is not null then '…' || right(new.perceptor_tin_extranjero, 4) end);
  if v_viejo is not null then
    v_viejo := v_viejo || jsonb_build_object(
      'perceptor_id_fiscal', case when old.perceptor_id_fiscal is not null then '…' || right(old.perceptor_id_fiscal, 4) end,
      'perceptor_tin_extranjero', case when old.perceptor_tin_extranjero is not null then '…' || right(old.perceptor_tin_extranjero, 4) end);
  end if;
  insert into public.solicitudes_pago_retencion_log (retencion_id, solicitud_id, accion, antes, despues, quien)
  values (new.id, new.solicitud_id, lower(tg_op), v_viejo, v_nuevo, (select auth.uid()));
  return null;
end $$;

create trigger trg_retencion_antes before insert or update on public.solicitudes_pago_retencion
  for each row execute function public._retencion_antes();
create trigger trg_retencion_log after insert or update on public.solicitudes_pago_retencion
  for each row execute function public._retencion_log();
revoke all on function public._retencion_antes(), public._retencion_log() from public, anon, authenticated;

-- ── puerta común de las dos RPC ───────────────────────────────────────────
create or replace function public._retencion_puerta(p_solicitud uuid)
returns public.solicitudes_pago language plpgsql security definer set search_path = '' as $$
declare s public.solicitudes_pago%rowtype;
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
  return s;
end $$;

-- p_datos: pemotong_entidad, perceptor_tipo, perceptor_nombre_fiscal, perceptor_residente,
-- perceptor_id_fiscal, perceptor_pais, perceptor_tin_extranjero, base, pph_tipo,
-- kode_objek_pajak, tarifa_pct, tarifa_reducida, exencion_motivo, exencion_documento_ref,
-- retencion_fecha, tipo_cambio_idr, tipo_cambio_fuente, tipo_cambio_fecha,
-- bukti_potong_numero, djp_ingresado_el, djp_justificante_ref.
-- Clave ausente = se conserva lo guardado. Edita la fila VIGENTE; si no hay, crea la siguiente
-- versión 'normal'. El retenido, la masa pajak y los importes IDR los calcula la base.
create or replace function public.solicitud_pago_retencion_guarda(p_solicitud uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  s     public.solicitudes_pago%rowtype;
  o     public.solicitudes_pago_retencion%rowtype;
  d     jsonb := coalesce(p_datos, '{}'::jsonb);
  v_uid uuid; v_n int; v_id uuid; v_ver int;
  v_ent text; v_tipo text; v_nombre text; v_res boolean; v_idf text; v_pais text; v_tin text;
  v_base numeric; v_pph text; v_kop text; v_tar numeric; v_red boolean; v_exm text; v_exd text;
  v_fret date; v_tc numeric; v_tcf text; v_tcd date; v_bukti text; v_ing date; v_just text;
begin
  s := public._retencion_puerta(p_solicitud);
  if nullif(btrim(coalesce(s.beneficiario_email, '')), '') is null then
    raise exception 'Esta solicitud no tiene beneficiario: no hay perceptor al que retener' using errcode = '22023';
  end if;
  select count(*), max(u.user_id::text)::uuid into v_n, v_uid
    from public.usuarios u where lower(u.email) = lower(btrim(s.beneficiario_email));
  if v_n = 0 then
    raise exception 'El beneficiario de esta solicitud no tiene usuario en la intranet: dalo de alta antes de registrar su retención' using errcode = '22023';
  elsif v_n > 1 then
    raise exception 'Hay % usuarios con el email del beneficiario: resuélvelo en Usuarios antes de registrar la retención', v_n using errcode = '22023';
  end if;
  if v_uid = (select auth.uid()) then
    raise exception 'Nadie registra la retención de un pago a su propio nombre' using errcode = '42501';
  end if;

  select * into o from public.solicitudes_pago_retencion r
   where r.solicitud_id = p_solicitud and r.estado <> 'batal' and not r.sustituida;

  -- importes y números: clave presente que no se entiende → error (R1)
  if d ? 'base' then
    v_base := public.lw_parse_importe(d->>'base');
    if v_base is null then raise exception 'La base no es un importe válido' using errcode = '22023'; end if;
  else v_base := o.base; end if;
  if d ? 'tarifa_pct' then
    v_tar := public.lw_parse_importe(d->>'tarifa_pct');
    if v_tar is null then raise exception 'La tarifa no es un número válido' using errcode = '22023'; end if;
  else v_tar := o.tarifa_pct; end if;
  if d ? 'tipo_cambio_idr' then
    v_tc := public.lw_parse_importe(d->>'tipo_cambio_idr');
    if v_tc is null and nullif(btrim(coalesce(d->>'tipo_cambio_idr', '')), '') is not null then
      raise exception 'El tipo de cambio no es un número válido' using errcode = '22023';
    end if;
  else v_tc := o.tipo_cambio_idr; end if;

  v_res  := case when d ? 'perceptor_residente' then public._ret_bool(d->>'perceptor_residente', 'Residente') else o.perceptor_residente end;
  v_red  := case when d ? 'tarifa_reducida' then coalesce(public._ret_bool(d->>'tarifa_reducida', 'Tarifa reducida'), false) else coalesce(o.tarifa_reducida, false) end;
  v_fret := case when d ? 'retencion_fecha' then public._ret_fecha(d->>'retencion_fecha', 'La fecha de retención') else o.retencion_fecha end;
  v_fret := coalesce(v_fret, (s.pagado_en at time zone 'Asia/Makassar')::date);
  v_tcd  := case when d ? 'tipo_cambio_fecha' then public._ret_fecha(d->>'tipo_cambio_fecha', 'La fecha del tipo de cambio') else o.tipo_cambio_fecha end;
  v_ing  := case when d ? 'djp_ingresado_el' then public._ret_fecha(d->>'djp_ingresado_el', 'La fecha de ingreso en la DJP') else o.djp_ingresado_el end;

  v_ent    := case when d ? 'pemotong_entidad' then nullif(btrim(d->>'pemotong_entidad'), '') else o.pemotong_entidad end;
  v_tipo   := case when d ? 'perceptor_tipo' then nullif(btrim(d->>'perceptor_tipo'), '') else o.perceptor_tipo end;
  v_nombre := case when d ? 'perceptor_nombre_fiscal' then nullif(btrim(d->>'perceptor_nombre_fiscal'), '') else o.perceptor_nombre_fiscal end;
  v_idf    := case when d ? 'perceptor_id_fiscal' then nullif(regexp_replace(coalesce(d->>'perceptor_id_fiscal', ''), '[^0-9]', '', 'g'), '') else o.perceptor_id_fiscal end;
  v_pais   := case when d ? 'perceptor_pais' then nullif(upper(btrim(d->>'perceptor_pais')), '') else o.perceptor_pais end;
  v_tin    := case when d ? 'perceptor_tin_extranjero' then nullif(btrim(d->>'perceptor_tin_extranjero'), '') else o.perceptor_tin_extranjero end;
  v_pph    := case when d ? 'pph_tipo' then nullif(btrim(lower(d->>'pph_tipo')), '') else o.pph_tipo end;
  v_kop    := case when d ? 'kode_objek_pajak' then nullif(btrim(d->>'kode_objek_pajak'), '') else o.kode_objek_pajak end;
  v_exm    := case when d ? 'exencion_motivo' then nullif(btrim(d->>'exencion_motivo'), '') else o.exencion_motivo end;
  v_exd    := case when d ? 'exencion_documento_ref' then nullif(btrim(d->>'exencion_documento_ref'), '') else o.exencion_documento_ref end;
  v_tcf    := case when d ? 'tipo_cambio_fuente' then nullif(btrim(d->>'tipo_cambio_fuente'), '') else o.tipo_cambio_fuente end;
  v_bukti  := case when d ? 'bukti_potong_numero' then nullif(btrim(d->>'bukti_potong_numero'), '') else o.bukti_potong_numero end;
  v_just   := case when d ? 'djp_justificante_ref' then nullif(btrim(d->>'djp_justificante_ref'), '') else o.djp_justificante_ref end;

  if v_ent is null or v_tipo is null or v_nombre is null or v_res is null or v_base is null
     or v_pph is null or v_tar is null then
    raise exception 'Faltan datos: sociedad retenedora, tipo de perceptor, nombre fiscal, residencia, base, tipo de PPh y tarifa son obligatorios' using errcode = '22023';
  end if;
  if v_base > s.importe then
    raise exception 'La base (%) no puede superar el bruto pagado (%)', v_base, s.importe using errcode = '22023';
  end if;
  if v_bukti is not null and s.moneda <> 'IDR' and (v_tc is null or v_tcf is null or v_tcd is null) then
    raise exception 'Antes de numerar el bukti potong: tipo de cambio a IDR, su fuente y su fecha' using errcode = '22023';
  end if;

  if o.id is null then
    select coalesce(max(r.version), 0) + 1 into v_ver from public.solicitudes_pago_retencion r where r.solicitud_id = p_solicitud;
    insert into public.solicitudes_pago_retencion (
      solicitud_id, version, estado, pemotong_entidad, perceptor_user_id, perceptor_email,
      perceptor_tipo, perceptor_nombre_fiscal, perceptor_residente, perceptor_id_fiscal, perceptor_pais,
      perceptor_tin_extranjero, moneda, bruto, base, pph_tipo, kode_objek_pajak, tarifa_pct,
      tarifa_reducida, pph_retenido, exencion_motivo, exencion_documento_ref, retencion_fecha, masa_pajak,
      tipo_cambio_idr, tipo_cambio_fuente, tipo_cambio_fecha, bukti_potong_numero, djp_ingresado_el,
      djp_justificante_ref)
    values (s.id, v_ver, 'normal', v_ent, v_uid, lower(btrim(s.beneficiario_email)),
      v_tipo, v_nombre, v_res, v_idf, v_pais, v_tin, s.moneda, s.importe, v_base, v_pph, v_kop, v_tar,
      v_red, 0, v_exm, v_exd, v_fret, to_char(v_fret, 'YYYY-MM'),
      v_tc, v_tcf, v_tcd, v_bukti, v_ing, v_just)
    returning id into v_id;
  else
    update public.solicitudes_pago_retencion r set
      pemotong_entidad = v_ent, perceptor_tipo = v_tipo, perceptor_nombre_fiscal = v_nombre,
      perceptor_residente = v_res, perceptor_id_fiscal = v_idf, perceptor_pais = v_pais,
      perceptor_tin_extranjero = v_tin, base = v_base, pph_tipo = v_pph, kode_objek_pajak = v_kop,
      tarifa_pct = v_tar, tarifa_reducida = v_red, exencion_motivo = v_exm, exencion_documento_ref = v_exd,
      retencion_fecha = v_fret, tipo_cambio_idr = v_tc, tipo_cambio_fuente = v_tcf,
      tipo_cambio_fecha = v_tcd, bukti_potong_numero = v_bukti, djp_ingresado_el = v_ing,
      djp_justificante_ref = v_just
    where r.id = o.id
    returning r.id into v_id;
  end if;
  return v_id;
end $$;

-- Rectificar un bukti potong ya emitido (A3): p_accion 'pembetulan' (nueva versión editable,
-- sin número, copia de la anterior) o 'batal' (anulación: copia congelada con el mismo número).
-- La anterior queda `sustituida`. Motivo obligatorio. Devuelve el id de la fila nueva.
create or replace function public.solicitud_pago_retencion_rectifica(p_solicitud uuid, p_accion text, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  s public.solicitudes_pago%rowtype;
  o public.solicitudes_pago_retencion%rowtype;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_id uuid;
begin
  s := public._retencion_puerta(p_solicitud);
  if p_accion not in ('pembetulan', 'batal') then
    raise exception 'Acción desconocida: % (pembetulan o batal)', p_accion using errcode = '22023';
  end if;
  if v_motivo is null then raise exception 'Rectificar o anular una retención exige un motivo' using errcode = '22023'; end if;
  select * into o from public.solicitudes_pago_retencion r
   where r.solicitud_id = p_solicitud and r.estado <> 'batal' and not r.sustituida for update;
  if not found then raise exception 'Esta solicitud no tiene una retención vigente que rectificar' using errcode = 'P0002'; end if;
  if o.bukti_potong_numero is null then
    raise exception 'La retención aún no tiene bukti potong: se corrige editándola, no con una rectificación' using errcode = '22023';
  end if;
  if o.perceptor_user_id = (select auth.uid()) then
    raise exception 'Nadie rectifica la retención de un pago a su propio nombre' using errcode = '42501';
  end if;

  perform set_config('app.via_retencion_rectifica', 'on', true);
  update public.solicitudes_pago_retencion r set sustituida = true where r.id = o.id;
  perform set_config('app.via_retencion_rectifica', '', true);

  insert into public.solicitudes_pago_retencion (
    solicitud_id, version, estado, sustituye_a, motivo, pemotong_entidad, perceptor_user_id, perceptor_email,
    perceptor_tipo, perceptor_nombre_fiscal, perceptor_residente, perceptor_id_fiscal, perceptor_pais,
    perceptor_tin_extranjero, moneda, bruto, base, pph_tipo, kode_objek_pajak, tarifa_pct,
    tarifa_reducida, pph_retenido, exencion_motivo, exencion_documento_ref, retencion_fecha, masa_pajak,
    tipo_cambio_idr, tipo_cambio_fuente, tipo_cambio_fecha, bukti_potong_numero, djp_ingresado_el,
    djp_justificante_ref)
  select o.solicitud_id, (select max(r.version) + 1 from public.solicitudes_pago_retencion r where r.solicitud_id = p_solicitud),
    p_accion, o.id, v_motivo, o.pemotong_entidad, o.perceptor_user_id, o.perceptor_email,
    o.perceptor_tipo, o.perceptor_nombre_fiscal, o.perceptor_residente, o.perceptor_id_fiscal, o.perceptor_pais,
    o.perceptor_tin_extranjero, o.moneda, o.bruto, o.base, o.pph_tipo, o.kode_objek_pajak, o.tarifa_pct,
    o.tarifa_reducida, o.pph_retenido, o.exencion_motivo, o.exencion_documento_ref, o.retencion_fecha, o.masa_pajak,
    o.tipo_cambio_idr, o.tipo_cambio_fuente, o.tipo_cambio_fecha,
    case when p_accion = 'batal' then o.bukti_potong_numero end,
    case when p_accion = 'batal' then o.djp_ingresado_el end,
    case when p_accion = 'batal' then o.djp_justificante_ref end
  returning id into v_id;
  return v_id;
end $$;

-- ── R2: nace cerrado; S1: la lectura del perceptor solo por su user_id ───
revoke all on function public._retencion_puerta(uuid) from public, anon, authenticated;
revoke all on function public.solicitud_pago_retencion_guarda(uuid, jsonb),
  public.solicitud_pago_retencion_rectifica(uuid, text, text) from public, anon, authenticated;
alter table public.solicitudes_pago_retencion enable row level security;
alter table public.solicitudes_pago_retencion_log enable row level security;
revoke all on public.solicitudes_pago_retencion, public.solicitudes_pago_retencion_log from public, anon, authenticated;

create policy "retencion: admin con casilla todas, el perceptor la suya"
  on public.solicitudes_pago_retencion for select to authenticated
  using ((public.es_admin() and public.puede('comisiones'))
         or perceptor_user_id = (select auth.uid()));
-- solicitudes_pago_retencion_log: sin policy ni grant — nace cerrado (sin llamador en la app).
