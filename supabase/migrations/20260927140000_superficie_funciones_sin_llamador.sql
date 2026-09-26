-- destructivo-ok: solo quita permisos de EJECUTAR a funciones sin llamador con sesión; no toca filas ni borra funciones.
-- Reducir la exposición (owner, 27-sep-2026: «¿por qué casi 460 endpoints?»). Análisis por pieza en
-- encargos/20260927_lawang_superficie_api_detalle.md (Seguridad, solo lectura) y re-verificado contra la base
-- (0 policies, 0 vistas, 0 funciones INVOKER ni defaults que las llamen) antes de escribir esto.
--
-- A) Solo las llaman funciones SECURITY DEFINER de la base (corren como su dueño) → authenticated no las
--    necesita. Se APLAZAN (siguen como están) cuatro que alcanza código que corre con la sesión:
--    _bancos_cuenta_valida (la llama _bancos_perfil_autoria, INVOKER), lw_importe y lw_importe_texto
--    (carta_cobrado_aplica_hitos, INVOKER) y lw_orden_natural (valor por defecto de una columna).
-- B) Nadie las llama: agente_reescribe_pdf_manual, carta_cobrado_recalcula, unidad_parte_cobrada (borrarlas
--    lo decide el owner). modelo_precio_construccion espera al bloque 3.
-- C) Web pública: las llaman las páginas con la clave anónima como Bearer (siempre rol anon, haya o no sesión
--    en el navegador): el permiso de authenticated sobra; anon se queda.
-- service_role conserva EXECUTE en todo (la usan edges con service role, p. ej. `parametro` en
-- libera-reservas-vencidas). Se revoca también de PUBLIC: si el permiso venía por ahí, revocar solo del rol no
-- basta (lección del 27-sep, seguridad_2026.md §1.ter).
do $$
declare f record;
  solo_base text[] := array['_sc_columnas_clients','_sc_mes_cerrado','catalogo_tramo_activo','contrato_firma_viva',
    'contrato_nombres_compradores','contrato_nombres_factura','contratos_mismo_comprador','crm_usuario_activo',
    'deck_proyecto_abierto','es_gestor','lead_a_mi_alcance','mismo_proyecto','puede_proyecto_de','puede_proyecto_id',
    'traspaso_carta_estado','parametro',
    'agente_reescribe_pdf_manual','carta_cobrado_recalcula','unidad_parte_cobrada'];
  publicas text[] := array['investor_deck_fotos','investor_deck_faq','unidades_estado_publico','deck_ubicacion_publica',
    'modelo_fotos_publico','parcelas_tamanos_disponibles','deck_config_publico','investor_deck_modelos',
    'investor_deck_documentos','investor_deck_forecast','investor_deck_parcelas','deck_forecast_ejemplo_publico',
    'catalogo_publico','envios_pausados'];
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname = any(solo_base || publicas) loop
    execute format('revoke execute on function %s from public, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
    if f.proname = any(solo_base) then
      execute format('revoke execute on function %s from anon', f.sig);
    else
      execute format('grant execute on function %s to anon', f.sig);
    end if;
  end loop;
end $$;
