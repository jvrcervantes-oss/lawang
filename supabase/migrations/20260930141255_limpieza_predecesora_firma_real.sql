-- Aplicada el 30-sep-2026 por la sesión principal (encargo equipos de venta, LAW-478 (3)).
-- destructivo-ok: owner 30-sep «Sí, las dos» — borrar _condicion_predecesora (sin llamador, revocada, marcada OBSOLETA); la anterior migración usó una firma equivocada
do $$
declare v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%_condicion_predecesora(%' and p.proname <> '_condicion_predecesora';
  if v_n > 0 then raise exception '_condicion_predecesora todavía tiene % llamador(es): no se borra', v_n; end if;
end $$;
drop function if exists public._condicion_predecesora(uuid, uuid, text, text, date, uuid);
