-- Anade cobrado_suelo/cobrado_obra/obra_firmada a unidades_estado (LATERAL a
-- unidad_parte_cobrada_split, misma fuente que ya usa `facturado`, asi que
-- nunca pueden contradecirse). Columnas nuevas al final -- CREATE OR REPLACE
-- VIEW compatible, nada existente cambia de nombre ni de orden.
-- v4/proyectos las usa para la barra de recaudacion por parcela, partida en
-- suelo/construccion (encargo del owner).
create or replace view public.unidades_estado as
select
  u.id,
  u.codigo,
  u.proyecto,
  u.tipo,
  u.superficie_m2,
  coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) as precio,
  u.moneda,
  u.estado,
  u.contrato_id,
  u.notas,
  u.created_at,
  u.precio_suelo,
  u.precio_construccion,
  u.modelo,
  u.obra_fase,
  u.obra_fecha_entrega,
  u.obra_actualizado,
  c.numero as contrato_numero,
  c.comprador_nombre,
  c.bloqueado as contrato_firmado,
  coalesce(cp.cobrado_suelo, 0) + coalesce(cp.cobrado_obra, 0) as facturado,
  case
    when coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) > 0
      then round((coalesce(cp.cobrado_suelo, 0) + coalesce(cp.cobrado_obra, 0))
           / coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) * 100, 1)
    else null
  end as pct_cobrado,
  u.fase_masterplan,
  u.zona_masterplan,
  u.precio as precio_guardado,
  c.creado_por as contrato_creado_por,
  coalesce(cp.cobrado_suelo, 0) as cobrado_suelo,
  coalesce(cp.cobrado_obra, 0) as cobrado_obra,
  coalesce(cp.obra_firmada, false) as obra_firmada
from public.unidades u
left join public.contratos c on c.id = u.contrato_id
left join lateral public.unidad_parte_cobrada_split(u.id) cp on true;
