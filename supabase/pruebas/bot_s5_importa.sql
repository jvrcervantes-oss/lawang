-- Prueba de la migracion 20261010100100_bot_s5_importa_citas (S5 del encargo bot de Lawang, 9-oct-2026).
-- Todo dentro de un DO que acaba SIEMPRE en una excepcion (rollback, sin rastro). Telefonos de mentira (999...). Veredicto: «PRUEBA OK|FALLA: FALLOS=n de N casos».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo se crea la funcion temporal pg_temp.llama.
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_ae uuid; v_ae_em text; v_ea text; v_src text;
  r text; n bigint;
  v_dia date; v_fut text; v_pas text;
  v_l1 uuid; v_l2 uuid; v_l3 uuid; v_l4 uuid;
  p jsonb;
begin
  execute $f$
    create function pg_temp.llama(p_rol text, p_sub uuid, p_email text, p_sql text) returns text
    language plpgsql as $g$
    declare v text;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_rol, 'email', p_email)::text, true);
      execute format('set local role %I', p_rol);
      begin
        execute 'select (' || p_sql || ')::text' into v;
        reset role;
        return 'OK:' || coalesce(v, '');
      exception when others then
        reset role;
        return 'E' || sqlstate;
      end;
    end $g$;
  $f$;

  select user_id, email, empresas[1] into v_ae, v_ae_em, v_ea from public.usuarios
   where rol = 'admin_empresa' and ambito = 'empresa' and activo and cardinality(empresas) = 1 and 'closers' = any (herramientas) order by user_id limit 1;
  select m.clave into v_src from public.crm_origen_empresa m where m.empresa = v_ea order by m.clave limit 1;
  if v_ae is null or v_src is null then raise exception 'FALLOS=1 | sin perfil/origen de prueba'; end if;
  if exists (select 1 from public.lead_accion where tipo in ('llamada','visita')) then raise exception 'FALLOS=1 | hay citas reales: la prueba cuenta filas'; end if;

  select d into v_dia from generate_series((now() at time zone 'Asia/Makassar')::date + 3, (now() at time zone 'Asia/Makassar')::date + 20, interval '1 day') d
   where extract(isodow from d) between 1 and 5 order by d limit 1;
  v_fut := to_char(v_dia, 'YYYY-MM-DD') || 'T10:00';
  v_pas := to_char((now() at time zone 'Asia/Makassar')::date - 2, 'YYYY-MM-DD') || 'T10:00';

  insert into public.leads (whatsapp, name, source) values ('99912340001', 'L1', v_src) returning id into v_l1;
  insert into public.leads (whatsapp, name, source) values ('99912340002', 'L2', v_src) returning id into v_l2;
  insert into public.leads (whatsapp, name, source) values ('99912340003', 'L3a', v_src);
  insert into public.leads (whatsapp, name, source) values ('99912340003', 'L3b', v_src);
  insert into public.leads (whatsapp, name, source) values ('99912340004', 'L4', v_src) returning id into v_l4;
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
    values (v_l4, 'ya hay una', v_dia, 'x@x', 'x@x', 'llamada', (v_fut::timestamp at time zone 'Asia/Makassar'), 'confirmada', 'humano');

  p := jsonb_build_array(
    jsonb_build_object('id','a1','phone','+999 1234 0001','when',v_fut,'title','Call w/ L1 - 10:00 AEST','closer','closer@x.test','notes','con closer'),
    jsonb_build_object('id','a2','phone','99912340002','when',v_fut,'title','Visita a la parcela','closer','','notes',''),
    jsonb_build_object('id','a3','phone','99912340001','when',v_pas,'title','pasada','closer','c@x'),
    jsonb_build_object('id','a4','phone','99900009999','when',v_fut,'title','sin lead'),
    jsonb_build_object('id','a5','phone','99912340003','when',v_fut,'title','ambiguo'),
    jsonb_build_object('id','a6','phone','99912340001','when','manana','title','fecha mala'),
    jsonb_build_object('id','a7','phone','','when',v_fut,'title','sin telefono'),
    jsonb_build_object('id','a8','phone','99912340004','when',v_fut,'title','el lead ya tiene una'));

  -- 1. nadie con rol normal puede llamarla
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, '(select count(*) from public._bot_importa_citas(''[]''::jsonb))');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [1 authenticated pudo importar: ' || r || ']'; end if;
  r := pg_temp.llama('service_role', null, null, '(select count(*) from public._bot_importa_citas(''[]''::jsonb))');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [2 service_role pudo importar: ' || r || ']'; end if;

  -- 2. resultados por cita
  select string_agg(x.ref || '=' || x.resultado, ',' order by x.ref) into r from public._bot_importa_citas(p) x;
  total := total + 1; if r <> 'redis:a1=importada,redis:a2=importada,redis:a3=pasada,redis:a4=sin_lead,redis:a5=ambiguo,redis:a6=fecha_invalida,redis:a7=sin_telefono,redis:a8=lead_ya_tiene_cita' then
    fallos := fallos + 1; resumen := resumen || ' [3 resultados: ' || r || ']'; end if;

  -- 3. lo importado lleva su marca y su estado
  total := total + 1; if not exists (select 1 from public.lead_accion where ref_origen = 'redis:a1' and lead_id = v_l1 and origen = 'importado' and estado = 'confirmada'
        and tipo = 'llamada' and importada_en is not null and responsable = 'closer@x.test' and que = 'con closer' and decidida_por = 'closer@x.test'
        and cuando_ts = (v_fut::timestamp at time zone 'Asia/Makassar')) then
    fallos := fallos + 1; resumen := resumen || ' [4 a1 mal importada]'; end if;
  total := total + 1; if not exists (select 1 from public.lead_accion where ref_origen = 'redis:a2' and lead_id = v_l2 and origen = 'importado' and estado = 'propuesta'
        and tipo = 'visita' and decidida_por is null and que = 'Visita a la parcela') then
    fallos := fallos + 1; resumen := resumen || ' [5 a2 mal importada]'; end if;

  -- 4. repetirla no duplica
  select string_agg(x.ref || '=' || x.resultado, ',' order by x.ref) into r from public._bot_importa_citas(p) x;
  select count(*) into n from public.lead_accion where ref_origen is not null;
  total := total + 1; if n <> 2 or r not like 'redis:a1=ya_importada,redis:a2=ya_importada,%' then
    fallos := fallos + 1; resumen := resumen || ' [6 repetir duplico o no lo reconocio: ' || r || ' filas ' || n || ']'; end if;

  -- 5. la agenda las ve
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, '(select count(*) from public.crm_citas_agenda() a where a.origen = ''importado'')');
  total := total + 1; if r <> 'OK:2' then fallos := fallos + 1; resumen := resumen || ' [7 la agenda no ve las importadas: ' || r || ']'; end if;

  -- 6. entrada que no es una lista
  begin perform * from public._bot_importa_citas('{"a":1}'::jsonb); total := total + 1; fallos := fallos + 1; resumen := resumen || ' [8 acepto un objeto]';
  exception when sqlstate 'PT400' then total := total + 1; end;

  raise exception 'PRUEBA %: FALLOS=% de % casos |%', case when fallos = 0 then 'OK' else 'FALLA' end, fallos, total, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
