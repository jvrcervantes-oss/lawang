/*
 * 21-sep-2026: deck_forecast_ejemplo_publico() pasa de devolver UN ejemplo fijo (Villa Dali
 * en Palm Field W5) a devolver un OBJETO por slug de modelo, con los pares (modelo,proyecto)
 * confirmados por el owner como datos reales -- no una fila cualquiera con publicado=true:
 * Dali tiene tres filas de deck_forecast y dos son de prueba (Bonian Village con 5% de
 * ocupacion, Horizon S1 con "50" redondo en todo, sin publicar). El filtro no puede ser
 * automatico (publicado=true solo, o destacado=true) porque la fila de Bonian SI esta
 * publicada Y marcada destacado, y es la de prueba -- hay que fijar el par a mano, igual
 * que la version anterior fijaba un UUID.
 *
 * Confirmados por el owner (21-sep-2026): Dali y Dream comparten la misma nota de
 * autoria ("owner (WhatsApp), 15-sep-2026: forecast Average minimo +10% ROI", mismo lote).
 * Dune esta publicado con numeros no redondos (no tiene pinta de dummy) pero SIN nota de
 * quien lo cargo -- se incluye igual porque publicarlo fue una decision deliberada, pero
 * queda marcado aparte para quien audite el dato despues.
 *
 * Un modelo SIN par aqui (Loftbung/Temple/Trinity) no sale en el objeto -- la landing debe
 * OMITIR la seccion entera para ese modelo, nunca caer al ejemplo de otro modelo distinto
 * (esa cascada era justo el problema: toda ficha ensenaba "Villa Dali" se mirara la que se
 * mirara).
 */
create or replace function public.deck_forecast_ejemplo_publico()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_object_agg(m.slug, jsonb_build_object(
    'proyecto',           pr.nombre,
    'modelo',              m.nombre,
    'moneda',             df.moneda,
    'adr_medio',          df.adr_medio,
    'adr_optimo',         df.adr_optimo,
    'ocupacion_media',    df.ocupacion_media,
    'ocupacion_optima',   df.ocupacion_optima,
    'inversion_base',     df.inversion_base,
    'pct_gestion',        dfp.pct_gestion,
    'pct_mantenimiento',  dfp.pct_mantenimiento,
    'pct_impuesto',       dfp.pct_impuesto
  )), '{}'::jsonb)
  from public.deck_forecast df
  join public.deck_forecast_proyecto dfp on dfp.proyecto_id = df.proyecto_id
  join public.proyectos pr on pr.id = df.proyecto_id
  join public.modelos m on m.id = df.modelo_id
  where (df.proyecto_id, df.modelo_id) in (
    ('ee279df3-43f9-4299-a9dc-7daf4df6f6d6'::uuid, '2ced5a54-5c76-4f9e-a031-45353d7f2e40'::uuid), -- Dali / Palm Field W5
    ('ee279df3-43f9-4299-a9dc-7daf4df6f6d6'::uuid, '83a761fb-99b0-49cb-a29d-72847eb7b3c9'::uuid), -- Dream / Palm Field W5
    ('ee279df3-43f9-4299-a9dc-7daf4df6f6d6'::uuid, 'c498bea1-f6c3-4ae7-89a3-0c64212cd28e'::uuid)   -- Dune / Palm Field W5
  )
    and df.publicado
    and dfp.publicado;
$$;

revoke all on function public.deck_forecast_ejemplo_publico() from public;
grant execute on function public.deck_forecast_ejemplo_publico() to anon, authenticated;

comment on function public.deck_forecast_ejemplo_publico() is
  'Ejemplo economico real por modelo (Dali/Dream/Dune en Palm Field W5, pares fijos confirmados por el owner) para el snapshot financiero de /modelo/<id>. Sin parametros: no se puede pedir otro proyecto ni enumerar el resto del deck. Un modelo sin par aqui no debe caer al ejemplo de otro. 21-sep-2026.';
;
