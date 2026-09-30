-- PENDIENTE (30-sep-2026): no_destruir.py lo frenó por el DROP TRIGGER y no se rodea. No destruye datos: solo recrea los
-- dos triggers con la misma definición viva. Sin aplicarlo no cambia nada funcional (la función que llaman ya está
-- arreglada en la migración law474_arreglos_revisor). Espera OK del owner para aplicarlo con su marca destructivo-ok.
-- LAW-474 (f), arreglo 3 del revisor (30-sep-2026): los dos triggers de contrato_closer se recrean con DROP IF EXISTS
-- delante, para que la migración se pueda volver a pasar sin fallar por «ya existe». Misma definición que la viva
-- (20260930120030 y 20260930120750); la función que llaman la cambia law474_arreglos_revisor (la anterior).

drop trigger if exists trg_contrato_closer_a_devengos_vivos on public.contrato_closer;
create trigger trg_contrato_closer_a_devengos_vivos
  before update of closer_email on public.contrato_closer
  for each row
  when (lower(coalesce(old.closer_email, '')) is distinct from lower(coalesce(new.closer_email, '')))
  execute function public._trg_contrato_closer_devengos_vivos();

drop trigger if exists trg_contrato_closer_a_devengos_vivos_borrado on public.contrato_closer;
create trigger trg_contrato_closer_a_devengos_vivos_borrado
  before delete on public.contrato_closer
  for each row
  execute function public._trg_contrato_closer_devengos_vivos();
