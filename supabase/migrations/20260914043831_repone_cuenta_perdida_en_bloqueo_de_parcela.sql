-- REGRESIÓN CAZADA al contar filas después del rename: `ppjb_parcela` tenía 14
-- cuentas y su siembra original creó 15 (verificado ese mismo día: «ppjb_parcela
-- · 15 cuentas»). La que faltaba es `land_balian_usd`.
--
-- No se puede atribuir con certeza a una sentencia concreta —ninguna fila de la
-- tabla tiene `actualizado_por`, así que NADIE ha usado el panel todavía y no fue
-- una edición humana— y se repone porque el estado correcto es conocido y
-- comprobable: el Bloqueo de Parcela es el único contrato que pacta escrow
-- notarial y su reparto se sembró a propósito con TODAS las cuentas activas
-- (`if(slug==='ppjb_parcela') return opts;` era la regla en el JS que se mudó).
--
-- Dejar 14 habría sido una regresión muda: una cuenta que el desplegable ofrecía
-- esta mañana y hoy no, sin que nadie lo pidiera.
--
-- Idempotente: la misma forma que la siembra original, así que repone lo que
-- falte y no duplica lo que esté.
insert into public.plantilla_cuentas (slug, clave)
select 'ppjb_parcela', c.clave
from public.cuentas_bancarias c
where c.activa
on conflict (slug, clave) do nothing;;
