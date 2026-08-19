-- ════════════════════════════════════════════════════════════════════════════
-- CADA UNIDAD ENSEÑA SU PARTE DE LO COBRADO — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- EL CASO (owner): RP00055 lleva DOS parcelas, C2 y D3 de Soka Village W2, a
-- 20.000 EUR cada una — 40.000 en total. Se cobran 10.000 de reserva (5.000 por
-- parcela) y la ficha de CADA parcela dice **50% pagado**. Lo pagado es el 25%.
--
-- LA CAUSA: `unidades_estado` compara TODO lo cobrado del contrato contra el
-- precio de UNA unidad — `contrato_cobrado(u.contrato_id) / u.precio`. Con una
-- parcela por contrato salía bien; multi-parcela (18-ago) lo rompió, y el
-- número aparece dos veces (10.000 contra 20.000, y otra vez 10.000 contra
-- 20.000) en vez de repartirse.
--
-- ⚠️ LO QUE **NO** HAY QUE TOCAR, y casi se toca: `avanza_unidad_por_cobro`,
-- que es quien decide cuándo una parcela pasa a `cobrada`, YA está bien desde
-- `parcelas_multiples.sql` (18-ago): compara `v_cobrado >= v_precio_unidades`,
-- o sea contra la SUMA de las unidades del contrato, no contra una. Se sacó su
-- `prosrc` de producción antes de escribir esto y coincide con el repo. Quien
-- lo "arregle" copiando la versión de `estado_unidad_por_tipo_y_cobro.sql` (la
-- de 11-ago, que sigue en el repo) le quitará de paso el control de moneda
-- mezclada (`v_mon`/`v_nmon`) que aquella no tenía. No es el fichero vivo.
--
-- EL REPARTO: proporcional al precio de cada unidad y, si los precios no están
-- puestos (CR00025 tiene tres unidades y `sum(precio)` sale null), a partes
-- iguales. Nunca se inventa un precio: sin precios, tres unidades es un tercio
-- cada una, que es lo único defendible.
--
-- Así el porcentaje de la vista y el salto a `cobrada` dicen lo mismo: la
-- unidad llega al 100% exactamente cuando el contrato cubre la suma de sus
-- unidades, que es cuando la función las marca cobradas.

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
    -- misma raíz que usa avanza_unidad_por_cobro: una Construcción cuelga de su
    -- Reserva y su dinero cuenta para las unidades que retiene la raíz
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

-- ── la vista: cada unidad, su parte ────────────────────────────────────────
-- Mismas columnas, mismo orden y mismos nombres que la vista viva (un CREATE
-- OR REPLACE VIEW falla si no coinciden byte a byte). Solo cambian las dos
-- expresiones. `facturado` pasa a ser lo cobrado DE ESA UNIDAD: la columna vive
-- en una fila de unidad, y el total del contrato ya lo da Operaciones, que
-- calcula el suyo aparte y no lee esta vista.
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

-- ── efecto medido ANTES de aplicar (28 unidades con contrato) ───────────────
-- Cambian 4, y las 4 para bien:
--   · RP00055/C2 y /D3 — el caso del owner: de «50% cada una» a 25% (5.000 de
--     20.000), que es lo pagado de verdad.
--   · RP00050/A2 y RP00021/SH-1 — parcelas con una Construcción colgando. La
--     vista vieja miraba SOLO su propio contrato, así que SH-1 decía 0% con
--     41.620 EUR cobrados en su CC00010 (el caso de LAW-39). Ahora cuenta la
--     raíz y sus hijos, igual que hace `avanza_unidad_por_cobro`.
--
-- Y con eso las dos cosas dicen por fin lo mismo: la parte de una unidad es
--   total_operacion * precio_unidad / suma_precios_del_contrato
-- así que su porcentaje llega al 100% EXACTAMENTE cuando
--   total_operacion >= suma_precios_del_contrato
-- que es la condición con la que la función la marca `cobrada`. Antes podían
-- contradecirse: la ficha decía 60% y el estado ya era «cobrada».
