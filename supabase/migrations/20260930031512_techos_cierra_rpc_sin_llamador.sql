-- Reducir la exposición (30-sep-2026): la ficha de Modelos guarda los techos solo por modelo_techos_guarda_lote.
-- modelo_techo_edita y modelo_techos_guarda se quedan sin llamador en el navegador: solo las llama el lote (DEFINER).
revoke execute on function public.modelo_techo_edita(uuid, jsonb, boolean) from authenticated;
revoke execute on function public.modelo_techos_guarda(uuid, jsonb) from authenticated;
