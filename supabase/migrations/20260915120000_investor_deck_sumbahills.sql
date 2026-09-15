-- Investor Deck: Sumba Hills — slug + masterplan interactivo (15-sep-2026, tarde).
-- Revision previa hecha (Seguridad+Legal+Datos, CEO/flujos/revision_previa.md) sobre
-- el plan antes de escribir esto. Decisiones que dan forma a esta migracion:
--
-- 1. Alcance de publicacion (UPDATE masivo de abajo): decidido por el OWNER en esta
--    misma sesion (AskUserQuestion, tras el hallazgo de Seguridad de que marcar las
--    228 filas es un UPDATE masivo en produccion y requiere su OK explicito, no del
--    departamento) -- eligio "todas las 228, sin filtrar por estado", mismo criterio
--    que ya se uso para Palm Field. Autorizacion real obtenida, no asumida.
-- 2. Sin seccion de tenencia/legal-security: la estructura legal de Sumba Hills
--    (Hak Sewa/HGB/Hak Pakai) no esta resuelta todavia (hallazgo de Legal) -- no se
--    copia la de Palm Field (retirada ya de la plantilla generica el 15-sep por el
--    mismo motivo), se omite hasta que exista ese dato real.
-- 3. masterplan_imagen apunta a un MANIFIESTO JSON, no a una imagen suelta:
--    /investor-deck/masterplan/sumbahills.json, fichero estatico versionado en el
--    repo (recomendacion de Datos en la revision previa) -- no cabe en el bucket
--    publico `deck` (solo admite image/webp) ni requiere sesion admin para servirse.
--    2 paginas, 206 codigos con poligono real medido sobre el PDF vectorial del
--    cliente (filtro de color del trazo de parcela + verificacion visual propia,
--    no a ojo); las 23 unidades (SH-206..SH-228) que el PDF actual no dibuja siguen
--    en el listado en vivo de investor_deck_parcelas, solo sin marcador en el plano.
-- 4. Reutiliza investor_deck_parcelas/deck_config_publico ya existentes y validados
--    (Seguridad, revision previa): ninguna funcion nueva, ningun cambio de RLS.

update public.proyectos
   set slug = 'sumbahills'
 where nombre = 'Sumba Hills'
   and slug is null;

insert into public.deck_config_proyecto (proyecto_id, titulo, meta_desc, tipo_venta, masterplan_activo, masterplan_imagen)
select id,
       '{"en":"Sumba Hills - Investor Deck"}'::jsonb,
       '{"en":"Investor deck for due diligence"}'::jsonb,
       'parcela',
       true,
       '/investor-deck/masterplan/sumbahills.json'
  from public.proyectos
 where nombre = 'Sumba Hills'
on conflict (proyecto_id) do update
   set masterplan_activo = excluded.masterplan_activo,
       masterplan_imagen = excluded.masterplan_imagen;

-- UPDATE masivo autorizado explicitamente por el owner (ver punto 1 arriba): activa
-- la visibilidad publica del deck para las 228 unidades reales de Sumba Hills. Solo
-- toca `publicado_investor_deck`; estado, precio y el resto de columnas no se tocan.
update public.unidades
   set publicado_investor_deck = true
 where proyecto = 'Sumba Hills';
