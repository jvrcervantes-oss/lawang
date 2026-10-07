-- Prueba del BLOQUE 1 del cierre de empresas (8-oct-2026): proyectos, parcelas, contratos y reservas por empresa.
-- Dos bloques `do`, cada uno acaba en raise (rollback, sin rastro). Se ejecuta cada uno DESPUES de su migracion (o pegado tras ella en la misma peticion para ensayarla sin rastro):
--   Parte A -> migracion 20261008100000 (proyectos y parcelas) · Parte B -> migracion 20261008100100 (contratos y reservas).
-- No crea usuarios: convierte fichas de agente EXISTENTES dentro de la transaccion (como f2_2b_empresas.sql):
--   ya = admin_empresa/lawang · cr = super_admin_empresa/sandal_woods · ad4 = admin_empresa con las dos · ctl = agente de control NO tocado
-- Cada linea OK/FALLO. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop

-- ============================== PARTE A: proyectos y parcelas ==============================
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_ctl text; e_adm text;
  pl uuid; psw uuid; npl text; npsw text; ul uuid; usw uuid; pk uuid; cl text; cs text; dl jsonb; ds jsonb; dlsw jsonb;
  so_lw uuid; so_sw uuid;
  r text := ''; g text; v uuid; n int; x text; y text;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin')
     and user_id not in (ya, cr, ad4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{unidades,documentacion,obra}', tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{unidades,documentacion,obra}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{unidades,documentacion,obra}', tipos_contrato='{}' where user_id=ad4;
  select id, nombre into pl, npl from public.proyectos pr where empresa='lawang' and exists (select 1 from public.unidades u where u.proyecto_id=pr.id) order by nombre limit 1;
  select id, nombre into psw, npsw from public.proyectos pr where empresa='sandal_woods' and exists (select 1 from public.unidades u where u.proyecto_id=pr.id) order by nombre limit 1;
  select id into pk from public.proyectos where empresa is null order by nombre limit 1;
  select id, codigo into ul, cl from public.unidades where proyecto_id=pl order by codigo limit 1;
  select id, codigo into usw, cs from public.unidades where proyecto_id=psw order by codigo limit 1;
  dl := jsonb_build_object('codigo', cl, 'proyecto', npl);
  ds := jsonb_build_object('codigo', cs, 'proyecto', npsw);
  dlsw := jsonb_build_object('codigo', cl, 'proyecto', npsw);
  -- un socio asignado en un proyecto de Lawang y otro que solo esta en proyectos de Sandal Woods
  select us.socio_id into so_lw from public.unidad_socio us join public.unidades u on u.id=us.unidad_id join public.proyectos p on p.id=u.proyecto_id where p.empresa='lawang' limit 1;
  select s.id into so_sw from public.socios s where s.activo
     and not exists (select 1 from public.unidad_socio us join public.unidades u on u.id=us.unidad_id join public.proyectos p on p.id=u.proyecto_id where us.socio_id=s.id and p.empresa='lawang') limit 1;

  -- corre: como la persona (JWT con email + role authenticated); con p_rol=false conserva el rol (funciones que solo ejecuta service_role). Devuelve 'ok' o 'sqlstate|mensaje'
  create or replace function pg_temp.corre(p_uid uuid, p_email text, p_sql text, p_rol boolean default true) returns text language plpgsql as $f$
  declare s text;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email',p_email)::text, true);
    if p_rol then set local role authenticated; end if;
    begin execute p_sql; s := 'ok';
    exception when others then s := sqlstate || '|' || left(sqlerrm, 70); end;
    reset role;
    return s;
  end $f$;
  create or replace function pg_temp.valor(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
  declare s text;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email',p_email)::text, true);
    set local role authenticated;
    begin execute p_sql into s; exception when others then s := 'ERR ' || sqlstate; end;
    reset role;
    return s;
  end $f$;
  create or replace function pg_temp.espera(p_label text, p_got text, p_want text) returns text language plpgsql as $f$
  begin
    return case when split_part(p_got,'|',1) = p_want then 'OK   ' else 'FALLO' end || format(' %s [%s | esperaba %s]', p_label, p_got, p_want) || E'\n';
  end $f$;

  -- ---- ya = admin de Lawang: lo suyo pasa, lo de Sandal Woods y lo sin empresa se rechaza
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_cambiar_estado(%L, (select estado from public.proyectos where id=%L))', pl, pl));   r := r || pg_temp.espera('ya cambiar_estado propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_cambiar_estado(%L, (select estado from public.proyectos where id=%L))', psw, psw)); r := r || pg_temp.espera('ya cambiar_estado AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_fijar_plazo(%L,1,10)', pl));  r := r || pg_temp.espera('ya fijar_plazo propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_fijar_plazo(%L,1,10)', psw)); r := r || pg_temp.espera('ya fijar_plazo AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', pl));  r := r || pg_temp.espera('ya proyecto_guarda propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', psw)); r := r || pg_temp.espera('ya proyecto_guarda AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.renombrar_proyecto(%L,%L)', npl, npl));   r := r || pg_temp.espera('ya renombrar propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.renombrar_proyecto(%L,%L)', npsw, npsw)); r := r || pg_temp.espera('ya renombrar AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.socios_parcelas(%L)', pl));  r := r || pg_temp.espera('ya socios_parcelas propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.socios_parcelas(%L)', psw)); r := r || pg_temp.espera('ya socios_parcelas AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_guarda(%L, %L::jsonb, ''prueba b1 de empresas, sin efecto'')', ul, dl));    r := r || pg_temp.espera('ya unidad_guarda propia (con contrato: como admin de la empresa exige motivo y lo da)', g, 'ok');
  g := pg_temp.corre(ctl, e_ctl, format('select public.unidad_guarda(%L, %L::jsonb, ''prueba b1 de empresas, sin efecto'')', ul, dl));  r := r || pg_temp.espera('control unidad_guarda propia con contrato: sigue rechazado', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_guarda(%L, %L::jsonb, null)', usw, ds));   r := r || pg_temp.espera('ya unidad_guarda AJENA', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_guarda(%L, %L::jsonb, null)', ul, dlsw));  r := r || pg_temp.espera('ya mover parcela a proyecto ajeno', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_guarda(null, %L::jsonb, null)', jsonb_build_object('codigo','ZZ-B1-1','proyecto',npl))); r := r || pg_temp.espera('ya alta de parcela en proyecto propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_guarda(null, %L::jsonb, null)', jsonb_build_object('codigo','ZZ-B1-2','proyecto',npsw))); r := r || pg_temp.espera('ya alta de parcela en proyecto AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.unidades_importa(%L::jsonb)', jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-B1-3','proyecto',npl)))); r := r || pg_temp.espera('ya unidades_importa proyecto propio', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.unidades_importa(%L::jsonb)', jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-B1-4','proyecto',npsw)))); r := r || pg_temp.espera('ya unidades_importa proyecto AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_socio_asigna(%L, null, null)', ul));  r := r || pg_temp.espera('ya quitar socio de parcela propia', g, 'ok');
  g := pg_temp.corre(ya, e_ya, format('select public.unidad_socio_asigna(%L, null, null)', usw)); r := r || pg_temp.espera('ya quitar socio de parcela AJENA', g, '42501');
  if so_lw is not null then g := pg_temp.corre(ya, e_ya, format('select public.unidad_socio_asigna(%L, %L, null)', ul, so_lw)); r := r || pg_temp.espera('ya asigna un socio ya usado en Lawang', g, 'ok'); end if;
  if so_sw is not null then g := pg_temp.corre(ya, e_ya, format('select public.unidad_socio_asigna(%L, %L, null)', ul, so_sw)); r := r || pg_temp.espera('ya NO asigna un socio solo de Sandal Woods', g, '42501'); end if;
  if so_sw is not null then
    x := pg_temp.valor(ya, e_ya, format('select count(*)::text from jsonb_array_elements(public.socios_parcelas(%L)->''socios'') s where s->>''id'' = %L', pl, so_sw));
    r := r || case when x = '0' then 'OK   ' else 'FALLO' end || format(' ya socios_parcelas no lista socios solo de Sandal Woods [%s]', x) || E'\n';
  end if;
  -- ad4 (admin de las dos empresas) ve todos los socios que se usan en alguna de las dos
  x := pg_temp.valor(ad4, e_ad4, format('select count(*)::text from jsonb_array_elements(public.socios_parcelas(%L)->''socios'')', pl));
  n := (select count(*) from public.socios s where s.activo and exists (select 1 from public.unidad_socio us where us.socio_id = s.id));
  r := r || case when x::int = n then 'OK   ' else 'FALLO' end || format(' ad4 ve los socios usados en sus empresas [%s/%s]', x, n) || E'\n';
  -- borrar: un admin_empresa NO borra (como un admin global); un super_admin_empresa borra en su empresa, nunca en la otra
  g := pg_temp.corre(ya, e_ya, format('select public.borrar_proyecto(%L)', npl)); r := r || pg_temp.espera('ya borrar_proyecto propio (admin no es super)', g, '42501');
  g := pg_temp.corre(cr, e_cr, format('select public.borrar_proyecto(%L)', npsw)); r := r || pg_temp.espera('cr borrar_proyecto propio (pasa la puerta; tiene unidades -> 23503)', g, '23503');
  g := pg_temp.corre(cr, e_cr, format('select public.borrar_proyecto(%L)', npl));  r := r || pg_temp.espera('cr borrar_proyecto AJENO', g, '42501');
  g := pg_temp.corre(jv, 'jvr.cervantes@gmail.com', format('select public.borrar_proyecto(%L)', npl)); r := r || pg_temp.espera('super global borra en cualquier empresa (pasa la puerta -> 23503)', g, '23503');
  g := pg_temp.corre(cr, e_cr, $s$select public.proyecto_alta('Zz borrable b1 cr')$s$); r := r || pg_temp.espera('cr crea un proyecto vacio', g, 'ok');
  g := pg_temp.corre(cr, e_cr, $s$select public.borrar_proyecto('Zz borrable b1 cr')$s$); r := r || pg_temp.espera('cr borra de verdad un proyecto vacio propio', g, 'ok');
  -- borrar_unidad: authenticated no tiene EXECUTE (desde el 30-sep); la puerta se prueba con los claims de la persona sin cambiar de rol
  g := pg_temp.corre(ya, e_ya, format('select public.borrar_unidad(%L)', ul), false); r := r || pg_temp.espera('ya borrar_unidad propia (admin no es super)', g, '42501');
  g := pg_temp.corre(cr, e_cr, format('select public.borrar_unidad(%L)', usw), false); r := r || pg_temp.espera('cr borrar_unidad propia (pasa la puerta)', g, 'ok');
  g := pg_temp.corre(cr, e_cr, format('select public.borrar_unidad(%L)', ul), false);  r := r || pg_temp.espera('cr borrar_unidad AJENA', g, '42501');
  if pk is not null then
    g := pg_temp.corre(ya, e_ya, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', pk)); r := r || pg_temp.espera('ya proyecto SIN empresa', g, '42501');
    g := pg_temp.corre(cr, e_cr, format('select public.borrar_proyecto((select nombre from public.proyectos where id=%L))', pk)); r := r || pg_temp.espera('cr borrar proyecto SIN empresa', g, '42501');
    g := pg_temp.corre(ad4, e_ad4, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', pk)); r := r || pg_temp.espera('ad4 proyecto SIN empresa', g, '42501');
  end if;
  g := pg_temp.corre(ad4, e_ad4, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', pl));  r := r || pg_temp.espera('ad4 proyecto_guarda lawang', g, 'ok');
  g := pg_temp.corre(ad4, e_ad4, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', psw)); r := r || pg_temp.espera('ad4 proyecto_guarda sandal', g, 'ok');
  -- cambiar la empresa de un proyecto existente: solo super global
  g := pg_temp.corre(ya, e_ya, format('select public.proyecto_empresa_guarda(%L, ''lawang'')', pl)); r := r || pg_temp.espera('ya proyecto_empresa_guarda', g, '42501');
  g := pg_temp.corre(cr, e_cr, format('select public.proyecto_empresa_guarda(%L, ''sandal_woods'')', psw)); r := r || pg_temp.espera('cr proyecto_empresa_guarda', g, '42501');
  g := pg_temp.corre(jv, 'jvr.cervantes@gmail.com', format('select public.proyecto_empresa_guarda(%L, ''lawang'')', pl)); r := r || pg_temp.espera('super global cambia la empresa', g, 'ok');
  -- es_manager_de
  x := pg_temp.valor(ya, e_ya, format('select (public.es_manager_de(%L) and not public.es_manager_de(%L) and not public.es_manager_de(%L))::text', pl, psw, pk));
  r := r || case when x = 'true' then 'OK   ' else 'FALLO' end || format(' ya es_manager_de (lawang si, sandal no, sin empresa no) [%s]', x) || E'\n';
  -- crear proyecto: solo de sus empresas, la empresa la fija el servidor
  g := pg_temp.corre(ya, e_ya, $s$select public.proyecto_alta('Zz prueba b1 ya')$s$);
  x := (select empresa from public.proyectos where nombre = 'Zz prueba b1 ya');
  r := r || case when g = 'ok' and x = 'lawang' then 'OK   ' else 'FALLO' end || format(' ya proyecto_alta nace en su empresa [%s, %s]', g, x) || E'
';
  g := pg_temp.corre(ya, e_ya, $s$select public.proyecto_alta('Zz prueba b1 ya2', 'sandal_woods')$s$); r := r || pg_temp.espera('ya proyecto_alta en empresa ajena', g, '42501');
  g := pg_temp.corre(ya, e_ya, $s$select public.proyecto_alta('Zz prueba b1 ya3', 'lawang')$s$);       r := r || pg_temp.espera('ya proyecto_alta con su empresa explicita', g, 'ok');
  g := pg_temp.corre(cr, e_cr, $s$select public.proyecto_alta('Zz prueba b1 cr')$s$);                    r := r || pg_temp.espera('cr proyecto_alta', g, 'ok');
  g := pg_temp.corre(ad4, e_ad4, $s$select public.proyecto_alta('Zz prueba b1 ad4')$s$);                 r := r || pg_temp.espera('ad4 proyecto_alta sin empresa (varias): pide indicarla', g, '22023');
  g := pg_temp.corre(ad4, e_ad4, $s$select public.proyecto_alta('Zz prueba b1 ad4', 'sandal_woods')$s$);  r := r || pg_temp.espera('ad4 proyecto_alta indicando una suya', g, 'ok');
  g := pg_temp.corre(ctl, e_ctl, $s$select public.proyecto_alta('Zz prueba b1 ctl')$s$);                  r := r || pg_temp.espera('agente de control proyecto_alta', g, '42501');
  if adm is not null then
    g := pg_temp.corre(adm, e_adm, $s$select public.proyecto_alta('Zz prueba b1 adm')$s$);                r := r || pg_temp.espera('admin global proyecto_alta (como antes)', g, 'ok');
    g := pg_temp.corre(adm, e_adm, $s$select public.proyecto_alta('Zz prueba b1 adm2', 'lawang')$s$);      r := r || pg_temp.espera('admin global (no super) no fija empresa', g, '42501');
  end if;
  g := pg_temp.corre(jv, 'jvr.cervantes@gmail.com', $s$select public.proyecto_alta('Zz prueba b1 jv', 'lawang')$s$); r := r || pg_temp.espera('super global fija empresa al crear', g, 'ok');
  -- proyecto_vinculos_datos (duena lw_lector, respeta RLS)
  -- el proyecto de Sandal Woods con mas parcelas: el admin de Lawang cuenta cero, el super global cuenta lo real
  x := pg_temp.valor(ya, e_ya, $s$select (public.proyecto_vinculos_datos((select p.nombre from public.proyectos p where p.empresa='sandal_woods' order by (select count(*) from public.unidades u where u.proyecto_id=p.id) desc limit 1))->>'unidades')$s$);
  y := pg_temp.valor(jv, 'jvr.cervantes@gmail.com', $s$select (public.proyecto_vinculos_datos((select p.nombre from public.proyectos p where p.empresa='sandal_woods' order by (select count(*) from public.unidades u where u.proyecto_id=p.id) desc limit 1))->>'unidades')$s$);
  r := r || case when x = '0' and y ~ '^[0-9]+$' and y::int > 0 then 'OK   ' else 'FALLO' end || format(' proyecto_vinculos_datos: admin de Lawang cuenta cero [%s], super global cuenta lo real [%s]', x, y) || E'
';
  g := pg_temp.corre(ctl, e_ctl, format('select public.proyecto_cambiar_estado(%L, (select estado from public.proyectos where id=%L))', pl, pl)); r := r || pg_temp.espera('control cambiar_estado', g, '42501');
  g := pg_temp.corre(ctl, e_ctl, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', pl)); r := r || pg_temp.espera('control proyecto_guarda', g, '42501');
  if adm is not null then
    g := pg_temp.corre(adm, e_adm, format('select public.proyecto_guarda(%L, ''{}''::jsonb)', psw)); r := r || pg_temp.espera('admin global proyecto_guarda en cualquier empresa', g, 'ok');
    g := pg_temp.corre(adm, e_adm, format('select public.borrar_proyecto(%L)', npl)); r := r || pg_temp.espera('admin global NO borra proyecto (como antes)', g, '42501');
  end if;
  select count(*) into n from regexp_split_to_table(r, E'\n') l where l like 'FALLO%';
  raise exception E'\n%FALLOS=%', r, n;
end $t$;

-- ============================== PARTE B: contratos y reservas ==============================
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_ctl text; e_adm text;
  cl_carta uuid; cs_carta uuid; cl_lib uuid; cs_lib uuid; cl_firm uuid; cs_firm uuid; cl_rp uuid; cs_rp uuid; cl_cons uuid; cs_cons uuid; ul_carta uuid;
  r text := ''; g text; n int; x text; y text; f text; payload jsonb;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin')
     and user_id not in (ya, cr, ad4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{contratos,comisiones_reparto}', tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{contratos,comisiones_reparto}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{contratos,comisiones_reparto}', tipos_contrato='{}' where user_id=ad4;
  -- contratos de prueba por empresa (lectura como postgres)
  select c.id into cl_carta from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.tipo='carta_reserva' and not coalesce(c.bloqueado,false) and c.liberado_en is null and c.contrato_padre_id is null order by c.numero limit 1;
  select c.id into cs_carta from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.tipo='carta_reserva' and not coalesce(c.bloqueado,false) and c.liberado_en is null and c.contrato_padre_id is null order by c.numero limit 1;
  select c.id into cl_lib from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.tipo='carta_reserva' and c.liberado_en is not null order by c.numero limit 1;
  select c.id into cs_lib from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.tipo='carta_reserva' and c.liberado_en is not null order by c.numero limit 1;
  select c.id into cl_firm from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.bloqueado and c.contrato_padre_id is null and c.tipo='carta_reserva' order by c.numero limit 1;
  select c.id into cs_firm from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.bloqueado and c.contrato_padre_id is null and c.tipo='carta_reserva' order by c.numero limit 1;
  select c.id into cl_rp from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.tipo='reserva_parcela' and not coalesce(c.bloqueado,false) and c.liberado_en is null
     and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id=c.id) and not exists (select 1 from public.contratos h where h.contrato_padre_id=c.id) order by c.numero limit 1;
  select c.id into cs_rp from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.tipo='reserva_parcela' and not coalesce(c.bloqueado,false) and c.liberado_en is null
     and not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id=c.id) and not exists (select 1 from public.contratos h where h.contrato_padre_id=c.id) order by c.numero limit 1;
  select c.id into cl_cons from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.tipo='construccion' and not coalesce(c.bloqueado,false) order by c.numero limit 1;
  select c.id into cs_cons from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.tipo='construccion' and not coalesce(c.bloqueado,false) order by c.numero limit 1;
  select id into ul_carta from public.unidades where contrato_id = cl_carta limit 1;

  create or replace function pg_temp.corre(p_uid uuid, p_email text, p_sql text, p_rol boolean default true) returns text language plpgsql as $f$
  declare s text;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email',p_email)::text, true);
    if p_rol then set local role authenticated; end if;
    begin execute p_sql; s := 'ok';
    exception when others then s := sqlstate || '|' || left(sqlerrm, 70); end;
    reset role;
    return s;
  end $f$;
  create or replace function pg_temp.valor(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
  declare s text;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email',p_email)::text, true);
    set local role authenticated;
    begin execute p_sql into s; exception when others then s := 'ERR ' || sqlstate; end;
    reset role;
    return s;
  end $f$;
  -- want: un codigo = ese error exacto ('ok' = sin error) · '!a,b' = cualquier resultado que NO sea ninguno de esos codigos (paso la puerta de permisos) · '~patron' = el texto completo casa (LIKE)
  create or replace function pg_temp.espera(p_label text, p_got text, p_want text) returns text language plpgsql as $f$
  declare ok boolean;
  begin
    ok := case when left(p_want,1) = '!' then not (split_part(p_got,'|',1) = any (string_to_array(substr(p_want,2), ',')))
               when left(p_want,1) = '~' then p_got like substr(p_want,2)
               else split_part(p_got,'|',1) = p_want end;
    return case when ok then 'OK   ' else 'FALLO' end || format(' %s [%s | esperaba %s]', p_label, p_got, p_want) || E'\n';
  end $f$;

  -- ---- reservas
  g := pg_temp.corre(ya, e_ya, format('select public.libera_reserva(%L, %L, ''desistida'', ''prueba b1'')', ul_carta, cl_carta)); r := r || pg_temp.espera('ya libera_reserva carta propia (pasa la puerta)', g, '!42501');
  g := pg_temp.corre(ya, e_ya, format('select public.libera_reserva(%L, %L, ''desistida'', ''prueba b1'')', ul_carta, cs_carta)); r := r || pg_temp.espera('ya libera_reserva carta AJENA', g, '42501');
  g := pg_temp.corre(ctl, e_ctl, format('select public.libera_reserva(%L, %L, ''desistida'', ''prueba b1'')', ul_carta, cl_carta)); r := r || pg_temp.espera('control libera_reserva sigue rechazado', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.prorroga_reserva(%L, 30, ''motivo de prueba b1'', false)', cl_carta)); r := r || pg_temp.espera('ya prorroga_reserva propia (pasa la puerta)', g, '!42501');
  g := pg_temp.corre(ya, e_ya, format('select public.prorroga_reserva(%L, 30, ''motivo de prueba b1'', false)', cs_carta)); r := r || pg_temp.espera('ya prorroga_reserva AJENA', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.deshace_liberacion(%L, ''motivo de prueba b1'')', cl_lib)); r := r || pg_temp.espera('ya deshace_liberacion propia (pasa la puerta)', g, '!42501');
  g := pg_temp.corre(ya, e_ya, format('select public.deshace_liberacion(%L, ''motivo de prueba b1'')', cs_lib)); r := r || pg_temp.espera('ya deshace_liberacion AJENA', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.carta_cobrado_recalcula(%L)', cl_rp), false); r := r || pg_temp.espera('ya carta_cobrado_recalcula propia (pasa la puerta)', g, '!42501');
  g := pg_temp.corre(ya, e_ya, format('select public.carta_cobrado_recalcula(%L)', cs_rp), false); r := r || pg_temp.espera('ya carta_cobrado_recalcula AJENA', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_calendario_aplica(%L::jsonb, %L::jsonb, 1000, null, %L)', '{"calendario":"manual","hitos":[{"fecha":"2027-01-01","pct":100}]}', '{"calendario":"estandar","hitos":[]}', cl_cons), false);
  r := r || pg_temp.espera('ya calendario a medida en contrato propio (pasa: es admin de su empresa)', g, '!42501');
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_calendario_aplica(%L::jsonb, %L::jsonb, 1000, null, %L)', '{"calendario":"manual","hitos":[{"fecha":"2027-01-01","pct":100}]}', '{"calendario":"estandar","hitos":[]}', cs_cons), false);
  r := r || pg_temp.espera('ya calendario a medida en contrato AJENO', g, '42501');
  g := pg_temp.corre(ctl, e_ctl, format('select public.contrato_calendario_aplica(%L::jsonb, %L::jsonb, 1000, null, %L)', '{"calendario":"manual","hitos":[{"fecha":"2027-01-01","pct":100}]}', '{"calendario":"estandar","hitos":[]}', cl_cons), false);
  r := r || pg_temp.espera('control calendario a medida sigue rechazado', g, '42501');
  -- ---- contratos
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_desbloquea(%L)', cs_firm)); r := r || pg_temp.espera('cr desbloquea contrato firmado propio', g, 'ok');
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_desbloquea(%L)', cl_firm)); r := r || pg_temp.espera('cr desbloquea contrato AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_desbloquea(%L)', cl_firm)); r := r || pg_temp.espera('ya (admin) no desbloquea ni el propio', g, '42501');
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_firmas_anula(%L, ''editar'', true, ''justificacion de prueba b1'')', cs_firm)); r := r || pg_temp.espera('cr anula firmas dadas del propio (pasa la puerta)', g, '!42501');
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_firmas_anula(%L, ''editar'', true, ''justificacion de prueba b1'')', cl_firm)); r := r || pg_temp.espera('ya (admin) no anula firmas dadas', g, '42501');
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_firmas_anula(%L, ''editar'', true, ''justificacion de prueba b1'')', cl_firm)); r := r || pg_temp.espera('cr no anula firmas de la otra empresa', g, '42501');
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_saldo(%L)', cs_firm)); r := r || pg_temp.espera('cr contrato_saldo propio', g, 'ok');
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_saldo(%L)', cl_firm)); r := r || pg_temp.espera('cr contrato_saldo AJENO', g, '42501');
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_saldo(%L)', cl_firm)); r := r || pg_temp.espera('ya contrato_saldo propio', g, 'ok');
  -- guardar: firmado solo lo guarda el super de la empresa; sin firmar, el admin de la empresa
  payload := (select jsonb_build_object('tipo', c.tipo, 'datos', c.datos) from public.contratos c where c.id = cs_firm);
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_guarda(%L, %L::jsonb)', cs_firm, payload)); r := r || pg_temp.espera('cr contrato_guarda firmado propio (pasa)', g, '!42501,23514');
  payload := (select jsonb_build_object('tipo', c.tipo, 'datos', c.datos) from public.contratos c where c.id = cl_firm);
  g := pg_temp.corre(cr, e_cr, format('select public.contrato_guarda(%L, %L::jsonb)', cl_firm, payload)); r := r || pg_temp.espera('cr contrato_guarda firmado AJENO (no editable)', g, '23514');
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_guarda(%L, %L::jsonb)', cl_firm, payload)); r := r || pg_temp.espera('ya (admin) contrato_guarda firmado propio (no editable: lo abre un super)', g, '23514');
  payload := (select jsonb_build_object('tipo', c.tipo, 'datos', c.datos) from public.contratos c where c.id = cl_rp);
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_guarda(%L, %L::jsonb)', cl_rp, payload)); r := r || pg_temp.espera('ya contrato_guarda sin firmar propio (pasa)', g, '!42501,23514');
  payload := (select jsonb_build_object('tipo', c.tipo, 'datos', c.datos) from public.contratos c where c.id = cs_rp);
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_guarda(%L, %L::jsonb)', cs_rp, payload)); r := r || pg_temp.espera('ya contrato_guarda sin firmar AJENO', g, '42501');
  -- clausulas negociadas (trigger por rol): el admin de la empresa las activa en SU contrato
  payload := (select jsonb_build_object('tipo', c.tipo, 'datos', jsonb_set(c.datos, '{fields,clausulas_negociadas}', '"prueba b1"')) from public.contratos c where c.id = cl_rp);
  g := pg_temp.corre(ya, e_ya, format('select public.contrato_guarda(%L, %L::jsonb)', cl_rp, payload)); r := r || pg_temp.espera('ya activa clausulas negociadas en contrato propio', g, '!42501,23514');
  if adm is not null then
    g := pg_temp.corre(adm, e_adm, format('select public.contrato_guarda(%L, %L::jsonb)', cl_rp, payload)); r := r || pg_temp.espera('admin global activa clausulas negociadas (como antes)', g, '!42501,23514');
  end if;
  -- borrar una operacion: super de empresa si es de su empresa y toda la cadena; admin_empresa como un admin global (solo lo suyo sin firmar)
  g := pg_temp.corre(cr, e_cr, format('select public.borrar_operacion(%L)', cs_rp)); r := r || pg_temp.espera('cr borra una operacion de su empresa', g, 'ok');
  g := pg_temp.corre(cr, e_cr, format('select public.borrar_operacion(%L)', cl_rp)); r := r || pg_temp.espera('cr NO borra una operacion de la otra empresa', g, '~P0001|El contrato%');
  g := pg_temp.corre(ya, e_ya, format('select public.borrar_operacion(%L)', cl_rp)); r := r || pg_temp.espera('ya (admin) borra como un admin global: lo ajeno no', g, '~P0001|El contrato%');
  g := pg_temp.corre(jv, 'jvr.cervantes@gmail.com', format('select public.borrar_operacion(%L)', cl_rp)); r := r || pg_temp.espera('super global borra en cualquier empresa', g, 'ok');
  -- lectura: cada uno ve lo de su empresa en las tablas hijas de contratos y los eventos completos solo el super de empresa
  x := pg_temp.valor(cr, e_cr, 'select count(*)::text from public.contrato_eventos');
  y := (select count(*)::text from public.contrato_eventos e join public.contratos c on c.id=e.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods');
  r := r || case when x = y then 'OK   ' else 'FALLO' end || format(' cr ve TODOS los eventos de sus contratos [%s/%s]', x, y) || E'\n';
  x := pg_temp.valor(ya, e_ya, 'select count(*)::text from public.contrato_eventos');
  y := (select count(*)::text from public.contrato_eventos e join public.contratos c on c.id=e.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang'
         and e.evento <> all (array['editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear','cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha']));
  r := r || case when x = y then 'OK   ' else 'FALLO' end || format(' ya (admin) ve los eventos normales de su empresa [%s/%s]', x, y) || E'\n';
  foreach f in array array['contratos','contrato_vencimientos','contrato_firmas','contrato_prorrogas','contrato_anexo_paginas','unidades','proyectos'] loop
    x := pg_temp.valor(ya, e_ya, format('select count(*)::text from public.%I', f));
    y := case f when 'contratos' then (select count(*)::text from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang')
                when 'contrato_vencimientos' then (select count(*)::text from public.contrato_vencimientos t join public.contratos c on c.id=t.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang')
                when 'contrato_firmas' then (select count(*)::text from public.contrato_firmas t join public.contratos c on c.id=t.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang')
                when 'contrato_prorrogas' then (select count(*)::text from public.contrato_prorrogas t join public.contratos c on c.id=t.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang')
                when 'contrato_anexo_paginas' then (select count(*)::text from public.contrato_anexo_paginas t join public.contratos c on c.id=t.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang')
                when 'unidades' then (select count(*)::text from public.unidades u join public.proyectos p on p.id=u.proyecto_id where p.empresa='lawang')
                else (select count(*)::text from public.proyectos where empresa='lawang') end;
    r := r || case when x = y then 'OK   ' else 'FALLO' end || format(' ya (admin de Lawang) ve TODO %s de su empresa y nada mas [%s/%s]', f, x, y) || E'\n';
  end loop;
  -- las funciones convertidas ya no dejan una puerta global suelta (salvo las que la mantienen a proposito: borrar_operacion, rama de rol de los triggers)
  for f in select p.oid::regprocedure::text from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in
      ('libera_reserva','prorroga_reserva','deshace_liberacion','carta_cobrado_recalcula','contrato_calendario_aplica',
       'contrato_guarda','contrato_desbloquea','contrato_firmas_anula','contrato_poder_vincula','contrato_saldo',
       '_contrato_anexo_check','_contrato_pdf_firmado_fijo','proyecto_cambiar_estado','proyecto_fijar_plazo','proyecto_guarda','renombrar_proyecto','unidad_guarda',
       'unidad_socio_asigna','unidad_parte_cobrada_split','socios_parcelas','trg_valida_unidad_id_contrato','borrar_proyecto','borrar_unidad','es_manager_de') loop
    x := pg_get_functiondef(f::regprocedure);
    x := replace(replace(x, 'es_admin_de(', ''), 'es_super_admin_de(', '');
    n := (length(x) - length(replace(x, 'public.es_admin()', ''))) / length('public.es_admin()') + (length(x) - length(replace(x, 'public.es_super_admin()', ''))) / length('public.es_super_admin()');
    if f like '%es_manager_de%' then n := n - 1; end if;   -- es_manager_de conserva es_admin() como primera rama (global)
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' sin puerta global suelta: %s [%s sueltas]', f, n) || E'\n';
  end loop;
  select count(*) into n from regexp_split_to_table(r, E'\n') l where l like 'FALLO%';
  raise exception E'\n%FALLOS=%', r, n;
end $t$;

-- ============================== PARTE C: super_admin_empresa sin casillas (migracion 20261008100200) ==============================
-- Resultado medido en produccion con rollback tras la migracion 3 (8-oct): super sin casillas guarda contrato/parcela/importa en SU empresa = ok; en la OTRA = 42501; admin_empresa sin casillas = 42501 en los tres.
do $t$
declare jv uuid; ya uuid; e_ya text; cr uuid; e_cr text; psw uuid; nsw text; pl uuid; npl text; cs uuid; cl uuid; pays jsonb; payl jsonb; r text := ''; usw uuid; ul uuid; codsw text; codl text; n int;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=cr;
  select pr.id, pr.nombre into psw, nsw from public.proyectos pr where empresa='sandal_woods' and exists (select 1 from public.unidades u where u.proyecto_id=pr.id) order by nombre limit 1;
  select pr.id, pr.nombre into pl, npl from public.proyectos pr where empresa='lawang' and exists (select 1 from public.unidades u where u.proyecto_id=pr.id) order by nombre limit 1;
  select u.id, u.codigo into usw, codsw from public.unidades u where proyecto_id=psw limit 1;
  select u.id, u.codigo into ul, codl from public.unidades u where proyecto_id=pl limit 1;
  select c.id into cs from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='sandal_woods' and c.tipo='reserva_parcela' and not coalesce(c.bloqueado,false) limit 1;
  select c.id into cl from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa='lawang' and c.tipo='reserva_parcela' and not coalesce(c.bloqueado,false) limit 1;
  pays := (select jsonb_build_object('tipo', tipo, 'datos', datos) from public.contratos where id=cs);
  payl := (select jsonb_build_object('tipo', tipo, 'datos', datos) from public.contratos where id=cl);
  create or replace function pg_temp.c(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
  declare s text; begin
    perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email',p_email)::text, true);
    set local role authenticated;
    begin execute p_sql; s := 'ok'; exception when others then s := sqlstate; end;
    reset role; return s; end $f$;
  r := r || case when pg_temp.c(cr,e_cr,format('select public.contrato_guarda(%L,%L::jsonb)',cs,pays)) = 'ok' then 'OK   ' else 'FALLO' end || ' super sin casillas guarda contrato propio' || E'\n';
  r := r || case when pg_temp.c(cr,e_cr,format('select public.contrato_guarda(%L,%L::jsonb)',cl,payl)) = '42501' then 'OK   ' else 'FALLO' end || ' super sin casillas guarda contrato AJENO' || E'\n';
  r := r || case when pg_temp.c(cr,e_cr,format('select public.unidad_guarda(%L,%L::jsonb,''motivo de prueba b1 largo'')',usw,jsonb_build_object('codigo',codsw,'proyecto',nsw))) = 'ok' then 'OK   ' else 'FALLO' end || ' super sin casillas unidad_guarda propia' || E'\n';
  r := r || case when pg_temp.c(cr,e_cr,format('select public.unidad_guarda(%L,%L::jsonb,''motivo de prueba b1 largo'')',ul,jsonb_build_object('codigo',codl,'proyecto',npl))) = '42501' then 'OK   ' else 'FALLO' end || ' super sin casillas unidad_guarda AJENA' || E'\n';
  r := r || case when pg_temp.c(cr,e_cr,format('select public.unidades_importa(%L::jsonb)',jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-B1-7','proyecto',nsw)))) = 'ok' then 'OK   ' else 'FALLO' end || ' super sin casillas importa en proyecto propio' || E'\n';
  r := r || case when pg_temp.c(cr,e_cr,format('select public.unidades_importa(%L::jsonb)',jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-B1-6','proyecto',npl)))) = '42501' then 'OK   ' else 'FALLO' end || ' super sin casillas importa en proyecto AJENO' || E'\n';
  r := r || case when pg_temp.c(ya,e_ya,format('select public.contrato_guarda(%L,%L::jsonb)',cs,pays)) = '42501' then 'OK   ' else 'FALLO' end || ' admin sin casillas NO guarda contrato' || E'\n';
  r := r || case when pg_temp.c(ya,e_ya,format('select public.unidad_guarda(%L,%L::jsonb,''motivo de prueba b1 largo'')',usw,jsonb_build_object('codigo',codsw,'proyecto',nsw))) = '42501' then 'OK   ' else 'FALLO' end || ' admin sin casillas NO guarda parcela' || E'\n';
  r := r || case when pg_temp.c(ya,e_ya,format('select public.unidades_importa(%L::jsonb)',jsonb_build_array(jsonb_build_object('fila',1,'codigo','ZZ-B1-5','proyecto',nsw)))) = '42501' then 'OK   ' else 'FALLO' end || ' admin sin casillas NO importa' || E'\n';
  select count(*) into n from regexp_split_to_table(r, E'\n') l where l like 'FALLO%';
  raise exception E'\n%FALLOS=%', r, n;
end $t$;
