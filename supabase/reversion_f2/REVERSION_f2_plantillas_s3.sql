-- Reversion de la migracion 20261008990000 (plantillas por empresa · S3, validador en servidor, 7-oct-2026).
-- Quita las 9 funciones puras del validador. No hay datos que deshacer (no escribe ni lee ninguna tabla). Solo se puede aplicar si las RPC de S2
-- (plantilla_guarda / plantilla_activa) ya no llaman al validador; si siguen llamandolo, esas RPC fallaran hasta que se vuelva a aplicar la migracion.
-- destructivo-ok: drop de 9 funciones propias, sin datos; la migracion que las crea es la unica que las usa
begin;
drop function if exists public.plantilla_cuerpo_valida_semilla(text, text);
drop function if exists public.plantilla_cuerpo_valida(text, text);
drop function if exists public._plantilla_valida(text, text, boolean);
drop function if exists public._plantilla_analiza(text, boolean);
drop function if exists public._plantilla_style_valido(text);
drop function if exists public._plantilla_texto(text, boolean);
drop function if exists public._plantilla_clases();
drop function if exists public._plantilla_campos_if();
drop function if exists public._plantilla_marcadores();
commit;
