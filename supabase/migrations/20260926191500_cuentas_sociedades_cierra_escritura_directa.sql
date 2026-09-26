-- destructivo-ok: QUITA permisos de escritura directa (insert/update/delete) a anon/authenticated sobre las 5 tablas de a quién se paga y quién emite; no borra ni cambia ninguna fila. OK del owner 26-sep.
-- LAW-336 pieza 4, 26-sep-2026. /intranet/cuentas/, /intranet/sociedades/ y editores.js (v4) ya van por
-- cuenta_bancaria_guarda / reparto_cuentas_guarda / plantilla_contrato_guarda / sociedad_guarda (servido
-- en producción, VERDE del verificador). Ninguna otra pantalla ni función escribe en estas tablas
-- (medido: grep del repo y pg_proc). Las edges con service_role no dependen de estos GRANT.
revoke insert, update, delete on public.cuentas_bancarias, public.sociedades, public.plantillas_contrato,
  public.plantilla_cuentas, public.proyecto_cuentas from anon, authenticated;
-- sociedades tenía además GRANT UPDATE por columna (16 columnas): se retira explícito.
revoke update (label, razon, marca, npwp, npwp_label, nib, domicilio, rep, logo, logo_alto, emisor_debajo,
  folio, tinta, activa, orden, es_indonesia) on public.sociedades from anon, authenticated;
