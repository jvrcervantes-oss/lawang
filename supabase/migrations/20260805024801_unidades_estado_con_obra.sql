-- destructivo-ok: drop de una VISTA (sin datos) para recrearla idéntica + columnas de obra; el "u.*" se expandió al crearla y no incluye las columnas nuevas de unidades
drop view if exists public.unidades_estado;
create view public.unidades_estado as
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
