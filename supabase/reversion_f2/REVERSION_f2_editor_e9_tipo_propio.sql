-- Reversion de la migracion 20261010040000 (E9 · tipo propio emitible, 8-oct-2026).
-- GUARDA: aborta si ya existe algun contrato con tipo propio (fuera de los 17): quitar el tipo dejaria esas filas sin poder editarse. Hay que decidir antes que se hace con ellas.
-- Vuelve al CHECK de 17 tipos, al mapa fijo de _plantilla_slug_de_tipo (sin comodin) y al set_contrato_numero sin la rama CX; elimina los dos triggers, la RPC de lista y sus funciones.
-- La secuencia contratos_cx_seq se DEJA (borrarla destruye el contador de numeros ya emitidos).
-- destructivo-ok: no toca filas; aborta antes si hay contratos de tipo propio
begin;
do $g$
declare n int;
begin
  select count(*) into n from public.contratos c where c.tipo <> all (array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
    'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck']::text[]);
  if n > 0 then raise exception 'REVERSION ABORTADA: hay % contrato(s) con tipo propio', n using errcode = '55000'; end if;
end $g$;
drop trigger trg_00_contrato_tipo_valido on public.contratos;
drop trigger plantilla_propia_archivada on public.plantilla_contrato_versiones;
drop function public._trg_contrato_tipo_valido();
drop function public._trg_plantilla_propia_archivada();
drop function public.plantilla_contratos_propios_activos(text);
alter table public.contratos drop constraint contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check check (
  tipo = any (array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
                    'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck']::text[]));
create or replace function public._plantilla_slug_de_tipo(p_tipo text) returns text
language sql immutable security definer set search_path = '' as $$
  select m.slug from (values
    ('reserva_parcela', 'ppjb_parcela'), ('construccion', 'ppjb_construccion'), ('contrato_general', 'ppjb_reserva'), ('commercial_offer', 'commercial_offer'),
    ('carta_reserva', 'carta_reserva'), ('carta_reserva_ampliada', 'carta_reserva_ampliada'), ('acuerdo_comercial', 'commercial_collaboration'),
    ('protocolo_operativo', 'colaborador_operativo'), ('ppjb_bonian', 'ppjb_bonian'), ('ppjb_bonian_c2', 'ppjb_bonian_c2'), ('hak_sewa_notario', 'hak_sewa_notario'),
    ('carta_reserva_hak_sewa', 'carta_reserva_hak_sewa'), ('carta_reserva_pma', 'carta_reserva_pma'), ('poa', 'poa_notario'), ('cc00014_timon', 'cc00014_timon'),
    ('adenda', 'adenda'), ('carta_reserva_investor_deck', 'carta_reserva_investor_deck')
  ) as m(tipo, slug) where m.tipo = p_tipo
$$;
revoke all on function public._plantilla_slug_de_tipo(text) from public, anon, authenticated, service_role;
-- set_contrato_numero: se restituye el `else raise exception` original (copiar el cuerpo de la migracion 20260910/tipos_de_contrato.sql de antes de este cambio)
create or replace function public.set_contrato_numero() returns trigger language plpgsql set search_path to '' as $$
declare n bigint; prefix text; seqname text;
begin
  if new.numero is not null then return new; end if;
  case new.tipo
    when 'reserva_parcela' then prefix := 'RP'; seqname := 'public.contratos_rp_seq';
    when 'construccion' then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'contrato_general' then prefix := 'CG'; seqname := 'public.contratos_cg_seq';
    when 'commercial_offer' then prefix := 'CO'; seqname := 'public.contratos_co_seq';
    when 'carta_reserva' then prefix := 'CR'; seqname := 'public.contratos_cr_seq';
    when 'carta_reserva_ampliada' then prefix := 'CA'; seqname := 'public.contratos_ca_seq';
    when 'acuerdo_comercial' then prefix := 'AC'; seqname := 'public.contratos_ac_seq';
    when 'protocolo_operativo' then prefix := 'PO'; seqname := 'public.contratos_po_seq';
    when 'ppjb_bonian' then prefix := 'PB'; seqname := 'public.contratos_pb_seq';
    when 'ppjb_bonian_c2' then prefix := 'C2'; seqname := 'public.contratos_c2_seq';
    when 'hak_sewa_notario' then prefix := 'HS'; seqname := 'public.contratos_hs_seq';
    when 'carta_reserva_hak_sewa' then prefix := 'CH'; seqname := 'public.contratos_ch_seq';
    when 'poa' then prefix := 'PA'; seqname := 'public.contratos_poa_seq';
    when 'cc00014_timon' then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'carta_reserva_pma' then prefix := 'CP'; seqname := 'public.contratos_cp_seq';
    when 'adenda' then prefix := 'AD'; seqname := 'public.contratos_ad_seq';
    when 'carta_reserva_investor_deck' then prefix := 'CD'; seqname := 'public.contratos_cd_seq';
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$$;
commit;
