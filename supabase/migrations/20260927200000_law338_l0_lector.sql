-- LAW-338 · bloque L0 — rol lector de las RPC de lectura por pantalla.
-- Diseño y revisiones previas #128 (Seguridad + Datos): encargos/20260927_lawang_law338_lecturas_bloques.md
--
-- QUÉ HACE (solo construye; no revoca nada de authenticated/anon, no toca pantallas ni RPC existentes):
--   1. Rol `lw_lector` NOLOGIN NOINHERIT NOBYPASSRLS, concedido SOLO a postgres (para poder ser dueño de las
--      futuras `<pantalla>_datos` SECURITY DEFINER). Nunca se le da authenticated/anon ni USAGE en `auth`.
--   2. SELECT = copia EXACTA de lo que `authenticated` lee hoy (91 tablas/vistas + el grant de columna
--      usuarios.numero_usuario). Ninguna escritura.
--   3. EXECUTE en las auxiliares que usan las policies de lectura de public y las vistas security_invoker,
--      solo las que authenticated ya ejecuta (contrato_identificadores NO: authenticated tampoco la tiene).
--      auth.uid()/auth.email() ya son ejecutables por PUBLIC: no se concede nada en `auth`.
--   4. public.uid_sesion(): envoltorio DEFINER de auth.uid() para el cuerpo de las RPC (que como lw_lector no
--      puede nombrar el esquema auth). EXECUTE solo a lw_lector.
--   5. Las 78 policies SELECT `TO authenticated` pasan a `TO authenticated, lw_lector` (las 12 `TO public`
--      ya lo cubren). Así, dentro de una DEFINER con dueño lw_lector la RLS filtra igual que hoy.
--   6. Storage «creatividades: leer ficheros» deja de hacer EXISTS directo sobre public.creatividades y pasa a
--      la auxiliar DEFINER public.creatividad_ve_fichero(name), que repite la policy de lectura de la tabla
--      (creatividad_puede_ver) + la condición original: mismo resultado, y creatividades se podrá cerrar (L2).
--
-- Las listas de 2, 3 y 5 se generaron del catálogo el 27-sep-2026 y van LITERALES para que el fichero sea
-- reproducible. El invariante «lw_lector es copia de authenticated» vive en tools/salud_lawang.py --sql.

-- ── 1. Rol ────────────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'lw_lector') then
    create role lw_lector nologin noinherit nobypassrls;
  end if;
end $$;
alter role lw_lector nologin noinherit nobypassrls nocreatedb nocreaterole noreplication;
grant lw_lector to postgres with inherit true, set true;

-- ── 2. Lectura: copia exacta de authenticated ─────────────────────────────────────────────────────────────
grant usage on schema public to lw_lector;
grant select on
  public.apoderados_hak_sewa, public.bancos_conciliacion, public.bancos_movimientos, public.bancos_perfiles,
  public.bloques_legales, public.borrados, public.bot_bloqueos, public.bot_consultas, public.bot_faq,
  public.bot_fuentes, public.bot_respuestas_copiadas, public.bot_temas, public.clients, public.comision_admin_fees,
  public.comision_admin_lineas, public.comision_admin_tarifas, public.comisiones_devengadas, public.comunicado_envios,
  public.comunicados, public.condicion_tramos, public.condiciones_comision, public.contrato_compradores,
  public.contrato_documentos, public.contrato_eventos, public.contrato_firmas, public.contrato_prorrogas,
  public.contrato_tipo_etapa, public.contrato_vencimientos, public.contratos, public.contratos_diseno,
  public.correcciones_datos, public.correos_enviados, public.creatividad_fotos, public.creatividad_modelos,
  public.creatividades, public.cuentas_bancarias, public.deck_config_proyecto, public.deck_faq, public.deck_forecast,
  public.deck_forecast_proyecto, public.deck_fotos, public.deck_publicaciones, public.documentos_desactualizados,
  public.documentos_proyecto, public.documents, public.equipo_miembros, public.equipos_venta, public.extras,
  public.facturas, public.firmantes_cred, public.gasto_categorias, public.gastos, public.gastos_log,
  public.hilo_soporte, public.lead_estados, public.leads, public.mantenimiento, public.mensajes_comprador,
  public.modelo_documentos, public.modelo_extras, public.modelo_techos, public.modelos, public.modelos_precios_log,
  public.modelos_sin_catalogar, public.modelos_villa, public.notificaciones, public.obra_fases, public.obra_fotos,
  public.obra_partes_trabajo, public.obra_progreso_fase_zona, public.parametros, public.plantilla_cuentas,
  public.plantillas_contrato, public.portal_accesos, public.privilegios_ejercidos, public.proveedores,
  public.proyecto_cuentas, public.proyecto_eventos, public.proyecto_plazo_pago, public.proyectos,
  public.recibi_aplicaciones, public.referidos_contactos, public.sociedades, public.sociedades_log,
  public.solicitudes_cambio, public.solicitudes_colaborador, public.solicitudes_pago, public.tipos_vivienda,
  public.unidades, public.unidades_estado, public.usuarios
to lw_lector;
-- grant de columna que authenticated tiene aparte del de tabla (usuarios.numero_usuario)
grant select (numero_usuario) on public.usuarios to lw_lector;

-- ── 3. EXECUTE en las auxiliares de las policies de lectura y de las vistas invoker ──────────────────────
grant execute on function
  public._equipo_de_condicion_comision(uuid),
  public.agente_ve_unidad_obra(uuid),
  public.cliente_visible(text, uuid),
  public.contrato_visible(text, uuid),
  public.creatividad_puede_ver(text, text),
  public.diferencias_con_ficha(jsonb, jsonb),
  public.documento_visible(text, uuid, uuid),
  public.es_admin(),
  public.es_agente(),
  public.es_manager_de(uuid),
  public.es_manager_de_equipo(uuid),
  public.es_portal(),
  public.es_super_admin(),
  public.es_suyo(text),
  public.modelo_norm(text),
  public.proyecto_visible(uuid),
  public.puede(text),
  public.puede_proyecto(text, uuid),
  public.unidad_parte_cobrada_split(uuid),
  public.unidad_visible(uuid)
to lw_lector;

-- ── 4. uid_sesion(): el usuario de la sesión, sin nombrar `auth` desde el cuerpo de las RPC ──────────────
create or replace function public.uid_sesion()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select auth.uid() $$;
alter function public.uid_sesion() owner to postgres;
revoke all on function public.uid_sesion() from public, anon, authenticated;
grant execute on function public.uid_sesion() to lw_lector;

-- ── 5. Policies de lectura: authenticated + lw_lector ─────────────────────────────────────────────────────
alter policy "apoderados hak sewa: solo con sesion" on public.apoderados_hak_sewa to authenticated, lw_lector;
alter policy "bancos_conciliacion: leer" on public.bancos_conciliacion to authenticated, lw_lector;
alter policy "bancos_movimientos: leer" on public.bancos_movimientos to authenticated, lw_lector;
alter policy "bancos_perfiles: leer" on public.bancos_perfiles to authenticated, lw_lector;
alter policy "bloques_legales: leer" on public.bloques_legales to authenticated, lw_lector;
alter policy "super admin lee borrados" on public.borrados to authenticated, lw_lector;
alter policy "bot_bloqueos: agentes leen" on public.bot_bloqueos to authenticated, lw_lector;
alter policy "bot_consultas: quien ve el contrato ve sus consultas" on public.bot_consultas to authenticated, lw_lector;
alter policy "bot_faq: agentes leen" on public.bot_faq to authenticated, lw_lector;
alter policy "bot_fuentes: agentes leen" on public.bot_fuentes to authenticated, lw_lector;
alter policy "bot_respuestas_copiadas: quien ve la consulta ve la copia" on public.bot_respuestas_copiadas to authenticated, lw_lector;
alter policy "bot_temas: agentes leen" on public.bot_temas to authenticated, lw_lector;
alter policy "cada uno lo suyo, el manager lo de su proyecto, admin todo" on public.clients to authenticated, lw_lector;
alter policy "comision_admin_fees: leer" on public.comision_admin_fees to authenticated, lw_lector;
alter policy "comision_admin_lineas: leer" on public.comision_admin_lineas to authenticated, lw_lector;
alter policy "comision_admin_tarifas: leer" on public.comision_admin_tarifas to authenticated, lw_lector;
alter policy "comisiones_devengadas: leer" on public.comisiones_devengadas to authenticated, lw_lector;
alter policy comunicado_envios_admin_select on public.comunicado_envios to authenticated, lw_lector;
alter policy comunicados_admin_select on public.comunicados to authenticated, lw_lector;
alter policy "condicion_tramos: leer" on public.condicion_tramos to authenticated, lw_lector;
alter policy "tramos: el manager lee los de su equipo" on public.condicion_tramos to authenticated, lw_lector;
alter policy "condiciones: el manager lee las de su equipo" on public.condiciones_comision to authenticated, lw_lector;
alter policy "condiciones_comision: leer" on public.condiciones_comision to authenticated, lw_lector;
alter policy "agentes leen contrato_compradores" on public.contrato_compradores to authenticated, lw_lector;
alter policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos to authenticated, lw_lector;
alter policy "agentes leen firmas de sus contratos" on public.contrato_firmas to authenticated, lw_lector;
alter policy prorrogas_select on public.contrato_prorrogas to authenticated, lw_lector;
alter policy "crm ve el catalogo de etapas" on public.contrato_tipo_etapa to authenticated, lw_lector;
alter policy vencimientos_select on public.contrato_vencimientos to authenticated, lw_lector;
alter policy "agentes leen sus contratos" on public.contratos to authenticated, lw_lector;
alter policy "agentes autenticados leen diseno" on public.contratos_diseno to authenticated, lw_lector;
alter policy "agentes leen correcciones" on public.correcciones_datos to authenticated, lw_lector;
alter policy "correos: leer lo propio o del contrato visible" on public.correos_enviados to authenticated, lw_lector;
alter policy "creatividad_fotos: leer" on public.creatividad_fotos to authenticated, lw_lector;
alter policy "creatividad_modelos: leer" on public.creatividad_modelos to authenticated, lw_lector;
alter policy "creatividades: leer" on public.creatividades to authenticated, lw_lector;
alter policy "cuentas: solo con sesion" on public.cuentas_bancarias to authenticated, lw_lector;
alter policy "documentacion: leer" on public.documentos_proyecto to authenticated, lw_lector;
alter policy "agentes leen documentos de sus compradores" on public.documents to authenticated, lw_lector;
alter policy "equipo_miembros: leer" on public.equipo_miembros to authenticated, lw_lector;
alter policy "equipos_venta: leer" on public.equipos_venta to authenticated, lw_lector;
alter policy "extras: leer" on public.extras to authenticated, lw_lector;
alter policy "agentes leen sus facturas" on public.facturas to authenticated, lw_lector;
alter policy "firmantes cred: solo con sesion" on public.firmantes_cred to authenticated, lw_lector;
alter policy "categorias: leer" on public.gasto_categorias to authenticated, lw_lector;
alter policy "gastos: leer" on public.gastos to authenticated, lw_lector;
alter policy "gastos_log: leer" on public.gastos_log to authenticated, lw_lector;
alter policy "comprador lee su estado" on public.hilo_soporte to authenticated, lw_lector;
alter policy "equipo lee los tickets" on public.hilo_soporte to authenticated, lw_lector;
alter policy "crm lee las columnas del tablero" on public.lead_estados to authenticated, lw_lector;
alter policy mantenimiento_leer on public.mantenimiento to authenticated, lw_lector;
alter policy "comprador ve su hilo de mensajes" on public.mensajes_comprador to authenticated, lw_lector;
alter policy "equipo ve hilos de mensajes" on public.mensajes_comprador to authenticated, lw_lector;
alter policy "modelo_docs: leer" on public.modelo_documentos to authenticated, lw_lector;
alter policy "modelo_extras: leer" on public.modelo_extras to authenticated, lw_lector;
alter policy "techos: leer" on public.modelo_techos to authenticated, lw_lector;
alter policy "modelos: leer" on public.modelos to authenticated, lw_lector;
alter policy "admins leen el historial de precios" on public.modelos_precios_log to authenticated, lw_lector;
alter policy "modelos: leer" on public.modelos_villa to authenticated, lw_lector;
alter policy "obra_fases: leer" on public.obra_fases to authenticated, lw_lector;
alter policy "obra_fotos: el equipo lee las de sus proyectos" on public.obra_fotos to authenticated, lw_lector;
alter policy parametros_select on public.parametros to authenticated, lw_lector;
alter policy "mapeo cuentas: solo con sesion" on public.plantilla_cuentas to authenticated, lw_lector;
alter policy "plantillas de pago: solo con sesion" on public.plantillas_contrato to authenticated, lw_lector;
alter policy "agentes ven accesos del portal" on public.portal_accesos to authenticated, lw_lector;
alter policy "proveedores: leer" on public.proveedores to authenticated, lw_lector;
alter policy "cuentas por proyecto: solo con sesion" on public.proyecto_cuentas to authenticated, lw_lector;
alter policy "agentes leen proyectos" on public.proyectos to authenticated, lw_lector;
alter policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones to authenticated, lw_lector;
alter policy "admins con usuarios ven referidos" on public.referidos_contactos to authenticated, lw_lector;
alter policy "sociedades: leer" on public.sociedades to authenticated, lw_lector;
alter policy "sociedades_log: leer solo super" on public.sociedades_log to authenticated, lw_lector;
alter policy "solicitudes_cambio: cada uno las suyas, admin todas" on public.solicitudes_cambio to authenticated, lw_lector;
alter policy "admins con usuarios ven solicitudes" on public.solicitudes_colaborador to authenticated, lw_lector;
alter policy "agentes leen tipos_vivienda" on public.tipos_vivienda to authenticated, lw_lector;
alter policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades to authenticated, lw_lector;
alter policy "cada uno lee su ficha, el admin todas" on public.usuarios to authenticated, lw_lector;
alter policy "el equipo se ve entre si" on public.usuarios to authenticated, lw_lector;

-- ── 6. Storage: «creatividades: leer ficheros» sin EXISTS directo sobre public.creatividades ─────────────
-- Antes el EXISTS corría como authenticated y le aplicaba la policy «creatividades: leer»
-- (creatividad_puede_ver). La auxiliar corre como postgres (BYPASSRLS), así que la repite EXPLÍCITA
-- además de la condición original: mismo resultado fila a fila, probado el 27-sep-2026.
create or replace function public.creatividad_ve_fichero(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.creatividades c
     where c.id::text = (storage.foldername(p_name))[1]
       and public.creatividad_puede_ver(c.tipo, c.estado)
       and (public.creatividad_puede_hacer(c.tipo)
            or (public.puede('creatividades_ver')
                and c.estado in ('aprobada', 'publicada')
                and (c.path = p_name or c.estado_path = p_name or c.portada_path = p_name))))
$$;
alter function public.creatividad_ve_fichero(text) owner to postgres;
revoke all on function public.creatividad_ve_fichero(text) from public, anon;
grant execute on function public.creatividad_ve_fichero(text) to authenticated;

alter policy "creatividades: leer ficheros" on storage.objects
  using (bucket_id = 'creatividades' and public.creatividad_ve_fichero(name));
