-- Foto de no-regresion del BLOQUE 6 (datos compartidos que se separan por empresa: diseno de contratos, firmantes/apoderados, deck, creatividades, documentos, obra, ajustes) del encargo de empresas (8-oct-2026).
-- Por cada usuario (JWT con email + set local role authenticated) saca un md5 de LOS IDS que ve en cada tabla y de lo que devuelven las funciones del bloque.
-- Termina en raise (sin rastro). Debe dar el MISMO md5 antes y despues de cada migracion del bloque 6 (los 34 usuarios no cambian).
-- Detalle: poniendo v_detalle = 'email@...' imprime los hashes campo a campo de ese usuario, para localizar la diferencia.
-- destructivo-ok: solo lectura; el raise final lo revierte todo
do $t$
declare
  u record; pr text[]; q text; h text; o text; todo text := ''; n int := 0;
  v_detalle text := '';
  pl uuid; ps uuid; m1 uuid; m2 uuid; mt uuid;
begin
  select id into pl from public.proyectos where empresa = 'lawang' order by nombre limit 1;
  select id into ps from public.proyectos where empresa = 'sandal_woods' order by nombre limit 1;
  select id into m1 from public.modelos where slug = 'tropical';
  select id into m2 from public.modelos where slug = 'dali';
  pr := array[
    'select slug from public.plantillas_contrato',
    'select slug || clave from public.plantilla_cuentas',
    'select concat_ws(''|'',slug,md5(public.contrato_diseno_datos(slug)::text)) from public.plantillas_contrato where slug in (''ppjb_reserva'',''ppjb_parcela'',''ppjb_construccion'')',
    'select md5(public.firmantes_datos()::text)',
    'select md5(public.apoderados_datos()::text)',
    'select md5(public.bloque_legal_datos(''como_se_compra'',''es'')::text)',
    'select id from public.modelos',
    'select id from public.extras',
    'select id from public.modelo_extras',
    'select id from public.modelo_techos',
    'select techo_id::text || proyecto_id::text from public.modelo_techo_proyectos',
    'select id from public.modelos_villa',
    'select id from public.modelo_documentos',
    'select proyecto_id::text from public.deck_config_proyecto',
    'select id from public.deck_faq',
    'select id from public.deck_fotos',
    'select id from public.deck_forecast',
    'select proyecto_id::text from public.deck_forecast_proyecto',
    'select md5(public.creatividades_datos(null, null, null, 200, null)::text)',
    'select md5(public.creatividades_datos(''pieza'', null, null, 200, null)::text)',
    'select md5(public.creatividades_datos(''dossier'', null, null, 200, null)::text)',
    'select id from public.documentos_proyecto',
    'select id from public.obra_fotos',
    'select id from public.obra_partes_trabajo',
    'select id from public.obra_progreso_fase_zona',
    'select clave from public.obra_fases',
    'select clave from public.tipos_vivienda',
    'select clave from public.sociedades',
    format('select md5(public.dossier_datos(%L, array[%L,%L]::uuid[])::text)', pl, m1, m2),
    format('select md5(public.dossier_datos(%L, array[%L]::uuid[])::text)', ps, m2),
    format('select md5(public.modelo_extras_opciones(%L)::text)', m1),
    format('select md5(public.modelo_techos_opciones(%L, %L)::text)', m1, pl),
    format('select md5(public.modelo_techos_opciones(%L, %L)::text)', m2, ps),
    'select md5(public.plantillas_uso()::text)',
    'select concat_ws(''|'',tipo,contratos,firmados) from public.plantillas_uso()',
    'select md5(public.ajustes_config_datos()::text)',
    'select md5(public.ajustes_log_datos(50)::text)',
    'select md5(public.mantenimiento_datos()::text)',
    'select md5(public.sociedades_ajustes_datos()::text)',
    'select md5(public.intranet_estado()::text)',
    'select md5(public.instancia_marca()::text)',
    format('select md5(public.ficha_publica_lee(%L)::text)', pl),
    format('select md5(public.ficha_publica_lee(%L)::text)', ps),
    format('select public.es_manager_de(%L)::text', pl),
    format('select public.es_manager_de(%L)::text', ps),
    format('select public.documento_proyecto_puede(%L)::text', pl),
    format('select public.documento_proyecto_puede(%L)::text', ps),
    'select public.creatividad_puede_hacer(''pieza'')::text || public.creatividad_puede_hacer(''dossier'')::text',
    format('select public.agente_ve_proyecto_obra(%L)::text', pl),
    format('select public.agente_ve_proyecto_obra(%L)::text', ps)
  ];
  for u in select user_id, email from public.usuarios order by email loop
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    o := '';
    foreach q in array pr loop
      begin
        execute 'select md5(coalesce(string_agg(x::text, '','' order by x::text),'''')) from (' || q || ') t(x)' into h;
        o := o || left(h, 5) || ' ';
      exception when others then o := o || 'E' || sqlstate || ' ';
      end;
    end loop;
    reset role;
    if v_detalle = '' then todo := todo || left(md5(o), 8) || ' ' || u.email || E'\n';
    elsif u.email = v_detalle then todo := o; end if;
    n := n + 1;
  end loop;
  raise exception E'FOTOB6 usuarios=%\nMD5=%\n%', n, md5(todo), todo;
end $t$;
