-- F4 (30-sep-2026): la forma por id de comision_visible solo la llaman funciones DEFINER (corren como postgres).
-- Sin llamador desde el navegador -> sin EXECUTE para authenticated (reducir la exposicion, CLAUDE.md).
revoke execute on function public.comision_visible(uuid) from authenticated;
