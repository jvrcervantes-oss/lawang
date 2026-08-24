-- destructivo-ok: el único `drop` es `drop trigger if exists` sobre un trigger
-- que este mismo fichero recrea a continuación (idempotencia estándar, Postgres
-- no tiene `CREATE OR REPLACE TRIGGER` en esta versión); no borra datos ni
-- ningún objeto ajeno.
-- ════════════════════════════════════════════════════════════════════════════
-- UNA UNIDAD SE REVISA TAMBIÉN AL CORREGIR SU PRECIO — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- EL CASO (owner): B7 de Tamarind Rise (unidad de RP00071/CC00033) salía
-- "cobrada" con solo 45.525 EUR cobrados de 118.275 (38,5%). El 21-ago, cuando
-- entró el segundo recibí, el cálculo daba cobrada de verdad bajo el precio de
-- unidad que había EN ESE MOMENTO; el precio se corrigió después y nadie volvió
-- a preguntarle a `avanza_unidad_por_cobro` si eso seguía siendo cierto.
--
-- LA CAUSA: `avanza_unidad_por_cobro` solo la disparan dos triggers —
-- `trg_avanza_por_recibi` (facturas) y `trg_avanza_por_aplicacion`
-- (recibi_aplicaciones) — los dos sobre el DINERO. Ninguno mira `unidades`.
-- Cambiar el precio de una unidad no es un evento de dinero, pero SÍ cambia el
-- denominador de la misma cuenta (`v_cobrado >= v_precio_unidades`), así que un
-- precio corregido después de que la unidad ya avanzó de estado se queda
-- congelado con el estado viejo — no hay ratchet que lo proteja, simplemente
-- nadie la vuelve a llamar.
--
-- LA CURA: un tercer trigger, sobre `unidades`, que llama a la MISMA función
-- (no se reimplementa el cálculo) cuando cambia `precio`. `avanza_unidad_por_cobro`
-- ya resuelve raíz/hijos e ignora monedas mezcladas — llamarla desde aquí no
-- añade una segunda versión de esa lógica, solo un tercer disparador.
--
-- Verificado en vivo antes de escribir esto: `select
-- avanza_unidad_por_cobro('ba87e81f-...')` (RP00071, la raíz de B7) la corrigió
-- sola a 'vendida' — la función ya calculaba bien, solo faltaba quien la llamase.

create or replace function public.trg_revalua_unidad_por_precio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.precio is distinct from old.precio and new.contrato_id is not null then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  return new;
end;
$$;

revoke all on function public.trg_revalua_unidad_por_precio() from public, anon;

drop trigger if exists trg_revalua_unidad_por_precio on public.unidades;
create trigger trg_revalua_unidad_por_precio
  after update of precio on public.unidades
  for each row execute function public.trg_revalua_unidad_por_precio();
