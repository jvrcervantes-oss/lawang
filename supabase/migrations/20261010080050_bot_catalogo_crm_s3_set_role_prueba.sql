-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (nombre exacto; version real del catalogo 20261008161133, el prefijo sigue al fichero padre para que el orden de replay sea el de aplicacion; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20261010080100_bot_catalogo_crm_s3_saneo.sql
-- Para PROBAR con el rol real: postgres necesita poder hacer SET ROLE bot_lawang (en PG16 crear el rol no concede SET). No da ningun permiso nuevo al bot.
grant bot_lawang to postgres with set true;
