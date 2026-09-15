create or replace view public.unidades_estado
with (security_invoker = true) as
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
  cp.cobrado_suelo + cp.cobrado_obra as facturado,
  case
    when cp.cobrado_suelo is null then null
    when coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) > 0
      then round((cp.cobrado_suelo + cp.cobrado_obra)
           / coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) * 100, 1)
    else null
  end as pct_cobrado,
  u.fase_masterplan,
  u.zona_masterplan,
  u.precio as precio_guardado,
  c.creado_por as contrato_creado_por,
  cp.cobrado_suelo,
  cp.cobrado_obra,
  cp.obra_firmada
from public.unidades u
left join public.contratos c on c.id = u.contrato_id
left join lateral public.unidad_parte_cobrada_split(u.id) cp on true;

comment on view public.unidades_estado is
  'Estado en vivo de unidades + su contrato. security_invoker=true a proposito (LAW-42,
   reincidente 3 veces): sin esto, un CREATE OR REPLACE se olvida de re-declararlo y la
   vista vuelve a correr con los privilegios del dueno, saltandose la RLS de contratos
   entera. facturado/pct_cobrado/cobrado_suelo/cobrado_obra/obra_firmada salen NULL
   cuando el contrato de la unidad no es visible para quien consulta -- la decision es
   de unidad_parte_cobrada_split() (LAW-186 mitad B, 15-sep-2026), no de esta vista: no
   se duplica el criterio aqui a proposito, para no tener dos copias de la misma regla
   que puedan divergir.';;
