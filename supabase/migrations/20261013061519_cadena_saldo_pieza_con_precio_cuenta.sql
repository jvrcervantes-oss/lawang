-- SUSTITUIDA el mismo día por 20261013062019_cadena_saldo_tope_se_queda_estrecho (2.º code-review): contar una pieza
-- CON precio inflaba el tope (app.html:536-543: una Adenda no lleva precio; el Hak Sewa lo lleva en hsn_precio_rp, en
-- IDR) y sumar un hijo en otra moneda lo mezclaba. Lo de abajo es el relato de lo que se aplicó entonces.
-- _cadena_saldo, corrección de 20261013060855 el mismo día (13-oct-2026): una pieza que acompaña (Poder, Hak Sewa,
-- Adenda) SIN precio no deja la cadena «sin precio», pero si TIENE precio, cuenta. Y se quita la guarda de moneda.
--
-- Por qué (code-review sobre 20261013060855, comprobado en el código):
--   1. 20261013060855 sacaba del precio a la pieza aunque tuviera precio. Una Adenda que sube el precio pactado
--      (Bloqueo 100.000 + Adenda 20.000) dejaba el tope en 100.000 y bloqueaba la factura legítima de 110.000.
--   2. La pantalla no hace eso: cuentaGrupo() (contracts/assets/operaciones-cuentas.js:105-107) suma precio_total
--      de todo lo que no es preliminar, piezas incluidas, y una pieza sin precio suma 0 sin dejar el grupo «sin
--      precio». Y etapaOperacion (mismo fichero, :155 y :196) solo da por cobrada una pieza de PIEZAS_ACOMPANAN si
--      NO tiene precio: con precio «cae al flujo normal». Lo que se ve y lo que se hace valer no pueden divergir
--      (regla del 5-oct de las facturas): el servidor hace ahora lo mismo.
--   3. La guarda otra_moneda era casi código muerto: trg_contrato_moneda_desde_unidad le pone al hijo la moneda del
--      padre (o de su parcela) al darlo de alta, así que un hijo «en otra moneda» solo existe si se toca la columna
--      tras firmar. Prometía cerrar «sumar monedas distintas» y no lo cerraba. Fuera; la pantalla tampoco la tiene.
--      El Hak Sewa con precio en IDR no entra en el precio porque su precio no va en precio_total (va en
--      hsn_precio_rp), no por su moneda: la columna moneda del Hak Sewa hijo hereda EUR del Bloqueo.
--
-- Regla que queda (solo cambia sin_precio respecto al vivo de 20261005210000; precio vuelve a ser el de entonces):
--     precio     = sum(precio_total)               raíz + hijos que no son carta de reserva          (sin cambio)
--     sin_precio = alguno de esos sin precio, SALVO un hijo poa/hak_sewa_notario/adenda sin precio  (cambio),
--                  o ninguno tiene precio (una Carta con solo su Poder sigue «sin precio», como antes)
--   Lista gemela de PIEZAS_ACOMPANAN (operaciones-cuentas.js:179). No se lee de contrato_tipo_etapa: allí
--   hak_sewa_notario tiene etapa 'contrato' y commercial_offer 'ninguna' sin estar en la lista del front.
--   Las facturas (fa) siguen contando todo el grupo, también las emitidas sobre una pieza: con precio, su precio
--   está en el tope; sin precio, es dinero de la venta (hoy 0 facturas vivas sobre esas piezas).
--
-- Medido el 13-oct contra producción frente al vivo anterior a 20261013060855: cambia SOLO RP00170 (45.900 EUR,
-- sin_precio true → false: su Poder PA00010 no tiene precio). 0 cadenas cambian su precio (ninguna pieza que
-- acompaña tiene precio_total hoy); los 6 Hak Sewa sueltos como raíz siguen sin precio.
--
-- Prueba: supabase/pruebas/cadena_saldo_piezas_que_acompanan.sql (transacción que acaba en raise, sin rastro).
--
-- Vuelta atrás: la definición de 20261005210000 (líneas 30-60), que solo difiere en la línea de sin_precio:
--     coalesce((select bool_or(ca.precio_total is null) from ca where ca.tipo not like 'carta\_reserva%'), true),
--   y el CTE ca sin la columna pieza. create or replace conserva el revoke de 20261005210000 (sin execute para
--   public, anon, authenticated ni service_role; lo comprueba la prueba).

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
    -- pieza: hijo que acompaña a la venta (gemela de PIEZAS_ACOMPANAN en contracts/assets/operaciones-cuentas.js).
    -- Si no tiene precio no deja la cadena «sin precio»; si lo tiene, cuenta como cualquier otro.
    select c.id, c.tipo, c.precio_total,
           c.id <> r.id and c.tipo in ('poa', 'hak_sewa_notario', 'adenda') as pieza
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
         (select sum(ca.precio_total) from ca where ca.tipo not like 'carta\_reserva%'),
         -- sin precio: falta el de alguno que no es pieza, o no hay ningún precio (p. ej. una Carta con solo su Poder)
         coalesce((select bool_or(ca.precio_total is null and not ca.pieza) or not bool_or(ca.precio_total is not null)
                     from ca where ca.tipo not like 'carta\_reserva%'), true),
         coalesce((select sum(fa.subtotal) from fa), 0),
         coalesce((select sum(fa.total) from fa), 0),
         coalesce((select sum(fa.cobrado) from fa), 0)
    from ro;
$function$;
