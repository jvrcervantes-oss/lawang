-- destructivo-ok: contiene ALTER TABLE ... DROP CONSTRAINT (redefine el CHECK
-- de contratos.tipo para admitir el tipo nuevo -- mismo patron ya usado en
-- carta_reserva_ampliada.sql y carta_reserva_pma.sql, no borra ninguna fila,
-- y preserva TODOS los tipos ya existentes leidos en vivo de pg_constraint) y
-- la palabra TRUNCATE aparece solo dentro de un REVOKE (retira un privilegio
-- de anon, no ejecuta ningun TRUNCATE). Nada de esto toca datos existentes.
-- Revision previa hecha (Seguridad+Legal+Desarrollo), CEO/flujos/revision_previa.md.
--
-- INVESTOR DECK / DATA ROOM PÚBLICO — Palm Field (piloto) — 10-sep-2026.
-- Ver comentarios largos en el intento anterior (mismo contenido); aquí solo
-- se corrige la lista de tipos del punto 5, que faltaba de tipos reales en
-- producción (ppjb_bonian, adenda) leídos de pg_get_constraintdef en vivo.

revoke insert, update, delete, truncate, references, trigger
  on public.clients, public.contratos, public.contrato_compradores
  from anon;

alter table public.unidades
  add column if not exists publicado_investor_deck boolean not null default false,
  add column if not exists cuota_reserva_investor_deck numeric;

comment on column public.unidades.publicado_investor_deck is
  'Opt-in explícito: si esta parcela sale en el data room público de inversores. Default false a propósito — nada se publica solo.';
comment on column public.unidades.cuota_reserva_investor_deck is
  'Importe de la cuota de reserva para el flujo autoservicio del Investor Deck. NULL = el botón Reservar no emite nada para esa parcela (pendiente de que un agente lo fije). Nunca se deriva de un porcentaje inventado.';

update public.unidades set publicado_investor_deck = true where proyecto = 'Palm Field W5';

create table if not exists public.investor_deck_config (
  id int primary key default 1,
  validez_reserva_dias int,
  plazo_devolucion_dias int,
  jurisdiccion text,
  updated_at timestamptz not null default now(),
  constraint investor_deck_config_singleton check (id = 1)
);
insert into public.investor_deck_config (id) values (1) on conflict (id) do nothing;
alter table public.investor_deck_config enable row level security;

comment on table public.investor_deck_config is
  'Parámetros legales del flujo de reserva autoservicio (Investor Deck). Fila única, nace vacía: hasta que el owner+Legal la rellenen, investor_deck_reservar() no emite ninguna Carta de Reserva.';

create table if not exists public.investor_deck_verificaciones (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  codigo_hash text not null,
  intentos int not null default 0,
  usado boolean not null default false,
  expira_at timestamptz not null,
  creado_at timestamptz not null default now()
);
create index if not exists investor_deck_verif_email_idx on public.investor_deck_verificaciones (lower(email), creado_at desc);
alter table public.investor_deck_verificaciones enable row level security;

comment on table public.investor_deck_verificaciones is
  'Códigos de un solo uso para confirmar el email del inversor antes de emitir una Carta de Reserva en autoservicio. codigo_hash = sha256(codigo), nunca el código en claro. Solo la toca service_role desde las Edge Functions investor-deck-codigo / investor-deck-reservar.';

create sequence if not exists public.contratos_cd_seq;

alter table public.contratos drop constraint if exists contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial','protocolo_operativo',
    'ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario','carta_reserva_hak_sewa','poa',
    'cc00014_timon','carta_reserva_pma','adenda',
    'carta_reserva_investor_deck'
  ]));

create or replace function public.set_contrato_numero()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  n bigint;
  prefix text;
  seqname text;
begin
  if new.numero is not null then
    return new;
  end if;
  case new.tipo
    when 'reserva_parcela'    then prefix := 'RP'; seqname := 'public.contratos_rp_seq';
    when 'construccion'       then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'contrato_general'   then prefix := 'CG'; seqname := 'public.contratos_cg_seq';
    when 'commercial_offer'   then prefix := 'CO'; seqname := 'public.contratos_co_seq';
    when 'carta_reserva'      then prefix := 'CR'; seqname := 'public.contratos_cr_seq';
    when 'carta_reserva_ampliada' then prefix := 'CA'; seqname := 'public.contratos_ca_seq';
    when 'carta_reserva_hak_sewa' then prefix := 'HS'; seqname := 'public.contratos_hs_seq';
    when 'acuerdo_comercial'  then prefix := 'AC'; seqname := 'public.contratos_ac_seq';
    when 'protocolo_operativo' then prefix := 'PO'; seqname := 'public.contratos_po_seq';
    when 'carta_reserva_pma'  then prefix := 'CP'; seqname := 'public.contratos_cp_seq';
    when 'carta_reserva_investor_deck' then prefix := 'CD'; seqname := 'public.contratos_cd_seq';
    when 'ppjb_bonian'        then prefix := 'PJ'; seqname := 'public.contratos_pj_seq';
    when 'ppjb_bonian_c2'     then prefix := 'PJ'; seqname := 'public.contratos_pj_seq';
    when 'hak_sewa_notario'   then prefix := 'HN'; seqname := 'public.contratos_hn_seq';
    when 'poa'                then prefix := 'PA'; seqname := 'public.contratos_pa_seq';
    when 'cc00014_timon'      then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'adenda'             then prefix := 'AD'; seqname := 'public.contratos_ad_seq';
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$function$;

create or replace function public.investor_deck_parcelas(p_proyecto text)
returns table(codigo text, estado text, superficie_m2 numeric, precio numeric, cuota_reserva numeric, moneda text)
language sql
security definer
stable
set search_path = public
as $$
  select codigo, estado, superficie_m2,
         coalesce(precio, precio_suelo) as precio,
         cuota_reserva_investor_deck as cuota_reserva,
         moneda
    from public.unidades
   where proyecto = p_proyecto
     and publicado_investor_deck = true
   order by codigo;
$$;

revoke all on function public.investor_deck_parcelas(text) from public;
grant execute on function public.investor_deck_parcelas(text) to anon, authenticated;

comment on function public.investor_deck_parcelas is
  'Lectura pública y acotada del inventario para el data room de inversores: solo unidades con publicado_investor_deck=true. Nunca notas, contrato_id ni datos del comprador.';

create or replace function public.investor_deck_reservar(
  p_proyecto text,
  p_codigo text,
  p_email text,
  p_nombre text,
  p_pasaporte text,
  p_telefono text,
  p_nacionalidad text,
  p_domicilio text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text;
  v_precio_suelo numeric;
  v_superficie numeric;
  v_cuota numeric;
  v_cfg record;
  v_datos jsonb;
  v_id uuid;
  v_numero text;
begin
  select * into v_cfg from public.investor_deck_config where id = 1;
  if v_cfg is null or v_cfg.validez_reserva_dias is null or v_cfg.plazo_devolucion_dias is null or v_cfg.jurisdiccion is null then
    return jsonb_build_object('ok', false, 'motivo', 'reserva_no_configurada');
  end if;

  if coalesce(btrim(p_nombre),'') = '' or coalesce(btrim(p_pasaporte),'') = '' or coalesce(btrim(p_email),'') = '' then
    return jsonb_build_object('ok', false, 'motivo', 'datos_incompletos');
  end if;

  select estado, precio_suelo, superficie_m2, cuota_reserva_investor_deck
    into v_estado, v_precio_suelo, v_superficie, v_cuota
    from public.unidades
   where proyecto = p_proyecto and codigo = p_codigo and publicado_investor_deck = true
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'no_disponible');
  end if;
  if v_estado <> 'disponible' then
    return jsonb_build_object('ok', false, 'motivo', 'no_disponible');
  end if;
  if v_cuota is null or v_cuota <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'reserva_no_configurada');
  end if;

  v_datos := jsonb_build_object(
    'fields', jsonb_build_object(
      'proyecto_nombre', p_proyecto,
      'parcela_codigo', p_codigo,
      'adq1_tipo', 'persona',
      'adq1_nombre', btrim(p_nombre),
      'adq1_pasaporte', btrim(p_pasaporte),
      'adq1_email', lower(btrim(p_email)),
      'adq1_telefono', coalesce(btrim(p_telefono), ''),
      'adq1_nacionalidad', coalesce(btrim(p_nacionalidad), ''),
      'adq1_domicilio', coalesce(btrim(p_domicilio), ''),
      'regimen_tenencia', 'Hak Sewa',
      'superficie_suelo_m2', v_superficie::text,
      'precio_suelo', v_precio_suelo::text,
      'precio_reserva', v_cuota::text,
      'validez_dias', v_cfg.validez_reserva_dias::text,
      'plazo_devolucion_dias', v_cfg.plazo_devolucion_dias::text,
      'jurisdiccion', v_cfg.jurisdiccion,
      'fecha_solicitud', to_char(now(), 'DD Mon YYYY')
    )
  );

  insert into public.contratos (tipo, datos, proyecto_nombre, parcela_codigo, precio_total, moneda, creado_por, bloqueado)
  values ('carta_reserva_investor_deck', v_datos, p_proyecto, p_codigo, v_cuota, 'EUR',
          'investor-portal-autoservicio@lawangproperties.com', false)
  returning id, numero into v_id, v_numero;

  return jsonb_build_object('ok', true, 'numero', v_numero, 'contrato_id', v_id);
exception when others then
  raise warning 'investor_deck_reservar(%,%) fallo: %', p_proyecto, p_codigo, sqlerrm;
  return jsonb_build_object('ok', false, 'motivo', 'no_disponible');
end;
$$;

revoke all on function public.investor_deck_reservar(text,text,text,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.investor_deck_reservar(text,text,text,text,text,text,text,text) to service_role;

comment on function public.investor_deck_reservar is
  'Única puerta de escritura del Investor Deck. Solo service_role (Edge investor-deck-reservar, tras verificar el email). Bloqueo atómico por FOR UPDATE, precio server-side, creado_por fijo (no es un agente real), config legal obligatoria antes de emitir nada.';
;
