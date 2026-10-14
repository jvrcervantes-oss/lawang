-- APLICADA el 14-oct-2026 (versión 20261014133241, apply_migration, ventana del owner). Batería prueba_comisiones_1nov
-- 33/33 antes (ensayo deshecho) y después; comisiones_1nov_imputacion 0 desacuerdos; vuelta: supabase/vivo/
-- 20261014_cobro_primero_parcela/vuelta_f3.sql.
--
-- F3 de «primero la parcela, luego la obra» (encargo 20261014_lawang_cobro_primero_parcela): la regla de comisiones de
-- las ventas desde el 1-nov-2026 (_comisiones_bases_firmadas). Las únicas condiciones que leen lo cobrado por parte
-- (tramos pct_cobrado_suelo_firmado / pct_cobrado_obra_firmada) rigen desde el 1-nov (medido el 14-oct: 12 sucesoras
-- c0a11010-…-01..12, todas vigente_desde 2026-11-01). Las BASES (columnas 1–2, precios firmados) no cambian: el
-- reconciliador y la trazabilidad, que solo leen bases, no mueven ningún devengo ya generado.
--
-- QUÉ CAMBIA respecto a la migración 20261014012527_comisiones_regla_1nov:
--   1. «Lo cobrado en un contrato de obra no sube a la parcela» deja de valer (owner, 14-oct-2026: la regla general de
--      _unidad_cobro_cascada manda también en comisiones). Bolsa = todo lo cobrado en los contratos FIRMADOS de la
--      familia: parcela + cartas + obra.
--        parcela = least(precio parcela firmada, bolsa)
--        obra    = least(precio obra firmada, bolsa - parcela)
--   2. Solo cuentan contratos FIRMADOS, como hasta ahora (owner, 28-sep: «no se paga comisión sin contrato firmado»;
--      confirmado por el owner el 14-oct para F3, recomendación de Administración). Con el Bloqueo firmado y el dinero
--      apuntado en una Construcción aún sin firmar, la parcela no avanza hasta que se firme la Construcción: lento, pero
--      un devengo pagado no se puede deshacer y al revés sí se recupera.
--   3. GUARDA NUEVA (Administración, 14-oct): sin parcela firmada, si la venta tiene un Bloqueo de Parcela VIVO SIN
--      FIRMAR (raíz o hijo, no liberado), lo cobrado en obra NO cuenta todavía como obra. Sin ella, una Construcción
--      firmada con el 25 % cobrado devengaría, y al firmarse el Bloqueo ese dinero pasaría a llenar la parcela con la
--      comisión de obra ya pagada. Mira cualquier Bloqueo de la familia (no solo la raíz, como la cascada) a propósito:
--      aquí solo puede FRENAR un pago, nunca adelantarlo. Una venta sin ningún Bloqueo (obra suelta, raíz carta sin
--      Bloqueo) sigue como hasta ahora: su obra cuenta lo cobrado en obra.
--   Se mantienen: la carta no suma en ninguna BASE (su cobro sí es pago), adenda = obra (_comisiones_parte_obra), sin
--   parcela firmada no hay cascada (la carta no desborda a obra), solo la moneda de la raíz, multimoneda = bandera.

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
  -- COBRADO (14-oct-2026, misma regla que _unidad_cobro_cascada):
  --   bolsa   = cobrado en TODOS los contratos firmados de la familia (parcela + cartas + obra)
  --   parcela = least(precio parcela firmada, bolsa)                 -- nunca > 100 %
  --   obra    = least(precio obra firmada, bolsa - parcela)          -- nunca > 100 %
  --   * Sin parcela firmada (precio 0) no hay cascada: la obra cuenta solo lo cobrado en obra (la carta es la señal de
  --     una parcela que aún no existe), y además, si hay un Bloqueo de Parcela vivo SIN firmar en la familia, la obra
  --     cuenta 0 (guarda F3): al firmarse, ese dinero llenaría la parcela con el devengo de obra ya pagado.
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
    select exists (select 1 from public.contratos c
                    where (c.id = p_raiz or c.contrato_padre_id = p_raiz)
                      and c.tipo = 'reserva_parcela' and not coalesce(c.bloqueado, false)
                      and c.liberado_en is null) as bloqueo_sin_firmar
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
