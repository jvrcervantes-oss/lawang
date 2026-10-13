-- SUSTITUIDA el mismo día por 20261013061519_cadena_saldo_pieza_con_precio_cuenta (code-review): sacar del precio una
-- pieza CON precio rompía el tope de una Adenda que sube lo pactado y divergía de cuentaGrupo, y la guarda de moneda era
-- casi código muerto. Lo de abajo es el relato de lo que se aplicó entonces; la regla vigente y su porqué, en 061519.
-- _cadena_saldo: lo que acompaña a la venta (Poder, Hak Sewa, Adenda) no cuenta en el precio de la cadena (13-oct-2026).
--
-- Por qué. Orden del owner del 13-oct: el Hak Sewa sigue a la venta (1 Bloqueo · 2 Construcción · 3 Hak Sewa · 4 Poder)
-- y el asistente lo guarda colgado de su Bloqueo (contrato_padre_id). El Hak Sewa no lleva precio_total: su precio va en
-- hsn_precio_rp, en IDR, y el Bloqueo suele ir en EUR. _cadena_saldo (vivo hasta hoy, idéntico a 20261005210000_facturas_tope_cadena_y_recibi_pendiente) hacía
--     precio     = sum(precio_total)               de raíz + hijos, tipo not like 'carta\_reserva%'
--     sin_precio = coalesce(bool_or(precio_total is null), true)   mismo filtro
-- así que un hijo poa/hak_sewa_notario/adenda sin precio ponía sin_precio = true: _factura_tope_cadena dejaba de
-- comprobar el tope (línea `if ... v_s.sin_precio ... then return`) y contrato_saldo devolvía por_facturar = null. Y si
-- llevara precio, sumaba IDR con EUR. Medido el 13-oct contra producción (148 cadenas raíz con algún contrato que no es carta de reserva): pasaba YA en 1 cadena,
-- RP00170 (precio 45.900 EUR, sin_precio = true solo por su Poder PA00010 sin precio). Con esta regla cambia SOLO esa:
-- 0 cadenas cambian su precio, 0 piezas que acompañan tienen precio_total, 0 hijos con otra moneda, y las 6 raíces que
-- son ellas mismas un Hak Sewa suelto (HS00003…HS00012, sin precio) quedan como estaban.
--
-- Qué cambia (dos columnas nuevas en el CTE ca y las dos líneas de precio y sin_precio; firma, DEFINER, search_path,
-- r, ro, fa y el resto del select, idénticos al vivo):
--   1. Un HIJO de tipo poa, hak_sewa_notario o adenda no entra en precio ni en sin_precio. Solo hijo: si la raíz es
--      un Hak Sewa suelto se sigue mirando su propio precio_total, como hasta hoy.
--      Lista explícita y no el catálogo contrato_tipo_etapa a propósito: allí hak_sewa_notario tiene etapa 'contrato'
--      y commercial_offer tiene 'ninguna' sin estar en la lista del front, así que derivarla de esa tabla discreparía
--      en silencio con la pantalla. Fuente gemela: PIEZAS_ACOMPANAN = ['poa','hak_sewa_notario','adenda'] en
--      contracts/assets/operaciones-cuentas.js (cuentaGrupo). Si una cambia, cambian las dos.
--   2. Un hijo que sí cuenta pero con moneda propia distinta de la de la raíz pone sin_precio = true y no se suma al
--      precio (que queda solo en la moneda de la raíz, la misma con la que fa filtra las facturas), en vez de
--      sumarse a la cuenta de otra moneda. Hoy no afecta a ninguna cadena (medido: 0); cierra el mismo fallo
--      (sumar monedas distintas) para la Construcción u otro hijo que llegue en IDR bajo un Bloqueo en EUR. No se
--      filtra el precio por moneda (bajaría el tope y bloquearía facturas legítimas): se declara «sin precio».
--   Las facturas (fa) no cambian: una factura emitida sobre una pieza en la moneda de la raíz sigue siendo dinero de
--   la venta y cuenta en facturado. Hoy no hay ninguna (medido: 0 facturas vivas sobre poa/hak_sewa_notario/adenda).
--
-- Consumidores (los tres, por la misma función): _factura_tope_cadena (tope al dar de alta/editar factura) y
-- contrato_saldo (pantalla). Las demás funciones que suman precio_total de la cadena (_comisiones_precio_total,
-- _comisiones_precio_total_todos, comision_trazabilidad, crm_ranking_closers) solo usan sum(), que salta los null, o
-- filtran precio_total is not null: un Poder/Hak Sewa sin precio no las mueve. Ninguna usa bool_or(... is null).
--
-- Prueba: supabase/pruebas/cadena_saldo_piezas_que_acompanan.sql (transacción que acaba en raise, sin rastro).
--
-- Vuelta atrás: volver a crear la función con la definición anterior, que es la de 20261005210000 (líneas 30-60, idéntica al vivo del 13-oct):
--   en el select final, las dos líneas
--     (select sum(ca.precio_total) from ca where ca.tipo not like 'carta\_reserva%'),
--     coalesce((select bool_or(ca.precio_total is null) from ca where ca.tipo not like 'carta\_reserva%'), true),
--   y el CTE ca sin las columnas cuenta/otra_moneda:
--     ca as (select c.id, c.tipo, c.precio_total from public.contratos c, r where c.id = r.id or c.contrato_padre_id = r.id)
--   (create or replace con la misma firma conserva el revoke de 20261005210000: sin execute para public, anon, authenticated ni service_role; lo comprueba la prueba).

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
    -- cuenta: entra en el precio de la cadena. Fuera: las cartas de reserva (como siempre) y, solo si son HIJOS, las
    -- piezas que acompañan a la venta (gemela de PIEZAS_ACOMPANAN en contracts/assets/operaciones-cuentas.js).
    -- otra_moneda: hijo que cuenta pero va en otra moneda que la raíz; no se suma y deja la cadena «sin precio».
    select c.id, c.tipo, c.precio_total,
           c.tipo not like 'carta\_reserva%'
           and not (c.id <> r.id and c.tipo in ('poa', 'hak_sewa_notario', 'adenda')) as cuenta,
           c.id <> r.id and c.moneda is not null
           and c.moneda is distinct from (select ro.moneda from ro) as otra_moneda
      from public.contratos c, r
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
         (select sum(ca.precio_total) from ca where ca.cuenta and not ca.otra_moneda),
         -- sin precio: alguno de los que cuentan no tiene precio, o un hijo que cuenta va en otra moneda (no se suma)
         coalesce((select bool_or(ca.precio_total is null or ca.otra_moneda) from ca where ca.cuenta), true),
         coalesce((select sum(fa.subtotal) from fa), 0),
         coalesce((select sum(fa.total) from fa), 0),
         coalesce((select sum(fa.cobrado) from fa), 0)
    from ro;
$function$;
