-- Aplicada el 30-sep-2026 por la sesión principal (encargo equipos de venta, LAW-481 (1) y LAW-478 (3)).
-- Limpieza técnica autorizada por el owner el 30-sep («Sí, las dos»). No borra datos.
-- destructivo-ok: owner 30-sep «Sí, las dos» — recrear los dos triggers de contrato_closer con drop if exists (misma definición viva) y borrar _condicion_predecesora, sin llamador
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

do $$
declare v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%_condicion_predecesora(%' and p.proname <> '_condicion_predecesora';
  if v_n > 0 then raise exception '_condicion_predecesora todavía tiene % llamador(es): no se borra', v_n; end if;
end $$;
-- (firma equivocada: no borró nada; la borra la migración siguiente con la firma real)
drop function if exists public._condicion_predecesora(uuid, uuid, text, uuid, text, date);
