-- Lawang · facturas — tipo de documento + enlace real al contrato
-- 28-jul-2026
--
-- 1) `tipo`: Factura / Factura proforma / Recibí.
--    Cada tipo lleva SU PROPIA serie. Una proforma no es un documento fiscal:
--    si consumiera la serie de facturas dejaría huecos en la numeración oficial,
--    que es justo lo que un contable no puede explicar. INV / PRO / REC.
--    El número se asigna al guardar y NO se recalcula: cambiar el tipo de un
--    documento ya emitido no lo renumera (la app bloquea el selector una vez
--    guardado, por eso mismo).
--
-- 2) `contrato_id`: la relación de verdad, con FK. Un contrato puede tener
--    VARIAS facturas, así que el enlace vive en el lado de la factura; desde el
--    contrato se listan sus facturas con un select por `contrato_id`. Se evita a
--    propósito duplicar un "tiene_factura" en `contratos`: serían dos verdades
--    que acaban contradiciéndose en cuanto una factura se anule.
--    `on delete set null`: borrar un contrato no debe llevarse por delante una
--    factura ya emitida.

alter table public.facturas
  add column if not exists tipo        text not null default 'factura',
  add column if not exists contrato_id uuid references public.contratos(id) on delete set null;

do $$ begin
  alter table public.facturas
    add constraint facturas_tipo_check check (tipo in ('factura','proforma','recibi'));
exception when duplicate_object then null; end $$;

create index if not exists facturas_contrato_id_idx on public.facturas(contrato_id);

create sequence if not exists public.facturas_proforma_seq;
create sequence if not exists public.facturas_recibi_seq;

create or replace function public.set_factura_numero()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.numero is null then
    new.numero := case new.tipo
      when 'proforma' then 'PRO' || lpad(nextval('public.facturas_proforma_seq')::text, 5, '0')
      when 'recibi'   then 'REC' || lpad(nextval('public.facturas_recibi_seq')::text, 5, '0')
      else                 'INV' || lpad(nextval('public.facturas_seq')::text, 5, '0')
    end;
  end if;
  return new;
end;
$$;

comment on column public.facturas.tipo is
  'factura | proforma | recibi. Decide el prefijo del numero (INV/PRO/REC), cada uno con su serie.';
comment on column public.facturas.contrato_id is
  'Contrato del que sale esta factura. Un contrato puede tener varias.';

-- Comprobación:
-- select column_name from information_schema.columns where table_name='facturas' and column_name in ('tipo','contrato_id');
