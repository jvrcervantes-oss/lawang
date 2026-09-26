-- destructivo-ok: retira permisos y policies de ESCRITURA directa (el navegador ya escribe por RPC/edge desde el commit de los bloques 4 y 5); no borra ni cambia ninguna fila.
-- Frontera frontend/backend — bloques 4 y 5, CIERRE (27-sep-2026, LAW-336 / LAW-337). Plan y revisión previa #127:
-- encargos/20260927_lawang_frontera_b4_b5_resto.md
-- APLICAR SOLO cuando las pantallas nuevas estén SERVIDAS (Hostinger + CDN): con estas policies fuera, la versión vieja de
-- documentación, obra, creatividades, comunicados, soporte, asistente, bancos, gastos y «Reasignar autor» deja de guardar.
--
-- Desde aquí `authenticated`/`anon` solo LEEN estas 11 tablas, y en los buckets `documentacion`, `obra`,
-- `creatividades` y `gastos` solo leen. Escriben: documento_proyecto_guarda, obra_foto_cambia, comunicado_guarda,
-- comunicado_borra, hilo_soporte_estado, solicitud_cambio_pide, bot_respuesta_copiada, banco_perfil_guarda,
-- reasigna_autor (SECURITY DEFINER, permiso dentro); la edge `ficheros` con documento_proyecto_registra/_borra,
-- obra_foto_registra/_borra, gasto_justificante_registra y creatividad_guarda (solo service_role); y lo que ya escribía
-- por DEFINER (creatividad_estado, portal_enviar_mensaje, triggers de correcciones_datos, etc.).
-- El 27-sep no había ninguna función INVOKER que escribiera en estas tablas (medido) ni ninguna edge que lo hiciera con
-- la sesión del usuario.

-- ── tablas: fuera cualquier escritura (un REVOKE de tabla quita también los grants por COLUMNA) ────────────────────
revoke insert, update, delete, truncate, maintain on
  public.documentos_proyecto, public.obra_fotos, public.creatividades, public.creatividad_fotos, public.creatividad_modelos,
  public.comunicados, public.hilo_soporte, public.solicitudes_cambio, public.bot_respuestas_copiadas, public.bancos_perfiles,
  public.correcciones_datos
from authenticated, anon;

-- policies de escritura (las de lectura se quedan, salvo las dos ALL que se sustituyen abajo)
drop policy if exists "documentacion: subir" on public.documentos_proyecto;
drop policy if exists "documentacion: editar" on public.documentos_proyecto;
drop policy if exists "documentacion: borrar" on public.documentos_proyecto;
drop policy if exists "creatividades: crear" on public.creatividades;
drop policy if exists "creatividades: editar borrador" on public.creatividades;
drop policy if exists "creatividad_fotos: poner" on public.creatividad_fotos;
drop policy if exists "creatividad_fotos: quitar" on public.creatividad_fotos;
drop policy if exists "creatividad_modelos: poner" on public.creatividad_modelos;
drop policy if exists "creatividad_modelos: quitar" on public.creatividad_modelos;
drop policy if exists "comunicados_admin_insert" on public.comunicados;
drop policy if exists "comunicados_admin_update" on public.comunicados;
drop policy if exists "comunicados_admin_delete" on public.comunicados;
drop policy if exists "solicitudes_cambio: el equipo pide lo que ve" on public.solicitudes_cambio;
drop policy if exists "bot_respuestas_copiadas: cada uno copia lo suyo" on public.bot_respuestas_copiadas;
drop policy if exists "bot_respuestas_copiadas: cada uno corrige lo suyo" on public.bot_respuestas_copiadas;
drop policy if exists "bancos_perfiles: crear" on public.bancos_perfiles;
drop policy if exists "bancos_perfiles: editar" on public.bancos_perfiles;
drop policy if exists "agentes crean correcciones" on public.correcciones_datos;

-- hilo_soporte: la ALL daba también la LECTURA a todo el equipo → se sustituye por una SELECT igual de amplia (la bandeja
-- de soporte la lee el equipo entero; acotarla a «quien ve al comprador» es otra decisión, no de esta pieza).
drop policy if exists "equipo lee y cambia el estado" on public.hilo_soporte;
create policy "equipo lee los tickets" on public.hilo_soporte for select to authenticated using (public.es_agente());

-- obra_fotos: la lectura pasa a tener ALCANCE POR PROYECTO vía la unidad (revisión #127 de Seguridad; decisión del
-- estudio por coherencia con documentación, reversible, anotada para el owner). Antes: cualquier agente veía todas.
drop policy if exists "obra_fotos: con la herramienta escriben" on public.obra_fotos;
drop policy if exists "obra_fotos: agentes leen" on public.obra_fotos;
create policy "obra_fotos: el equipo lee las de sus proyectos" on public.obra_fotos for select to authenticated
  using (public.agente_ve_unidad_obra(unidad_id));

-- ── Storage ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- subir/borrar solo la edge (service role). NO se tocan las lecturas: «documentacion: agentes leen», «portal lee la
-- documentacion compartida», «creatividades: leer ficheros», «gastos: leer justificantes», «portal ve sus fotos de obra».
drop policy if exists "documentacion: agentes escriben" on storage.objects;
drop policy if exists "documentacion: super admin borra" on storage.objects;
drop policy if exists "creatividades: subir ficheros" on storage.objects;
drop policy if exists "gastos: subir justificantes" on storage.objects;
-- `obra`: su única policy del equipo era ALL (también daba la lectura, de cualquier objeto) → SELECT con alcance
drop policy if exists "obra: el equipo gestiona las fotos" on storage.objects;
create policy "obra: el equipo lee las fotos de sus proyectos" on storage.objects for select to authenticated
  using (bucket_id = 'obra' and public.agente_ve_foto_obra(name));

-- `documentacion` no tenía tipos admitidos (50 MB de cualquier cosa): los mismos que la edge (TIPOS_DOC).
update storage.buckets set allowed_mime_types = array[
  'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
  'application/msword', 'application/vnd.ms-excel', 'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'text/csv', 'image/vnd.dwg', 'image/vnd.dxf', 'application/zip']
 where id = 'documentacion';

-- La RPC vieja de justificantes de gasto: ya no la llama nadie (la sustituye gasto_justificante_registra, solo edge).
revoke all on function public.gasto_anade_justificante(uuid, text, text) from public, anon, authenticated;

-- ── Comprobación: si queda cualquier escritura, se para ─────────────────────────────────────────────────────────
do $$
declare v_n int; t text[] := array['documentos_proyecto', 'obra_fotos', 'creatividades', 'creatividad_fotos', 'creatividad_modelos',
  'comunicados', 'hilo_soporte', 'solicitudes_cambio', 'bot_respuestas_copiadas', 'bancos_perfiles', 'correcciones_datos'];
begin
  select count(*) into v_n
    from pg_class c, lateral aclexplode(c.relacl) a
   where c.relnamespace = 'public'::regnamespace and c.relname = any (t)
     and a.grantee in ('authenticated'::regrole, 'anon'::regrole)
     and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'MAINTAIN');
  if v_n > 0 then raise exception 'Quedan % privilegios de escritura de tabla para authenticated/anon', v_n; end if;
  -- grants por COLUMNA (Seguridad #127): relacl no los enseña
  select count(*) into v_n from information_schema.column_privileges
   where table_schema = 'public' and table_name = any (t) and grantee in ('authenticated', 'anon')
     and privilege_type in ('INSERT', 'UPDATE');
  if v_n > 0 then raise exception 'Quedan % privilegios de escritura por columna para authenticated/anon', v_n; end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and cmd <> 'SELECT' and tablename = any (t);
  if v_n > 0 then raise exception 'Quedan % policies de escritura en las tablas de los bloques 4 y 5', v_n; end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and cmd <> 'SELECT'
     and (coalesce(qual, '') ~ '''(documentacion|obra|creatividades|gastos)''' or coalesce(with_check, '') ~ '''(documentacion|obra|creatividades|gastos)''');
  if v_n > 0 then raise exception 'Quedan % policies de escritura en los buckets documentacion/obra/creatividades/gastos', v_n; end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.gasto_anade_justificante(uuid, text, text)'::regprocedure
              and (p.proacl is null or p.proacl::text ~ 'authenticated=|anon=|(^|[{,])=X')) then
    raise exception 'gasto_anade_justificante sigue ejecutable fuera de service_role';
  end if;
end $$;
