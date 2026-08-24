-- destructivo-ok: los `drop trigger/policy if exists` son idempotencia estándar
-- sobre objetos que este mismo fichero recrea a continuación (mismo patrón que
-- el resto del repo, ver law71_editar_firmado_y_borrar_facturas.sql); no borra
-- datos ni ningún objeto ajeno. Las dos funciones se `create or replace`, no se
-- borran filas de ninguna tabla.

alter table public.contratos add column if not exists unidad_id uuid references public.unidades(id);
create index if not exists contratos_unidad_id_idx on public.contratos(unidad_id);

create or replace function public.trg_valida_unidad_id_contrato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_raiz uuid;
  v_unidad_contrato uuid;
begin
  if new.unidad_id is null then return new; end if;

  if tg_op = 'UPDATE' and new.unidad_id is distinct from old.unidad_id
     and not public.es_admin() then
    raise exception 'solo un admin puede cambiar la parcela de un contrato ya guardado' using errcode = '42501';
  end if;

  v_raiz := coalesce(new.contrato_padre_id, new.id);
  select contrato_id into v_unidad_contrato from public.unidades where id = new.unidad_id;
  if v_unidad_contrato is distinct from v_raiz then
    raise exception 'unidad_id debe pertenecer a la misma reserva raíz del contrato' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.trg_valida_unidad_id_contrato() from public, anon;

drop trigger if exists trg_valida_unidad_id_contrato on public.contratos;
create trigger trg_valida_unidad_id_contrato
  before insert or update of unidad_id on public.contratos
  for each row execute function public.trg_valida_unidad_id_contrato();

create or replace function public.unidad_parte_cobrada(p_unidad uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  with u as (
    select id, contrato_id, precio from public.unidades where id = p_unidad
  ),
  raiz as (
    select coalesce(c.contrato_padre_id, c.id) as id
      from public.contratos c join u on u.contrato_id = c.id
  ),
  hijos as (
    select h.id, h.unidad_id, coalesce(public.contrato_cobrado(h.id), 0) as cobrado
      from public.contratos h join raiz r on h.contrato_padre_id = r.id
  ),
  hermanas as (
    select x.id, x.precio
      from public.unidades x join u on x.contrato_id = u.contrato_id
  ),
  asignadas as (
    select distinct hj.unidad_id as id from hijos hj where hj.unidad_id is not null
  ),
  hermanas_sin_asignar as (
    select h.id, h.precio from hermanas h
     where not exists (select 1 from asignadas a where a.id = h.id)
  ),
  cobrado_raiz as (
    select coalesce(public.contrato_cobrado(r.id), 0) as total from raiz r
  ),
  cobrado_sin_asignar as (
    select coalesce(sum(hj.cobrado), 0) as total from hijos hj where hj.unidad_id is null
  ),
  cobrado_mio as (
    select coalesce(sum(hj.cobrado), 0) as total from hijos hj where hj.unidad_id = p_unidad
  ),
  tot_hermanas as (select count(*) n, sum(precio) suma from hermanas),
  tot_sin_asignar as (select count(*) n, sum(precio) suma from hermanas_sin_asignar),
  parte_raiz as (
    select case
      when (select suma from tot_hermanas) > 0
        then (select total from cobrado_raiz) * (select precio from u) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0
        then (select total from cobrado_raiz) / (select n from tot_hermanas)
      else 0
    end as v
  ),
  parte_sin_asignar as (
    select case
      when not exists (select 1 from hermanas_sin_asignar where id = p_unidad) then 0
      when (select suma from tot_sin_asignar) > 0
        then (select total from cobrado_sin_asignar) * (select precio from u) / (select suma from tot_sin_asignar)
      when (select n from tot_sin_asignar) > 0
        then (select total from cobrado_sin_asignar) / (select n from tot_sin_asignar)
      else 0
    end as v
  )
  select (select v from parte_raiz) + (select v from parte_sin_asignar) + (select total from cobrado_mio);
$$;

revoke all on function public.unidad_parte_cobrada(uuid) from public, anon;
grant execute on function public.unidad_parte_cobrada(uuid) to authenticated;

create or replace view public.unidades_estado as
select u.id, u.codigo, u.proyecto, u.tipo, u.superficie_m2, u.precio, u.moneda, u.estado,
       u.contrato_id, u.notas, u.created_at, u.precio_suelo, u.precio_construccion, u.modelo,
       u.obra_fase, u.obra_fecha_entrega, u.obra_actualizado,
       c.numero          as contrato_numero,
       c.comprador_nombre,
       c.bloqueado       as contrato_firmado,
       coalesce(public.unidad_parte_cobrada(u.id), 0) as facturado,
       case when u.precio > 0
            then round(coalesce(public.unidad_parte_cobrada(u.id), 0) / u.precio * 100, 1) end as pct_cobrado,
       u.fase_masterplan, u.zona_masterplan
  from public.unidades u
  left join public.contratos c on c.id = u.contrato_id;

alter view public.unidades_estado set (security_invoker = true);
grant select on public.unidades_estado to authenticated;

create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_raiz_id uuid;
  v_mon     text;
  v_nmon    int;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  select min(u.moneda), count(distinct u.moneda)
    into v_mon, v_nmon
    from public.unidades u where u.contrato_id = v_raiz_id;
  if coalesce(v_nmon, 0) > 1 then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from v_mon
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from v_mon
  ) into v_mezcla;
  if v_mezcla then return; end if;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when coalesce(u.precio, 0) > 0
                and public.unidad_parte_cobrada(u.id) >= u.precio then 'cobrada'
           when public.unidad_parte_cobrada(u.id) > 0 then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end;
$$;
;
