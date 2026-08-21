-- El REVOKE ALL FROM PUBLIC de la migracion anterior no bastó: Supabase
-- concede EXECUTE a anon por privilegios por defecto del esquema, aparte de
-- PUBLIC (mismo tipo de trampa ya documentada para RPCs de esta suite -- ver
-- reference_supabase_revoke_public_no_basta). Se revoca a anon explicitamente.
revoke execute on function public.contratos_equipo() from anon;
revoke execute on function public.facturas_equipo() from anon;
revoke execute on function public.contrato_firmas_equipo() from anon;;
