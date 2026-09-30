-- PROPUESTA — NO APLICADA (Ajustes del ERP, S3, 30-sep-2026). No es una migración: vive en contracts/sql/ a propósito, para que el
-- octavo invariante de salud_lawang.py (migraciones de la base = ficheros del repo) no la cuente como pendiente.
--
-- QUÉ ARREGLA. Hoy `authenticated` tiene SELECT a nivel de TABLA sobre `sociedades` y la policy «sociedades: leer» es `using (true)`:
-- un comprador del portal (29 de las 63 cuentas de Auth, contexto/seguridad_2026.md §7) lee por REST TODAS las columnas, incluidas
-- `creado_por` y `actualizado_por` (correos del equipo) y `actualizado_en`. El portal solo necesita lo que ya va impreso en sus
-- documentos: las 15 columnas que lee `cargarSociedades` (contracts/assets/entities.js). Es una exposición ANTERIOR a esta tarea.
--
-- POR QUÉ NO SE HA APLICADO CON S3. El único llamador con `select('*')` sobre `sociedades` era REG['sociedades'] de
-- intranet/v4/assets/datos.js (la pantalla vieja de Sociedades, que S3 sustituye por una redirección a Ajustes); en producción sigue
-- sirviéndose el código viejo hasta que aterrice S3, y con el GRANT recortado ese `select *` daría «permission denied» y dejaría
-- muerta la pantalla hasta el aterrizaje. Aplicarlo ANTES que el front sería romper lo que funciona.
--
-- CUÁNDO APLICARLO. Después de que S3 esté en producción (la pantalla vieja ya redirige) y tras comprobar en el repo que nada más
-- hace `select *`/`select()` sobre sociedades:  grep -rnE "from\('sociedades'\)" --include=*.js --include=*.html  (solo columnas
-- explícitas). Las funciones DEFINER (dueño postgres: `congela_emisor_factura`, `sociedad_guarda`, `sociedades_ajustes_datos`…) y las
-- edges con service_role no dependen de este GRANT; `contrato_sociedad_existe` y `bot_pendientes` (SECURITY INVOKER) solo leen `clave`
-- y el JSON de contratos: la columna `clave` queda concedida.
--
-- Después de aplicarlo: correr contracts/sql/prueba_ajustes_sociedades.sql; el caso J2 pasa de «EXPUESTO» a «cerrado».
-- El rol lector (lw_lector) conserva SELECT de tabla: las lecturas `*_datos` heredan la RLS y no pasan por este GRANT.
revoke select on public.sociedades from authenticated;
grant select (clave, label, razon, marca, npwp, npwp_label, nib, domicilio, rep, logo, logo_alto, emisor_debajo, folio, tinta,
              activa, orden, es_indonesia)
  on public.sociedades to authenticated;
