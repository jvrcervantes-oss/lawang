create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod     text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy    text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant text;
  ocupada text;
begin
  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  select c.numero into ocupada
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;
  if ocupada is not null then
    raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  update public.unidades u
     set contrato_id = new.id,
         estado = case
           when u.estado in ('bloqueada','no_disponible') then u.estado
           when coalesce(new.bloqueado, false) then 'vendida'
           else 'reservada'
         end
   where u.proyecto = proy and u.codigo = cod;

  return new;
end $$;

drop trigger if exists trg_sincroniza_unidad on public.contratos;
create trigger trg_sincroniza_unidad
  after insert or update on public.contratos
  for each row execute function public.sincroniza_unidad_contrato();

create or replace function public.libera_unidad_sin_contrato()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.contrato_id is null and old.contrato_id is not null
     and new.estado = old.estado
     and old.estado in ('reservada','vendida') then
    new.estado := 'disponible';
  end if;
  return new;
end $$;

drop trigger if exists trg_libera_unidad on public.unidades;
create trigger trg_libera_unidad
  before update on public.unidades
  for each row execute function public.libera_unidad_sin_contrato();

create or replace view public.unidades_estado as
select u.*,
       c.numero          as contrato_numero,
       c.comprador_nombre,
       c.bloqueado       as contrato_firmado,
       coalesce(f.facturado, 0) as facturado,
       case when u.precio > 0
            then round(coalesce(f.facturado, 0) / u.precio * 100, 1) end as pct_cobrado
  from public.unidades u
  left join public.contratos c on c.id = u.contrato_id
  left join lateral (
     select sum(x.total) as facturado
       from public.facturas x
      where x.contrato_id = u.contrato_id
        and coalesce(x.anulada, false) = false
        and x.tipo <> 'proforma'
  ) f on true;

alter view public.unidades_estado set (security_invoker = true);
grant select on public.unidades_estado to authenticated;;
