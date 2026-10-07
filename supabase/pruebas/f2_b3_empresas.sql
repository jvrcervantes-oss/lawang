-- Prueba del BLOQUE 3 (Fase 2 empresas, 7-oct-2026): clientes/KYC, comunicacion, CRM/leads, notificaciones y portal.
-- Cuatro secciones INDEPENDIENTES (cada una es una peticion: setup + casos + raise final que revierte todo). Se pegan DESPUES de las migraciones (o detras de ellas para ensayarlas sin rastro).
-- No crea usuarios: convierte fichas existentes dentro de la transaccion:
--   ya = admin_empresa/lawang · cr = super_admin_empresa/sandal_woods · ad4 = admin_empresa con las dos · p4 = super_admin_empresa/lawang · ctl = agente SIN empresas (control: como hoy) · adm = admin global
-- Cada linea OK/FALLO, termina en «FALLOS=n». El esperado se pasa como texto: el resultado escalar o el sqlstate del error.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop de datos
--
-- ===== SETUP COMUN (copiado al principio de cada seccion) =====
-- create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
-- declare got text; r text;
-- begin
--   perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
--   execute format('set local role %I', p_rol);
--   begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
--   reset role;
--   return case when got = p_esp then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
-- end $f$;
--
-- ===== SECCION 1: CLIENTES Y KYC =====
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
  cl uuid; cs uuid; cb uuid; cn uuid; dl uuid; db uuid; r text := ''; fallos int;
  x text; hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios}';
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
  -- clientes de muestra (medidos como postgres)
  select c.id into cl from public.clients c
   where exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id)
     and not exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id=cc.contrato_id left join public.proyectos pr on pr.id=k.proyecto_id where cc.client_id=c.id and pr.empresa is distinct from 'lawang')
     and not exists (select 1 from public.facturas f where f.client_id=c.id and public.empresa_de_factura(f.id) is distinct from 'lawang')
   order by (exists (select 1 from public.documents d where d.client_id=c.id and d.retirado_el is null)) desc, c.id limit 1;
  select c.id into cs from public.clients c
   where exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id)
     and not exists (select 1 from public.contrato_compradores cc join public.contratos k on k.id=cc.contrato_id left join public.proyectos pr on pr.id=k.proyecto_id where cc.client_id=c.id and pr.empresa is distinct from 'sandal_woods')
     and not exists (select 1 from public.facturas f where f.client_id=c.id and public.empresa_de_factura(f.id) is distinct from 'sandal_woods')
   order by c.id limit 1;
  select cc.client_id into cb from public.contrato_compradores cc join public.contratos k on k.id=cc.contrato_id join public.proyectos p on p.id=k.proyecto_id
   group by cc.client_id having count(distinct p.empresa) filter (where p.empresa in ('lawang','sandal_woods'))=2
   order by (select count(*) from public.documents d where d.client_id=cc.client_id) desc, cc.client_id limit 1;
  select c.id into cn from public.clients c
   where not exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id) and not exists (select 1 from public.facturas f where f.client_id=c.id)
     and not exists (select 1 from public.portal_accesos pa where pa.client_id=c.id) and not exists (select 1 from public.reservations rv where rv.client_id=c.id)
   order by c.id limit 1;
  select d.id into dl from public.documents d where d.client_id=cl and d.retirado_el is null limit 1;
  select d.id into db from public.documents d where d.client_id=cb and d.retirado_el is null limit 1;
  -- cn lo lleva p4 (super de Lawang): asi lo ve y lo puede borrar
  update public.clients set propietario = e_p4 where id = cn;

  -- visibilidad de las fichas (RLS)
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.clients where id in (%L,%L,%L)', cl, cs, cb), '2', 'ya (Lawang) ve su cliente y el compartido, no el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select count(*)::text from public.clients where id in (%L,%L,%L)', cl, cs, cb), '2', 'cr (Sandal Woods) ve el suyo y el compartido, no el de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.clients where id = %L', cn), '1', 'ya (Lawang) ve el cliente sin contratos que lleva p4 (misma empresa)') || E'\n';
  r := r || pg_temp.t(p4, e_p4, format('select count(*)::text from public.clients where id = %L', cn), '1', 'p4 ve el cliente sin contratos que lleva el') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select count(*)::text from public.clients where id = %L', cn), '1', 'ad4 (Lawang) ve el cliente sin contratos que lleva p4 (misma empresa)') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select count(*)::text from public.clients where id = %L', cn), '0', 'cr (otra empresa) no ve el cliente sin contratos de p4') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.documents where client_id = %L', cs), '0', 'ya no ve documentos KYC del cliente de Sandal Woods') || E'\n';
  -- editar fichas
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cl, '{"notes":"prueba b3"}'), 'true', 'ya edita la ficha de su cliente') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cb, '{"notes":"prueba b3"}'), 'true', 'ya edita la ficha del cliente compartido (la ficha es una; los contratos no)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cs, '{"notes":"prueba b3"}'), '42501', 'ya NO edita la ficha del cliente de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cl, '{"notes":"prueba b3"}'), '42501', 'cr NO edita la ficha del cliente de Lawang') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cs, '{"kyc_status":"verified"}'), '42501', 'agente de control sigue sin aprobar KYC (o sin ver la ficha)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_guarda(null, %L::jsonb) is not null)::text', '{"full_name":"Cliente Prueba B3","email":"prueba.b3.empresa@example.com","phone":"+34600000000","nationality":"ES","passport_number":"B3PRUEBA001","kyc_status":"verified"}'), 'true', 'ya da de alta una ficha nueva (y puede aprobar su KYC como un administrador)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select count(*)::text from public.clients where email = ''prueba.b3.empresa@example.com''', '1', 'ya ve la ficha que acaba de crear') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select count(*)::text from public.clients where email = ''prueba.b3.empresa@example.com''', '0', 'cr no ve la ficha nueva de ya') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select (public.cliente_guarda(%L, %L::jsonb) is not null)::text', cs, '{"notes":"prueba b3"}'), 'true', 'admin global sigue editando cualquier ficha') || E'\n';
  -- traspasar
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cl, e_ad4), 'true', 'ya traspasa su cliente a ad4 (comparten Lawang)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cl, e_cr), '22023', 'ya NO traspasa a una persona solo de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cb, e_ad4), '42501', 'ya NO traspasa el cliente compartido (exclusivo)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cs, e_ad4), '42501', 'ya NO traspasa el cliente de la otra empresa') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cb, e_ya), 'true', 'admin global traspasa el compartido como siempre') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select (public.cliente_traspasa(%L, %L, ''prueba'') is not null)::text', cl, e_ya), '42501', 'agente de control sigue sin traspasar') || E'\n';
  -- retirar documentos KYC (solo service_role, con p_uid)
  if dl is not null then
    r := r || pg_temp.t(ya, e_ya, format('select (public.documento_kyc_retira(%L, %L, ''retirada de prueba por empresa'')->>''conservado'')', ya, dl), '42501', 'ya (admin) NO retira KYC de quien ya tiene contratos: es de super', 'service_role') || E'\n';
    r := r || pg_temp.t(cr, e_cr, format('select (public.documento_kyc_retira(%L, %L, ''retirada de prueba por empresa'')->>''conservado'')', cr, dl), '42501', 'cr (otra empresa) NO retira KYC del cliente de Lawang', 'service_role') || E'\n';
    r := r || pg_temp.t(p4, e_p4, format('select (public.documento_kyc_retira(%L, %L, ''retirada de prueba por empresa'')->>''conservado'')', p4, dl), 'true', 'p4 (super de Lawang) retira KYC de su cliente con contratos (se conserva el fichero)', 'service_role') || E'\n';
  end if;
  if db is not null then
    r := r || pg_temp.t(p4, e_p4, format('select (public.documento_kyc_retira(%L, %L, ''retirada de prueba por empresa'')->>''conservado'')', p4, db), '42501', 'p4 NO retira KYC del cliente compartido (exclusivo)', 'service_role') || E'\n';
    r := r || pg_temp.t(adm, e_adm, format('select (public.documento_kyc_retira(%L, %L, ''retirada de prueba por empresa'')->>''conservado'')', adm, db), '42501', 'admin global no super sigue sin retirar KYC de quien tiene contratos', 'service_role') || E'\n';
  end if;
  -- borrar ficha vacia (service_role)
  r := r || pg_temp.t(ya, e_ya, format('select (public.borrar_comprador(%L)->>''borrado'')', cn), '42501', 'ya (admin) NO borra fichas: es de super', 'service_role') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.borrar_comprador(%L)->>''borrado'')', cn), '42501', 'cr (super de otra empresa) NO borra la ficha vacia de p4', 'service_role') || E'\n';
  r := r || pg_temp.t(p4, e_p4, format('select (public.borrar_comprador(%L)->>''borrado'')', cn), 'true', 'p4 (super de Lawang) borra una ficha vacia suya', 'service_role') || E'\n';
  -- traspaso con documentos
  r := r || pg_temp.t(ya, e_ya, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''prueba'')).facturas_movidas::text', cl, e_ad4), '42501', 'ya (admin) NO traspasa con documentos: es de super') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''prueba'')).facturas_movidas::text', cl, e_ad4), '42501', 'cr NO traspasa un cliente de Lawang con documentos') || E'\n';
  r := r || pg_temp.t(p4, e_p4, format('select (public.traspasar_cliente_con_documentos(%L, %L, ''prueba'')).facturas_movidas is not null', cl, e_cr), '23514', 'p4 NO traspasa a una persona solo de Sandal Woods') || E'\n';
  r := r || pg_temp.t(p4, e_p4, format('select ((public.traspasar_cliente_con_documentos(%L, %L, ''prueba'')).facturas_movidas is not null)::text', cl, e_ya), 'true', 'p4 traspasa con documentos un cliente de Lawang a ya (la ficha ya era de ad4)') || E'\n';
  r := r || pg_temp.t(p4, e_p4, format('select ((public.traspasar_cliente_con_documentos(%L, %L, ''prueba'')).facturas_movidas is not null)::text', cb, e_ad4), '42501', 'p4 NO traspasa con documentos el cliente compartido') || E'\n';
  -- directorio: comprador_ficha y comprador_buscar
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_ficha(%L)', cl), '1', 'ya abre la ficha de su cliente') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_ficha(%L)', cs), '0', 'ya NO abre la ficha del cliente de Sandal Woods por id') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L)', cs), '1', 'agente de control sigue abriendo cualquier ficha (sin cambio)') || E'\n';
  select split_part(email,'@',1) into x from public.clients where id = cs and email is not null;
  if x is not null and length(x) >= 3 then
    r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', x, cs), '0', 'ya NO encuentra al cliente de Sandal Woods en el buscador de duplicados') || E'\n';
    r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_buscar(%L) where id = %L', x, cs), '1', 'agente de control lo sigue encontrando') || E'\n';
  end if;
  -- puertas de las helpers a los roles: nada de EXECUTE sobre las internas
  r := r || pg_temp.t(ya, e_ya, 'select public.es_admin_en_alguna_empresa()::text', '42501', 'las helpers internas no se pueden llamar desde fuera') || E'\n';
  fallos := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;

-- ===== SECCION 2: COMUNICADOS ===== (mismo setup que la seccion 1: pg_temp.t y las personas; sin el bloque de clientes)
-- Para no enviar nada ni pegar a la red: dentro de la transaccion se anulan _comunicados_despierta() y envios_pausados() (el raise final lo deshace).
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  return case when got = p_esp then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
create or replace function public._comunicados_despierta() returns void language sql as 'select 1';
create or replace function public.envios_pausados() returns boolean language sql as 'select false';
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; p4 uuid; ctl uuid;
  e_ya text; e_cr text; e_ad4 text; e_p4 text; e_ctl text;
  g uuid; l1 uuid; l2 uuid; s1 uuid; r text := ''; fallos int;
  hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios}';
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into p4, e_p4 from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4,p4) order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ad4;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=p4;
  r := r || pg_temp.t(jv, 'jvr.cervantes@gmail.com', 'select (public.comunicado_guarda(null, ''{"asunto":"B3 global","cuerpo":"x"}''::jsonb)->>''empresa'')', 'null', 'global crea un comunicado global (empresa nula)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select (public.comunicado_guarda(null, ''{"asunto":"B3 L1","cuerpo":"x"}''::jsonb)->>''empresa'')', 'lawang', 'ya crea un comunicado: queda de Lawang sin decirlo') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select (public.comunicado_guarda(null, ''{"asunto":"B3 sin empresa","cuerpo":"x"}''::jsonb)->>''empresa'')', '22023', 'ad4 (dos empresas) debe elegir la empresa') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select (public.comunicado_guarda(null, ''{"asunto":"B3 S1","cuerpo":"x","empresa":"sandal_woods"}''::jsonb)->>''empresa'')', 'sandal_woods', 'ad4 crea uno de Sandal Woods eligiendolo') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select (public.comunicado_guarda(null, ''{"asunto":"B3 L2","cuerpo":"x","empresa":"lawang"}''::jsonb)->>''empresa'')', 'lawang', 'ad4 crea uno de Lawang eligiendolo') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select (public.comunicado_guarda(null, ''{"asunto":"B3 ajeno","cuerpo":"x","empresa":"sandal_woods"}''::jsonb)->>''empresa'')', '42501', 'ya NO crea un comunicado de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select (public.comunicado_guarda(null, ''{"asunto":"B3 agente","cuerpo":"x"}''::jsonb)->>''empresa'')', '42501', 'agente de control sigue sin gestionar comunicados') || E'\n';
  select id into g from public.comunicados where asunto='B3 global';
  select id into l1 from public.comunicados where asunto='B3 L1';
  select id into l2 from public.comunicados where asunto='B3 L2';
  select id into s1 from public.comunicados where asunto='B3 S1';
  r := r || pg_temp.t(jv, 'jvr.cervantes@gmail.com', 'select jsonb_array_length(public.comunicacion_datos(100,null)->''comunicados'')::text', (select count(*) from public.comunicados)::text, 'global ve todos los comunicados') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select jsonb_array_length(public.comunicacion_datos(100,null)->''comunicados'')::text', '2', 'ya ve solo los de Lawang (L1 y L2), ni los globales ni los de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, 'select jsonb_array_length(public.comunicacion_datos(100,null)->''comunicados'')::text', '1', 'cr ve solo el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, 'select jsonb_array_length(public.comunicacion_datos(100,null)->''comunicados'')::text', '3', 'ad4 ve los de las dos empresas pero no los globales') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select jsonb_path_exists(public.comunicacion_datos(100,null)->''usuarios'', ''$[*] ? (@.email == "%s")'')::text', e_cr), 'false', 'ya no ve como destinatario a alguien solo de Sandal Woods') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select jsonb_path_exists(public.comunicacion_datos(100,null)->''usuarios'', ''$[*] ? (@.email == "%s")'')::text', e_p4), 'true', 'ya ve como destinatario a p4 (Lawang)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select jsonb_path_exists(public.comunicacion_datos(100,null)->''usuarios'', ''$[*] ? (@.email == "%s")'')::text', e_ctl), 'true', 'ya ve como destinatario a quien trabaja para las dos (sin restriccion)') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select public.comunicacion_datos(100,null)::text', '42501', 'agente de control sigue sin entrar') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.comunicado_datos(%L)->''comunicado''->>''id'')', l1), l1::text, 'ya abre su comunicado') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.comunicado_datos(%L)->''comunicado''->>''id'')', l1), 'null', 'cr no abre el comunicado de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.comunicado_datos(%L)->''comunicado''->>''id'')', g), 'null', 'ya no abre un comunicado global') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.comunicado_guarda(%L, ''{"asunto":"B3 L1 editado"}''::jsonb)->>''asunto'')', l1), 'B3 L1 editado', 'ya edita su comunicado') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select (public.comunicado_guarda(%L, ''{"asunto":"hackeado"}''::jsonb)->>''asunto'')', l1), '22023', 'cr no edita el comunicado de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.comunicado_guarda(%L, ''{"asunto":"hackeado"}''::jsonb)->>''asunto'')', g), '22023', 'ya no edita un comunicado global') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.comunicado_encolar(%L, array[%L,%L,%L,%L]::uuid[])::text', l2, ya, cr, p4, ctl), '3', 'ya encola a 4 y llegan 3: se cae el de Sandal Woods') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.comunicado_encolar(%L, array[%L]::uuid[])::text', l2, cr), 'P0002', 'cr no encola un comunicado de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.comunicado_encolar(%L, array[%L]::uuid[])::text', g, ya), 'P0002', 'ya no encola un comunicado global') || E'\n';
  r := r || pg_temp.t(jv, 'jvr.cervantes@gmail.com', format('select public.comunicado_encolar(%L, array[%L,%L]::uuid[])::text', g, ya, cr), '2', 'global sigue enviando a quien quiera') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.comunicado_prueba(%L)', l2), e_ya, 'ya se manda una prueba de un comunicado de su empresa') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.comunicado_prueba(%L)', l2), 'P0002', 'cr no prueba un comunicado de Lawang') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select public.comunicado_borra(%L)::text', l1), '22023', 'cr no borra el comunicado de Lawang') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select (public.comunicado_borra(%L) is not null)::text', l1), 'true', 'ya borra su comunicado') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select public.comunicado_borra(%L)::text', g), '22023', 'ya no borra un comunicado global') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select public.referidos_datos(10,null)::text', '42501', 'referidos siguen cerrados a un rol de empresa') || E'\n';
  r := r || pg_temp.t(ya, e_ya, 'select public.solicitudes_alta_datos(10,null)::text', '42501', 'solicitudes de alta siguen cerradas a un rol de empresa') || E'\n';
  fallos := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
