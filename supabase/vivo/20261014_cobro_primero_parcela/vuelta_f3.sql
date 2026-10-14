-- VUELTA de F3 (migración 20261014133241_comisiones_1nov_primero_parcela). Deja _comisiones_bases_firmadas como estaba
-- en producción el 14-oct-2026 antes de aplicarla (copiada con pg_get_functiondef esa tarde): la regla del 13-oct, en la
-- que lo cobrado en obra no sube a la parcela y sin la guarda del Bloqueo sin firmar. No toca datos. Las bases no cambian
-- en ninguna de las dos versiones; antes del 1-nov-2026 no mueve ningún devengo (los tramos que leen lo cobrado por parte
-- rigen desde esa fecha). Después del 1-nov, revertir solo con la decisión del owner y pasando comisiones_reconciliar.
create or replace function public._comisiones_bases_firmadas(p_raiz uuid)
 returns table(suelo_firmado numeric, obra_firmada numeric, cobrado_suelo_firmado numeric, cobrado_obra_firmada numeric,
               cobrado_directo_suelo numeric, cobrado_directo_obra numeric, cobrado_cartas numeric, multimoneda boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- Regla del owner del 13-oct-2026 (ventas desde el 1-nov). Conjunto = familia de la raíz (raíz + hijos)
  -- firmados (bloqueados) y no liberados. Parte = contrato_tipo_etapa.es_obra (tipo sin fila = no obra).
  -- BASES: las cartas de reserva (raíz o hija) no suman en ninguna («la carta no devenga comisiones»).
  -- COBRADO, «primero parcela, luego obra» (owner, 13-oct-2026, decisión cerrada):
  --   bolsa      = cobrado en los contratos de parcela + cobrado en las cartas firmadas de la familia
  --   parcela    = least(precio parcela firmada, bolsa)                      -- nunca > 100 %
  --   obra       = least(precio obra firmada, cobrado en obra + (bolsa - parcela))   -- nunca > 100 %
  --   * Lo cobrado en la carta es pago del cliente: completa primero la parcela firmada y el sobrante va a obra.
  --   * Lo cobrado en la propia RP por encima de su precio firmado (RP00047: la RP lleva el precio de la parcela
  --     y el de la casa) es el mismo dinero sin parte asignada: desborda a obra con la misma regla.
  --   * Lo cobrado en un contrato de obra es de obra: su exceso no sube a la parcela (queda topado).
  --   * Sin parcela firmada (precio 0) no hay desborde: la carta es la señal de una parcela que aún no existe, y si
  --     el sobrante disparara la obra, al firmarse la RP ese dinero volvería a la parcela con el devengo de obra ya
  --     pagado (no se puede deshacer). Ese dinero cuenta en cuanto se firma la parcela.
  -- Columnas 5–7: el cobrado en bruto (para el snapshot y la trazabilidad: auditar la imputación).
  -- MONEDA (13-oct-2026): solo cuentan contratos y cobros en la moneda de la raíz; multimoneda = la familia tiene algún
  -- contrato firmado no liberado en otra moneda (el motor y el reconciliador no tocan entonces los tramos «firmados»).
  -- PARTE: _comisiones_parte_obra (adenda = obra).
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
  ), i as (
    select s.*, case when s.p > 0 then greatest(least(s.p, s.cp + s.cc), 0) else 0 end as ip from s
  )
  select i.p, i.o, i.ip,
         greatest(least(i.o, i.co + case when i.p > 0 then greatest(i.cp + i.cc - i.ip, 0) else 0 end), 0),
         i.cp, i.co, i.cc,
         exists (select 1 from fam f where f.moneda is distinct from (select r.moneda from r))
    from i;
$function$;
