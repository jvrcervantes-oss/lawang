-- STUB DE ENSAYO — NO ES UNA MIGRACION, NO VA A PRODUCCION. (S2 plantillas por empresa, 7-oct-2026)
-- Sustituye al validador de servidor de S3 (`public.plantilla_cuerpo_valida(cuerpo, esqueleto) -> {ok, errores[]}`, migracion 20261008990000+) SOLO para ensayar S2 dentro de
-- una transaccion que acaba en rollback. Devuelve ok=true siempre. La migracion final de S2 NO lo crea: sin S3, guardar y activar fallan cerrado (55000).
create or replace function public.plantilla_cuerpo_valida(p_cuerpo text, p_esqueleto text) returns jsonb
language sql immutable as $$ select jsonb_build_object('ok', true, 'errores', '[]'::jsonb) $$;
