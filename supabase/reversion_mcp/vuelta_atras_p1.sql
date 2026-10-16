-- destructivo-ok: VUELTA ATRÁS de 20261016073011_mcp_f1_p1_base.sql y, si se llegaron a aplicar, supabase/propuestas/20261016140000_mcp_f1_abre_conexion.sql y 20261016150000_mcp_f1_purga.sql (puente MCP de Lawang).
-- Solo a mano, con OK del owner y su válvula (tools/no_destruir.py), y con copia previa:
--   python erp/respaldo_instancia.py lawang --previa "antes de revertir el puente MCP P1"
-- PASO 1 — PARAR (no borra nada; basta casi siempre): `update public.ia_ajustes set encendido = false` (Ajustes › IA) y, si hace
-- falta cerrar la puerta, `revoke execute on function public.ia_puente(text, jsonb) from anon;`. Con eso ninguna conexión llama.
-- PASO 2 — QUITAR LA PIEZA: antes, retirar la edge `mcp` (supabase functions delete mcp) y revertir P2 (vuelta_atras_p2.sql).
-- ia_llamadas es el registro de quién consultó qué: con filas, este bloque PARA. Exportarlo y decidir con el owner.
begin;
do $$
begin
  if exists (select 1 from public.ia_llamadas) then
    raise exception 'ia_llamadas tiene filas: exportar y decidir con el owner antes de borrar';
  end if;
end $$;
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from cron.job where jobname = 'ia-purga-diaria') then
    perform cron.unschedule('ia-purga-diaria');
  end if;
end $$;
drop function if exists public.ia_conexion_revoca(uuid);
drop function if exists public.ia_conexion_autoriza(text);
drop function if exists public.ia_puente(text, jsonb);
drop function if exists privado.ia_despacha(text, jsonb);
drop function if exists privado.mcp_cierra(bigint, integer, text);
drop function if exists privado.mcp_puerta(text, jsonb);
drop function if exists privado.ia_conexion_motivo(uuid);
drop function if exists privado.ia_revoca(uuid, text);
drop function if exists privado.ia_token_nuevo(uuid, text, timestamptz, text, text);
drop function if exists privado.ia_hash(text);
drop function if exists privado.ia_b64url(bytea);
drop function if exists privado.ia_purga();
drop function if exists privado.ia_auth_usuario(uuid);
drop function if exists privado.ia_aleatorio();
drop table if exists public.ia_llamadas;
drop table if exists public.ia_tokens;
drop table if exists public.ia_conexiones;
drop table if exists public.ia_peticiones;
drop table if exists public.ia_uso;
drop table if exists public.ia_permisos;
drop table if exists public.ia_clientes;
drop table if exists public.ia_ajustes;
revoke execute on function public.uid_sesion() from ia_puente_rol;
revoke execute on function public.es_super_admin() from ia_puente_rol;
revoke usage on schema privado from ia_puente_rol;
revoke usage on schema public from ia_puente_rol;
drop role if exists ia_puente_rol;
commit;
