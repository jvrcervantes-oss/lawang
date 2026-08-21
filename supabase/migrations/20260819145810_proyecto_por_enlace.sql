alter table public.contratos add column if not exists proyecto_id uuid references public.proyectos(id);
alter table public.facturas  add column if not exists proyecto_id uuid references public.proyectos(id);
create index if not exists contratos_proyecto_idx on public.contratos (proyecto_id);
create index if not exists facturas_proyecto_idx  on public.facturas  (proyecto_id);

comment on column public.contratos.proyecto_id is
  'Referencia al proyecto. proyecto_nombre es su ESPEJO: se escribe desde aqui en cada guardado y no puede divergir. Si es null, el contrato nombra un proyecto que no esta en la tabla — huerfano visible, no silencioso.';

create or replace function public.trg_espejo_proyecto()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
begin
  if new.proyecto_id is null and nullif(btrim(coalesce(new.proyecto_nombre,'')),'') is not null then
    select p.id into new.proyecto_id from public.proyectos p where p.nombre = new.proyecto_nombre;
  end if;

  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      if tg_table_name = 'contratos' then
        new.proyecto_nombre := v_nombre;
      elsif coalesce(new.proyecto_nombre,'') = '' then
        new.proyecto_nombre := v_nombre;
      end if;
    end if;
  end if;
  return new;
end $$;

revoke all on function public.trg_espejo_proyecto() from public, anon, authenticated;

drop trigger if exists trg_espejo_proyecto on public.contratos;
create trigger trg_espejo_proyecto before insert or update of proyecto_id, proyecto_nombre
  on public.contratos for each row execute function public.trg_espejo_proyecto();

drop trigger if exists trg_espejo_proyecto on public.facturas;
create trigger trg_espejo_proyecto before insert or update of proyecto_id, proyecto_nombre
  on public.facturas for each row execute function public.trg_espejo_proyecto();

create or replace function public.trg_proyecto_renombrado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.nombre is not distinct from old.nombre then return new; end if;

  update public.unidades  set proyecto = new.nombre where proyecto_id = new.id;
  update public.contratos set proyecto_nombre = new.nombre where proyecto_id = new.id;
  update public.facturas
     set proyecto_nombre = replace(proyecto_nombre, old.nombre, new.nombre)
   where proyecto_id = new.id and proyecto_nombre like old.nombre || '%';

  update public.contratos c
     set datos = jsonb_set(c.datos, '{fields,proyecto_nombre}', to_jsonb(new.nombre))
   where c.proyecto_id = new.id
     and not coalesce(c.bloqueado, false)
     and c.datos #>> '{fields,proyecto_nombre}' = old.nombre
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas f
     set datos = jsonb_set(f.datos, '{fields,proyecto_nombre}',
                           to_jsonb(replace(f.datos #>> '{fields,proyecto_nombre}', old.nombre, new.nombre)))
   where f.proyecto_id = new.id
     and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)
     and f.datos #>> '{fields,proyecto_nombre}' like old.nombre || '%';

  return new;
end $$;

revoke all on function public.trg_proyecto_renombrado() from public, anon, authenticated;

drop trigger if exists trg_proyecto_renombrado on public.proyectos;
create trigger trg_proyecto_renombrado after update of nombre on public.proyectos
  for each row execute function public.trg_proyecto_renombrado();

create or replace view public.proyectos_huerfanos as
select 'contrato'::text as tipo, c.numero, c.proyecto_nombre as nombra_a, c.bloqueado as congelado
  from public.contratos c
 where nullif(btrim(coalesce(c.proyecto_nombre,'')),'') is not null and c.proyecto_id is null
union all
select 'factura', f.numero, f.proyecto_nombre, coalesce(f.anulada,false) or coalesce(f.enviada,false)
  from public.facturas f
 where nullif(btrim(coalesce(f.proyecto_nombre,'')),'') is not null and f.proyecto_id is null;

alter view public.proyectos_huerfanos set (security_invoker = true);
grant select on public.proyectos_huerfanos to authenticated;;
