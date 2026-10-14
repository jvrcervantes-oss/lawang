-- Guarda F3 con la misma clase que la propia regla (15-oct-2026, lawang-cola-2; CAMBIOS del revisor sobre 72e994303, ALTA).
--
-- QUÉ ARREGLA. 20261014133241 (aplicada el 14-oct) frena la obra cuando la venta tiene un Bloqueo de Parcela vivo sin
-- firmar, pero solo miraba tipo = 'reserva_parcela'. La parcela de la regla (`p`) es en cambio todo contrato firmado de
-- la familia que no es obra ni carta (contrato_general, commercial_offer, acuerdo_comercial…). Una raíz contrato_general
-- SIN firmar + una Construcción firmada con el 25 % cobrado devengaba la obra; al firmarse la raíz, la bolsa pasaba
-- entera a la parcela con el devengo de obra ya pagado (y un devengo pagado no se deshace). Ahora la guarda usa la misma
-- clase que `p`: vivo, sin firmar, moneda de la raíz, ni carta ni obra.
--
-- A QUIÉN AFECTA HOY. A nadie todavía: las únicas condiciones que leen lo cobrado por parte (pct_cobrado_suelo_firmado /
-- pct_cobrado_obra_firmada) rigen desde el 1-nov-2026 (medido por la sesión de F3 el 14-oct: 12 sucesoras, todas
-- vigente_desde 2026-11-01). Las BASES (columnas 1–2) no cambian. Solo puede FRENAR un devengo, nunca adelantarlo.
--
-- PRUEBA: contracts/sql/prueba_comisiones_1nov.sql, G4b invertido (raíz contrato_general sin firmar → obra 0, ningún
-- devengo) y G4c nuevo (raíz carta sin firmar → la guarda no aplica, devenga manager:2:8000.00). Corre sobre la venta real
-- RP00133 dentro de una transacción que se deshace y necesita la válvula del owner: NO corre en una rama vacía.
-- VUELTA: supabase/vivo/20261014_cobro_primero_parcela/vuelta_f3b.sql (la definición de 20261014133241).
-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); el maestro no tiene comisiones por cobrado por parte.

create or replace function public._comisiones_bases_firmadas(p_raiz uuid)
 returns table(suelo_firmado numeric, obra_firmada numeric, cobrado_suelo_firmado numeric, cobrado_obra_firmada numeric,
               cobrado_directo_suelo numeric, cobrado_directo_obra numeric, cobrado_cartas numeric, multimoneda boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- Regla del owner del 13-oct-2026 (ventas desde el 1-nov), con «primero la parcela» del 14-oct-2026 (F3).
  -- Conjunto = familia de la raíz (raíz + hijos) FIRMADOS (bloqueados) y no liberados. Parte = _comisiones_parte_obra
  -- (contrato_tipo_etapa.es_obra; adenda = obra; tipo sin fila = no obra).
  -- BASES: las cartas de reserva (raíz o hija) no suman en ninguna («la carta no devenga comisiones»).
  -- COBRADO (14-oct-2026, la idea de _unidad_cobro_cascada pero NO su misma definición de parcela: la cascada toma
  -- parcela = solo la raíz reserva_parcela y deja fuera los Bloqueos hijo; aquí parcela = todo lo firmado que no es
  -- obra ni carta. Divergencia conocida, anotada para que Administración decida si se unifican; revisor, 15-oct):
  --   bolsa   = cobrado en TODOS los contratos firmados de la familia (parcela + cartas + obra)
  --   parcela = least(precio parcela firmada, bolsa)                 -- nunca > 100 %
  --   obra    = least(precio obra firmada, bolsa - parcela)          -- nunca > 100 %
  --   * Sin parcela firmada (precio 0) no hay cascada: la obra cuenta solo lo cobrado en obra (la carta es la señal de
  --     una parcela que aún no existe), y además, si hay en la familia un contrato vivo SIN firmar de la clase de `p`
  --     (ni carta ni obra), la obra cuenta 0 (guarda F3): al firmarse, ese dinero llenaría la parcela con el devengo de
  --     obra ya pagado.
  -- Columnas 5–7: el cobrado en bruto (para el snapshot y la trazabilidad: auditar la imputación).
  -- MONEDA (13-oct-2026): solo cuentan contratos y cobros en la moneda de la raíz; multimoneda = la familia tiene algún
  -- contrato firmado no liberado en otra moneda (el motor y el reconciliador no tocan entonces los tramos «firmados»).
  with r as (
    select c.moneda from public.contratos c where c.id = p_raiz
  ), fam as (
    select c.id, c.tipo, c.moneda, c.precio_total
      from public.contratos c
     where (c.id = p_raiz or c.contrato_padre_id = p_raiz)
       and coalesce(c.bloqueado, false)
       and c.liberado_en is null
  ), x as (
    select f.id, coalesce(f.precio_total, 0) as precio, public._comisiones_parte_obra(f.tipo, e.es_obra) as es_obra,
           coalesce(f.tipo, '') like 'carta_reserva%' as es_carta
      from fam f
      left join public.contrato_tipo_etapa e on e.tipo = f.tipo
     where f.moneda is not distinct from (select r.moneda from r)
  ), y as (
    select x.precio, x.es_obra, x.es_carta, public._contrato_cobrado_interno(x.id, (select r.moneda from r)) as cobrado from x
  ), s as (
    select coalesce(sum(y.precio)  filter (where not y.es_carta and not y.es_obra), 0) as p,
           coalesce(sum(y.precio)  filter (where not y.es_carta and y.es_obra), 0)     as o,
           coalesce(sum(y.cobrado) filter (where not y.es_carta and not y.es_obra), 0) as cp,
           coalesce(sum(y.cobrado) filter (where not y.es_carta and y.es_obra), 0)     as co,
           coalesce(sum(y.cobrado) filter (where y.es_carta), 0)                       as cc
      from y
  ), g as (
    -- Guarda F3 con la MISMA clasificación que `p` (15-oct-2026, revisor): cualquier contrato de la familia, vivo, SIN
    -- firmar, en la moneda de la raíz, que no sea carta ni obra (Bloqueo, contrato_general, oferta, acuerdo…): al
    -- firmarse entraría en `p` y la bolsa llenaría primero la parcela con la obra ya devengada. Antes miraba solo
    -- tipo = 'reserva_parcela' y una raíz contrato_general sin firmar dejaba devengar la obra.
    select exists (select 1 from public.contratos c
                     left join public.contrato_tipo_etapa e on e.tipo = c.tipo
                    where (c.id = p_raiz or c.contrato_padre_id = p_raiz)
                      and not coalesce(c.bloqueado, false)
                      and c.liberado_en is null
                      and c.moneda is not distinct from (select r.moneda from r)
                      and not coalesce(c.tipo, '') like 'carta_reserva%'
                      and not public._comisiones_parte_obra(c.tipo, e.es_obra)) as bloqueo_sin_firmar
  ), i as (
    select s.*, case when s.p > 0 then greatest(least(s.p, s.cp + s.cc + s.co), 0) else 0 end as ip from s
  )
  select i.p, i.o, i.ip,
         greatest(least(i.o, case when i.p > 0 then i.cp + i.cc + i.co - i.ip
                                  when (select g.bloqueo_sin_firmar from g) then 0
                                  else i.co end), 0),
         i.cp, i.co, i.cc,
         exists (select 1 from fam f where f.moneda is distinct from (select r.moneda from r))
    from i;
$function$;
