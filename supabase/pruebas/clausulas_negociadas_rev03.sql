-- Prueba (se revierte sola: acaba en RAISE) de las cláusulas negociadas REV03 — 2-oct-2026.
-- Usa tablas temporales con las funciones reales; no toca `contratos`.
-- Esperado:
--   A) 1:agente_activa_rechazado 2:agente_sin_campo_pasa 3:admin_activa_pasa 4:agente_edita_sin_tocar_pasa 5:agente_apaga_rechazado
--   B) ficha=empresa -> adq1_tipo=empresa rev03_dni= rev03_hgb=si | sin REV03 -> rev03_dni=(quitada)
-- Cualquier «MAL» o un valor distinto es fallo.

-- A) Solo admin/super_admin cambian clausulas_negociadas.
do $$
declare v_agente uuid; v_admin uuid; v_res text := '';
begin
  select user_id into v_agente from public.usuarios where activo and rol not in ('super_admin','admin') limit 1;
  select user_id into v_admin  from public.usuarios where activo and rol in ('admin','super_admin') order by rol limit 1;
  create temp table t_r (id int primary key, datos jsonb) on commit drop;
  create trigger trg_clausulas_negociadas_rol before insert or update on t_r for each row execute function public.clausulas_negociadas_rol();
  perform set_config('request.jwt.claims', json_build_object('sub', v_agente, 'role','authenticated')::text, true);
  begin insert into t_r values (1, '{"fields":{"clausulas_negociadas":"si"}}'); v_res := v_res || '1:MAL ';
  exception when insufficient_privilege then v_res := v_res || '1:agente_activa_rechazado '; end;
  insert into t_r values (2, '{"fields":{"adq1_nombre":"x"}}'); v_res := v_res || '2:agente_sin_campo_pasa ';
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role','authenticated')::text, true);
  update t_r set datos = '{"fields":{"clausulas_negociadas":"si"}}' where id=2; v_res := v_res || '3:admin_activa_pasa ';
  perform set_config('request.jwt.claims', json_build_object('sub', v_agente, 'role','authenticated')::text, true);
  update t_r set datos = '{"fields":{"clausulas_negociadas":"si","adq1_nombre":"y"}}' where id=2; v_res := v_res || '4:agente_edita_sin_tocar_pasa ';
  begin update t_r set datos = '{"fields":{}}' where id=2; v_res := v_res || '5:MAL ';
  exception when insufficient_privilege then v_res := v_res || '5:agente_apaga_rechazado '; end;
  raise exception 'RESULTADO: %', v_res;
end $$;

-- B) Las derivadas las estampa la base DESPUÉS del espejo del comprador (adq1_tipo falseado).
do $$
declare v_cli uuid; v_res text := ''; d jsonb; v_tipo text; v_id uuid;
begin
  select id, tipo into v_cli, v_tipo from public.clients where tipo = 'empresa' limit 1;
  create temp table t_p (id uuid primary key default gen_random_uuid(), bloqueado boolean default false, datos jsonb) on commit drop;
  create trigger trg_espejo_comprador before insert or update on t_p for each row execute function public.trg_espejo_comprador();
  create trigger trg_rev03_estampa before insert or update of datos on t_p for each row execute function public.rev03_estampa();
  insert into t_p(datos) values (jsonb_build_object('adq1_client_id', v_cli, 'fields', jsonb_build_object('clausulas_negociadas','si','adq1_tipo','persona','regimen_tenencia','leasehold','rev03_dni','si'))) returning id into v_id;
  select datos into d from t_p where id = v_id;
  v_res := 'ficha=' || coalesce(v_tipo,'?') || ' -> adq1_tipo=' || coalesce(d->'fields'->>'adq1_tipo','?') || ' rev03_dni=' || coalesce(d->'fields'->>'rev03_dni','(sin)') || ' rev03_hgb=' || coalesce(d->'fields'->>'rev03_hgb','(sin)');
  update t_p set datos = jsonb_set(datos, '{fields,clausulas_negociadas}', '""') where id = v_id;
  select datos into d from t_p where id = v_id;
  v_res := v_res || ' | sin REV03 -> rev03_dni=' || coalesce(d->'fields'->>'rev03_dni','(quitada)');
  raise exception 'RESULTADO: %', v_res;
end $$;
