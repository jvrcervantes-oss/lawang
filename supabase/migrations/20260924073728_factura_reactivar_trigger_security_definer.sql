-- registra_privilegio no tiene EXECUTE para authenticated (solo lo llaman
-- funciones DEFINER, como trg_factura_exige_contrato_bloqueado). El trigger
-- pasa a DEFINER para poder dejar el rastro; auth.uid() sigue leyendo el JWT.
alter function public.factura_anulada_solo_cambia_autor() security definer;
revoke execute on function public.factura_anulada_solo_cambia_autor() from public, anon, authenticated;
