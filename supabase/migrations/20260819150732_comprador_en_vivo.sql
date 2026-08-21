create or replace function public.espeja_comprador(p_datos jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when cl.id is null then p_datos
    else jsonb_set(p_datos, '{fields}',
           coalesce(p_datos->'fields', '{}'::jsonb) ||
           jsonb_strip_nulls(jsonb_build_object(
             'adq1_nombre',         cl.full_name,
             'adq1_pasaporte',      cl.passport_number,
             'adq1_email',          cl.email,
             'adq1_telefono',       cl.phone,
             'adq1_domicilio',      cl.address,
             'adq1_nacionalidad',   cl.nationality,
             'adq1_forma_juridica', cl.forma_juridica,
             'adq1_registro',       cl.registro_num,
             'adq1_rep_nombre',     cl.rep_nombre,
             'adq1_rep_cargo',      cl.rep_cargo,
             'adq1_tipo',           cl.tipo)))
  end
  from (select 1) x
  left join public.clients cl on cl.id = nullif(p_datos->>'adq1_client_id','')::uuid;
$$;

revoke all on function public.espeja_comprador(jsonb) from public, anon, authenticated;

create or replace function public.trg_espejo_comprador()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.bloqueado, false) then return new; end if;
  if exists (select 1 from public.contrato_firmas cf where cf.contrato_id = new.id) then return new; end if;
  new.datos := public.espeja_comprador(new.datos);
  return new;
end $$;

revoke all on function public.trg_espejo_comprador() from public, anon, authenticated;

drop trigger if exists trg_espejo_comprador on public.contratos;
create trigger trg_espejo_comprador before insert or update of datos on public.contratos
  for each row execute function public.trg_espejo_comprador();

create or replace function public.trg_cliente_actualizado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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

  update public.contratos c
     set datos = public.espeja_comprador(c.datos),
         comprador_nombre = case
           when jsonb_typeof(c.datos->'compradores') = 'array'
                and jsonb_array_length(c.datos->'compradores') > 0
             then c.comprador_nombre
           else new.full_name end
   where (c.datos->>'adq1_client_id')::uuid = new.id
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
end $$;

revoke all on function public.trg_cliente_actualizado() from public, anon, authenticated;

drop trigger if exists trg_cliente_actualizado on public.clients;
create trigger trg_cliente_actualizado after update on public.clients
  for each row execute function public.trg_cliente_actualizado();;
