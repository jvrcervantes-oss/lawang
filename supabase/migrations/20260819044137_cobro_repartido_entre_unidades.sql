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
  cobrado as (
    select coalesce(public.contrato_cobrado(r.id), 0)
         + coalesce((select sum(public.contrato_cobrado(h.id))
                       from public.contratos h where h.contrato_padre_id = r.id), 0) as total
      from raiz r
  ),
  hermanas as (
    select count(*) as n, sum(x.precio) as suma
      from public.unidades x join u on x.contrato_id = u.contrato_id
  )
  select case
    when (select suma from hermanas) > 0
      then (select total from cobrado) * (select precio from u) / (select suma from hermanas)
    when (select n from hermanas) > 0
      then (select total from cobrado) / (select n from hermanas)
    else 0
  end;
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
grant select on public.unidades_estado to authenticated;;
