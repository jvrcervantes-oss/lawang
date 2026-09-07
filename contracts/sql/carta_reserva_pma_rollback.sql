-- Estado PREVIO a `carta_reserva_pma.sql` (7-sep-2026), capturado de la base viva
-- con `pg_get_constraintdef` y `pg_get_functiondef` justo antes de aplicar.
-- Es el "backup" que pide CLAUDE.md para este cambio: aquí no se toca ni una fila,
-- solo el esquema, y la política del estudio es que el esquema se respalda
-- versionándolo (`tools/respaldo_supabase.py` copia DATOS, no esquema, y lo dice).
-- Para revertir: ejecutar este fichero entero. La secuencia `contratos_cp_seq` se
-- queda creada y vacía a propósito — borrarla no aporta nada y sí puede pisar a
-- otra sesión.

alter table public.contratos drop constraint if exists contratos_tipo_check;  -- destructivo-ok: revertir CHECK al estado previo
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial','protocolo_operativo',
    'ppjb_bonian','ppjb_bonian_c2','hak_sewa_notario','carta_reserva_hak_sewa',
    'poa','cc00014_timon'
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
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$function$;
