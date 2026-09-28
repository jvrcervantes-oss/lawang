-- AXW-58 (28-sep-2026, revisor de d335bb01): 20260927231922 puso search_path = '' a deck_ubicacion_publica pero
-- no lo comprobaba. Esta migración solo VERIFICA (no cambia nada): falla si la función no tiene exactamente
-- search_path vacío o si anon perdió su EXECUTE (el investor deck público la llama).
do $$
declare cfg text[];
begin
  select p.proconfig into cfg from pg_proc p where p.oid = 'public.deck_ubicacion_publica(text)'::regprocedure;
  if cfg is null or not ('search_path=""' = any(cfg)) then
    raise exception 'AXW-58: deck_ubicacion_publica no tiene search_path vacio: %', cfg;
  end if;
  if not has_function_privilege('anon', 'public.deck_ubicacion_publica(text)', 'EXECUTE') then
    raise exception 'AXW-58: el deck publico perdio la ubicacion';
  end if;
end $$;
