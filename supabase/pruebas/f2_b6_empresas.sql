-- Prueba del BLOQUE 6 (Fase 2 empresas, 8-oct-2026): datos compartidos que se separan por empresa (diseno de contratos, firmantes/apoderados), deck, creatividades, documentos, obra, ajustes.
-- Secciones INDEPENDIENTES (cada una es una peticion: setup + casos + raise final que revierte todo). Se pegan DESPUES de las migraciones (o detras de ellas para ensayarlas sin rastro).
-- No crea usuarios: convierte fichas existentes dentro de la transaccion:
--   ya = admin_empresa/lawang · cr = super_admin_empresa/sandal_woods · ad4 = admin_empresa con las dos · p4 = super_admin_empresa/lawang · ctl = agente SIN empresas (control: como hoy) · adm = admin global
-- Cada linea OK/FALLO, termina en «FALLOS=n». El esperado se pasa como texto: el resultado escalar o el sqlstate del error.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop de datos
--
-- ===== SETUP COMUN (copiado al principio de cada seccion) =====
-- create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text ... (ver seccion 1)
--
-- ===== SECCION 1: DISENO POR EMPRESA, FIRMANTES Y APODERADOS =====
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  return case when got = p_esp then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; p4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_p4 text; e_ctl text; e_adm text;
  r text := ''; fallos int; x text; hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios}';
  d_res jsonb; d_par jsonb; d_con jsonb; h_res text; h_par text; h_con text; v_sw_res text;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into p4, e_p4 from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4,p4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ad4;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=p4;

  -- la copia: tres disenos por empresa, identicos a los de la tabla comun
  r := r || case when (select count(*) from public.contratos_diseno_empresa where empresa='lawang')=3 and (select count(*) from public.contratos_diseno_empresa where empresa='sandal_woods')=3 then 'OK   ' else 'FALLO' end || ' copia: 3 disenos por empresa' || E'\n';
  r := r || case when not exists (select 1 from public.contratos_diseno_empresa c join public.contratos_diseno d using (slug) where c.design is distinct from d.design) then 'OK   ' else 'FALLO' end || ' copia: mismo contenido que la tabla comun' || E'\n';
  select md5(design::text) into h_res from public.contratos_diseno where slug='ppjb_reserva';
  select md5(design::text) into h_par from public.contratos_diseno where slug='ppjb_parcela';

  -- lectura por la RPC (la tabla nueva no se lee directa)
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.contratos_diseno_empresa', '42501', 'ya no lee la tabla de disenos directa (sin permiso)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select md5((public.contrato_diseno_empresa_datos(''ppjb_reserva'',''lawang'')->''design'')::text)', h_res, 'ya (Lawang) lee el diseno de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select (public.contrato_diseno_empresa_datos(''ppjb_reserva'',''sandal_woods'')->''design'')::text', 'null', 'ya NO lee el diseno de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select md5((public.contrato_diseno_empresa_datos(''ppjb_reserva'',''sandal_woods'')->''design'')::text)', h_res, 'cr (Sandal Woods) lee el suyo') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select (public.contrato_diseno_empresa_datos(''ppjb_reserva'',''lawang'')->''design'')::text', 'null', 'cr NO lee el de Lawang') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select md5((public.contrato_diseno_empresa_datos(''ppjb_reserva'',''sandal_woods'')->''design'')::text)', h_res, 'ad4 (las dos) lee el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select md5((public.contrato_diseno_empresa_datos(''ppjb_parcela'',''sandal_woods'')->''design'')::text)', h_par, 'admin global lee el de cualquier empresa') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select md5((public.contrato_diseno_empresa_datos(''ppjb_parcela'',''lawang'')->''design'')::text)', h_par, 'agente de control (sin empresas) lo lee como hoy') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select md5((public.contrato_diseno_datos(''ppjb_parcela'')->''design'')::text)', h_par, 'la lectura vieja sigue igual') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select public.contrato_diseno_empresa_datos(null,''lawang'')::text', '22023', 'sin slug: 22023') || E'\n';

  -- escritura por la RPC
  select design into d_par from public.contratos_diseno where slug='ppjb_parcela';
  select design into d_con from public.contratos_diseno where slug='ppjb_construccion';
  select md5(design::text) into h_con from public.contratos_diseno where slug='ppjb_construccion';
  r := r || pg_temp.t(ya, e_ya, format('select public.contratos_diseno_empresa_guarda(''lawang'',''ppjb_reserva'',%L::jsonb)', d_con::text), 'ppjb_reserva', 'ya guarda el diseno de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.contratos_diseno_empresa_guarda(''sandal_woods'',''ppjb_reserva'',%L::jsonb)', d_par::text), '42501', 'ya NO guarda el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.contratos_diseno_empresa_guarda(''lawang'',''ppjb_reserva'',%L::jsonb)', d_par::text), '42501', 'cr NO guarda el de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.contratos_diseno_empresa_guarda(''lawang'',''ppjb_reserva'',%L::jsonb)', d_par::text), '42501', 'agente de control rechazado') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.contratos_diseno_empresa_guarda(''inventada'',''ppjb_reserva'',%L::jsonb)', d_par::text), '22023', 'empresa inventada: 22023') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select public.contratos_diseno_empresa_guarda(''lawang'',''ppjb_reserva'',''{"docLogo": 5}''::jsonb)', '22023', 'diseno con forma rara: lo rechaza el validador') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select public.contratos_diseno_empresa_guarda(''sandal_woods'',''ppjb_construccion'',%L::jsonb)', d_par::text), 'ppjb_construccion', 'admin global guarda el de cualquiera') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select public.contratos_diseno_empresa_guarda(''sandal_woods'',''ppjb_parcela'',%L::jsonb)', d_par::text), 'ppjb_parcela', 'ad4 (las dos) guarda el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.contratos_diseno_guarda(''ppjb_reserva'', ''{}''::jsonb)', '42501', 'la escritura vieja (compartida) sigue cerrada a un rol de empresa') || E'\n';

  -- lo escrito por ya quedo en SU copia y no toco ni la comun ni la de la otra empresa
  select md5(design::text) into x from public.contratos_diseno_empresa where empresa='lawang' and slug='ppjb_reserva';
  r := r || case when x = h_con then 'OK   ' else 'FALLO' end || ' la copia de Lawang cambio' || E'\n';
  select md5(design::text) into x from public.contratos_diseno_empresa where empresa='sandal_woods' and slug='ppjb_reserva';
  r := r || case when x = h_res then 'OK   ' else 'FALLO' end || ' la copia de Sandal Woods NO cambio' || E'\n';
  select md5(design::text) into x from public.contratos_diseno where slug='ppjb_reserva';
  r := r || case when x = h_res then 'OK   ' else 'FALLO' end || ' la tabla comun NO cambio (los contratos ya emitidos no se tocan)' || E'\n';

  -- sincronia: un cambio en la tabla comun llega a las copias que nadie personalizo
  update public.contratos_diseno set design = d_par, updated_at = now() where slug = 'ppjb_reserva';
  select md5(design::text) into x from public.contratos_diseno_empresa where empresa='sandal_woods' and slug='ppjb_reserva';
  r := r || case when x = h_par then 'OK   ' else 'FALLO' end || ' sincronia: la copia que nadie personalizo sigue a la comun' || E'\n';
  select md5(design::text) into x from public.contratos_diseno_empresa where empresa='lawang' and slug='ppjb_reserva';
  r := r || case when x = h_con then 'OK   ' else 'FALLO' end || ' sincronia: la copia que Lawang personalizo NO sigue a la comun' || E'
';

  -- firmantes y apoderados
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '2', 'ya ve los 2 firmantes de Lawang') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select (public.firmantes_datos()->''firmantes''->0->>''nombre'')', 'Pablo Cantero Gambín', 'cr ve solo a Pablo (Sandal Woods)') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '1', 'cr ve 1 firmante') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '3', 'ad4 (las dos) ve los 3') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '3', 'control ve los 3 como hoy') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '3', 'admin global ve los 3') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from jsonb_array_elements(public.apoderados_datos()->''apoderados'')', '2', 'ya ve los 2 apoderados de Lawang') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from jsonb_array_elements(public.apoderados_datos()->''apoderados'')', '0', 'cr NO ve los apoderados (NIK) de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from jsonb_array_elements(public.apoderados_datos()->''apoderados'')', '2', 'control ve los 2 como hoy') || E'\n';
  -- una fila nueva sin empresa nace cerrada para quien tiene alcance por empresa
  insert into public.firmantes_cred (nombre, cred_es, cred_en, cred_id) values ('Prueba Sin Empresa', 'x', 'x', 'x');
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '2', 'firmante sin empresa: ya NO lo ve (nace cerrado)') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from jsonb_array_elements(public.firmantes_datos()->''firmantes'')', '4', 'firmante sin empresa: control SI lo ve') || E'\n';

  -- exposicion: nada a anon
  r := r || pg_temp.t(ya, e_ya, 'select 1::text', '1', 'sanidad') || E'\n';
  r := r || pg_temp.t(null, null, 'select public.contratos_diseno_empresa_guarda(''lawang'',''ppjb_reserva'',''{}''::jsonb)', '42501', 'anon no ejecuta la escritura', 'anon') || E'\n';
  r := r || pg_temp.t(null, null, 'select public.contrato_diseno_empresa_datos(''ppjb_reserva'',''lawang'')::text', '42501', 'anon no ejecuta la lectura', 'anon') || E'\n';

  select count(*) into fallos from regexp_matches(r, 'FALLO', 'g');
  raise exception E'SECCION 1\n%\nFALLOS=%', r, fallos;
end $t$;

-- ===== SECCION 2: DECK, FICHAS PUBLICAS, MODELOS POR PROYECTO =====
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
-- las funciones que solo ejecuta la edge (service_role) y se ponen en la piel del usuario con _actua_como(p_uid)
create function pg_temp.sv(p_sql text, p_esp text, p_et text) returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  set local role service_role;
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; p4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_p4 text; e_ctl text; e_adm text;
  r text := ''; fallos int; hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios}';
  pl uuid; ps uuid; pk uuid; fql uuid; fqs uuid; fqk uuid; fol uuid; fos uuid; fom uuid;
  vl record; vs record; sl text; ss text; vl_ver timestamptz; vs_ver timestamptz; ml uuid[];
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into p4, e_p4 from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4,p4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ad4;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=p4;

  -- fixtures reales (medidos como postgres)
  select p.id into pl from public.proyectos p where p.empresa='lawang' and exists (select 1 from public.deck_faq f where f.proyecto_id=p.id) and exists (select 1 from public.deck_fotos f where f.proyecto_id=p.id and f.ambito='proyecto') and exists (select 1 from public.modelos_villa v where v.proyecto_id=p.id) order by p.nombre limit 1;
  select p.id into ps from public.proyectos p where p.empresa='sandal_woods' and exists (select 1 from public.deck_faq f where f.proyecto_id=p.id) and exists (select 1 from public.deck_fotos f where f.proyecto_id=p.id and f.ambito='proyecto') and exists (select 1 from public.modelos_villa v where v.proyecto_id=p.id) order by p.nombre limit 1;
  select p.id into pk from public.proyectos p where p.empresa is null and exists (select 1 from public.deck_faq f where f.proyecto_id=p.id) order by p.nombre limit 1;
  select id into fql from public.deck_faq where proyecto_id=pl order by id limit 1;
  select id into fqs from public.deck_faq where proyecto_id=ps order by id limit 1;
  select id into fqk from public.deck_faq where proyecto_id=pk order by id limit 1;
  select id into fol from public.deck_fotos where proyecto_id=pl and ambito='proyecto' order by id limit 1;
  select id into fos from public.deck_fotos where proyecto_id=ps and ambito='proyecto' order by id limit 1;
  select id into fom from public.deck_fotos where ambito='modelo' order by id limit 1;
  select * into vl from public.modelos_villa where proyecto_id=pl and modelo_id is not null order by id limit 1;
  select * into vs from public.modelos_villa where proyecto_id=ps and modelo_id is not null order by id limit 1;
  select f.slug, f.actualizado_en into sl, vl_ver from public.fichas_publicas f join public.proyectos p on p.id=f.proyecto_id where p.empresa='lawang' order by f.slug limit 1;
  select f.slug, f.actualizado_en into ss, vs_ver from public.fichas_publicas f join public.proyectos p on p.id=f.proyecto_id where p.empresa='sandal_woods' order by f.slug limit 1;
  select array_agg(modelo_id) into ml from public.modelos_villa where proyecto_id=pl and modelo_id is not null;
  r := r || 'fixtures: pl=' || coalesce(pl::text,'-') || ' ps=' || coalesce(ps::text,'-') || ' pk=' || coalesce(pk::text,'-') || ' fql=' || (fql is not null)::text || ' fqs=' || (fqs is not null)::text || ' fol=' || (fol is not null)::text || ' fos=' || (fos is not null)::text || ' fom=' || (fom is not null)::text || ' vl=' || (vl.id is not null)::text || ' vs=' || (vs.id is not null)::text || ' sl=' || coalesce(sl,'-') || ' ss=' || coalesce(ss,'-') || E'\n';

  -- DECK: configuracion
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', pl), pl::text, 'ya cambia la config del deck de un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', ps), '42501', 'ya NO cambia la del deck de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', ps), ps::text, 'cr cambia la del deck de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', pk), '42501', 'cr NO toca el deck de un proyecto sin empresa') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', ps), ps::text, 'ad4 (las dos) cambia el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', pk), pk::text, 'admin global cambia el de un proyecto sin empresa') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.deck_config_guarda(%L, ''{"titulo":{"en":"Prueba"},"meta_desc":{"en":"Prueba meta"}}''::jsonb)::text', pl), '42501', 'agente de control rechazado') || E'\n';
  -- DECK: preguntas
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_faq_guarda(%L, %L, ''{"orden": 77}''::jsonb)::text', fql, pl), fql::text, 'ya edita una FAQ de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_faq_guarda(%L, %L, ''{"orden": 77}''::jsonb)::text', fqs, ps), '42501', 'ya NO edita una FAQ de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_faq_guarda(%L, %L, ''{"orden": 77}''::jsonb)::text', fqs, pl), '42501', 'ya NO edita la FAQ de otra empresa diciendo que es de su proyecto (la empresa sale de la fila)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_faq_guarda(null, %L, ''{"pregunta":{"es":"p","en":"p"},"respuesta":{"es":"r","en":"r"}}''::jsonb) is not null', pl), 'true', 'ya crea una FAQ en un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_faq_guarda(null, %L, ''{"pregunta":{"es":"p","en":"p"},"respuesta":{"es":"r","en":"r"}}''::jsonb) is not null', ps), '42501', 'ya NO crea una FAQ en Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_faq_borra(%L)::text', fql), '42501', 'cr NO borra una FAQ de Lawang') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_faq_borra(%L)::text', fqs), fqs::text, 'cr borra una FAQ de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_faq_borra(%L)::text', fqk), '42501', 'cr NO borra una FAQ de un proyecto sin empresa') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select public.deck_faq_borra(%L)::text', fqk), fqk::text, 'admin global borra la de un proyecto sin empresa') || E'\n';
  -- DECK: fotos
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_foto_cambia(%L, ''{"pie":{"en":"x"}}''::jsonb)::text', fol), fol::text, 'ya cambia una foto de proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_foto_cambia(%L, ''{"pie":{"en":"x"}}''::jsonb)::text', fos), '42501', 'ya NO cambia una foto de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_foto_cambia(%L, ''{"pie":{"en":"x"}}''::jsonb)::text', fom), '42501', 'ya NO cambia una foto de MODELO (catalogo compartido)') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select public.deck_foto_cambia(%L, ''{"pie":{"en":"x"}}''::jsonb)::text', fom), fom::text, 'admin global cambia la foto de modelo') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_foto_mueve(%L, 1)::text', fol), '!42501', 'ya mueve una foto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_foto_mueve(%L, 1)::text', fos), '42501', 'ya NO mueve una de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_foto_mueve(%L, 1)::text', fos), '!42501', 'cr mueve una de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_foto_fijar_vista(%L, null)::text', fom), '42501', 'ya NO fija la vista de una foto de modelo') || E'\n';
  -- DECK: prevision, modelos del proyecto
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_prevision_guarda(%L, %L, null, null)::text', pl, vl.modelo_id), '!42501', 'ya llega a la prevision de un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.deck_prevision_guarda(%L, %L, null, null)::text', ps, vs.modelo_id), '42501', 'ya NO a la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.deck_prevision_guarda(%L, %L, null, null)::text', ps, vs.modelo_id), '!42501', 'cr llega a la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.modelos_proyecto_fija(%L, %L::uuid[])::text', pl, ml), '!42501', 'ya fija los modelos de un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.modelos_proyecto_fija(%L, %L::uuid[])::text', ps, ml), '42501', 'ya NO fija los de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.modelos_proyecto_fija(%L, %L::uuid[])::text', pl, ml), '42501', 'agente de control rechazado') || E'\n';
  -- las que ejecuta la edge (service_role, en la piel del usuario)
  r := r || pg_temp.sv(format('select public.deck_transicion_empieza(%L, %L, true)::text', ya, pl), '!42501', 'edge: ya abre el deck de Lawang') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_transicion_empieza(%L, %L, true)::text', ya, ps), '42501', 'edge: ya NO el de Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.investor_deck_activa_como(%L, %L, true)::text', ya, ps), '42501', 'edge: ya NO activa el investor deck de Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.investor_deck_activa_como(%L, %L, true)::text', ya, pl), '!42501', 'edge: ya llega a activar el de Lawang') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_borra(%L, %L, true)::text', ya, fol), '!42501', 'edge: ya comprueba el borrado de una foto de Lawang') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_borra(%L, %L, true)::text', ya, fos), '42501', 'edge: ya NO borra una de Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_borra(%L, %L, true)::text', ya, fom), '42501', 'edge: ya NO borra una de modelo') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_registra(%L, ''proyecto'', %L, ''x'', ''x'')::text', ya, pl), '!42501', 'edge: ya registra en Lawang (la ruta mala da 22023)') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_registra(%L, ''proyecto'', %L, ''x'', ''x'')::text', ya, ps), '42501', 'edge: ya NO registra en Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_registra(%L, ''modelo'', %L, ''x'', ''x'')::text', ya, vl.modelo_id), '42501', 'edge: ya NO registra una foto de modelo') || E'\n';
  r := r || pg_temp.sv(format('select public.deck_foto_registra(%L, ''modelo'', %L, ''x'', ''x'')::text', adm, vl.modelo_id), '!42501', 'edge: admin global SI registra una foto de modelo') || E'\n';
  -- FICHA PUBLICA
  r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_lee(%L)::text', pl), '!42501', 'ya lee las fichas de un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_lee(%L)::text', ps), '42501', 'ya NO lee las de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_lee(%L)::text', pk), '42501', 'ya NO lee las de un proyecto sin empresa') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select public.ficha_publica_lee(%L)::text', pk), '!42501', 'admin global lee las de un proyecto sin empresa') || E'\n';
  if sl is not null then
    r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_guarda(%L, ''{"orden": 5}''::jsonb, %L)::text', sl, vl_ver), '!42501', 'ya edita una ficha de Lawang') || E'\n';
    r := r || pg_temp.t(cr, e_cr, format('select public.ficha_publica_guarda(%L, ''{"orden": 5}''::jsonb, %L)::text', sl, vl_ver), '42501', 'cr NO edita una ficha de Lawang') || E'\n';
    r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_guarda(%L, jsonb_build_object(''proyecto_id'', %L::text), %L)::text', sl, ps, vl_ver), '42501', 'ya NO lleva su ficha a un proyecto de Sandal Woods') || E'\n';
    r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_guarda(%L, ''{"proyecto_id": null}''::jsonb, %L)::text', sl, vl_ver), '42501', 'ya NO deja su ficha sin proyecto') || E'\n';
  end if;
  if ss is not null then
    r := r || pg_temp.t(ya, e_ya, format('select public.ficha_publica_guarda(%L, ''{"orden": 5}''::jsonb, %L)::text', ss, vs_ver), '42501', 'ya NO edita una ficha de Sandal Woods') || E'\n';
    r := r || pg_temp.t(cr, e_cr, format('select public.ficha_publica_guarda(%L, ''{"orden": 5}''::jsonb, %L)::text', ss, vs_ver), '!42501', 'cr edita una ficha de Sandal Woods') || E'\n';
    r := r || pg_temp.t(ad4, e_ad4, format('select public.ficha_publica_guarda(%L, ''{"orden": 5}''::jsonb, %L)::text', ss, vs_ver), '!42501', 'ad4 (las dos) edita una de Sandal Woods') || E'\n';
  end if;
  r := r || pg_temp.t(ya, e_ya, 'select public.ficha_publica_guarda(''ficha-nueva-prueba'', ''{"linea":"villa","region_key":"bali"}''::jsonb, null)::text', '42501', 'ya NO crea una ficha nueva (sin proyecto = global)') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select public.ficha_publica_guarda(''ficha-nueva-prueba'', ''{"linea":"villa","region_key":"bali"}''::jsonb, null)::text', '!42501', 'admin global SI crea una ficha nueva') || E'\n';
  -- PRECIOS POR PROYECTO (el precio base sigue siendo de un global)
  r := r || pg_temp.t(ya, e_ya, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vl.modelo_id, vl.id, vl.precio_construccion), 'true', 'ya cambia el precio de un modelo EN un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vs.modelo_id, vs.id, vs.precio_construccion), '42501', 'ya NO cambia el precio en un proyecto de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vs.modelo_id, vs.id, vs.precio_construccion), 'true', 'cr cambia el precio en un proyecto de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vl.modelo_id, vl.id, vl.precio_construccion), '42501', 'cr NO en un proyecto de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''base'', 1))->>''ok'')', vl.modelo_id), '42501', 'ya NO cambia el precio BASE del modelo (catalogo compartido)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''moneda'', ''USD'', ''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vl.modelo_id, vl.id, vl.precio_construccion), '42501', 'ya NO mezcla moneda con un precio por proyecto') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric)), ''altas'', jsonb_build_array(jsonb_build_object(''proyecto_id'', %L::text, ''precio'', null))))->>''ok'')', vl.modelo_id, vl.id, vl.precio_construccion, ps), '42501', 'ya NO se cuela con un alta en un proyecto de Sandal Woods junto a uno suyo') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', ''no-es-uuid''))))->>''ok'')', vl.modelo_id), '42501', 'ya con un id roto: 42501 y no un error raro') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vl.modelo_id, vl.id, vl.precio_construccion), '42501', 'agente de control rechazado') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select (public.modelo_precios_guarda(%L, jsonb_build_object(''villas'', jsonb_build_array(jsonb_build_object(''id'', %L::text, ''precio'', %L::numeric))))->>''ok'')', vs.modelo_id, vs.id, vs.precio_construccion), 'true', 'admin global cambia el de cualquiera') || E'\n';
  -- el catalogo compartido sigue cerrado a un rol de empresa
  r := r || pg_temp.t(ya, e_ya, format('select public.modelo_guarda(%L, ''{}''::jsonb)::text', vl.modelo_id), '42501', 'ya NO edita el modelo (catalogo compartido)') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.extras_catalogo_guarda(''[]''::jsonb, false)::text', '42501', 'cr NO edita el catalogo de extras') || E'\n';
  -- anon
  r := r || pg_temp.t(null, null, format('select public.deck_config_guarda(%L, ''{}''::jsonb)::text', pl), '42501', 'anon no ejecuta deck_config_guarda', 'anon') || E'\n';
  select count(*) into fallos from regexp_matches(r, 'FALLO', 'g');
  raise exception E'SECCION 2\n%\nFALLOS=%', r, fallos;
end $t$;

-- ===== SECCION 3: CREATIVIDADES, DOSSIER Y LECTURAS DEL DECK =====
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
create function pg_temp.sv(p_sql text, p_esp text, p_et text) returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  set local role service_role;
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; p4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_p4 text; e_ctl text; e_adm text;
  r text := ''; fallos int;
  hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios,creatividades,dossier}';
  pl uuid; ps uuid; cl uuid; cs uuid; cn uuid; ml uuid[]; n_l int; n_s int; n_k int; n_m int;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into p4, e_p4 from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4,p4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  -- ya = admin de Lawang CON casillas · cr = super de Sandal Woods SIN ninguna casilla · ctl = agente sin empresas con las casillas de creatividades/dossier
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ad4;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=p4;
  update public.usuarios set herramientas=hs::text[] where user_id=ctl;

  select p.id into pl from public.proyectos p where p.empresa='lawang' and exists (select 1 from public.modelos_villa v where v.proyecto_id=p.id) order by p.nombre limit 1;
  select p.id into ps from public.proyectos p where p.empresa='sandal_woods' and exists (select 1 from public.modelos_villa v where v.proyecto_id=p.id) order by p.nombre limit 1;
  select array_agg(modelo_id) into ml from public.modelos_villa where proyecto_id=pl and modelo_id is not null;
  -- creatividades de prueba (dentro de la transaccion): una de cada empresa y una general sin proyecto
  cl := gen_random_uuid(); cs := gen_random_uuid(); cn := gen_random_uuid();
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cl, 'pieza', 'Prueba Lawang', pl, cl::text || '/estado-1.json');
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cs, 'pieza', 'Prueba Sandal', ps, cs::text || '/estado-1.json');
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cn, 'pieza', 'Prueba General', null, cn::text || '/estado-1.json');

  -- quien puede hacer
  r := r || pg_temp.t(ctl, e_ctl, 'select public.creatividad_puede_hacer(''pieza'')::text', 'true', 'control: tiene la casilla') || E'
';
  r := r || pg_temp.t(ya, e_ya, 'select public.creatividad_puede_hacer(''pieza'')::text', 'true', 'ya (admin con casilla) puede hacer creatividades') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.creatividad_puede_hacer(''pieza'')::text', 'true', 'cr (super de empresa SIN casilla) puede hacer creatividades') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.creatividad_puede_hacer(''dossier'')::text', 'true', 'cr puede hacer dossiers sin casilla') || E'\n';
  -- un admin de empresa SIN casilla no puede (como un admin global sin casilla)
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set herramientas='{}' where user_id=p4;
  r := r || pg_temp.t(p4, e_p4, 'select public.creatividad_puede_hacer(''pieza'')::text', 'true', 'p4 es SUPER de Lawang: no necesita casilla') || E'\n';
  -- visibilidad
  r := r || pg_temp.t(ya, e_ya, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cl), 'true', 'ya ve la creatividad de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cs), 'false', 'ya NO ve la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cn), 'false', 'ya NO ve la general sin proyecto (nace cerrada)') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cs), 'true', 'cr ve la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cl), 'false', 'cr NO ve la de Lawang') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cs), 'true', 'ad4 (las dos) ve la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cs), 'true', 'agente de control ve la de Sandal Woods como hoy') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cn), 'true', 'agente de control ve la general como hoy') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select (public.creatividades_datos(null,null,null,200,null)::text like ''%%%s%%'')::text', cn), 'true', 'admin global ve la general') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.creatividad_datos(%L)::text like ''%%Prueba Sandal%%'')::text', cs), 'false', 'ya NO abre la de Sandal Woods por id') || E'\n';
  -- cambiar de estado (la empresa sale de la fila, no de lo que mande la pantalla)
  r := r || pg_temp.t(ya, e_ya, format('select public.creatividad_estado(%L, ''pendiente'')::text', cl), '!42501', 'ya manda a revision una de Lawang (llega a la validacion de fichero: 23514)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.creatividad_estado(%L, ''aprobada'')::text', cl), '!42501', 'ya (admin de Lawang) aprueba una de Lawang: pasa la puerta de admin') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.creatividad_estado(%L, ''pendiente'')::text', cs), 'P0002', 'ya NO toca la de Sandal Woods (no existe para el)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.creatividad_estado(%L, ''pendiente'')::text', cn), 'P0002', 'ya NO toca la general') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.creatividad_estado(%L, ''aprobada'')::text', cs), '!42501', 'cr (super de Sandal Woods, sin casilla) aprueba una de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.creatividad_estado(%L, ''aprobada'')::text', cl), 'P0002', 'cr NO toca la de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.creatividad_estado(%L, ''aprobada'')::text', cl), '42501', 'agente de control: aprobar sigue siendo de un admin') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.creatividad_estado(%L, ''pendiente'')::text', cs), '!42501', 'agente de control con casilla manda a revision cualquiera, como hoy') || E'\n';
  -- guardar y descargar
  r := r || pg_temp.sv(format('select public.creatividad_guarda(%L, gen_random_uuid(), ''pieza'', jsonb_build_object(''titulo'',''x'',''proyecto_id'',%L::text), null, null, null, null, null)::text', ya, ps), '42501', 'edge: ya NO crea una creatividad en un proyecto de Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.creatividad_guarda(%L, gen_random_uuid(), ''pieza'', jsonb_build_object(''titulo'',''x''), null, null, null, null, null)::text', ya), '42501', 'edge: ya NO crea una sin proyecto') || E'\n';
  r := r || pg_temp.sv(format('select public.creatividad_guarda(%L, gen_random_uuid(), ''pieza'', jsonb_build_object(''titulo'',''x'',''proyecto_id'',%L::text), null, null, null, null, null)::text', ya, pl), '!42501', 'edge: ya crea una en un proyecto de Lawang') || E'\n';
  r := r || pg_temp.sv(format('select public.creatividad_guarda(%L, %L, ''pieza'', jsonb_build_object(''titulo'',''x''), null, null, null, null, null)::text', ya, cs), '42501', 'edge: ya NO edita la de Sandal Woods por id') || E'\n';
  r := r || pg_temp.sv(format('select public.creatividad_guarda(%L, gen_random_uuid(), ''pieza'', jsonb_build_object(''titulo'',''x''), null, null, null, null, null)::text', ctl), '!42501', 'edge: el agente de control crea sin proyecto, como hoy') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.creatividad_descarga(%L, ''x'')::text', cs), '42501', 'ya NO descarga la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.creatividad_descarga(%L, ''x'')::text', cl), '!42501', 'ya llega a descargar la de Lawang (fichero inexistente: 22023)') || E'\n';
  -- dossier
  r := r || pg_temp.t(ya, e_ya, format('select public.dossier_datos(%L, %L::uuid[])::text', pl, ml), '!42501', 'ya monta un dossier de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.dossier_datos(%L, %L::uuid[])::text', ps, ml), '42501', 'ya NO de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.dossier_datos(%L, %L::uuid[])::text', ps, ml), '!42501', 'cr (super sin casilla) monta uno de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.dossier_datos(%L, %L::uuid[])::text', pl, ml), '42501', 'cr NO de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.dossier_datos(%L, %L::uuid[])::text', ps, ml), '42501', 'agente de control: un proyecto que no es suyo sigue sin ser suyo (proyecto_visible)') || E'\n';
  -- exposicion
  r := r || pg_temp.t(ya, e_ya, 'select public._puede_herr_o_super_empresa(''dossier'')::text', '42501', 'el ayudante sigue sin EXECUTE para authenticated') || E'\n';
  r := r || pg_temp.t(null, null, 'select public._puede_herr_o_super_empresa(''dossier'')::text', '42501', 'ni para anon', 'anon') || E'\n';
  -- LECTURAS DEL DECK
  select count(*) into n_l from public.deck_faq f join public.proyectos p on p.id=f.proyecto_id where p.empresa='lawang';
  select count(*) into n_s from public.deck_faq f join public.proyectos p on p.id=f.proyecto_id where p.empresa='sandal_woods';
  select count(*) into n_k from public.deck_faq f join public.proyectos p on p.id=f.proyecto_id where p.empresa is null;
  select count(*) into n_m from public.deck_fotos where ambito='modelo';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.deck_faq', n_l::text, 'ya lee solo las preguntas del deck de Lawang') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from public.deck_faq', n_s::text, 'cr lee solo las de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select count(*)::text from public.deck_faq', (n_l + n_s)::text, 'ad4 lee las de las dos (no las del proyecto sin empresa)') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.deck_faq', (n_l + n_s + n_k)::text, 'agente de control lee todas como hoy') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.deck_fotos where ambito = ''modelo''', n_m::text, 'ya lee las fotos de MODELO (catalogo compartido)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.deck_fotos f join public.proyectos p on p.id=f.proyecto_id where p.empresa is distinct from ''lawang''', '0', 'ya no lee fotos de proyecto de otra empresa') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.deck_config_proyecto c join public.proyectos p on p.id=c.proyecto_id where p.empresa is distinct from ''lawang''', '0', 'ya no lee la config del deck de otra empresa') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from public.deck_forecast', '0', 'cr no lee las previsiones de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select (count(*) > 0)::text from public.deck_forecast', 'true', 'agente de control lee las previsiones como hoy') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.modelo_techo_proyectos t join public.proyectos p on p.id=t.proyecto_id where p.empresa is distinct from ''lawang''', '0', 'ya no lee a que proyectos de otra empresa se aplica un techo') || E'\n';
  select count(*) into fallos from regexp_matches(r, 'FALLO', 'g');
  raise exception E'SECCION 3\n%\nFALLOS=%', r, fallos;
end $t$;

-- ===== SECCION 4: DOCUMENTOS DE PROYECTO, OBRA, USO DE PLANTILLAS Y AJUSTES DE LA INSTANCIA =====
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
create function pg_temp.sv(p_sql text, p_esp text, p_et text) returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  set local role service_role;
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; p4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_p4 text; e_ctl text; e_adm text;
  r text := ''; fallos int;
  hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios,documentacion,obra}';
  pl uuid; ps uuid; dl uuid; ds uuid; ul uuid; us uuid; n_sw bigint; n_la bigint; n_tot bigint;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into p4, e_p4 from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4,p4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  -- ya = admin de Lawang CON casillas · cr = super de Sandal Woods SIN casillas · ad4 = admin de las dos SIN casillas · p4 = super de Lawang sin casillas · ctl = agente de control con casillas
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=ad4;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=p4;
  update public.usuarios set herramientas=hs::text[] where user_id=ctl;

  select p.id into pl from public.proyectos p where p.empresa='lawang' and exists (select 1 from public.documentos_proyecto d where d.proyecto_id=p.id) and exists (select 1 from public.unidades u where u.proyecto_id=p.id) order by p.nombre limit 1;
  select p.id into ps from public.proyectos p where p.empresa='sandal_woods' and exists (select 1 from public.documentos_proyecto d where d.proyecto_id=p.id) and exists (select 1 from public.unidades u where u.proyecto_id=p.id) order by p.nombre limit 1;
  select id into dl from public.documentos_proyecto where proyecto_id=pl and not general order by id limit 1;
  select id into ds from public.documentos_proyecto where proyecto_id=ps and not general order by id limit 1;
  select id into ul from public.unidades where proyecto_id=pl order by id limit 1;
  select id into us from public.unidades where proyecto_id=ps order by id limit 1;

  -- DOCUMENTOS: quien puede (casilla + empresa)
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_puede(%L)::text', pl), 'true', 'ya (admin con casilla) puede en Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_puede(%L)::text', ps), 'false', 'ya NO en Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.documento_proyecto_puede(%L)::text', ps), 'true', 'cr (super de empresa SIN casilla) puede en Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.documento_proyecto_puede(%L)::text', pl), 'false', 'cr NO en Lawang') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select public.documento_proyecto_puede(%L)::text', pl), 'false', 'ad4 (admin SIN casilla) NO: un admin necesita la casilla') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.documento_proyecto_puede(%L)::text', pl), 'false', 'agente de control: sigue sin ser encargado de ese proyecto') || E'\n';
  -- DOCUMENTOS: editar
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_guarda(%L, ''{"titulo":"Prueba"}''::jsonb)::text', dl), dl::text, 'ya edita un documento de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_guarda(%L, ''{"titulo":"Prueba"}''::jsonb)::text', ds), '42501', 'ya NO edita uno de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.documento_proyecto_guarda(%L, ''{"titulo":"Prueba"}''::jsonb)::text', ds), ds::text, 'cr (super sin casilla) edita uno de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select public.documento_proyecto_guarda(%L, ''{"titulo":"Prueba"}''::jsonb)::text', dl), '42501', 'ad4 (sin casilla) NO edita') || E'\n';
  -- publicar en el dosier de inversores: lo decide el admin de la empresa del proyecto
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_guarda(%L, ''{"publicado_investor_deck": true, "confidencial": false}''::jsonb)::text', dl), dl::text, 'ya (admin de Lawang) publica en el dosier un documento de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_guarda(%L, ''{"titulo":"Cambio"}''::jsonb)::text', dl), dl::text, 'ya cambia el titulo de un documento ya publicado en el dosier (es su empresa)') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.documento_proyecto_guarda(%L, ''{"publicado_investor_deck": true, "confidencial": false}''::jsonb)::text', dl), '42501', 'agente de control NO publica en el dosier') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.documento_proyecto_guarda(%L, ''{"general": true}''::jsonb)::text', dl), '42501', 'ya NO marca un documento como general de la empresa (de un global)') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select public.documento_proyecto_guarda(%L, ''{"general": true}''::jsonb)::text', ds), ds::text, 'admin global SI lo marca') || E'\n';
  -- DOCUMENTOS: registrar y borrar (las ejecuta la edge, en la piel del usuario)
  r := r || pg_temp.sv(format('select public.documento_proyecto_registra(%L, %L, ''x'', null)::text', ya, pl), '!42501', 'edge: ya registra en Lawang (la ruta mala da 22023)') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_registra(%L, %L, ''x'', null)::text', ya, ps), '42501', 'edge: ya NO registra en Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_registra(%L, %L, ''x'', null)::text', cr, ps), '!42501', 'edge: cr (super sin casilla) registra en Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', ya, dl), '!42501', 'edge: ya comprueba el borrado de uno de Lawang') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', ya, ds), '42501', 'edge: ya NO borra uno de Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', cr, ds), '!42501', 'edge: cr (super sin casilla) borra uno de Sandal Woods') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', cr, dl), '42501', 'edge: cr NO borra uno de Lawang') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', ad4, dl), '42501', 'edge: ad4 (admin sin casilla) NO borra') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', ctl, dl), '42501', 'edge: agente de control NO borra') || E'\n';
  r := r || pg_temp.sv(format('select public.documento_proyecto_borra(%L, %L, true)::text', adm, ds), '!42501', 'edge: admin global (con casilla) comprueba el borrado de cualquiera') || E'\n';
  -- OBRA
  r := r || pg_temp.t(ya, e_ya, format('select public.obra_puede(%L)::text', ul), 'true', 'ya (admin con casilla Obra) en una parcela de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.obra_puede(%L)::text', us), 'false', 'ya NO en una de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.obra_puede(%L)::text', us), 'true', 'cr (super sin casilla) en una de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.obra_puede(%L)::text', ul), 'false', 'cr NO en una de Lawang') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select public.obra_puede(%L)::text', ul), 'false', 'ad4 (admin sin casilla) NO') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.obra_puede(%L)::text', ul), 'false', 'agente de control: como hoy') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.agente_ve_proyecto_obra(%L)::text', pl), 'true', 'ya ve la obra de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.agente_ve_proyecto_obra(%L)::text', ps), 'false', 'ya NO ve la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.agente_ve_proyecto_obra(%L)::text', ps), 'true', 'cr (sin casilla) ve la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.obra_actualizar(%L, ''x'', current_date)::text', ul), '!42501', 'ya llega a actualizar la obra de una parcela de Lawang (la fase mala da otro error)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.obra_actualizar(%L, ''x'', current_date)::text', us), '42501', 'ya NO actualiza la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.obra_actualizar(%L, ''x'', current_date)::text', us), '!42501', 'cr (sin casilla) llega a actualizar la de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.obra_contratos_afectados(%L, ''x'', ''x'', ''x'')::text', ps), '!42501', 'cr (sin casilla) llega a la lista de contratos afectados por una obra de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.obra_contratos_afectados(%L, ''x'', ''x'', ''x'')::text', pl), '42501', 'cr NO la de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select public.obra_confirmar_avance(%L, ''x'', ''x'', ''x'', 0, null, null)::text', pl), '42501', 'agente de control NO confirma un avance de obra') || E'\n';
  -- USO DE PLANTILLAS: un super de empresa ve el uso de SUS contratos
  select count(*) into n_sw from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.tipo is not null;
  select count(*) into n_la from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.tipo is not null;
  select count(*) into n_tot from public.contratos c where c.tipo is not null;
  r := r || pg_temp.t(cr, e_cr, 'select coalesce(sum(contratos),0)::text from public.plantillas_uso()', n_sw::text, 'cr (super de Sandal Woods) ve el uso de sus contratos') || E'\n';
  r := r || pg_temp.t(p4, e_p4, 'select coalesce(sum(contratos),0)::text from public.plantillas_uso()', n_la::text, 'p4 (super de Lawang) ve el de Lawang') || E'\n';
  r := r || pg_temp.t(jv, 'jvr.cervantes@gmail.com', 'select coalesce(sum(contratos),0)::text from public.plantillas_uso()', n_tot::text, 'el propietario (super global) ve el de todos (incluidos los sin proyecto)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select coalesce(sum(contratos),0)::text from public.plantillas_uso()', '0', 'ya (admin, no super) no ve nada: como un admin global hoy') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select coalesce(sum(contratos),0)::text from public.plantillas_uso()', '0', 'admin global (no super): como hoy') || E'\n';
  -- AJUSTES DE LA INSTANCIA: cerrados a un rol de empresa (de toda la instancia)
  r := r || pg_temp.t(ya, e_ya, 'select public.ajustes_config_datos()::text', '42501', 'ya NO lee los ajustes de la instancia') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.ajustes_config_datos()::text', '42501', 'cr NO lee los ajustes de la instancia') || E'\n';
  r := r || pg_temp.t(p4, e_p4, 'select public.ajustes_config_datos()::text', '42501', 'p4 (super de empresa) NO lee los ajustes de la instancia') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.ajustes_config_guardar(''dominio_web'', to_jsonb(''https://x.example''::text), ''prueba'')::text', '42501', 'cr NO cambia un ajuste de la instancia') || E'\n';
  r := r || pg_temp.t(p4, e_p4, 'select public.ajustes_config_guardar(''dominio_web'', to_jsonb(''https://x.example''::text), ''prueba'')::text', '42501', 'p4 NO cambia un ajuste de la instancia') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.ajustes_log_datos(10)::text', '42501', 'cr NO lee el registro de ajustes') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select public.mantenimiento_envios(true, ''prueba'')::text', '42501', 'ya NO pausa los envios de la instancia') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select public.mantenimiento_intranet(true, ''prueba'')::text', '42501', 'cr NO cierra la intranet de la instancia') || E'\n';
  r := r || pg_temp.t(p4, e_p4, 'select public.mantenimiento_intranet(true, ''prueba'')::text', '42501', 'p4 NO cierra la intranet de la instancia') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select (public.intranet_estado() is not null)::text', 'true', 'ya SI lee si la intranet esta abierta (lo lee todo el mundo)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select public.instancia_marca()::text', '!42501', 'ya lee el nombre de la instancia (lo lee todo el mundo)') || E'\n';
  r := r || pg_temp.t(adm, e_adm, 'select public.ajustes_config_guardar(''dominio_web'', to_jsonb(''https://x.example''::text), ''prueba'')::text', '42501', 'admin global (no super): como hoy') || E'\n';
  r := r || pg_temp.t(jv, 'jvr.cervantes@gmail.com', 'select (public.ajustes_config_datos() is not null)::text', 'true', 'el propietario SI lee los ajustes') || E'\n';
  select count(*) into fallos from regexp_matches(r, 'FALLO', 'g');
  raise exception E'SECCION 4\n%\nFALLOS=%', r, fallos;
end $t$;

-- ===== SECCION 5: FICHEROS DE CREATIVIDADES (bucket) =====
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text; ok boolean;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  -- (la funcion vive en el esquema privado: la llama la policy de storage; aqui se prueba como dueno con la identidad simulada)
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  ok := case when left(p_esp,1) = '!' then got <> substr(p_esp,2) else got = p_esp end;
  return case when ok then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ctl uuid; adm uuid; e_ya text; e_cr text; e_ctl text; e_adm text;
  r text := ''; fallos int; hs text := '{creatividades,dossier}';
  pl uuid; ps uuid; cl uuid; cs uuid; cn uuid;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set herramientas=hs::text[] where user_id=ctl;
  select p.id into pl from public.proyectos p where p.empresa='lawang' order by p.nombre limit 1;
  select p.id into ps from public.proyectos p where p.empresa='sandal_woods' order by p.nombre limit 1;
  cl := gen_random_uuid(); cs := gen_random_uuid(); cn := gen_random_uuid();
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cl, 'pieza', 'Prueba Lawang', pl, cl::text || '/estado-1.json');
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cs, 'pieza', 'Prueba Sandal', ps, cs::text || '/estado-1.json');
  insert into public.creatividades (id, tipo, titulo, proyecto_id, estado_path) values (cn, 'pieza', 'Prueba General', null, cn::text || '/estado-1.json');
  r := r || pg_temp.t(ya, e_ya, format('select privado.creatividad_ve_fichero(%L)::text', cl::text || '/estado-1.json'), 'true', 'ya lee el fichero de una creatividad de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select privado.creatividad_ve_fichero(%L)::text', cs::text || '/estado-1.json'), 'false', 'ya NO lee el de una de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select privado.creatividad_ve_fichero(%L)::text', cn::text || '/estado-1.json'), 'false', 'ya NO lee el de una general sin proyecto') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select privado.creatividad_ve_fichero(%L)::text', cs::text || '/estado-1.json'), 'true', 'cr (super sin casilla) lee el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select privado.creatividad_ve_fichero(%L)::text', cl::text || '/estado-1.json'), 'false', 'cr NO lee el de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select privado.creatividad_ve_fichero(%L)::text', cs::text || '/estado-1.json'), 'true', 'agente de control lo lee como hoy') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select privado.creatividad_ve_fichero(%L)::text', cn::text || '/estado-1.json'), 'true', 'agente de control lee el de la general como hoy') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select privado.creatividad_ve_fichero(%L)::text', cn::text || '/estado-1.json'), '!42501', 'admin global: sin error de permiso') || E'\n';
  select count(*) into fallos from regexp_matches(r, 'FALLO', 'g');
  raise exception E'SECCION 5\n%\nFALLOS=%', r, fallos;
end $t$;
