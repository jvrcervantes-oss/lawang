-- Prueba por PERFILES de la migracion 20261010100000_bot_s5_agenda_postgres (S5 del encargo bot de Lawang, 9-oct-2026).
-- Se ejecuta DESPUES de aplicar la migracion. Todo ocurre dentro de un DO que acaba SIEMPRE en una excepcion (rollback, sin rastro):
-- el veredicto sale en el mensaje «FALLOS=n de N casos | ...». Solo cuenta y codigos, ningun dato personal. Los telefonos son de mentira (999...).
-- destructivo-ok: prueba en transaccion que termina en raise (rollback). El unico «drop» es nada: solo se crea la funcion temporal pg_temp.llama.
-- Perfiles reales (sin literales): propietario, admin_empresa con la herramienta `closers` (se le quita `leads` y luego el rol DENTRO de la transaccion
-- para probar al closer «solo closers» y al closer no admin), agente SIN closers, anon.
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_prop uuid; v_prop_em text; v_ae uuid; v_ae_em text; v_ag uuid; v_ag_em text; v_ea text; v_eb text;
  v_src_a text; v_src_b text;
  r text; n1 bigint; n2 bigint;
  v_la uuid; v_lb uuid; v_ld1 uuid; v_ld2 uuid; v_lc uuid;
  v_cb uuid; v_ca uuid; v_tarea uuid; v_id uuid;
  v_fut text; v_fut2 text; v_dia date;
  v_tel_a constant text := '99912345611'; v_tel_b constant text := '99912345612'; v_tel_d constant text := '99912345613'; v_tel_c constant text := '99912345614';
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

  select user_id, email into v_prop, v_prop_em from public.usuarios where es_propietario and activo limit 1;
  select user_id, email, empresas[1] into v_ae, v_ae_em, v_ea from public.usuarios
   where rol = 'admin_empresa' and ambito = 'empresa' and activo and cardinality(empresas) = 1 and 'closers' = any (herramientas) order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios
   where rol = 'agente' and ambito = 'global' and activo and not ('closers' = any (herramientas)) order by user_id limit 1;
  select e.clave into v_eb from public.empresas e where e.clave <> v_ea order by e.clave limit 1;
  select m.clave into v_src_a from public.crm_origen_empresa m where m.empresa = v_ea order by m.clave limit 1;
  select m.clave into v_src_b from public.crm_origen_empresa m where m.empresa = v_eb order by m.clave limit 1;
  if v_prop is null or v_ae is null or v_ag is null or v_eb is null or v_src_a is null or v_src_b is null then
    raise exception 'FALLOS=1 | sin perfiles/origenes de prueba (prop %, ae %, ag %, eb %, sa %, sb %)', v_prop is not null, v_ae is not null, v_ag is not null, v_eb is not null, v_src_a is not null, v_src_b is not null;
  end if;
  if exists (select 1 from public.lead_accion where tipo in ('llamada','visita')) then
    raise exception 'FALLOS=1 | hay citas reales en lead_accion: la prueba cuenta filas y asume cero';
  end if;

  -- un dia habil de Bali dentro de 60 dias, a las 10:00 (y otro distinto)
  select d into v_dia from generate_series((now() at time zone 'Asia/Makassar')::date + 3, (now() at time zone 'Asia/Makassar')::date + 20, interval '1 day') d
   where extract(isodow from d) between 1 and 5 order by d limit 1;
  v_fut  := to_char(v_dia, 'YYYY-MM-DD') || 'T10:00';
  v_fut2 := to_char(v_dia + 1, 'YYYY-MM-DD') || 'T11:30';

  insert into public.leads (whatsapp, name, source) values (v_tel_a, 'Lead A prueba', v_src_a) returning id into v_la;
  insert into public.leads (whatsapp, name, source) values (v_tel_b, 'Lead B prueba', v_src_b) returning id into v_lb;
  insert into public.leads (whatsapp, name, source) values (v_tel_d, 'Dup 1', v_src_a) returning id into v_ld1;
  insert into public.leads (whatsapp, name, source) values (v_tel_d, 'Dup 2', v_src_a) returning id into v_ld2;
  insert into public.leads (whatsapp, name, source) values (v_tel_c, 'Lead C prueba', v_src_a) returning id into v_lc;
  -- una cita del lead de la OTRA empresa y una tarea, sembradas como postgres
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
    values (v_lb, 'cita de B', v_dia, 'x@x', 'x@x', 'llamada', (v_fut::timestamp at time zone 'Asia/Makassar'), 'confirmada', 'humano') returning id into v_cb;
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo)
    values (v_lc, 'una tarea', v_dia, 'x@x', 'x@x', 'tarea') returning id into v_tarea;

  -- ═════════ A. QUIEN ENTRA ═════════
  r := pg_temp.llama('anon', null, null, '(select count(*) from public.crm_citas_agenda())');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A1 anon agenda: ' || r || ']'; end if;
  r := pg_temp.llama('anon', null, null, format('public.crm_cita_guardar(null, %L, %L)', v_tel_a, v_fut));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A2 anon guardar: ' || r || ']'; end if;
  r := pg_temp.llama('anon', null, null, format('public.crm_cita_cancelar(%L)', v_cb));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A3 anon cancelar: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, '(select count(*) from public.crm_citas_agenda())');
  total := total + 1; if r <> 'OK:0' then fallos := fallos + 1; resumen := resumen || ' [A4 agente sin closers ve citas: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, format('public.crm_cita_guardar(null, %L, %L)', v_tel_a, v_fut));
  total := total + 1; if r <> 'EPT403' then fallos := fallos + 1; resumen := resumen || ' [A5 agente sin closers guarda: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, format('public.crm_cita_cancelar(%L)', v_cb));
  total := total + 1; if r <> 'EPT403' then fallos := fallos + 1; resumen := resumen || ' [A6 agente sin closers cancela: ' || r || ']'; end if;

  -- ═════════ B. CLOSER «SOLO CLOSERS» (se le quita `leads` dentro de la transaccion) ═════════
  perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);   -- el propietario cambia permisos (trigger usuarios_bloquea_cambio_rol_herramientas)
  update public.usuarios set herramientas = array_remove(herramientas, 'leads') where user_id = v_ae;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('(public.crm_cita_guardar(null, %L, %L, %L, %L)->>%L)', v_tel_a, v_fut, 'otro@closer.test', 'notas de prueba', 'estado'));
  total := total + 1; if r <> 'OK:confirmada' then fallos := fallos + 1; resumen := resumen || ' [B1 crear sin leads: ' || r || ']'; end if;
  select id into v_ca from public.lead_accion where lead_id = v_la and tipo = 'llamada';
  total := total + 1; if not exists (select 1 from public.lead_accion where id = v_ca and origen = 'humano' and estado = 'confirmada'
        and responsable = 'otro@closer.test' and cuando_ts = (v_fut::timestamp at time zone 'Asia/Makassar') and creada_por = v_ae_em and que = 'notas de prueba') then
    fallos := fallos + 1; resumen := resumen || ' [B2 la fila no es la esperada (admin de empresa agenda a nombre de otro, hora de Bali)]'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, '(select count(*) from public.crm_citas_agenda())');
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [B3 agenda ve ' || r || ' (esperaba 1: la de A; la de B es de otra empresa)]'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(null, %L, %L)', v_tel_b, v_fut));
  total := total + 1; if r <> 'EPT403' then fallos := fallos + 1; resumen := resumen || ' [B4 lead de otra empresa: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_cancelar(%L)', v_cb));
  total := total + 1; if r <> 'EPT403' then fallos := fallos + 1; resumen := resumen || ' [B5 cancelar cita de otra empresa: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(null, %L, %L)', v_tel_a, v_fut2));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [B6 segunda cita viva: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(null, %L, %L)', v_tel_d, v_fut));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [B7 telefono con 2 leads: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(null, %L, %L)', '99900000000', v_fut));
  total := total + 1; if r <> 'EPT404' then fallos := fallos + 1; resumen := resumen || ' [B8 telefono sin lead: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(null, %L, %L)', v_tel_c, 'manana por la tarde'));
  total := total + 1; if r <> 'EPT400' then fallos := fallos + 1; resumen := resumen || ' [B9 fecha invalida: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(null, %L, %L, null, null, %L)', v_tel_c, v_fut, 'reunion'));
  total := total + 1; if r <> 'EPT400' then fallos := fallos + 1; resumen := resumen || ' [B10 tipo invalido: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_cancelar(%L)', v_tarea));
  total := total + 1; if r <> 'EPT400' then fallos := fallos + 1; resumen := resumen || ' [B11 cancelar una tarea: ' || r || ']'; end if;
  -- editar la existente: no crea otra fila
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('(public.crm_cita_guardar(%L, null, %L, null, %L, %L)->>%L)', v_ca, v_fut2, 'cambiada', 'visita', 'estado'));
  total := total + 1; if r <> 'OK:confirmada' then fallos := fallos + 1; resumen := resumen || ' [B12 editar: ' || r || ']'; end if;
  select count(*) into n1 from public.lead_accion where lead_id = v_la and tipo in ('llamada', 'visita');
  total := total + 1; if n1 <> 1 or not exists (select 1 from public.lead_accion where id = v_ca and tipo = 'visita' and que = 'cambiada'
        and cuando_ts = (v_fut2::timestamp at time zone 'Asia/Makassar')) then
    fallos := fallos + 1; resumen := resumen || ' [B13 editar creo otra fila o no cambio (filas ' || n1 || ')]'; end if;
  -- el closer que ya no es admin: no puede agendar a nombre de otro
  perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);   -- el propietario cambia permisos (trigger usuarios_bloquea_cambio_rol_herramientas)
  update public.usuarios set rol = 'agente', ambito = 'global', herramientas = array['closers'] where user_id = v_ae;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(%L, null, %L, %L)', v_ca, v_fut, 'otro@closer.test'));
  total := total + 1; if r not like 'OK:%' or not exists (select 1 from public.lead_accion where id = v_ca and responsable = v_ae_em) then
    fallos := fallos + 1; resumen := resumen || ' [B14 un closer no admin agendo a nombre de otro: ' || r || ']'; end if;
  -- cancelar: sale de la agenda, la fila queda (historial) y el lead puede tener otra
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('(public.crm_cita_cancelar(%L)->>%L)', v_ca, 'estado'));
  total := total + 1; if r <> 'OK:cancelada' then fallos := fallos + 1; resumen := resumen || ' [B15 cancelar: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, '(select count(*) from public.crm_citas_agenda())');
  total := total + 1; if r <> 'OK:0' then fallos := fallos + 1; resumen := resumen || ' [B16 cancelada sigue en la agenda: ' || r || ']'; end if;
  total := total + 1; if not exists (select 1 from public.lead_accion where id = v_ca and estado = 'cancelada' and completada_en is not null and decidida_por = v_ae_em) then
    fallos := fallos + 1; resumen := resumen || ' [B17 la cancelada no conserva quien/cuando]'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_cancelar(%L)', v_ca));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [B18 cancelar dos veces: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(%L, null, %L)', v_ca, v_fut));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [B19 editar una cancelada: ' || r || ']'; end if;

  -- ═════════ C. EL BOT Y LA AGENDA CONVIVEN ═════════
  -- tras cancelar, el bot puede proponer; la propuesta sale en la agenda y editarla la confirma sin cambiar su origen
  r := public.bot_lead_cita(v_tel_a, v_fut, 'llamada', 'wamid.PRUEBA-S5-1');
  total := total + 1; if r <> 'propuesta' then fallos := fallos + 1; resumen := resumen || ' [C1 el bot no pudo proponer tras cancelar: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('(select count(*) from public.crm_citas_agenda() a where a.estado = %L and a.origen = %L)', 'propuesta', 'bot'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [C2 la propuesta del bot no sale en la agenda: ' || r || ']'; end if;
  select id into v_id from public.lead_accion where lead_id = v_la and estado = 'propuesta';
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.crm_cita_guardar(%L, null, %L)', v_id, v_fut2));
  total := total + 1; if r not like 'OK:%' or not exists (select 1 from public.lead_accion where id = v_id and estado = 'confirmada' and origen = 'bot' and decidida_por = v_ae_em and decidida_en is not null) then
    fallos := fallos + 1; resumen := resumen || ' [C3 editar la propuesta no la confirmo: ' || r || ']'; end if;

  -- ═════════ D. EL PROPIETARIO Y LA IMPORTACION ═════════
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, '(select count(*) from public.crm_citas_agenda())');
  select count(*) into n2 from public.lead_accion where tipo in ('llamada', 'visita') and estado <> 'cancelada';
  total := total + 1; if r <> 'OK:' || n2 then fallos := fallos + 1; resumen := resumen || ' [D1 el propietario ve ' || r || ' de ' || n2 || ']'; end if;
  -- la clave de importacion es unica: repetir la misma cita de Redis no la duplica
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen, ref_origen, importada_en)
    values (v_lc, 'importada', v_dia, 'x@x', 'x@x', 'llamada', (v_fut::timestamp at time zone 'Asia/Makassar'), 'confirmada', 'importado', 'redis:PRUEBA', now());
  begin
    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen, ref_origen, importada_en)
      values (v_ld1, 'importada', v_dia, 'x@x', 'x@x', 'llamada', (v_fut::timestamp at time zone 'Asia/Makassar'), 'confirmada', 'importado', 'redis:PRUEBA', now());
    total := total + 1; fallos := fallos + 1; resumen := resumen || ' [D2 la misma ref_origen entro dos veces]';
  exception when unique_violation then total := total + 1; end;

  raise exception 'PRUEBA %: FALLOS=% de % casos |%', case when fallos = 0 then 'OK' else 'FALLA' end, fallos, total, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
