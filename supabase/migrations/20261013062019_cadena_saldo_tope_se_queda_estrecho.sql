-- _cadena_saldo, regla definitiva del 13-oct-2026 (sustituye a 20261013060855 y 20261013061519, ambas del mismo día).
--
-- Qué pasaba (verificado contra pg_proc vivo el 13-oct): un hijo poa/hak_sewa_notario/adenda sin precio dejaba la
-- cadena sin_precio = true, así que _factura_tope_cadena no comprobaba el tope y contrato_saldo daba por_facturar
-- null. Con el Hak Sewa colgando del Bloqueo (orden del owner del 13-oct: 1 Bloqueo · 2 Construcción · 3 Hak Sewa ·
-- 4 Poder) pasaría en cada venta. Hoy ya pasaba en RP00170 (45.900 EUR) por su Poder PA00010.
--
-- Criterio para elegir la regla: esto es un TOPE. Un tope demasiado bajo para la factura y el super admin pasa
-- dejando registro (registra_privilegio 'factura_sobre_tope'); un tope inflado o apagado deja facturar de más sin
-- rastro. Ante un dato que no debería estar, se queda estrecho.
--
--   1. Las piezas que acompañan, cuando son HIJAS (poa, hak_sewa_notario, adenda), no entran en el precio ni en
--      «sin precio», tengan o no precio_total. Por diseño no llevan precio: contracts/app.html:536-543 («NO lleva
--      precio: si la adenda declarara precio_total, Operaciones sumaria el importe otra vez sobre la misma operacion
--      — el mismo fallo que ya costo 328.000 EUR por una villa de 164.000»), y el precio del Hak Sewa va en
--      hsn_precio_rp, en IDR, mientras su columna moneda hereda la del Bloqueo (trg_contrato_moneda_desde_unidad).
--      Si alguna vez una trae precio_total, es un error de dato y contarlo inflaría el tope (un Hak Sewa con
--      900.000.000 en precio_total lo apagaría de hecho). 061519 lo contaba: retirado.
--      Si la raíz es ella misma una pieza (Hak Sewa suelto), se mira su precio como siempre.
--      Lista explícita, gemela de PIEZAS_ACOMPANAN (contracts/assets/operaciones-cuentas.js:179). No se lee de
--      contrato_tipo_etapa: allí hak_sewa_notario tiene etapa 'contrato' y commercial_offer 'ninguna' sin estar en
--      la lista del front. Si una cambia, cambian las dos.
--   2. Un hijo con moneda propia distinta de la raíz (p. ej. una Construcción cuya parcela va en otra moneda:
--      trg_contrato_moneda_desde_unidad toma la de la parcela) no entra en el precio ni en «sin precio». Así precio
--      y facturado quedan en la misma moneda: fa solo cuenta facturas en la moneda de la raíz, y
--      _factura_tope_cadena no aplica el tope a una factura en otra moneda. 060855 lo marcaba «sin precio» (apagaba
--      el tope) y 061519 lo sumaba (mezclaba monedas): las dos, flojas.
--   3. Las facturas (fa) no cambian respecto a 20261005210000.
--
-- Regla:  cuenta  = no es carta de reserva y no es (hijo y pieza que acompaña) y no es (hijo en otra moneda)
--         precio     = sum(precio_total) de los que cuentan
--         sin_precio = alguno de los que cuentan sin precio, o ninguno cuenta
--
-- Medido el 13-oct en producción (172 raíces): frente a la función original (20261005210000) cambia SOLO RP00170
-- (sin_precio true → false, precio 45.900 EUR igual); frente a la viva 061519, 0 cadenas. Hoy ninguna pieza que
-- acompaña tiene precio_total y ningún hijo va en otra moneda que su raíz: la regla solo decide casos futuros.
--
-- Prueba: supabase/pruebas/cadena_saldo_piezas_que_acompanan.sql (transacción que acaba en raise, sin rastro).
--
-- Vuelta atrás: la definición de 20261005210000 (líneas 30-60): el CTE ca sin la columna cuenta y, en el select,
--     (select sum(ca.precio_total) from ca where ca.tipo not like 'carta\_reserva%'),
--     coalesce((select bool_or(ca.precio_total is null) from ca where ca.tipo not like 'carta\_reserva%'), true),
--   create or replace conserva el revoke de 20261005210000 (sin execute para public, anon, authenticated ni
--   service_role; lo comprueba la prueba).

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
    -- otra moneda que la raíz (precio y facturado, en la misma moneda).
    select c.id, c.tipo, c.precio_total,
           c.tipo not like 'carta\_reserva%'
           and not (c.id <> r.id and c.tipo in ('poa', 'hak_sewa_notario', 'adenda'))
           and not (c.id <> r.id and c.moneda is not null and c.moneda is distinct from ro.moneda) as cuenta
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
