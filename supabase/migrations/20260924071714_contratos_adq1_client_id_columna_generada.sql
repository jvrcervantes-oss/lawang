-- 24-sep-2026. Editar un comprador daba 500 (statement timeout 8s): trg_cliente_actualizado
-- buscaba sus contratos por (datos->>'adq1_client_id')::uuid, lo que descomprime el datos
-- entero (anexos base64, ~140 MB) de los 263 contratos: 9,5 s. Columna generada + índice.
-- Medido tras aplicar: el UPDATE del comprador, con sus 6 contratos refrescados, ~1 s.
alter table public.contratos add column adq1_client_id uuid
  generated always as ((datos->>'adq1_client_id')::uuid) stored;
create index contratos_adq1_client_id_idx on public.contratos (adq1_client_id);

create or replace function public.trg_cliente_actualizado()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.full_name is not distinct from old.full_name
     and new.passport_number is not distinct from old.passport_number
     and new.email          is not distinct from old.email
     and new.phone          is not distinct from old.phone
     and new.address        is not distinct from old.address
     and new.nationality    is not distinct from old.nationality
     and new.forma_juridica is not distinct from old.forma_juridica
     and new.registro_num   is not distinct from old.registro_num
     and new.rep_nombre     is not distinct from old.rep_nombre
     and new.rep_cargo      is not distinct from old.rep_cargo
     and new.tipo           is not distinct from old.tipo then
    return new;
  end if;

  -- adq1_client_id es COLUMNA generada (espejo de datos->>'adq1_client_id'):
  -- filtrar por la rama del jsonb descomprimía todos los contratos (timeout).
  update public.contratos c
     set datos = public.espeja_comprador(c.datos),
         comprador_nombre = case
           when jsonb_typeof(c.datos->'compradores') = 'array'
                and jsonb_array_length(c.datos->'compradores') > 0
             then c.comprador_nombre
           else new.full_name end
   where c.adq1_client_id = new.id
     and not coalesce(c.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas f
     set cliente_nombre = new.full_name,
         datos = jsonb_set(f.datos, '{fields}',
                   coalesce(f.datos->'fields','{}'::jsonb) ||
                   jsonb_strip_nulls(jsonb_build_object(
                     'cliente_nombre',    new.full_name,
                     'cliente_documento', new.passport_number,
                     'cliente_email',     new.email,
                     'cliente_domicilio', new.address)))
   where f.client_id = new.id
     and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)
     and coalesce(f.cliente_nombre,'') not like '%' || chr(183) || '%'
     and not exists (
       select 1 from public.contratos c
        where c.id = f.contrato_id
          and jsonb_typeof(c.datos->'compradores') = 'array'
          and jsonb_array_length(c.datos->'compradores') > 0);

  return new;
end $function$;
