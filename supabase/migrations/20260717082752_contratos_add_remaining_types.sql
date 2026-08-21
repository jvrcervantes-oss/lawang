-- Amplía la tabla contratos a los 7 tipos con numeración (todos menos Estatutos,
-- que es plantilla fija sin campos editables y no se guarda).

create sequence if not exists public.contratos_cg_seq start 1;  -- Contrato General (antes Reserva de Proyecto)
create sequence if not exists public.contratos_co_seq start 1;  -- Commercial Offer
create sequence if not exists public.contratos_cr_seq start 1;  -- Carta de Reserva
create sequence if not exists public.contratos_ac_seq start 1;  -- Acuerdo Comercial (antes Colaboración Comercial)
create sequence if not exists public.contratos_po_seq start 1;  -- Protocolo Operativo

alter table public.contratos drop constraint contratos_tipo_check;
alter table public.contratos add constraint contratos_tipo_check check (
  tipo in ('reserva_parcela','construccion','contrato_general','commercial_offer',
           'carta_reserva','acuerdo_comercial','protocolo_operativo')
);

create or replace function public.set_contrato_numero()
returns trigger
language plpgsql
set search_path = ''
as $$
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
    when 'acuerdo_comercial'  then prefix := 'AC'; seqname := 'public.contratos_ac_seq';
    when 'protocolo_operativo' then prefix := 'PO'; seqname := 'public.contratos_po_seq';
    else raise exception 'Tipo de contrato sin numeracion definida: %', new.tipo;
  end case;
  n := nextval(seqname);
  new.numero := prefix || lpad(n::text, 5, '0');
  return new;
end;
$$;;
