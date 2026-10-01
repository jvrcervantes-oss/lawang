-- AXW-116 (30-sep-2026): `authenticated` deja de leer la tabla `sociedades` entera; solo las columnas que un lector real necesita.
-- Antes: GRANT SELECT de tabla + policy «sociedades: leer» using (true) => un comprador del portal (authenticated) leia por REST
-- TODAS las columnas, incluidas creado_por / actualizado_por (correos del equipo) y creado_en / actualizado_en.
-- Las 17 columnas que se conceden son exactamente las que leen hoy: cargarSociedades (contracts/assets/entities.js: 15 + los filtros
-- activa/orden), bot-agentes (sesion del agente), datos.js/editores.js (clave,razon,label,activa / clave,label), contrato_sociedad_existe
-- y bot_pendientes (clave, razon). Las edges firma-submit / factura-vencimiento / ficheros usan service_role (no dependen de este grant);
-- las RPC definer (sociedades_ajustes_datos, sociedad_guarda, congela_emisor_factura) tampoco. lw_lector conserva su SELECT de tabla.
-- Lo que se quita a authenticated: creado_por, actualizado_por, creado_en, actualizado_en. Reversible: grant select on public.sociedades to authenticated.
revoke select on public.sociedades from authenticated;
grant select (clave, label, razon, marca, npwp, npwp_label, nib, domicilio, rep, logo, logo_alto, emisor_debajo, folio, tinta,
              activa, orden, es_indonesia)
  on public.sociedades to authenticated;
