-- destructivo-ok: retira permisos y policies de ESCRITURA directa (el navegador ya escribe por RPC/edge desde el commit del bloque 3); no borra ni cambia ninguna fila.
-- Frontera frontend/backend — bloque 3, CIERRE (27-sep-2026, LAW-336 / LAW-331). Plan y revisión previa #126:
-- encargos/20260927_lawang_frontera_b3_modelos_deck.md
-- APLICAR SOLO cuando las pantallas nuevas estén SERVIDAS (Hostinger + CDN): con estas policies fuera, la versión
-- vieja de cualquier pantalla de modelos, precios o deck deja de poder guardar.
-- Desde aquí `authenticated` solo LEE estas 11 tablas, y en los buckets `modelos` y `deck` solo lee. Escriben:
-- modelo_guarda, modelo_precios_guarda, modelo_techos_guarda, modelo_extras_guarda, modelo_ficha_guarda,
-- modelos_proyecto_fija, modelo_documento_cambia, deck_foto_cambia, deck_foto_mueve, deck_foto_fijar_vista,
-- deck_prevision_guarda, deck_config_guarda, deck_faq_guarda, deck_faq_borra, contratos_diseno_guarda
-- (SECURITY DEFINER, permiso dentro); la edge `ficheros` con modelo_documento_registra/_borra y
-- deck_foto_registra/_borra (solo service_role); y las funciones que ya escribían (renombrar_proyecto, que
-- exige es_admin dentro, y los triggers trg_espejo_modelo / trg_modelo_renombrado / deck_audita).

revoke insert, update, delete, truncate on
  public.modelos, public.modelo_techos, public.modelo_extras, public.modelos_villa, public.modelo_documentos,
  public.deck_forecast, public.deck_forecast_proyecto, public.deck_config_proyecto, public.deck_faq, public.deck_fotos,
  public.contratos_diseno
from authenticated, anon;

-- policies de escritura (las de lectura se quedan tal cual)
drop policy if exists "modelos: escribir" on public.modelos;
drop policy if exists "modelos: escribir" on public.modelos_villa;
drop policy if exists "techos: escribir" on public.modelo_techos;
drop policy if exists "modelo_extras: escribir" on public.modelo_extras;
drop policy if exists "modelo_docs: escribir" on public.modelo_documentos;
drop policy if exists "deck_forecast: escribir" on public.deck_forecast;
drop policy if exists "deck_forecast_proyecto: escribir" on public.deck_forecast_proyecto;
drop policy if exists "deck_config_proyecto: escribir" on public.deck_config_proyecto;
drop policy if exists "deck_faq: escribir" on public.deck_faq;
drop policy if exists "deck_fotos: escribir" on public.deck_fotos;
-- era FOR ALL (también daba lectura, pero la lectura ya la da «agentes autenticados leen diseno»)
drop policy if exists "agentes autenticados escriben diseno" on public.contratos_diseno;

-- Storage: subir/borrar en `modelos` y `deck` solo la edge (service role). NO se toca «modelos bucket: leer»
-- (la usa createSignedUrl para abrir un documento) ni la lectura pública del bucket `deck`.
drop policy if exists "modelos bucket: subir" on storage.objects;
drop policy if exists "modelos bucket: borrar" on storage.objects;
drop policy if exists "deck: sube admin" on storage.objects;
drop policy if exists "deck: borra admin" on storage.objects;

-- Consulta de Seguridad (27-sep): el registro de auditoría del deck lo escribe solo el trigger deck_audita (DEFINER);
-- hoy cualquier agente podía meter entradas falsas de «quién publicó qué». Y la vista modelos_sin_catalogar tenía
-- permisos de escritura que no sirven (GROUP BY): fuera por reducir la exposición.
revoke insert, update, delete, truncate on public.deck_publicaciones from authenticated, anon;
drop policy if exists "deck_publicaciones: escribir" on public.deck_publicaciones;
revoke insert, update, delete, truncate on public.modelos_sin_catalogar from authenticated, anon;

-- Comprobación: si queda cualquier privilegio de escritura o policy de escritura en estas tablas, se para.
do $$
declare v_n int;
begin
  select count(*) into v_n
    from pg_class c, lateral aclexplode(c.relacl) a
   where c.relnamespace = 'public'::regnamespace
     and c.relname in ('modelos', 'modelo_techos', 'modelo_extras', 'modelos_villa', 'modelo_documentos', 'deck_forecast',
                       'deck_forecast_proyecto', 'deck_config_proyecto', 'deck_faq', 'deck_fotos', 'contratos_diseno',
                       'deck_publicaciones', 'modelos_sin_catalogar')
     and a.grantee in ('authenticated'::regrole, 'anon'::regrole)
     and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_n > 0 then raise exception 'Quedan % privilegios de escritura para authenticated/anon', v_n; end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and cmd <> 'SELECT'
     and tablename in ('modelos', 'modelo_techos', 'modelo_extras', 'modelos_villa', 'modelo_documentos', 'deck_forecast',
                       'deck_forecast_proyecto', 'deck_config_proyecto', 'deck_faq', 'deck_fotos', 'contratos_diseno',
                       'deck_publicaciones');
  if v_n > 0 then raise exception 'Quedan % policies de escritura en las tablas del bloque 3', v_n; end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and cmd <> 'SELECT'
     and (coalesce(qual, '') ~ '''(modelos|deck)''' or coalesce(with_check, '') ~ '''(modelos|deck)''');
  if v_n > 0 then raise exception 'Quedan % policies de escritura en los buckets modelos/deck', v_n; end if;
end $$;
