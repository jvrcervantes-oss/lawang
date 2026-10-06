-- Prueba de f1_empresas (7-oct-2026): permisos de empresas / proyecto_empresa_guarda / trg_proyecto_empresa. Se ejecuta DESPUES de aplicar la migracion por execute_sql;
-- termina con un raise a proposito (sin rastro). Esperado: admin y agente 42501, super cambia y revierte, empresa falsa 22023, anon sin acceso, md5 de facturas/contratos/unidades/comision iguales.
-- Los user_id de abajo son de produccion del 7-oct: cambiarlos si ya no existen.
do $t$
declare r text := ''; v text; n int; pid uuid; h record;
  su text := '45d014eb-46f2-4770-87a7-69bbd08a44ae'; ad text := '24257595-aee2-4daa-8170-d268f46b9981'; ag text := 'dc1961c0-f623-40c2-82c7-baf94b29bac2';
begin
  for h in select 'facturas' t, count(*) n, md5(string_agg(f::text,'|' order by f.id::text)) m from public.facturas f
    union all select 'contratos', count(*), md5(string_agg(c::text,'|' order by c.id::text)) from public.contratos c
    union all select 'unidades', count(*), md5(string_agg(u::text,'|' order by u.id::text)) from public.unidades u
    union all select 'comision', count(*), md5(string_agg(l::text,'|' order by l::text)) from public.comision_admin_lineas l
  loop r := r || h.t||'='||h.n||'/'||h.m||'; '; end loop;
  r := r || E'\nREPARTO ' || (select string_agg(coalesce(empresa,'NULL')||':'||c, ',') from (select empresa, count(*) c from public.proyectos group by 1 order by 1) x);
  select id into pid from public.proyectos where nombre='Bonian Village';
  r := r || E'\nBonian=' || coalesce(public.empresa_de_proyecto(pid),'NULL') || ' nulo=' || coalesce(public.empresa_de_proyecto(null),'NULL');
  r := r || E'\nanon exec empresa_de_proyecto=' || has_function_privilege('anon','public.empresa_de_proyecto(uuid)','execute') || ' guarda=' || has_function_privilege('anon','public.proyecto_empresa_guarda(uuid,text)','execute') || ' tabla anon select=' || has_table_privilege('anon','public.empresas','select') || ' auth insert=' || has_table_privilege('authenticated','public.empresas','insert');
  -- admin (no super)
  perform set_config('request.jwt.claims', json_build_object('sub',ad,'role','authenticated','email','p@pabloglobal.es')::text, true);
  set local role authenticated;
  select count(*) into n from public.proyectos; r := r || E'\nadmin ve proyectos=' || n;
  select count(*) into n from public.empresas; r := r || ' empresas=' || n;
  r := r || ' empresa_de_proyecto=' || coalesce(public.empresa_de_proyecto(pid),'NULL');
  begin perform public.proyecto_empresa_guarda(pid,'sandal_woods'); r := r || E'\nadmin guarda=PERMITIDO(MAL)'; exception when others then r := r || E'\nadmin guarda rechazado ' || sqlstate; end;
  begin update public.proyectos set empresa='sandal_woods' where id=pid; r := r || ' admin update directo=PERMITIDO(MAL)'; exception when others then r := r || ' update directo rechazado ' || sqlstate; end;
  reset role;
  -- agente
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'role','authenticated','email','admin@lawangproperties.com')::text, true);
  set local role authenticated;
  select count(*) into n from public.empresas; r := r || E'\nagente empresas=' || n;
  begin perform public.proyecto_empresa_guarda(pid,null); r := r || ' agente guarda=PERMITIDO(MAL)'; exception when others then r := r || ' agente guarda rechazado ' || sqlstate; end;
  reset role;
  -- super
  perform set_config('request.jwt.claims', json_build_object('sub',su,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  set local role authenticated;
  perform public.proyecto_empresa_guarda(pid,'sandal_woods');
  r := r || E'\nsuper cambia Bonian -> ' || public.empresa_de_proyecto(pid);
  begin perform public.proyecto_empresa_guarda(pid,'inventada'); r := r || ' empresa falsa=PERMITIDO(MAL)'; exception when others then r := r || ' falsa rechazada ' || sqlstate; end;
  perform public.proyecto_empresa_guarda(pid,null); r := r || ' -> ' || coalesce(public.empresa_de_proyecto(pid),'NULL');
  reset role;
  -- lw_lector con claims de agente
  perform set_config('request.jwt.claims', json_build_object('sub',ag,'role','authenticated','email','admin@lawangproperties.com')::text, true);
  set local role lw_lector;
  select count(*) into n from public.proyectos; r := r || E'\nlw_lector proyectos=' || n;
  select count(*) into n from public.empresas; r := r || ' empresas=' || n || ' empresa_de_proyecto=' || coalesce(public.empresa_de_proyecto(pid),'NULL');
  reset role;
  -- FK
  begin update public.proyectos set empresa='nada' where id=pid; r := r || E'\nFK=PERMITIDO(MAL)'; exception when others then r := r || E'\nFK rechaza ' || sqlstate; end;
  -- clave fija
  begin update public.empresas set clave='x_nuevo' where clave='lawang'; r := r || ' clave=EDITADA(MAL)'; exception when others then r := r || ' clave fija ' || sqlstate; end;
  -- triggers de nombre/slug no se disparan: md5 de nuevo tras UPDATE OF empresa
  update public.proyectos set empresa = empresa where id=pid;
  for h in select 'facturas' t, md5(string_agg(f::text,'|' order by f.id::text)) m from public.facturas f union all select 'contratos', md5(string_agg(c::text,'|' order by c.id::text)) from public.contratos c union all select 'unidades', md5(string_agg(u::text,'|' order by u.id::text)) from public.unidades u union all select 'comision', md5(string_agg(l::text,'|' order by l::text)) from public.comision_admin_lineas l
  loop r := r || E'\nDESPUES ' || h.t || '=' || h.m; end loop;
  raise exception E'ENSAYO-OK (rollback)\n%', r;
end $t$;
