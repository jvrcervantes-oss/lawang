-- 24-sep-2026 — get_advisors tras 20260924200000_solicitudes_cambio: las dos funciones de
-- trigger (SECURITY DEFINER) quedaban con EXECUTE para anon/authenticated por el grant por
-- defecto. Llamadas sueltas fallan (no son trigger), pero se cierra igual.
revoke execute on function public._trg_solicitud_cambio_alta() from public, anon, authenticated;
revoke execute on function public._trg_solicitud_cambio_aviso() from public, anon, authenticated;
