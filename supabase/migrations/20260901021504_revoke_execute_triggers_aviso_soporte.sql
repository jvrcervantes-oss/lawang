-- Hallazgo del propio linter de Supabase tras aplicar 20260901120000: las
-- tres funciones trigger quedaron llamables por RPC pública (anon +
-- authenticated) via /rest/v1/rpc/_trg_aviso_*. No son explotables como
-- INSERT falso (Postgres las rechaza fuera de contexto de trigger: "trigger
-- functions can only be called as triggers"), pero no tienen por qué ser
-- superficie pública -- mismo revoke que ya se hizo con el helper
-- `_avisar_equipo_soporte`, olvidado en las tres funciones trigger.
revoke all on function public._trg_aviso_ticket_nuevo() from public, anon, authenticated;
revoke all on function public._trg_aviso_ticket_mensaje() from public, anon, authenticated;
revoke all on function public._trg_aviso_mensaje_comprador() from public, anon, authenticated;
;
