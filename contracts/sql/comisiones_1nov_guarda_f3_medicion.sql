-- SOLO LECTURA. Medición de la guarda F3 de comisiones (Administración, consulta de deploy del 15-oct-2026 sobre
-- 20261015065609_comisiones_guarda_f3_misma_clase; LAW-627). Se lanza al levantar la congelación del owner, ANTES de
-- decidir el refinamiento de la guarda; no cambia nada. Rol: el que puede llamar a _contrato_cobrado_interno
-- (service_role / editor SQL). Sin json_agg de contratos enteros.
-- No exige raíz firmada: comisiones_1nov_imputacion.sql (línea 19) filtra `bloqueado` en la raíz y por eso nunca ve
-- las familias con raíz sin firmar (G4a/G4b).
--
-- Cómo leer la consulta 1 (familias donde la guarda vieja de 133241 y la nueva de 071000 dan distinto):
--   1 solo_nueva_SIN_precio  → la pregunta (a) de LAW-627: frena solo por piezas que no mueven `p`. Importan las
--                              filas con con_obra_cobrada > 0 (sin obra cobrada, congelar no cuesta nada).
--   2 solo_nueva_con_precio  → congelación legítima (contrato general / PPJB sin firmar con precio).
--   3 solo_vieja             → Bloqueo sin firmar en otra moneda: antes frenaba, ahora no.
--   La columna tipo_pieza_sin_firmar dice qué tipos aparecen de verdad (para fijar la lista sin adivinar).
-- Si sale la clase 1 con obra cobrada, el refinamiento recomendado es, en lugar de la condición actual:
--   and not public._comisiones_parte_obra(c.tipo, e.es_obra)
--   and (coalesce(c.precio_total, 0) > 0 or c.tipo not in ('poa', 'hak_sewa_notario', 'commercial_offer'))
-- (no `precio_total > 0` a secas: un borrador de contrato general sin precio rellenado dejaría pasar la obra), como
-- create or replace posterior protegido con el md5 del cuerpo de 071000.

-- 1) vieja vs nueva
with raices as (
  select r.id as raiz, r.moneda
    from public.contratos r
   where r.contrato_padre_id is null and r.liberado_en is null
), fam as (
  select rz.raiz, rz.moneda as moneda_raiz, c.id, c.tipo, c.moneda,
         coalesce(c.bloqueado, false)                               as firmado,
         coalesce(c.precio_total, 0)                                as precio,
         public._comisiones_parte_obra(c.tipo, e.es_obra)           as es_obra,
         coalesce(c.tipo, '') like 'carta_reserva%'                 as es_carta,
         (c.moneda is not distinct from rz.moneda)                  as misma_moneda
    from raices rz
    join public.contratos c on c.id = rz.raiz or c.contrato_padre_id = rz.raiz
    left join public.contrato_tipo_etapa e on e.tipo = c.tipo
   where c.liberado_en is null
), fam_p as (
  select f.raiz,
         coalesce(sum(f.precio) filter (where f.firmado and f.misma_moneda and not f.es_carta and not f.es_obra), 0) as p,
         coalesce(sum(f.precio) filter (where f.firmado and f.misma_moneda and not f.es_carta and f.es_obra), 0)     as o
    from fam f group by f.raiz
), cand as (          -- donde la guarda decide: sin parcela firmada con precio, con obra firmada con precio
  select fp.raiz from fam_p fp where fp.p = 0 and fp.o > 0
), bloq as (          -- piezas vivas, sin firmar, ni carta ni obra
  select f.raiz, f.tipo, f.precio,
         (f.tipo = 'reserva_parcela') as frena_vieja,     -- 133241: solo el tipo, sin moneda
         f.misma_moneda               as frena_nueva      -- 071000: la clase de `p`, en la moneda de la raíz
    from fam f join cand c on c.raiz = f.raiz
   where not f.firmado and not f.es_carta and not f.es_obra
), fam_g as (
  select b.raiz, bool_or(b.frena_vieja) as vieja, bool_or(b.frena_nueva) as nueva,
         bool_or(b.frena_nueva and b.precio > 0) as nueva_con_precio
    from bloq b group by b.raiz
), obra_cobrada as (
  select f.raiz, sum(public._contrato_cobrado_interno(f.id, f.moneda_raiz)) as co
    from fam f join fam_g g on g.raiz = f.raiz
   where f.firmado and f.misma_moneda and not f.es_carta and f.es_obra
   group by f.raiz
)
select case when g.nueva and not g.vieja and not g.nueva_con_precio then '1 solo_nueva_SIN_precio'
            when g.nueva and not g.vieja                            then '2 solo_nueva_con_precio'
            when g.vieja and not g.nueva                            then '3 solo_vieja (otra moneda: la nueva NO frena)'
       end                                              as clase,
       b.tipo                                           as tipo_pieza_sin_firmar,
       count(distinct b.raiz)                           as familias,
       count(distinct b.raiz) filter (where coalesce(oc.co, 0) > 0) as con_obra_cobrada,
       count(*)                                         as piezas
  from bloq b
  join fam_g g on g.raiz = b.raiz
  left join obra_cobrada oc on oc.raiz = b.raiz
 where g.vieja is distinct from g.nueva
 group by 1, 2
 order by 1, 2;

-- 2) doble cuenta real (distinta de la de LAW-627 (b), que NO ocurre): dos contratos FIRMADOS de la clase parcela, con
--    precio y sin liberar (p. ej. una RP y el contrato general que la sustituye) suman los dos en `p`. Se evita
--    liberando el sustituido (liberado_en). Si sale > 0, cada familia se revisa a mano.
with raices as (
  select r.id as raiz, r.moneda
    from public.contratos r
   where r.contrato_padre_id is null and r.liberado_en is null
), fam as (
  select rz.raiz, c.precio_total,
         coalesce(c.bloqueado, false)                               as firmado,
         public._comisiones_parte_obra(c.tipo, e.es_obra)           as es_obra,
         coalesce(c.tipo, '') like 'carta_reserva%'                 as es_carta,
         (c.moneda is not distinct from rz.moneda)                  as misma_moneda
    from raices rz
    join public.contratos c on c.id = rz.raiz or c.contrato_padre_id = rz.raiz
    left join public.contrato_tipo_etapa e on e.tipo = c.tipo
   where c.liberado_en is null
)
select count(*) as familias_con_2_parcelas_firmadas_con_precio from (
  select f.raiz from fam f
   where f.firmado and f.misma_moneda and not f.es_carta and not f.es_obra and coalesce(f.precio_total, 0) > 0
   group by f.raiz having count(*) > 1) t;
