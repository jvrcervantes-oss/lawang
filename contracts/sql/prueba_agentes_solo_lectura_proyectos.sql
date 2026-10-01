-- PRUEBA POR ROL, COMO ATAQUE — agentes en solo lectura sobre proyectos, parcelas, documentos y obra (1-oct-2026).
-- Cubre 20261001123000_agentes_solo_lectura_en_proyectos.sql. Se ejecuta con execute_sql (MCP) o psql como postgres, UN BLOQUE:
-- acaba en `raise exception 'RES: …'`, que revierte la transacción entera y enseña el resultado: NO ESCRIBE NADA.
-- Cada punto debe decir «ok»; un «FALLO» es un agujero abierto. Un «debe fallar» solo vale si falla con 42501 (permiso): cualquier otro
-- error se marca FALLO, porque no prueba la guarda sino otra cosa. Usuarios de prueba (uid): agente 1cd031f2…, sales_manager 2a877afc…,
-- project_manager 48ee0d53… (supervisa 3 proyectos), admin 24257595…; cámbialos si ya no están activos.
-- Antes de la migración (1-oct-2026) los casos 1-5, 7, 8 y 12-14 daban FALLO.
do $$
declare
  r text := '';
  AG  text := '{"sub":"1cd031f2-c7da-455e-975f-c4e8708e36fb","email":"a@x.test","role":"authenticated"}';
  SM  text := '{"sub":"2a877afc-1c38-4171-b12a-68c9c3d9a521","email":"s@x.test","role":"authenticated"}';
  PM  text := '{"sub":"48ee0d53-7c72-425e-a36b-85b9495d99fe","email":"p@x.test","role":"authenticated"}';
  ADM text := '{"sub":"24257595-aee2-4daa-8170-d268f46b9981","email":"p@pabloglobal.es","role":"authenticated"}';
  v_pm_id uuid := '48ee0d53-7c72-425e-a36b-85b9495d99fe';
  v_mio text; v_mio_id uuid; v_ajeno text; v_ajeno_id uuid; v_libre uuid; v_modelo uuid; v_id uuid; v_unidad_mia uuid;
begin
  select p.id, p.nombre into v_mio_id, v_mio from public.proyectos p
   where exists (select 1 from public.usuarios x where x.user_id = v_pm_id and p.id = any (x.proyectos_supervisados)) order by p.nombre limit 1;
  select p.id, p.nombre into v_ajeno_id, v_ajeno from public.proyectos p
   where not exists (select 1 from public.usuarios x where x.user_id = v_pm_id and p.id = any (x.proyectos_supervisados)) order by p.nombre limit 1;
  select u.id into v_libre from public.unidades u where u.contrato_id is null and u.estado = 'disponible' and u.proyecto_id = v_mio_id limit 1;
  select u.id into v_unidad_mia from public.unidades u where u.proyecto_id = v_mio_id limit 1;
  select m.id into v_modelo from public.modelos m limit 1;
  if v_mio is null or v_ajeno is null or v_modelo is null then raise exception 'RES: faltan datos de prueba'; end if;

  -- 1. agente: nada de parcelas, documentos ni obra
  perform set_config('request.jwt.claims', AG, true); set local role authenticated;
  begin perform public.unidad_guarda(null, jsonb_build_object('codigo','ZZ-AG-1','proyecto',v_mio)); r := r || '1 FALLO agente da de alta parcela; ';
  exception when others then r := r || case when sqlstate = '42501' then '1 ok; ' else '1 FALLO otro error (' || sqlerrm || '); ' end; end;
  if v_libre is not null then
    begin perform public.unidad_guarda(v_libre, jsonb_build_object('codigo','ZZ-AG-2','proyecto',v_mio)); r := r || '2 FALLO agente edita parcela; ';
    exception when others then r := r || case when sqlstate = '42501' then '2 ok; ' else '2 FALLO otro error (' || sqlerrm || '); ' end; end;
  end if;
  begin perform public.unidades_importa(jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-AG-3','proyecto',v_mio))); r := r || '3 FALLO agente importa; ';
  exception when others then r := r || case when sqlstate = '42501' then '3 ok; ' else '3 FALLO otro error (' || sqlerrm || '); ' end; end;
  begin perform public.modelo_documentos_guarda(v_modelo, '[]'::jsonb); r := r || '12 FALLO agente guarda documentos de un modelo; ';
  exception when others then r := r || case when sqlstate = '42501' then '12 ok; ' else '12 FALLO otro error (' || sqlerrm || '); ' end; end;
  begin perform public.documento_proyecto_guarda(null, jsonb_build_object('proyecto_id', v_mio_id, 'titulo', 'ZZ', 'url', 'https://example.test/x')); r := r || '13 FALLO agente crea documento de proyecto; ';
  exception when others then r := r || case when sqlstate = '42501' then '13 ok; ' else '13 FALLO otro error (' || sqlerrm || '); ' end; end;
  begin perform public.obra_confirmar_avance(v_mio_id, null, null, 'x', 0, null, null); r := r || '14 FALLO agente confirma avance de obra; ';
  exception when others then r := r || case when sqlstate = '42501' then '14 ok; ' else '14 FALLO otro error (' || sqlerrm || '); ' end; end;
  if v_unidad_mia is not null then
    if public.obra_puede(v_unidad_mia) then r := r || '15 FALLO obra_puede abierto al agente; '; else r := r || '15 ok; '; end if;
  end if;
  if public.documento_proyecto_puede(v_mio_id) then r := r || '16 FALLO documento_proyecto_puede abierto al agente; '; else r := r || '16 ok; '; end if;

  -- 2. sales_manager: tampoco
  reset role; perform set_config('request.jwt.claims', SM, true); set local role authenticated;
  begin perform public.unidad_guarda(null, jsonb_build_object('codigo','ZZ-SM-1','proyecto',v_mio)); r := r || '4 FALLO sales_manager da de alta parcela; ';
  exception when others then r := r || case when sqlstate = '42501' then '4 ok; ' else '4 FALLO otro error (' || sqlerrm || '); ' end; end;
  begin perform public.unidades_importa(jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-SM-2','proyecto',v_mio))); r := r || '5 FALLO sales_manager importa; ';
  exception when others then r := r || case when sqlstate = '42501' then '5 ok; ' else '5 FALLO otro error (' || sqlerrm || '); ' end; end;

  -- 3. project_manager: sí en lo suyo, no en lo ajeno (alta, importación, edición y mover una parcela suya a otro proyecto)
  reset role; perform set_config('request.jwt.claims', PM, true); set local role authenticated;
  begin v_id := public.unidad_guarda(null, jsonb_build_object('codigo','ZZ-PM-1','proyecto',v_mio)); r := r || '6 encargado da de alta en lo suyo ok; ';
  exception when others then r := r || '6 FALLO encargado no puede dar de alta en lo suyo (' || sqlerrm || '); '; end;
  begin perform public.unidad_guarda(null, jsonb_build_object('codigo','ZZ-PM-2','proyecto',v_ajeno)); r := r || '7 FALLO encargado da de alta en proyecto ajeno; ';
  exception when others then r := r || case when sqlstate = '42501' then '7 ok; ' else '7 FALLO otro error (' || sqlerrm || '); ' end; end;
  begin perform public.unidades_importa(jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-PM-3','proyecto',v_ajeno))); r := r || '8 FALLO encargado importa en proyecto ajeno; ';
  exception when others then r := r || case when sqlstate = '42501' then '8 ok; ' else '8 FALLO otro error (' || sqlerrm || '); ' end; end;
  begin perform public.unidades_importa(jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-PM-4','proyecto',v_mio))); r := r || '9 encargado importa en lo suyo ok; ';
  exception when others then r := r || '9 FALLO encargado no puede importar en lo suyo (' || sqlerrm || '); '; end;
  if v_libre is not null then
    begin perform public.unidad_guarda(v_libre, jsonb_build_object('codigo','ZZ-PM-5','proyecto',v_mio)); r := r || '17 encargado edita parcela suya ok; ';
    exception when others then r := r || '17 FALLO encargado no puede editar parcela suya (' || sqlerrm || '); '; end;
    begin perform public.unidad_guarda(v_libre, jsonb_build_object('codigo','ZZ-PM-6','proyecto',v_ajeno)); r := r || '18 FALLO encargado mueve parcela a proyecto ajeno; ';
    exception when others then r := r || case when sqlstate = '42501' then '18 ok; ' else '18 FALLO otro error (' || sqlerrm || '); ' end; end;
  end if;
  begin perform public.modelo_documentos_guarda(v_modelo, '[]'::jsonb); r := r || '19 FALLO encargado guarda documentos de un modelo; ';
  exception when others then r := r || case when sqlstate = '42501' then '19 ok; ' else '19 FALLO otro error (' || sqlerrm || '); ' end; end;
  if public.puede('documentacion') then
    begin perform public.documento_proyecto_guarda(null, jsonb_build_object('proyecto_id', v_mio_id, 'titulo', 'ZZ', 'url', 'https://example.test/x')); r := r || '20 encargado crea documento en lo suyo ok; ';
    exception when others then r := r || '20 FALLO encargado no puede crear documento en lo suyo (' || sqlerrm || '); '; end;
    begin perform public.documento_proyecto_guarda(null, jsonb_build_object('proyecto_id', v_ajeno_id, 'titulo', 'ZZ', 'url', 'https://example.test/x')); r := r || '21 FALLO encargado crea documento en proyecto ajeno; ';
    exception when others then r := r || case when sqlstate = '42501' then '21 ok; ' else '21 FALLO otro error (' || sqlerrm || '); ' end; end;
  else r := r || '20-21 n/a (el encargado de prueba no tiene la casilla Documentación); ';
  end if;

  -- 4. admin: todo
  reset role; perform set_config('request.jwt.claims', ADM, true); set local role authenticated;
  begin perform public.unidad_guarda(null, jsonb_build_object('codigo','ZZ-ADM-1','proyecto',v_ajeno)); r := r || '10 admin da de alta ok; ';
  exception when others then r := r || '10 FALLO admin no puede dar de alta (' || sqlerrm || '); '; end;
  begin perform public.unidades_importa(jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-ADM-2','proyecto',v_ajeno))); r := r || '11 admin importa ok; ';
  exception when others then r := r || '11 FALLO admin no puede importar (' || sqlerrm || '); '; end;
  begin perform public.modelo_documentos_guarda(v_modelo, '[]'::jsonb); r := r || '22 admin guarda documentos de modelo ok; ';
  exception when others then r := r || '22 FALLO admin no puede guardar documentos de modelo (' || sqlerrm || '); '; end;

  reset role;
  raise exception 'RES: %', r;
end $$;
