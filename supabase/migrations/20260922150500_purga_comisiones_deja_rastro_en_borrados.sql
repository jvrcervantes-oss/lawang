-- Decisión del owner (22-sep-2026): la comisión/solicitud que borrar_operacion()
-- purga debe dejar rastro, igual que ya pasa con contratos y facturas
-- borrados. Ya existe el mecanismo genérico para esto (LAW-71,
-- 20260819044917_law71_caja_negra_y_rastro): la tabla public.borrados +
-- el trigger public.trg_guarda_antes_de_borrar(), que hoy solo cuelga de
-- contratos y facturas. Se reutiliza tal cual -- cero tabla nueva, mismo
-- patrón que ya audita el super_admin.
drop trigger if exists trg_guarda_antes_de_borrar on public.comisiones_devengadas;
create trigger trg_guarda_antes_de_borrar before delete on public.comisiones_devengadas
  for each row execute function public.trg_guarda_antes_de_borrar();

drop trigger if exists trg_guarda_antes_de_borrar on public.solicitudes_pago;
create trigger trg_guarda_antes_de_borrar before delete on public.solicitudes_pago
  for each row execute function public.trg_guarda_antes_de_borrar();
