-- PRUEBA FINAL DE AISLAMIENTO · SECCION 5 (7-oct-2026): escalada y escrituras cruzadas con llamadas REALES (argumentos validos).
-- ¿Puede un admin_empresa / super_admin_empresa darse mas alcance, mover personas u objetos a la otra empresa, o crear/editar cosas en la otra empresa?
-- Personas (fichas de agente convertidas dentro de la transaccion, todo en rollback): a=ae_L b=se_L c=ae_S d=se_S, vL/vS = agentes de lawang / sandal_woods.
-- Cada caso: OK/FALLO. «E» = tiene que dar error; «=valor» = el efecto observado tiene que ser ese; «ok» = control positivo (lo propio SI se puede).
-- destructivo-ok: cada llamada se deshace; termina en raise
create temp table res (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.corre(p_uid uuid, p_email text, p_sent text, p_cons text default null) returns text language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  begin
    set local statement_timeout = '8s';
    set local role authenticated;
    execute p_sent;
    reset role;
    if p_cons is not null then execute p_cons into v; end if;
    raise exception 'RB' using errcode = 'ZZ001', detail = coalesce(v, 'ok');
  exception
    when sqlstate 'ZZ001' then get stacked diagnostics v = pg_exception_detail; return v;
    when others then return 'E' || sqlstate || '|' || left(sqlerrm, 70);
  end;
end $f$;
create function pg_temp.espera(p_nombre text, p_obt text, p_esp text) returns void language plpgsql as $f$
declare alt text; oks boolean := false;
begin
  foreach alt in array string_to_array(p_esp, '||') loop
    if alt = 'E' then oks := oks or p_obt ~ '^E(42501|P0001|P0002|PT403)\|'; elsif alt = 'E*' then oks := oks or p_obt like 'E%'; else oks := oks or p_obt = alt; end if;
  end loop;
  insert into res (nombre, ok, detalle) values (p_nombre, oks, p_nombre || '  obtenido=[' || coalesce(p_obt, 'null') || ']  esperado=[' || p_esp || ']');
end $f$;

do $t$
declare
  jv uuid; je text; ids uuid[]; ems text[]; a uuid; ae text; b uuid; be text; c uuid; ce text; d uuid; de text; vl uuid; vle text; vs uuid; vse text;
  pl uuid; ps uuid; pln text; psn text; ul uuid; us uuid; ucl text; cl uuid; cs uuid; spl uuid; sps uuid; vl_ uuid; vs_ uuid; tl uuid; ts uuid; tsm text; clis uuid; cond_s uuid; fs uuid;
  fallos int; resumen text; v text;
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select array_agg(user_id order by o), array_agg(email order by o) into ids, ems from (
    select user_id, email, case email when 'yanayjefferson@gmail.com' then 1 when 'adenovit.b@gmail.com' then 2 when 'david@newconcisa.com' then 3 when 'cris.blueiestates@gmail.com' then 4 when 'dortegag@gmail.com' then 5 when 'eduxzone@gmail.com' then 6 end o
      from public.usuarios where email in ('yanayjefferson@gmail.com','adenovit.b@gmail.com','david@newconcisa.com','cris.blueiestates@gmail.com','dortegag@gmail.com','eduxzone@gmail.com')) q;
  a := ids[1]; ae := ems[1]; b := ids[2]; be := ems[2]; c := ids[3]; ce := ems[3]; d := ids[4]; de := ems[4]; vl := ids[5]; vle := ems[5]; vs := ids[6]; vse := ems[6];
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=a;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=b;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=c;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=d;
  update public.usuarios set empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{contratos}' where user_id=vl;
  update public.usuarios set empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{contratos}' where user_id=vs;
  perform set_config('request.jwt.claims', '', true); reset role;
  -- objetos
  select p.id, p.nombre into pl, pln from public.proyectos p where p.empresa='lawang' and exists (select 1 from public.contratos x where x.proyecto_id=p.id and x.unidad_id is not null) order by p.nombre limit 1;
  select p.id, p.nombre into ps, psn from public.proyectos p where p.empresa='sandal_woods' and exists (select 1 from public.contratos x where x.proyecto_id=p.id and x.unidad_id is not null) order by p.nombre limit 1;
  select x.id, x.unidad_id into cl, ul from public.contratos x where x.proyecto_id=pl and x.unidad_id is not null order by coalesce(x.bloqueado,false), x.created_at limit 1;
  select x.id, x.unidad_id into cs, us from public.contratos x where x.proyecto_id=ps and x.unidad_id is not null order by coalesce(x.bloqueado,false), x.created_at limit 1;
  select codigo into ucl from public.unidades where id = us;
  select s.id into spl from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id)='lawang' limit 1;
  select s.id into sps from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id)='sandal_woods' limit 1;
  select e.id into tl from public.equipos_venta e where e.empresa='lawang' limit 1;
  select e.id, e.manager_email into ts, tsm from public.equipos_venta e where e.empresa='sandal_woods' limit 1;
  select cc.client_id into clis from public.contrato_compradores cc where cc.contrato_id = cs limit 1;
  select co.id into cond_s from public.condiciones_comision co where co.empresa='sandal_woods' limit 1;
  select f.id into fs from public.facturas f where public.empresa_de_factura(f.id)='sandal_woods' and f.tipo='proforma' limit 1;
  select v1.id into vl_ from public.contrato_vencimientos v1 where public.empresa_de_contrato(v1.contrato_id)='lawang' and v1.factura_id is null limit 1;
  select v1.id into vs_ from public.contrato_vencimientos v1 where public.empresa_de_contrato(v1.contrato_id)='sandal_woods' and v1.factura_id is null limit 1;

  -- 1. escalada propia
  perform pg_temp.espera('E1 ae_L se da super_admin_empresa', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, '{"rol":"super_admin_empresa"}')), 'E');
  perform pg_temp.espera('E2 ae_L se da las dos empresas', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, '{"empresas":["lawang","sandal_woods"]}'), format('select empresas::text from public.usuarios where user_id=%L', a)), 'E||{lawang}');
  perform pg_temp.espera('E3 ae_L se hace global', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, '{"ambito":"global"}'), format('select ambito from public.usuarios where user_id=%L', a)), 'E||empresa');
  perform pg_temp.espera('E4 ae_L se da rol admin', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', a, '{"rol":"admin"}')), 'E');
  perform pg_temp.espera('E5 se_L se da super_admin global', pg_temp.corre(b, be, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', b, '{"rol":"super_admin"}')), 'E');
  perform pg_temp.espera('E6 se_L se da las dos empresas', pg_temp.corre(b, be, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', b, '{"empresas":["lawang","sandal_woods"]}'), format('select empresas::text from public.usuarios where user_id=%L', b)), 'E||{lawang}');
  perform pg_temp.espera('E7 se_L usuario_da_alcance a si mismo/otro', pg_temp.corre(b, be, format('select public.usuario_da_alcance(%L, %L, %L::text[])', vl, 'admin_empresa', '{sandal_woods}')), 'E');
  -- 2. mover personas
  perform pg_temp.espera('E8 ae_L manda a su agente a la otra empresa', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', vl, '{"empresas":["sandal_woods"]}'), format('select empresas::text from public.usuarios where user_id=%L', vl)), 'E||{lawang}');
  perform pg_temp.espera('E9 ae_L toca a un agente de la otra empresa', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', vs, '{"nombre":"zz"}')), 'E');
  perform pg_temp.espera('E10 ae_L le da a su agente un proyecto de la otra', pg_temp.corre(a, ae, format('select public.usuario_guarda_permisos(%L, %L::jsonb)', vl, format('{"proyectos":["%s"]}', ps)), format('select proyectos::text from public.usuarios where user_id=%L', vl)), 'E||{}');
  perform pg_temp.espera('E11 ae_L supervisa proyecto ajeno a su agente', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, true)', vl, ps), format('select proyectos_supervisados::text from public.usuarios where user_id=%L', vl)), 'E||{}');
  perform pg_temp.espera('E12 ae_L control: supervisa proyecto propio', pg_temp.corre(a, ae, format('select public.usuario_supervisa_proyecto(%L, %L, true)', vl, pl)), 'ok||E*');
  -- 3. crear y editar proyectos / equipos / unidades
  perform pg_temp.espera('P1 ae_L crea proyecto en la otra empresa', pg_temp.corre(a, ae, format('select public.proyecto_alta(%L, %L)', 'zz_aisl_s', 'sandal_woods')), 'E');
  perform pg_temp.espera('P2 ae_L control: crea proyecto propio', pg_temp.corre(a, ae, format('select public.proyecto_alta(%L, %L)', 'zz_aisl_l', 'lawang')), 'ok');
  perform pg_temp.espera('P3 ae_L edita ficha de proyecto ajeno', pg_temp.corre(a, ae, format('select public.proyecto_guarda(%L, %L::jsonb)', ps, '{"resort":"zz"}')), 'E');
  perform pg_temp.espera('P4 ae_L control: edita ficha de proyecto propio', pg_temp.corre(a, ae, format('select public.proyecto_guarda(%L, %L::jsonb)', pl, '{"resort":"zz"}')), 'ok');
  perform pg_temp.espera('P5 se_L mueve proyecto propio a la otra empresa', pg_temp.corre(b, be, format('select public.proyecto_empresa_guarda(%L, %L)', pl, 'sandal_woods'), format('select empresa from public.proyectos where id=%L', pl)), 'E||lawang');
  perform pg_temp.espera('P6 ae_L cambia estado de proyecto ajeno', pg_temp.corre(a, ae, format('select public.proyecto_cambiar_estado(%L, %L, false, null)', ps, 'cerrado')), 'E');
  perform pg_temp.espera('P7 ae_L renombra proyecto ajeno', pg_temp.corre(a, ae, format('select public.renombrar_proyecto(%L, %L)', psn, 'zz_renombrado')), 'E');
  perform pg_temp.espera('P8 ae_L borra proyecto ajeno', pg_temp.corre(a, ae, format('select public.borrar_proyecto(%L)', psn)), 'E');
  perform pg_temp.espera('Q1 ae_L cambia la empresa de un equipo ajeno', pg_temp.corre(a, ae, format('select public.equipo_venta_guarda(%L, %L, %L, %L)', ts, 'zz', tsm, 'lawang')), 'E');
  perform pg_temp.espera('Q2 ae_L edita un equipo ajeno (sin cambiar empresa)', pg_temp.corre(a, ae, format('select public.equipo_venta_guarda(%L, %L, %L, %L)', ts, 'zz', tsm, 'sandal_woods')), 'E');
  perform pg_temp.espera('Q3 ae_L anade miembro a equipo ajeno', pg_temp.corre(a, ae, format('select public.equipo_miembro_guarda(null, %L, %L, current_date, null)', ts, vle)), 'E');
  perform pg_temp.espera('Q4 ae_L activa/desactiva equipo ajeno', pg_temp.corre(a, ae, format('select public.equipo_venta_activa(%L, false)', ts)), 'E');
  perform pg_temp.espera('U1 se_L mueve parcela ajena a su proyecto', pg_temp.corre(b, be, format('select public.unidad_guarda(%L, %L::jsonb, %L)', us, format('{"codigo":"%s","proyecto":"%s"}', ucl, pln), 'zz motivo largo'), format('select proyecto_id::text from public.unidades where id=%L', us)), 'E||' || ps::text);
  perform pg_temp.espera('U2 ae_L edita parcela ajena', pg_temp.corre(a, ae, format('select public.unidad_guarda(%L, %L::jsonb, %L)', us, format('{"codigo":"%s","proyecto":"%s","notas":"zz"}', ucl, psn), 'zz motivo largo')), 'E');
  perform pg_temp.espera('U3 ae_L importa parcelas en proyecto ajeno', pg_temp.corre(a, ae, format('select public.unidades_importa(%L::jsonb)', format('[{"fila":1,"codigo":"ZZ1","proyecto":"%s"}]', psn))), 'E');
  -- 4. contratos, dinero, documentos de la otra empresa
  perform pg_temp.espera('C1 ae_L manda a firma contrato ajeno', pg_temp.corre(a, ae, format('select public.contrato_envia_firma(%L, %L, %L, %L, 1, %L, null)', cs, 'Zz Zz', 'zz@zz.test', 'adquiriente_1', repeat('a', 64))), 'E');
  perform pg_temp.espera('C2 ae_L control: manda a firma contrato propio', pg_temp.corre(a, ae, format('select public.contrato_envia_firma(%L, %L, %L, %L, 1, %L, null)', cl, 'Zz Zz', 'zz@zz.test', 'adquiriente_1', repeat('a', 64))), 'ok||E*');
  perform pg_temp.espera('C3 ae_L anula firmas de contrato ajeno', pg_temp.corre(a, ae, format('select public.contrato_firmas_anula(%L, %L, false, null)', cs, 'zz')), 'E');
  perform pg_temp.espera('C4 ae_L prorroga reserva ajena', pg_temp.corre(a, ae, format('select public.prorroga_reserva(%L, 5, %L, false)', cs, 'motivo de prueba largo')), 'E');
  perform pg_temp.espera('C5 ae_L libera reserva ajena', pg_temp.corre(a, ae, format('select public.libera_reserva(%L, %L, %L, %L)', us, cs, 'desistida', 'nota de prueba')), 'E');
  perform pg_temp.espera('C6 ae_L desbloquea contrato ajeno', pg_temp.corre(a, ae, format('select public.contrato_desbloquea(%L)', cs)), 'E');
  perform pg_temp.espera('C7 ae_L borra operacion ajena', pg_temp.corre(a, ae, format('select public.borrar_operacion(%L)', cs)), 'E');
  perform pg_temp.espera('C8 ae_L ajusta fecha de vencimiento ajeno', pg_temp.corre(a, ae, format('select public.vencimiento_ajusta_fecha(%L, current_date)', vs_)), 'E');
  perform pg_temp.espera('C9 ae_L control: ajusta vencimiento propio', pg_temp.corre(a, ae, format('select public.vencimiento_ajusta_fecha(%L, current_date)', vl_)), 'ok||E*');
  perform pg_temp.espera('D1 ae_L resuelve solicitud de pago ajena', pg_temp.corre(a, ae, format('select public.solicitud_pago_resuelve(%L, %L, null, null)', sps, 'aprobada')), 'E');
  perform pg_temp.espera('D2 ae_L control: resuelve solicitud propia', pg_temp.corre(a, ae, format('select public.solicitud_pago_resuelve(%L, %L, null, null)', spl, 'aprobada')), 'ok||E*');
  perform pg_temp.espera('D3 ae_L pide pago sobre contrato ajeno', pg_temp.corre(a, ae, format('select public.solicitud_pago_guarda(null, %L::jsonb)', format('{"contrato_id":"%s","concepto":"zz","importe":1}', cs))), 'E');
  perform pg_temp.espera('D4 ae_L emite factura sobre contrato ajeno', pg_temp.corre(a, ae, format('select public.factura_guarda(null, %L::jsonb)', format('{"contrato_id":"%s","tipo":"proforma","total":1}', cs))), 'E');
  perform pg_temp.espera('D5 ae_L borra proforma ajena', pg_temp.corre(a, ae, format('select public.factura_borra(%L)', fs)), 'E');
  perform pg_temp.espera('D6 ae_L anula factura ajena', pg_temp.corre(a, ae, format('select public.factura_anula(%L)', fs)), 'E');
  perform pg_temp.espera('D7 se_L reactiva factura ajena', pg_temp.corre(b, be, format('select public.factura_reactiva(%L)', fs)), 'E');
  perform pg_temp.espera('D8 se_L marca enviada factura ajena', pg_temp.corre(b, be, format('select public.factura_marca_enviada(%L)', fs), format('select enviada::text from public.facturas where id=%L', fs)), 'E||false||f');
  perform pg_temp.espera('D9 se_L crea cuenta de cobro de la otra empresa', pg_temp.corre(b, be, 'select public.cuenta_bancaria_guarda(''zzaisl'', ''{"label":"a","titular":"b","cuenta":"c","empresa":"sandal_woods"}''::jsonb, true, null)', 'select empresa from public.cuentas_bancarias where clave=''zzaisl'''), 'E||lawang');
  perform pg_temp.espera('D10 se_L edita la sociedad de la otra empresa', pg_temp.corre(b, be, 'select public.sociedad_guarda(''san_dal_woods'', ''{"razon":"zz","domicilio":"zz"}''::jsonb, false)'), 'E');
  perform pg_temp.espera('D11 ae_L guarda diseno de contrato de la otra empresa', pg_temp.corre(a, ae, 'select public.contratos_diseno_empresa_guarda(''sandal_woods'', ''cc'', ''{}''::jsonb)'), 'E');
  perform pg_temp.espera('D12 ae_L crea condicion de comision en la otra empresa', pg_temp.corre(a, ae, format('select public.condicion_comision_guarda(null, %L::jsonb, ''[]''::jsonb, %L)', '{"empresa":"sandal_woods","nivel":"closer","pct":1}', 'zz')), 'E');
  perform pg_temp.espera('D13 ae_L borra condicion de comision ajena', pg_temp.corre(a, ae, format('select public.condicion_comision_borra(%L)', cond_s)), 'E');
  perform pg_temp.espera('D14 ae_L crea comunicado de la otra empresa', pg_temp.corre(a, ae, 'select public.comunicado_guarda(null, ''{"asunto":"zz","cuerpo":"zz","empresa":"sandal_woods"}''::jsonb)', 'select empresa from public.comunicados where asunto = ''zz'' limit 1'), 'E||lawang');
  perform pg_temp.espera('D15 ae_L edita ficha de comprador ajeno', pg_temp.corre(a, ae, format('select public.cliente_guarda(%L, %L::jsonb)', clis, '{"nombre":"zz"}')), 'E');
  perform pg_temp.espera('D16 ae_L traspasa comprador ajeno', pg_temp.corre(a, ae, format('select public.traspasar_cliente_con_documentos(%L, %L, %L)', clis, ae, 'zz')), 'E');
  perform pg_temp.espera('D17 ae_L deck de proyecto ajeno', pg_temp.corre(a, ae, format('select public.deck_config_guarda(%L, %L::jsonb)', ps, '{}')), 'E');
  perform pg_temp.espera('D18 ae_L ficha publica de proyecto ajeno', pg_temp.corre(a, ae, format('select public.ficha_publica_guarda(%L, %L::jsonb, null)', 'zz', '{}')), 'E');
  perform pg_temp.espera('D19 ae_L modelos_proyecto_fija en proyecto ajeno', pg_temp.corre(a, ae, format('select public.modelos_proyecto_fija(%L, ''{}''::uuid[])', ps)), 'E');
  perform pg_temp.espera('D20 ae_L proyecto_fijar_plazo ajeno', pg_temp.corre(a, ae, format('select public.proyecto_fijar_plazo(%L, 1, 1)', ps)), 'E');
  perform pg_temp.espera('D21 ae_L anade socio a parcela ajena', pg_temp.corre(a, ae, format('select public.unidad_socio_asigna(%L, %L, %L)', us, gen_random_uuid(), 'zz')), 'E');
  perform pg_temp.espera('D22 ae_L obra: actualiza fase de parcela ajena', pg_temp.corre(a, ae, format('select public.obra_actualizar(%L, %L, current_date)', us, 'cimentacion')), 'E');

  select count(*) filter (where not ok), count(*) into fallos, v from res;
  select string_agg(detalle, E'\n' order by n) filter (where not ok) into resumen from res;
  raise exception E'S5 escalada: % casos, FALLOS=%\n%\nControles/otros:\n%', v, fallos, coalesce(resumen, '(ninguno)'), (select string_agg(nombre || ' -> ' || split_part(split_part(detalle, 'obtenido=[', 2), ']', 1), E'\n' order by n) from res where nombre like '%control%');
end $t$;
