-- Prueba del paso 3A (Fase 2, 7-oct-2026): usuario_da_alcance. Se ejecuta DESPUES de la migracion 20261007002000 (o pegada tras ella para ensayarla sin rastro). Termina en raise (rollback).
-- Debe acabar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise; sin drop
do $t$
declare
  jv uuid; pep uuid; e_pep text; ya uuid; cr uuid; e_ya text;
  r text := ''; fallos int := 0; ok boolean; j jsonb; n int; p_l uuid; p_s uuid; rol_ text; amb text; emp text[];
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into pep, e_pep from public.usuarios where activo and rol='super_admin' and not es_propietario limit 1;
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id into cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select id into p_l from public.proyectos where empresa='lawang' limit 1;
  select id into p_s from public.proyectos where empresa='sandal_woods' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='agente', ambito='global', empresas='{}', proyectos=array[p_l,p_s], proyectos_supervisados='{}' where user_id=ya;
  -- (1) el propietario da admin_empresa/lawang: cambia rol, ambito y empresas de golpe y quita el proyecto de Sandal Woods
  set local role authenticated;
  j := public.usuario_da_alcance(ya, 'admin_empresa', array['lawang']);
  reset role;
  select rol, ambito, empresas into rol_, amb, emp from public.usuarios where user_id=ya;
  ok := rol_='admin_empresa' and amb='empresa' and emp=array['lawang'] and (j->>'proyectos_quitados')::int = 1
        and (select proyectos from public.usuarios where user_id=ya) = array[p_l];
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' propietario da admin_empresa/lawang, quita proyecto ajeno: ' || j::text || E'\n'; if not ok then fallos:=fallos+1; end if;
  -- (2) rol de empresa sin empresas, empresa inexistente, super_admin, admin con empresas: rechazados
  set local role authenticated;
  ok := false; begin perform public.usuario_da_alcance(ya, 'admin_empresa', '{}'); exception when others then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' rol de empresa sin empresas rechazado' || E'\n'; if not ok then fallos:=fallos+1; end if;
  ok := false; begin perform public.usuario_da_alcance(ya, 'agente', array['nope']); exception when others then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' empresa inexistente rechazada' || E'\n'; if not ok then fallos:=fallos+1; end if;
  ok := false; begin perform public.usuario_da_alcance(ya, 'super_admin', '{}'); exception when others then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' super_admin no se da por aqui' || E'\n'; if not ok then fallos:=fallos+1; end if;
  ok := false; begin perform public.usuario_da_alcance(ya, 'admin', array['lawang']); exception when others then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' admin global con empresas rechazado' || E'\n'; if not ok then fallos:=fallos+1; end if;
  ok := false; begin perform public.usuario_da_alcance(jv, 'agente', '{}'); exception when others then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' nadie se cambia a si mismo' || E'\n'; if not ok then fallos:=fallos+1; end if;
  ok := false; begin perform public.usuario_da_alcance(pep, 'agente', '{}'); exception when others then ok := true; end;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' un super admin global no se toca' || E'\n'; if not ok then fallos:=fallos+1; end if;
  reset role;
  -- (3) un super admin que NO es propietario no puede
  perform set_config('request.jwt.claims', json_build_object('sub',pep,'role','authenticated','email',e_pep)::text, true);
  set local role authenticated;
  ok := false; begin perform public.usuario_da_alcance(cr, 'admin_empresa', array['lawang']); exception when sqlstate '42501' then ok := true; end;
  reset role;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' super admin no propietario rechazado' || E'\n'; if not ok then fallos:=fallos+1; end if;
  -- (4) un admin de empresa tampoco, y el anon no ejecuta
  perform set_config('request.jwt.claims', json_build_object('sub',ya,'role','authenticated','email',e_ya)::text, true);
  set local role authenticated;
  ok := false; begin perform public.usuario_da_alcance(cr, 'agente', '{}'); exception when sqlstate '42501' then ok := true; end;
  reset role;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' admin_empresa no da niveles' || E'\n'; if not ok then fallos:=fallos+1; end if;
  set local role anon;
  ok := false; begin perform public.usuario_da_alcance(cr, 'agente', '{}'); exception when sqlstate '42501' then ok := true; end;
  reset role;
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' anon sin EXECUTE' || E'\n'; if not ok then fallos:=fallos+1; end if;
  -- (5) devolver a agente global sin empresas
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  set local role authenticated;
  j := public.usuario_da_alcance(ya, 'agente', '{}');
  reset role;
  select rol, ambito, empresas into rol_, amb, emp from public.usuarios where user_id=ya;
  ok := rol_='agente' and amb='global' and emp='{}';
  r := r || case when ok then 'OK   ' else 'FALLO' end || ' vuelve a agente global sin empresas' || E'\n'; if not ok then fallos:=fallos+1; end if;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
