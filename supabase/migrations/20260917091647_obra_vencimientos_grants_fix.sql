-- El default ACL de este proyecto ya da INSERT/UPDATE/DELETE a "authenticated" directamente
-- (no via PUBLIC) en toda tabla nueva -- gotcha ya documentado ("el GRANT manda antes que la
-- policy"). El REVOKE FROM public, anon de la migracion anterior no bastaba: hay que revocar
-- de authenticated explicitamente y dejar solo SELECT, apoyado en las RLS policies ya creadas.

revoke all on public.obra_fase_orden_pago from authenticated;
revoke all on public.obra_progreso_fase_zona from authenticated;
revoke all on public.obra_partes_trabajo from authenticated;

grant select on public.obra_fase_orden_pago to authenticated;
grant select on public.obra_progreso_fase_zona to authenticated;
grant select on public.obra_partes_trabajo to authenticated;
