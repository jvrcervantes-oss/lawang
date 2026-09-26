-- destructivo-ok: solo retira el permiso de LEER a authenticated/anon en 45 tablas/vistas sin lector con sesión; no toca filas.
-- Reducir la exposición (owner, 27-sep-2026: «¿por qué casi 460 endpoints?»). Análisis por pieza de Seguridad
-- (encargos/20260927_lawang_superficie_api_detalle.md §2) y re-comprobado contra main tras publicar B3-B5 (grep de los
-- 45 nombres en contracts/, intranet/, portal/, investor-deck/, palmfield/, modelo/, formacion/, js/, assets/, api/ y
-- edges: solo comentarios, un icono y lecturas con service_role). Quien las lee es service_role (vigilante, panel-web,
-- fathom-webhook, edges) o funciones SECURITY DEFINER (los crm_*, portal_*, investor_deck_*), que no necesitan este
-- permiso. Cada tabla es una puerta de PostgREST (filtros, select=*, embebidos) que el servidor no ha elegido.
revoke select on
  -- del estudio, dentro de la base del cliente
  public.axisworks_cuentas, public.axisworks_facturas, public.axisworks_meta_campanas, public.axisworks_meta_campanas_conjuntos,
  public.axisworks_meta_exclusiones_segmento, public.axisworks_meta_insights_dia, public.axisworks_meta_targeting_historial,
  public.axisworks_meta_vigilancia,
  -- logs y rastro (los enseñan RPC con su permiso, o solo el estudio)
  public.comision_admin_lineas_log, public.comision_admin_tarifas_log, public.comisiones_ajustes_log, public.condiciones_comision_log,
  public.cuentas_bancarias_log, public.equipos_log, public.lead_acceso_log, public.lead_dueno_log, public.lead_estado_log,
  public.unidades_log, public.unidades_borradas, public.proyectos_borrados, public.creatividad_descargas,
  public.avisos_almacenamiento, public.avisos_soporte_equipo,
  -- CRM (se sirve por las RPC crm_* DEFINER)
  public.lead_accion, public.lead_closer, public.lead_contrato, public.lead_estado, public.lead_notas,
  public.lead_sugerencia, public.lead_tablero, public.fathom_call_insights,
  -- resto
  public.bancos_importaciones, public.contrato_roles_equipo, public.reclamaciones_venta_propia, public.obra_fase_orden_pago,
  public.investor_deck_config, public.investor_deck_verificaciones, public.preferencias_comprador, public.payments,
  public.reservations, public.plantillas_pago, public.contratos_construccion_sin_unidad, public.contratos_sin_parcela_vinculada,
  public.proyectos_huerfanos, public._respaldo_resort_sandalwoods
from authenticated, anon;

do $$
declare malos text;
begin
  select string_agg(c.relname, ', ') into malos from pg_class c
   where c.relnamespace = 'public'::regnamespace
     and c.relname in ('axisworks_cuentas','axisworks_facturas','axisworks_meta_campanas','axisworks_meta_campanas_conjuntos',
       'axisworks_meta_exclusiones_segmento','axisworks_meta_insights_dia','axisworks_meta_targeting_historial','axisworks_meta_vigilancia',
       'comision_admin_lineas_log','comision_admin_tarifas_log','comisiones_ajustes_log','condiciones_comision_log','cuentas_bancarias_log',
       'equipos_log','lead_acceso_log','lead_dueno_log','lead_estado_log','unidades_log','unidades_borradas','proyectos_borrados',
       'creatividad_descargas','avisos_almacenamiento','avisos_soporte_equipo','lead_accion','lead_closer','lead_contrato','lead_estado',
       'lead_notas','lead_sugerencia','lead_tablero','fathom_call_insights','bancos_importaciones','contrato_roles_equipo',
       'reclamaciones_venta_propia','obra_fase_orden_pago','investor_deck_config','investor_deck_verificaciones','preferencias_comprador',
       'payments','reservations','plantillas_pago','contratos_construccion_sin_unidad','contratos_sin_parcela_vinculada',
       'proyectos_huerfanos','_respaldo_resort_sandalwoods')
     and (has_table_privilege('authenticated', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'SELECT'));
  if malos is not null then raise exception 'Siguen legibles con sesión: %', malos; end if;
end $$;
