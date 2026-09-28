-- destructivo-ok: retira una FUNCIÓN sin llamador (no borra ninguna fila). AXW-66 S4b, 28-sep-2026, Datos.
-- La vieja investor_deck_activar(text, boolean) cambiaba el flag del deck sin mover antes las fotos y la podía llamar
-- cualquier `authenticated` (su única barrera era es_admin() dentro). Desde S4 (Lawang main f999dd22, servido en
-- lawangproperties.com: editores.js sha256 31d28a81…, que llama a la edge `ficheros` → `deck_activa`) no la llama
-- nadie: 0 llamadas en el repo de Lawang y 0 funciones de la base que la nombren (medido hoy). Su sucesora es
-- investor_deck_activa_como(p_uid, p_proyecto_id, p_activo), solo service_role (20260928101000).
-- En el maestro NO va todavía: el front publicado en erp.axisworks.studio aún la llama (ver encargo, S4b).
revoke all on function public.investor_deck_activar(text, boolean) from public, anon, authenticated;
drop function if exists public.investor_deck_activar(text, boolean);
