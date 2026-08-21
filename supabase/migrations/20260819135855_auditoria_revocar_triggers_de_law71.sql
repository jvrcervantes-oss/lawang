-- Auditoría de lo hecho hoy: las dos funciones de trigger de LAW-71 nacieron
-- PÚBLICAS y no las revoqué. Es la norma que el repo ya tiene escrita en
-- revocar_triggers_publicos.sql — «una función nueva nace pública» — y me la
-- salté las dos veces. El riesgo práctico es bajo (PostgREST no expone una
-- función que devuelve `trigger`: no puede construir el argumento), pero la
-- norma existe para no depender de ese detalle.
revoke all on function public.trg_guarda_antes_de_borrar() from public, anon, authenticated;
revoke all on function public.trg_registra_edicion_privilegiada() from public, anon, authenticated;;
