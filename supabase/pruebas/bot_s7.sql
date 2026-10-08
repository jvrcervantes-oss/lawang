-- Prueba por PERFILES de la migracion 20261010090000_bot_s7_casilla_vista_citas (S7 del encargo bot de Lawang, 9-oct-2026).
-- Se ejecuta DESPUES de aplicar la migracion, o antes, en el MISMO envio que ella (migracion + este bloque). Todo ocurre dentro de un DO que acaba
-- SIEMPRE en una excepcion (rollback, sin rastro): el veredicto sale en el mensaje «FALLOS=n de N casos | ...». Solo cuenta y codigos, ningun dato personal.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback). El unico «drop» es la funcion temporal pg_temp.llama.
-- Perfiles reales (sin literales): propietario, agente SIN la herramienta leads, project_manager CON leads, admin_empresa (propia y ajena), anon.
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_prop uuid; v_prop_em text;
  v_ag uuid; v_ag_em text;
  v_pm uuid; v_pm_em text;
  v_ae uuid; v_ae_em text; v_ea text; v_eb text;
  p_a uuid; p_b uuid; n_a text;
  r text; j jsonb; n1 bigint; n2 bigint; n3 bigint; v_en timestamptz;
  v_cuando text; v_tel1 constant text := '99912345601'; v_tel2 constant text := '99912345602';
  v_l1 uuid; v_l2 uuid; v_c1 uuid; v_c2 uuid; v_t2 uuid;
  v_cols text[]; v_prohibidas constant text[] := array['contrato_id', 'contrato_liberado_id', 'cuota_reserva_investor_deck', 'notas', 'precio_suelo', 'id', 'proyecto_id', 'comprador', 'cliente', 'telefono', 'email'];
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
  select user_id, email into v_ag, v_ag_em from public.usuarios
   where rol = 'agente' and ambito = 'global' and activo and not ('leads' = any (herramientas)) order by user_id limit 1;
  select user_id, email into v_pm, v_pm_em from public.usuarios
   where rol = 'project_manager' and ambito = 'global' and activo and 'leads' = any (herramientas) order by user_id limit 1;
  select user_id, email, empresas[1] into v_ae, v_ae_em, v_ea from public.usuarios
   where rol = 'admin_empresa' and ambito = 'empresa' and activo and cardinality(empresas) = 1 order by user_id limit 1;
  select e.clave into v_eb from public.empresas e where e.clave <> v_ea order by e.clave limit 1;
  select p.id, p.nombre into p_a, n_a from public.proyectos p where p.empresa = v_ea and p.activo
   order by (select count(*) from public.unidades u where u.proyecto_id = p.id and u.estado = 'disponible' and u.contrato_id is null) desc, p.nombre limit 1;
  select id into p_b from public.proyectos where empresa = v_eb and activo order by nombre limit 1;
  if v_prop is null or v_ag is null or v_pm is null or v_ae is null or p_a is null or p_b is null then
    raise exception 'FALLOS=1 | sin perfiles/proyectos de prueba (prop %, ag %, pm %, ae %, pa %, pb %)', v_prop is not null, v_ag is not null, v_pm is not null, v_ae is not null, p_a is not null, p_b is not null;
  end if;
  if exists (select 1 from public.proyectos where bot_publico) then
    raise exception 'FALLOS=1 | hay un proyecto abierto al bot antes de empezar: la prueba asume todos cerrados';
  end if;

  -- ═════════ A. LA CASILLA ═════════
  r := pg_temp.llama('anon', null, null, format('public.proyecto_bot_publico_poner(%L, true)', p_a));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A1 anon: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, format('public.proyecto_bot_publico_poner(%L, true)', p_a));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A2 agente: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_pm, v_pm_em, format('public.proyecto_bot_publico_poner(%L, true)', p_a));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A3 project_manager: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.proyecto_bot_publico_poner(%L, true)', p_b));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A4 admin de otra empresa: ' || r || ']'; end if;
  total := total + 1; if exists (select 1 from public.proyectos where bot_publico) then fallos := fallos + 1; resumen := resumen || ' [A4b algo se abrio sin permiso]'; end if;

  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('public.proyecto_bot_publico_poner(%L, true)', p_a));
  total := total + 1; if r not like 'OK:%' then fallos := fallos + 1; resumen := resumen || ' [A5 admin de su empresa: ' || r || ']'; end if;
  select bot_publico_en into v_en from public.proyectos where id = p_a;
  total := total + 1; if not exists (select 1 from public.proyectos where id = p_a and bot_publico and bot_publico_por = v_ae_em and bot_publico_en is not null) then
    fallos := fallos + 1; resumen := resumen || ' [A5b no sello quien/cuando]'; end if;
  -- repetir el mismo valor no cambia quien/cuando
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.proyecto_bot_publico_poner(%L, true)', p_a));
  total := total + 1; if r not like 'OK:%' or not exists (select 1 from public.proyectos where id = p_a and bot_publico_en = v_en and bot_publico_por = v_ae_em) then
    fallos := fallos + 1; resumen := resumen || ' [A6 repetir cambio el sello: ' || r || ']'; end if;
  -- lee: agente no; admin de su empresa si, y `visibles` coincide con bot_catalogo_leer()
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, format('public.proyecto_bot_publico_lee(%L)', p_a));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [A7 lee agente: ' || r || ']'; end if;
  select count(*) into n1 from public.bot_catalogo_leer() c where c.proyecto = n_a;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, format('(public.proyecto_bot_publico_lee(%L)->>%L)', p_a, 'visibles'));
  total := total + 1; if r <> 'OK:' || n1 then fallos := fallos + 1; resumen := resumen || ' [A8 visibles ' || r || ' vs ' || n1 || ']'; end if;
  -- cerrar
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('(public.proyecto_bot_publico_poner(%L, false)->>%L)', p_a, 'visibles'));
  total := total + 1; if r <> 'OK:0' or exists (select 1 from public.proyectos where id = p_a and bot_publico) then fallos := fallos + 1; resumen := resumen || ' [A9 cerrar: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.proyecto_bot_publico_poner(%L, true)', gen_random_uuid()));
  total := total + 1; if r <> 'EPT404' then fallos := fallos + 1; resumen := resumen || ' [A10 proyecto inexistente: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.proyecto_bot_publico_poner(%L, null)', p_a));
  total := total + 1; if r <> 'EPT400' then fallos := fallos + 1; resumen := resumen || ' [A11 valor nulo: ' || r || ']'; end if;

  -- ═════════ B. «LO QUE SABE EL BOT» ═════════
  r := pg_temp.llama('anon', null, null, 'public.bot_catalogo_ver()');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [B1 anon: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, 'public.bot_catalogo_ver()');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [B2 agente: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ae, v_ae_em, 'public.bot_catalogo_ver()');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [B3 admin de empresa (alcance acotado): ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_pm, v_pm_em, 'public.bot_catalogo_ver()');
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [B4 project_manager: ' || r || ']'; end if;
  -- todo cerrado: vacio y 0 proyectos abiertos
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, '(public.bot_catalogo_ver()->>''proyectos_abiertos'') || ''/'' || jsonb_array_length(public.bot_catalogo_ver()->''unidades'')');
  total := total + 1; if r <> 'OK:0/0' then fallos := fallos + 1; resumen := resumen || ' [B5 vacio: ' || r || ']'; end if;
  -- abrir uno: lo que sale == bot_catalogo_leer(), con exactamente sus columnas y ninguna prohibida
  perform pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.proyecto_bot_publico_poner(%L, true)', p_a));
  perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);
  set local role authenticated;
  j := public.bot_catalogo_ver();
  reset role;
  select count(*) into n1 from public.bot_catalogo_leer();
  total := total + 1; if jsonb_array_length(j->'unidades') <> n1 or n1 = 0 then fallos := fallos + 1; resumen := resumen || ' [B6 unidades ' || jsonb_array_length(j->'unidades') || ' vs leer ' || n1 || ']'; end if;
  total := total + 1; if (j->>'proyectos_abiertos')::int <> 1 then fallos := fallos + 1; resumen := resumen || ' [B7 abiertos ' || (j->>'proyectos_abiertos') || ']'; end if;
  select array_agg(k order by k) into v_cols from jsonb_object_keys((j->'unidades')->0) k;
  total := total + 1; if v_cols is distinct from array['codigo', 'disponible', 'modelo', 'moneda', 'precio', 'proyecto', 'superficie_m2', 'tipo'] then
    fallos := fallos + 1; resumen := resumen || ' [B8 columnas ' || coalesce(array_to_string(v_cols, ','), 'ninguna') || ']'; end if;
  total := total + 1; if v_cols && v_prohibidas then fallos := fallos + 1; resumen := resumen || ' [B9 sale una columna prohibida]'; end if;
  total := total + 1; if (j->>'bot_conectado')::boolean is distinct from coalesce((select rolcanlogin from pg_roles where rolname = 'bot_lawang'), false) then
    fallos := fallos + 1; resumen := resumen || ' [B10 bot_conectado]'; end if;
  perform pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.proyecto_bot_publico_poner(%L, false)', p_a));

  -- ═════════ C. DECIDIR UNA CITA ═════════
  v_cuando := to_char(date_trunc('week', now() at time zone 'Asia/Makassar') + interval '14 days' + interval '10 hours', 'YYYY-MM-DD"T"HH24:MI');
  total := total + 1; if public.bot_lead_upsert(v_tel1) <> 'creado' or public.bot_lead_upsert(v_tel2) <> 'creado' then fallos := fallos + 1; resumen := resumen || ' [C0 no se crearon los leads]'; end if;
  select id into v_l1 from public.leads where public._lw_tel_e164(whatsapp) = public._bot_e164(v_tel1);
  select id into v_l2 from public.leads where public._lw_tel_e164(whatsapp) = public._bot_e164(v_tel2);
  total := total + 1; if public.bot_lead_cita(v_tel1, v_cuando, 'llamada') <> 'propuesta' or public.bot_lead_cita(v_tel2, v_cuando, 'visita') <> 'propuesta' then
    fallos := fallos + 1; resumen := resumen || ' [C0b no se propusieron las citas]'; end if;
  select id into v_c1 from public.lead_accion where lead_id = v_l1 and tipo = 'llamada';
  select id into v_c2 from public.lead_accion where lead_id = v_l2 and tipo = 'visita';

  r := pg_temp.llama('anon', null, null, format('public.crm_lead_cita_decidir(%L, %L)', v_c1, 'confirmar'));
  total := total + 1; if r <> 'E42501' then fallos := fallos + 1; resumen := resumen || ' [C1 anon: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_ag, v_ag_em, format('public.crm_lead_cita_decidir(%L, %L)', v_c1, 'confirmar'));
  total := total + 1; if r <> 'EPT403' then fallos := fallos + 1; resumen := resumen || ' [C2 agente sin leads: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.crm_lead_cita_decidir(%L, %L)', v_c1, 'borrar'));
  total := total + 1; if r <> 'EPT400' then fallos := fallos + 1; resumen := resumen || ' [C3 decision invalida: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.crm_lead_cita_decidir(%L, %L)', gen_random_uuid(), 'confirmar'));
  total := total + 1; if r <> 'EPT404' then fallos := fallos + 1; resumen := resumen || ' [C4 cita inexistente: ' || r || ']'; end if;
  total := total + 1; if not exists (select 1 from public.lead_accion where id = v_c1 and estado = 'propuesta' and decidida_en is null) then fallos := fallos + 1; resumen := resumen || ' [C4b se toco sin permiso]'; end if;

  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('(public.crm_lead_cita_decidir(%L, %L)->>%L)', v_c1, 'confirmar', 'estado'));
  total := total + 1; if r <> 'OK:confirmada' then fallos := fallos + 1; resumen := resumen || ' [C5 confirmar: ' || r || ']'; end if;
  total := total + 1; if not exists (select 1 from public.lead_accion where id = v_c1 and estado = 'confirmada' and decidida_por = v_prop_em and decidida_en is not null
                                       and responsable = v_prop_em and completada_en is null) then fallos := fallos + 1; resumen := resumen || ' [C5b confirmar no dejo quien/cuando/responsable]'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.crm_lead_cita_decidir(%L, %L)', v_c1, 'confirmar'));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [C6 confirmar dos veces: ' || r || ']'; end if;
  -- el bot no pisa una cita confirmada
  total := total + 1; if public.bot_lead_cita(v_tel1, v_cuando, 'visita') <> 'ya_hay_cita' then fallos := fallos + 1; resumen := resumen || ' [C7 el bot pisó una cita confirmada]'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('(public.crm_lead_cita_decidir(%L, %L)->>%L)', v_c1, 'hecha', 'estado'));
  total := total + 1; if r <> 'OK:hecha' or not exists (select 1 from public.lead_accion where id = v_c1 and completada_en is not null and completada_por = v_prop_em) then
    fallos := fallos + 1; resumen := resumen || ' [C8 hecha: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.crm_lead_cita_decidir(%L, %L)', v_c1, 'cancelar'));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [C9 cita ya cerrada: ' || r || ']'; end if;
  -- cerrada la cita, el bot puede proponer otra
  total := total + 1; if public.bot_lead_cita(v_tel1, v_cuando, 'visita') <> 'propuesta' then fallos := fallos + 1; resumen := resumen || ' [C10 la cita cerrada no libero al bot]'; end if;

  -- «hecha» solo desde confirmada; cancelar desde propuesta libera
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.crm_lead_cita_decidir(%L, %L)', v_c2, 'hecha'));
  total := total + 1; if r <> 'EPT409' then fallos := fallos + 1; resumen := resumen || ' [C11 hecha desde propuesta: ' || r || ']'; end if;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('(public.crm_lead_cita_decidir(%L, %L)->>%L)', v_c2, 'cancelar', 'estado'));
  total := total + 1; if r <> 'OK:cancelada' or not exists (select 1 from public.lead_accion where id = v_c2 and completada_en is not null and decidida_por = v_prop_em) then
    fallos := fallos + 1; resumen := resumen || ' [C12 cancelar: ' || r || ']'; end if;
  -- una tarea no es una cita
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por) values (v_l2, 'Tarea de prueba', current_date + 3, v_prop_em, v_prop_em) returning id into v_t2;
  r := pg_temp.llama('authenticated', v_prop, v_prop_em, format('public.crm_lead_cita_decidir(%L, %L)', v_t2, 'cancelar'));
  total := total + 1; if r <> 'EPT400' or not exists (select 1 from public.lead_accion where id = v_t2 and completada_en is null) then fallos := fallos + 1; resumen := resumen || ' [C13 tarea: ' || r || ']'; end if;

  -- el hilo: la cita con su etiqueta y sin colarse como «tarea»
  perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);
  set local role authenticated;
  select count(*) filter (where tipo = 'cita'), count(*) filter (where tipo = 'cita_estado' and texto = 'hecha'),
         count(*) filter (where tipo in ('tarea', 'tarea_hecha') and texto ilike '%propuesta por el bot%')
    into n1, n2, n3 from public.crm_lead_hilo(v_l1);
  reset role;
  total := total + 1; if n1 <> 2 or n2 <> 1 or n3 <> 0 then fallos := fallos + 1; resumen := resumen || ' [C14 hilo: citas ' || n1 || ', hecha ' || n2 || ', citas como tarea ' || n3 || ']'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);
  set local role authenticated;
  select count(*) into n1 from public.crm_lead_hilo(v_l2) where tipo = 'tarea';
  reset role;
  total := total + 1; if n1 <> 1 then fallos := fallos + 1; resumen := resumen || ' [C15 la tarea dejo de salir como tarea: ' || n1 || ']'; end if;

  -- ═════════ D. QUIEN PUEDE EJECUTAR QUE ═════════
  select count(*) into n1 from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('proyecto_bot_publico_poner', 'proyecto_bot_publico_lee', 'bot_catalogo_ver', 'crm_lead_cita_decidir', '_bot_proyecto_estado')
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute')
          or (p.proname = '_bot_proyecto_estado' and has_function_privilege('authenticated', p.oid, 'execute')));
  total := total + 1; if n1 <> 0 then fallos := fallos + 1; resumen := resumen || ' [D1 ' || n1 || ' funciones ejecutables por quien no deben]'; end if;
  select count(*) into n1 from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('proyecto_bot_publico_poner', 'proyecto_bot_publico_lee', 'bot_catalogo_ver', 'crm_lead_cita_decidir')
     and has_function_privilege('authenticated', p.oid, 'execute');
  total := total + 1; if n1 <> 4 then fallos := fallos + 1; resumen := resumen || ' [D2 authenticated ejecuta ' || n1 || ' de 4]'; end if;

  raise exception 'FALLOS=% de % casos |%', fallos, total, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
