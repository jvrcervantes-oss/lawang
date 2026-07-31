-- Carta de Reserva ampliada — nuevo tipo de contrato con serie propia (CA).
-- 31-jul-2026. Motivo: el memorándum legal 002/LPH-LM/AGP/VII/2026 (despacho del
-- comprador) pedía en la Carta de Reserva quince cosas que no estaban. En vez de
-- reescribir la Carta corta —que tiene contratos ya emitidos— se añade una plantilla
-- APARTE. Necesita tipo propio porque TIPO_SLUG (app.html) mapea tipo→plantilla 1:1:
-- si las dos compartieran tipo, al reabrir un contrato guardado saldría la plantilla
-- equivocada.
--
-- Serie propia CA (no CR) para que las dos cartas no compartan numeración: mezclarlas
-- haría imposible saber, por el número, con qué texto se firmó una operación.

create sequence if not exists public.contratos_ca_seq;

alter table public.contratos drop constraint if exists contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check
  check (tipo = any (array[
    'reserva_parcela','construccion','contrato_general','commercial_offer',
    'carta_reserva','carta_reserva_ampliada','acuerdo_comercial','protocolo_operativo'
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
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$function$;
