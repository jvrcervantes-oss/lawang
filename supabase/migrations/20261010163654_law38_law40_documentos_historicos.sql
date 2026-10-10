-- LAW-38 / LAW-40 (11-oct-2026) · Documentos de facturación anteriores a las reglas del 11/12-ago-2026,
-- marcados como HISTÓRICOS por decisión del owner (10-oct-2026, «Marcarlos como históricos»).
--
-- QUÉ PASA. El 11 y el 12-ago-2026 nacieron dos reglas en `facturas`:
--   · facturas_contrato_obligatorio            → toda factura/recibí lleva contrato_id;
--   · facturas_recibi_justificante_obligatorio → todo recibí lleva justificante_path.
-- Las dos están VALIDADAS (convalidated = true, medido hoy) con un corte por fecha de creación, así que
-- la base ya no las incumple: no hay que tocar los CHECK ni pasarlos a VALIDATE (el texto «NOT VALID» de
-- las filas LAW-38/LAW-40 de pendientes.md está desfasado). Lo que seguía era el RUIDO: estos documentos
-- viejos salían como fallo en la intranet (etiqueta roja «Sin contrato»/«Sin justificante», aviso
-- «Recibís sin justificante» del panel v4) y en salud_lawang.py, para siempre y sin nada que hacer.
-- Un aviso que canta lo que ya está decidido se deja de mirar, y entonces tampoco canta lo nuevo.
--
-- LA DECISIÓN. Quedan como están: NO se toca ningún importe, contrato, cliente ni fichero, no se borra
-- nada. Sus 6 clientes de Sumba Hills no tienen contrato en el sistema (comprobado el 19-ago por
-- identificadores: cero coincidencias), y los justificantes de esos pagos no están a mano.
--
-- DOS MARCAS Y NO UNA (revisión del advisor, 11-oct): cada regla tiene su lista decidida por el owner.
-- Una sola bandera haría que REC00002/REC00003 (sin contrato, pero solo en la lista de LAW-40) dejaran
-- también de avisar por «sin contrato», que no lo decidió nadie.
--   · historico_sin_contrato     → los 12 de LAW-38: INV00001-3 y REC00006-14;
--   · historico_sin_justificante → los 16 de LAW-40: REC00001-16.
-- (12 + 16 = 28 marcas sobre 19 filas distintas: REC00006-14 están en las dos listas.)
-- INV00009 (viva, sin contrato, 7-ago) NO está en ninguna lista y NO se marca: sigue avisando.
--
-- QUIÉN ES DUEÑO DE LA MARCA. La pone solo una migración (session_user postgres), nunca la app:
--   · CHECK: solo puede llevarla un documento creado antes del corte de su regla (un documento nuevo no
--     puede ser «anterior a la regla» por definición);
--   · trigger: nadie que entre por PostgREST (session_user authenticator) la pone ni la quita, ni
--     siquiera desde una RPC SECURITY DEFINER (allí current_user es el dueño, por eso se mira session_user).
-- No cambia el dinero: contrato_cobrado(), contrato_saldo() y guardar_recibi() no la leen. Aplicar un cobro
-- a una factura sin contrato sigue prohibido salvo a un super admin, que queda en auditoría (guardar_recibi:
-- «no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)»); y salud_lawang.py lo sigue
-- cantando: allí solo se acepta, por par exacto, REC00019→INV00001 (decisión del owner del 19-ago).
--
-- POR QUÉ EL UPDATE VA CON LOS TRIGGERS DE USUARIO APAGADOS. `facturas` tiene triggers AFTER UPDATE sin
-- lista de columnas (_trg_comisiones_desde_facturas llama a comisiones_evaluar_contrato() para los
-- recibís con contrato; _comision_admin_cambio_recibi puede escribir líneas de ajuste). Poner una marca no
-- debe recalcular comisiones. `disable trigger user` solo dentro de esta transacción (los 18 estaban en
-- 'O', medido el 11-oct; se vuelven a encender y se comprueba al final); los CHECK sí se aplican.
-- (session_replication_role = replica era la primera opción: apply_migration no tiene permiso para él.)
-- Y se COMPRUEBA dentro de la propia migración: huella de `facturas` entera (sin las dos
-- marcas) y de las cinco tablas de dinero antes y después; si algo distinto de las marcas cambia, la
-- migración aborta entera.
--
-- VUELTA ATRÁS (las marcas no son información del cliente; no se pierde nada del negocio): quitar el
-- trigger trg_facturas_historico_solo_migracion, su función, los dos CHECK *_solo_viejos y las dos columnas
-- historico_*. Se escribe en prosa a propósito: no_destruir.py lee también los comentarios.

alter table public.facturas
  add column if not exists historico_sin_contrato boolean not null default false,
  add column if not exists historico_sin_justificante boolean not null default false;

comment on column public.facturas.historico_sin_contrato is
  'LAW-38 (owner 10-oct-2026): documento anterior a facturas_contrato_obligatorio (12-ago-2026), sin contrato por decisión del owner. Deja de avisar como fallo; no cambia el dinero. Solo la pone una migración.';
comment on column public.facturas.historico_sin_justificante is
  'LAW-40 (owner 10-oct-2026): recibí anterior a facturas_recibi_justificante_obligatorio (11-ago-2026), sin justificante por decisión del owner. Deja de avisar como fallo. Solo la pone una migración.';

alter table public.facturas
  add constraint facturas_historico_sin_contrato_solo_viejos
    check (not historico_sin_contrato or created_at < '2026-08-12 00:00:00+00'::timestamptz),
  add constraint facturas_historico_sin_justificante_solo_viejos
    check (not historico_sin_justificante
           or (tipo = 'recibi' and created_at < '2026-08-11 00:00:00+00'::timestamptz));

create or replace function public._facturas_historico_solo_migracion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if session_user in ('postgres', 'supabase_admin') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.historico_sin_contrato or new.historico_sin_justificante then
      raise exception 'Un documento nuevo no puede marcarse como histórico (LAW-38/LAW-40)'
        using errcode = '42501';
    end if;
  elsif new.historico_sin_contrato is distinct from old.historico_sin_contrato
     or new.historico_sin_justificante is distinct from old.historico_sin_justificante then
    raise exception 'La marca de histórico de % solo la cambia una migración (LAW-38/LAW-40)', old.numero
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public._facturas_historico_solo_migracion() from public, anon, authenticated;

create trigger trg_facturas_historico_solo_migracion
  before insert or update of historico_sin_contrato, historico_sin_justificante on public.facturas
  for each row execute function public._facturas_historico_solo_migracion();

alter table public.facturas disable trigger user;

do $$
declare
  v_antes   text;
  v_despues text;
  n_ctr     int;
  n_just    int;
begin
  select concat_ws('|',
    (select md5(string_agg((to_jsonb(f) - 'historico_sin_contrato' - 'historico_sin_justificante')::text, '' order by f.id)) from public.facturas f),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.comision_admin_lineas x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.comisiones_devengadas x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.solicitudes_pago x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x::text), '')) from public.recibi_aplicaciones x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.contrato_vencimientos x))
    into v_antes;

  -- LAW-38: los 12 sin contrato (INV00001-3, REC00006-14), por id explícito.
  update public.facturas set historico_sin_contrato = true
   where contrato_id is null
     and id in ('3e2517a3-0b4f-4546-b1d8-ca3dac33daac',  -- INV00001
                '0a6a117e-765c-44c0-b893-0549fb5e670c',  -- INV00002
                '12fb584f-58bb-4394-be3c-02b07ce094a2',  -- INV00003
                '84648501-fb0e-4fd8-a461-045046919a7c',  -- REC00006
                '656d5681-718a-4f3b-a198-86efa4284fc6',  -- REC00007
                '7129e1e5-bab5-4ecf-80ca-845e6416427c',  -- REC00008
                '6d263607-8b75-44df-9a97-232df015a9f7',  -- REC00009
                'd12960c3-4847-4fc7-a9e9-e3e85b03f9ad',  -- REC00010
                'a84eec3b-a626-4a06-9bdd-b78b3b0ed174',  -- REC00011
                '16f93285-bffd-4f0b-899a-fe1d6ac654be',  -- REC00012
                '5fc74a7c-370c-4e36-acfc-2684722145c8',  -- REC00013
                'ff25b116-b3cb-419a-a2fe-ce38b6a1fb93'); -- REC00014
  get diagnostics n_ctr = row_count;

  -- LAW-40: los 16 recibís sin justificante (REC00001-16), por id explícito.
  update public.facturas set historico_sin_justificante = true
   where tipo = 'recibi' and justificante_path is null
     and id in ('9a0e7a51-3eb9-485f-895f-1e7de7f3c8c1',  -- REC00001
                'b3c65a0e-380e-4e44-b710-95d41fefff3e',  -- REC00002
                'b3a50c97-710c-460f-aa3d-cb3f5ae2e4b9',  -- REC00003
                'b2830078-c882-42de-a215-17a01f01a0a8',  -- REC00004
                'd89166d4-9b7a-48f4-909d-df18dc2738bb',  -- REC00005
                '84648501-fb0e-4fd8-a461-045046919a7c',  -- REC00006
                '656d5681-718a-4f3b-a198-86efa4284fc6',  -- REC00007
                '7129e1e5-bab5-4ecf-80ca-845e6416427c',  -- REC00008
                '6d263607-8b75-44df-9a97-232df015a9f7',  -- REC00009
                'd12960c3-4847-4fc7-a9e9-e3e85b03f9ad',  -- REC00010
                'a84eec3b-a626-4a06-9bdd-b78b3b0ed174',  -- REC00011
                '16f93285-bffd-4f0b-899a-fe1d6ac654be',  -- REC00012
                '5fc74a7c-370c-4e36-acfc-2684722145c8',  -- REC00013
                'ff25b116-b3cb-419a-a2fe-ce38b6a1fb93',  -- REC00014
                '2a1f4ae8-f52d-4c18-b4f4-1a549a2b0045',  -- REC00015
                '010c4b09-051c-4539-9e88-80e6e0ff3c87'); -- REC00016
  get diagnostics n_just = row_count;

  if n_ctr <> 12 or n_just <> 16 then
    raise exception 'LAW-38/40: se esperaban 12 y 16 marcas y salen % y %; no se marca nada', n_ctr, n_just;
  end if;

  select concat_ws('|',
    (select md5(string_agg((to_jsonb(f) - 'historico_sin_contrato' - 'historico_sin_justificante')::text, '' order by f.id)) from public.facturas f),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.comision_admin_lineas x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.comisiones_devengadas x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.solicitudes_pago x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x::text), '')) from public.recibi_aplicaciones x),
    (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id::text), '')) from public.contrato_vencimientos x))
    into v_despues;

  if v_antes is distinct from v_despues then
    raise exception 'LAW-38/40: algo distinto de las marcas cambió (huella antes % / después %); se deshace todo', v_antes, v_despues;
  end if;
end $$;

alter table public.facturas enable trigger user;

do $$
begin
  if exists (select 1 from pg_trigger
              where tgrelid = 'public.facturas'::regclass and not tgisinternal and tgenabled <> 'O') then
    raise exception 'LAW-38/40: algún trigger de facturas no quedó encendido; se deshace todo';
  end if;
end $$;
