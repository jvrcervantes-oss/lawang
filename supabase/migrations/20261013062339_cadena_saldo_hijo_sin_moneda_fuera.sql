-- _cadena_saldo, ajuste de 20261013062019 el mismo día (13-oct-2026, 3.er code-review): un hijo SIN moneda bajo una
-- raíz CON moneda también se queda fuera del precio.
--
-- Por qué: 062019 dejaba fuera al hijo en otra moneda con `c.moneda is not null and c.moneda is distinct from
-- ro.moneda`, así que un hijo con moneda null sumaba su precio_total a la moneda de la raíz. contratos.moneda admite
-- null y trg_contrato_moneda_desde_unidad deja la moneda como llegó (null si no llegó) cuando no resuelve una sola
-- (parcelas en monedas mezcladas, o sin parcela ni padre con moneda). Un precio de moneda desconocida inflaría el tope: contra el criterio de 062019 (ante un dato
-- que no debería estar, el tope se queda estrecho). Ahora basta `c.moneda is distinct from ro.moneda`: raíz y
-- hijo ambos sin moneda siguen contando juntos, como siempre.
--
-- Medido el 13-oct: 102 hijos que cuentan, 0 con moneda null bajo una raíz con moneda, 0 raíces sin moneda con
-- hijos que cuentan → 0 cadenas cambian. El resto de la regla y su porqué, en 20261013062019.
--
-- Prueba: supabase/pruebas/cadena_saldo_piezas_que_acompanan.sql (caso N).
--
-- Vuelta atrás: la definición de 20261013062019 (misma función con `c.moneda is not null and` delante de
-- `c.moneda is distinct from ro.moneda`). create or replace conserva el revoke de 20261005210000.

create or replace function public._cadena_saldo(p_contrato uuid, p_excluir uuid default null::uuid)
 returns table(raiz uuid, raiz_numero text, moneda text, precio numeric, sin_precio boolean, facturado numeric, total_facturas numeric, cobrado numeric)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with r as (
    select coalesce(c.contrato_padre_id, c.id) as id from public.contratos c where c.id = p_contrato
  ), ro as (
    select c.id, c.numero, c.moneda from public.contratos c join r on r.id = c.id
  ), ca as (
    -- cuenta: entra en el precio de la cadena. Fuera: las cartas de reserva; los hijos que acompañan a la venta
    -- (gemela de PIEZAS_ACOMPANAN en contracts/assets/operaciones-cuentas.js), tengan o no precio; y los hijos en
    -- otra moneda que la raíz o sin moneda bajo una raíz con ella (precio y facturado, en la misma moneda).
    select c.id, c.tipo, c.precio_total,
           c.tipo not like 'carta\_reserva%'
           and not (c.id <> r.id and c.tipo in ('poa', 'hak_sewa_notario', 'adenda'))
           and not (c.id <> r.id and c.moneda is distinct from ro.moneda) as cuenta
      from public.contratos c, r, ro
     where c.id = r.id or c.contrato_padre_id = r.id
  ), fa as (
    select f.id, f.total,
           coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total) as subtotal,
           coalesce((select sum(ra.importe_aplicado)
                       from public.recibi_aplicaciones ra
                       join public.facturas rc on rc.id = ra.recibi_id
                      where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0) as cobrado
      from public.facturas f
      join ca on ca.id = f.contrato_id, ro
     where f.tipo = 'factura' and not coalesce(f.anulada, false)
       and f.moneda is not distinct from ro.moneda
       and f.id is distinct from p_excluir
  )
  select ro.id, ro.numero, ro.moneda,
         (select sum(ca.precio_total) from ca where ca.cuenta),
         coalesce((select bool_or(ca.precio_total is null) from ca where ca.cuenta), true),
         coalesce((select sum(fa.subtotal) from fa), 0),
         coalesce((select sum(fa.total) from fa), 0),
         coalesce((select sum(fa.cobrado) from fa), 0)
    from ro;
$function$;
