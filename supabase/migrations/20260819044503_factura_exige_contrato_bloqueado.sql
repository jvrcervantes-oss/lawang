create or replace function public.trg_factura_exige_contrato_bloqueado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bloqueado boolean;
  v_numero    text;
begin
  if new.tipo is distinct from 'factura' then return new; end if;

  if tg_op = 'UPDATE'
     and old.tipo is not distinct from new.tipo
     and old.contrato_id is not distinct from new.contrato_id then
    return new;
  end if;

  if new.contrato_id is null then return new; end if;

  select c.bloqueado, c.numero into v_bloqueado, v_numero
    from public.contratos c where c.id = new.contrato_id;

  if not coalesce(v_bloqueado, false) then
    raise exception 'el contrato % no esta bloqueado: una factura se emite cuando el contrato esta firmado y cerrado. Para cobrar antes, emite una proforma y su recibi',
      coalesce(v_numero, '?') using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists trg_factura_exige_contrato_bloqueado on public.facturas;
create trigger trg_factura_exige_contrato_bloqueado
  before insert or update of tipo, contrato_id on public.facturas
  for each row execute function public.trg_factura_exige_contrato_bloqueado();;
