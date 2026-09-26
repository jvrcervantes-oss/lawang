-- destructivo-ok: esto QUITA el permiso TRUNCATE (y TRIGGER, REFERENCES) a anon/authenticated; no vacia ninguna tabla ni toca una fila.
-- Rev. previa #119 (Seguridad) y LAW-330: TRUNCATE salta la RLS y los triggers por fila
-- (incluido trg_guarda_antes_de_borrar): con él un agente vaciaba `facturas` sin respaldo.
-- Nadie lo usa: 0 funciones con TRUNCATE (medido 26-sep), y por la REST no se puede lanzar.
-- Aplicada por MCP el 26-sep; después, 0 tablas de `public` con esos permisos para anon/authenticated.
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
-- Y que las tablas nuevas no nazcan con ellos (las crea `postgres`).
alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from anon, authenticated;
