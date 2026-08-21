create or replace view public.unidades_estado as
select
  u.id, u.codigo, u.proyecto, u.tipo, u.superficie_m2, u.precio, u.moneda, u.estado,
  u.contrato_id, u.notas, u.created_at, u.precio_suelo, u.precio_construccion, u.modelo,
  u.obra_fase, u.obra_fecha_entrega, u.obra_actualizado,
  c.numero as contrato_numero, c.comprador_nombre, c.bloqueado as contrato_firmado,
  coalesce(public.contrato_cobrado(u.contrato_id), 0) as facturado,
  case when u.precio > 0 then round(coalesce(public.contrato_cobrado(u.contrato_id), 0) / u.precio * 100, 1) else null end as pct_cobrado,
  u.fase_masterplan, u.zona_masterplan
from public.unidades u
left join public.contratos c on c.id = u.contrato_id;

alter view public.unidades_estado set (security_invoker = true);
revoke all on public.unidades_estado from anon, authenticated;
grant select on public.unidades_estado to authenticated;
;
