-- LAW-186 mitad B, correccion sobre la marcha (15-sep-2026): dos gates que podian divergir
--
-- La migracion 20260915100000 le puso a la VISTA su propio criterio de "es visible"
-- (`u.contrato_id is null or c.id is not null`) para nulear el cobro. La 20260915103000
-- le puso a la FUNCION su propio criterio (`es_suyo(...) or es_manager_de(...) or
-- es_admin()`). Son equivalentes para una sesion real de verdad -- pero son DOS copias
-- de la misma regla, y esta suite ya ha pagado varias veces por exactamente ese patron
-- (contexto/suite_lawang.md: "una lista a mano en dos sitios ES el bug").
--
-- Se detecto probando con una conexion SIN sesion (superuser del MCP, sin JWT):
-- para esa conexion la RLS de `contratos` no aplica (bypassa RLS por ser superuser),
-- asi que la vista veia `c.id is not null` (cree que es visible) mientras la funcion,
-- que si mira `auth.email()` de verdad, devolvia NULL (no hay sesion, no hay permiso).
-- El `coalesce(cp.cobrado_suelo, 0)` de la vista convertia ese NULL de "denegado" en un
-- 0 que parece "nada cobrado". Ese caso concreto (conexion sin JWT) no le pasa a un
-- agente real -- pero tener dos copias de la regla es la forma exacta del bug que
-- tarde o temprano diverge.
--
-- Arreglo: la vista deja de decidir nada. Pasa cp.* tal cual (sin coalesce a 0): la
-- funcion YA devuelve 0 real cuando hay permiso y nada cobrado, y NULL cuando no hay
-- permiso -- la vista ya no necesita, ni debe, volver a preguntarlo.
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
   que puedan divergir.';
