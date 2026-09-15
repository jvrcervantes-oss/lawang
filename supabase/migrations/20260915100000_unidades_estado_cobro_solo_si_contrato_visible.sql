-- LAW-186 mitad B (15-sep-2026): el cobro de una parcela ajena dejaba de ser secreto
--
-- QUE PASABA. `unidades_estado` (security_invoker=true) hace `left join contratos c` y
-- ESE join si respeta la RLS de `contratos` (`es_suyo(creado_por) or es_manager_de(proyecto_id)`):
-- para el contrato de un companero, `comprador_nombre`/`contrato_numero`/`contrato_firmado`
-- ya salian NULL, correctamente. Pero `facturado`, `pct_cobrado`, `cobrado_suelo`,
-- `cobrado_obra` y `obra_firmada` NO salen de ese join -- salen de
-- `unidad_parte_cobrada_split(u.id)`, que es SECURITY DEFINER y no comprueba ningun
-- permiso: calcula el cobro real de CUALQUIER unidad, la vea o no quien pregunta.
-- El parcelario de v4/Proyectos pinta esa barra por cada unidad visible del proyecto
-- (`barraUnidad()`, datos.js) -- un agente asignado al proyecto sin ser dueno del
-- contrato veia cuanto se habia facturado y que % se habia cobrado de la parcela de
-- un companero. El nombre estaba protegido; el estado de cuentas no.
--
-- Verificado contra la base real antes de tocar nada (no solo leyendo el .sql viejo):
-- select reloptions, pg_get_viewdef() de la vista y prosecdef de la funcion.
--
-- EL ARREGLO va en la VISTA, no en la funcion: `unidad_parte_cobrada_split` la sigue
-- necesitando el manager para agregar una cadena de contratos completa (mismo patron
-- "arithmetic not permission" que factura_aplicado(), documentado en
-- 20260911031517_equipo_deja_de_saltarse_la_rls.sql) -- estrecharla ahi rompería ESE
-- caso legitimo. Lo que hace falta es no PUBLICAR el resultado cuando el contrato no
-- es visible: mismo criterio que ya usa el join para el nombre --
-- `u.contrato_id is null or c.id is not null` -- sin contrato no hay nada que ocultar
-- (siempre 0), y con contrato visible el numero real sigue saliendo igual que antes.
--
-- CREATE OR REPLACE VIEW resetea `security_invoker` si no se declara inline (ya paso
-- 3 veces con esta misma vista) -- aqui va con `with (security_invoker = true)` en la
-- propia cabecera para no depender de acordarse de un ALTER aparte.
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
  case when u.contrato_id is null or c.id is not null
    then coalesce(cp.cobrado_suelo, 0) + coalesce(cp.cobrado_obra, 0)
    else null end as facturado,
  case
    when u.contrato_id is not null and c.id is null then null
    when coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) > 0
      then round((coalesce(cp.cobrado_suelo, 0) + coalesce(cp.cobrado_obra, 0))
           / coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) * 100, 1)
    else null
  end as pct_cobrado,
  u.fase_masterplan,
  u.zona_masterplan,
  u.precio as precio_guardado,
  c.creado_por as contrato_creado_por,
  case when u.contrato_id is null or c.id is not null then coalesce(cp.cobrado_suelo, 0) else null end as cobrado_suelo,
  case when u.contrato_id is null or c.id is not null then coalesce(cp.cobrado_obra, 0) else null end as cobrado_obra,
  case when u.contrato_id is null or c.id is not null then coalesce(cp.obra_firmada, false) else null end as obra_firmada
from public.unidades u
left join public.contratos c on c.id = u.contrato_id
left join lateral public.unidad_parte_cobrada_split(u.id) cp on true;

comment on view public.unidades_estado is
  'Estado en vivo de unidades + su contrato. security_invoker=true a proposito (LAW-42,
   reincidente 3 veces): sin esto, un CREATE OR REPLACE se olvida de re-declararlo y la
   vista vuelve a correr con los privilegios del dueno, saltandose la RLS de contratos
   entera. facturado/pct_cobrado/cobrado_suelo/cobrado_obra/obra_firmada salen NULL
   cuando el contrato de la unidad no es visible para quien consulta (LAW-186 mitad B,
   15-sep-2026): unidad_parte_cobrada_split() es SECURITY DEFINER sin gate de permiso,
   asi que sin este NULL el cobro real de una parcela ajena se veia igual que la del
   propio agente.';
