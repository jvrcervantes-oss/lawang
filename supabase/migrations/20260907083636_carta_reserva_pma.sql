create sequence if not exists public.contratos_cp_seq;

-- destructivo-ok: es un SWAP de CHECK, no un borrado de datos. Postgres no sabe
-- ampliar la lista de un CHECK en sitio: hay que soltarlo y volver a ponerlo, y
-- ambas van en la MISMA transaccion. Ni una fila se toca, y el estado previo
-- queda en `contracts/sql/carta_reserva_pma_rollback.sql`. Mismo patron con el
-- que se anadieron las series CA (31-jul), CH y PA.
alter table public.contratos drop constraint if exists contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial','protocolo_operativo',
    'ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario','carta_reserva_hak_sewa',
    'poa','cc00014_timon',
    'carta_reserva_pma'
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
    when 'acuerdo_comercial'  then prefix := 'AC'; seqname := 'public.contratos_ac_seq';
    when 'protocolo_operativo' then prefix := 'PO'; seqname := 'public.contratos_po_seq';
    when 'ppjb_bonian'        then prefix := 'PB'; seqname := 'public.contratos_pb_seq';
    when 'ppjb_bonian_c2'     then prefix := 'C2'; seqname := 'public.contratos_c2_seq';
    when 'hak_sewa_notario'   then prefix := 'HS'; seqname := 'public.contratos_hs_seq';
    when 'carta_reserva_hak_sewa' then prefix := 'CH'; seqname := 'public.contratos_ch_seq';
    when 'poa'                then prefix := 'PA'; seqname := 'public.contratos_poa_seq';
    when 'cc00014_timon'      then prefix := 'CC'; seqname := 'public.contratos_cc_seq';
    when 'carta_reserva_pma'  then prefix := 'CP'; seqname := 'public.contratos_cp_seq';
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$function$;;
