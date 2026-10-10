-- Prueba de la migracion 20261010080000_bot_catalogo_crm_s3 (S3 del encargo bot de Lawang).
-- Se ejecuta con el MCP (execute_sql) o psql como postgres. NO deja rastro: todo ocurre dentro de un DO que acaba SIEMPRE en
-- una excepcion, y la excepcion deshace la transaccion entera (equivale a un ROLLBACK).
--   · si todo va bien, el mensaje de la excepcion empieza por «PRUEBA OK»;
--   · si algo falla, empieza por «PRUEBA FALLA» y dice cual.
-- Se prueba con los ROLES REALES (set local role anon / authenticated / bot_lawang), no como postgres.
do $t$
declare
  v_ok text := '';
  v_n int; v_r text; v_json text;
  v_proy uuid; v_proy2 uuid; v_contrato uuid;
  v_u_vendible uuid; v_u_con_contrato uuid; v_u_otro uuid;
  v_lunes text; v_domingo text;
  v_cols text[];
  v_lead uuid; v_lead2 uuid;
  v_tel constant text := '99912345678';
begin
  -- ── siembra (como postgres) ────────────────────────────────────────────────
  select id into v_proy  from public.proyectos where nombre = 'Sumba Hills';
  select id into v_proy2 from public.proyectos where nombre = 'Palm Field W5';
  select id into v_contrato from public.contratos limit 1;
  if v_proy is null or v_proy2 is null or v_contrato is null then raise exception 'PRUEBA FALLA: falta siembra base'; end if;
  if (select bot_publico from public.proyectos where id = v_proy) or (select bot_publico from public.proyectos where id = v_proy2) then
    raise exception 'PRUEBA FALLA: hay un proyecto con bot_publico=true antes de empezar (la casilla nace cerrada)';
  end if;
  v_ok := v_ok || 'casilla cerrada por defecto en los dos proyectos; ';

  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio, moneda, estado, modelo)
    values ('ZZ-PRUEBA-1', 'Sumba Hills', v_proy, 'parcela', 500, 100000, 'EUR', 'disponible', 'Z') returning id into v_u_vendible;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio, moneda, estado, modelo, contrato_id, notas, precio_suelo)
    values ('ZZ-PRUEBA-2', 'Sumba Hills', v_proy, 'parcela', 400, 90000, 'EUR', 'disponible', 'Z', v_contrato, 'NOTA SECRETA', 7391357)
    returning id into v_u_con_contrato;
  insert into public.unidades (codigo, proyecto, proyecto_id, tipo, superficie_m2, precio, moneda, estado, modelo, notas)
    values ('ZZ-PRUEBA-3', 'Palm Field W5', v_proy2, 'parcela', 300, 70000, 'EUR', 'disponible', 'Z', 'NOTA SECRETA 2') returning id into v_u_otro;

  -- ── 1. anon y authenticated no pueden ejecutar nada del bot ni leer el log ──
  foreach v_r in array array['anon', 'authenticated'] loop
    execute format('set local role %I', v_r);
    begin perform * from public.bot_catalogo_leer(); raise exception 'PRUEBA FALLA: % ejecuto bot_catalogo_leer', v_r;
    exception when insufficient_privilege then null; end;
    begin perform public.bot_lead_upsert(v_tel); raise exception 'PRUEBA FALLA: % ejecuto bot_lead_upsert', v_r;
    exception when insufficient_privilege then null; end;
    begin perform public.bot_lead_nota(v_tel, 'x'); raise exception 'PRUEBA FALLA: % ejecuto bot_lead_nota', v_r;
    exception when insufficient_privilege then null; end;
    begin perform public.bot_lead_cita(v_tel, '2030-01-01T10:00', 'llamada'); raise exception 'PRUEBA FALLA: % ejecuto bot_lead_cita', v_r;
    exception when insufficient_privilege then null; end;
    begin perform count(*) from public.bot_acciones_log; raise exception 'PRUEBA FALLA: % leyo bot_acciones_log', v_r;
    exception when insufficient_privilege then null; end;
    begin perform public._bot_e164(v_tel); raise exception 'PRUEBA FALLA: % ejecuto _bot_e164', v_r;
    exception when insufficient_privilege then null; end;
    reset role;
  end loop;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and (p.proname like 'bot\_%' or p.proname like '\_bot\_%') and p.proname not in ('bot_copia_frena','bot_faq_aprobar','bot_faq_frena','bot_faq_inmutable','bot_faq_retirar','bot_fuentes_versiona','bot_pendientes','bot_respuesta_copiada','bot_temas_resumen','bot_temas_valida_patron')
               and has_function_privilege('service_role', p.oid, 'execute')) then
    raise exception 'PRUEBA FALLA: service_role puede ejecutar una funcion del bot (solo bot_lawang)';
  end if;
  v_ok := v_ok || 'anon/authenticated sin EXECUTE en las 4 funciones ni en el ayudante y sin SELECT en el log; ';

  -- ── 2. el rol del bot: ve solo sus funciones ───────────────────────────────
  set local role bot_lawang;
  begin perform count(*) from public.leads; raise exception 'PRUEBA FALLA: bot_lawang leyo leads';
  exception when insufficient_privilege then null; end;
  begin perform count(*) from public.unidades; raise exception 'PRUEBA FALLA: bot_lawang leyo unidades';
  exception when insufficient_privilege then null; end;
  begin perform count(*) from public.bot_acciones_log; raise exception 'PRUEBA FALLA: bot_lawang leyo el log directo';
  exception when insufficient_privilege then null; end;
  begin perform public._bot_log('nota', null, null, 'x'); raise exception 'PRUEBA FALLA: bot_lawang ejecuto _bot_log';
  exception when insufficient_privilege then null; end;
  reset role;
  v_ok := v_ok || 'bot_lawang sin acceso directo a leads/unidades/log; ';

  -- ── 3. catalogo con todo cerrado: ni una fila ───────────────────────────────
  set local role bot_lawang;
  select count(*) into v_n from public.bot_catalogo_leer();
  reset role;
  if v_n <> 0 then raise exception 'PRUEBA FALLA: con bot_publico=false en todos salieron % filas', v_n; end if;
  v_ok := v_ok || 'bot_publico=false en todos -> 0 filas; ';

  -- ── 4. abro UN proyecto (Sumba Hills): solo el vendible, nunca el que tiene contrato ni el otro proyecto ──
  update public.proyectos set bot_publico = true where id = v_proy;
  if (select bot_publico_por from public.proyectos where id = v_proy) is null
     or (select bot_publico_en from public.proyectos where id = v_proy) is null then
    raise exception 'PRUEBA FALLA: el trigger no sello quien/cuando';
  end if;
  set local role bot_lawang;
  select count(*) into v_n from public.bot_catalogo_leer();
  select string_agg(to_jsonb(c)::text, '|') into v_json from public.bot_catalogo_leer() c;
  reset role;
  if v_n < 1 or v_json not like '%ZZ-PRUEBA-1%' then raise exception 'PRUEBA FALLA: la unidad libre no aparece'; end if;
  if v_json like '%ZZ-PRUEBA-2%' then raise exception 'PRUEBA FALLA: aparece una unidad con comprador y contrato'; end if;
  if v_json like '%ZZ-PRUEBA-3%' then raise exception 'PRUEBA FALLA: aparece una unidad de un proyecto con bot_publico=false'; end if;
  if v_json like '%' || v_contrato::text || '%' then raise exception 'PRUEBA FALLA: el id de un contrato sale en el catalogo'; end if;
  if v_json like '%NOTA SECRETA%' or v_json like '%7391357%' then raise exception 'PRUEBA FALLA: salen notas o precio_suelo'; end if;
  if v_json like '%' || v_u_vendible::text || '%' then raise exception 'PRUEBA FALLA: sale el UUID interno de la unidad'; end if;
  -- columnas exactas
  select array_agg(x order by o) into v_cols from unnest(
    (select string_to_array(regexp_replace(pg_get_function_result('public.bot_catalogo_leer()'::regprocedure), '^TABLE\(|\)$', '', 'g'), ', '))
  ) with ordinality t(x, o);
  if v_cols is distinct from array['proyecto text','tipo text','codigo text','superficie_m2 numeric','precio numeric','moneda text','modelo text','disponible boolean'] then
    raise exception 'PRUEBA FALLA: columnas del catalogo distintas de las fijadas: %', v_cols;
  end if;
  v_ok := v_ok || 'catalogo: libre SI; con contrato NO; otro proyecto NO; sin contrato_id/notas/precio_suelo/UUID; 8 columnas exactas; ';

  -- ── 5. acciones de CRM con el rol real ─────────────────────────────────────
  -- 5.1 alta: invalido, creado, existente (mismo numero escrito distinto), idempotente por id de mensaje
  set local role bot_lawang;
  if public.bot_lead_upsert('abc') <> 'telefono_invalido' then raise exception 'PRUEBA FALLA: telefono invalido aceptado'; end if;
  if public.bot_lead_upsert(v_tel, E'Test\u0007 Nombre', 'bot-whatsapp-lawang', 'wamid.1') <> 'creado' then raise exception 'PRUEBA FALLA: no creo'; end if;
  if public.bot_lead_upsert('+' || v_tel, 'Otro', 'x', 'wamid.2') <> 'existente' then raise exception 'PRUEBA FALLA: no reconocio el numero con +'; end if;
  if public.bot_lead_upsert(v_tel, 'Otro', 'x', 'wamid.1') <> 'creado' then raise exception 'PRUEBA FALLA: el mismo id de mensaje no devolvio lo mismo (idempotencia)'; end if;
  reset role;
  select count(*) into v_n from public.leads where public._lw_tel_e164(whatsapp) = '+' || v_tel;
  if v_n <> 1 then raise exception 'PRUEBA FALLA: hay % leads con el telefono de prueba (debia ser 1)', v_n; end if;
  select id into v_lead from public.leads where public._lw_tel_e164(whatsapp) = '+' || v_tel;
  if (select name from public.leads where id = v_lead) <> 'Test Nombre' then raise exception 'PRUEBA FALLA: nombre mal saneado: %', (select name from public.leads where id = v_lead); end if;
  if (select source from public.leads where id = v_lead) <> 'bot-whatsapp-lawang' then raise exception 'PRUEBA FALLA: origen'; end if;
  if public.empresa_de_lead(v_lead) is distinct from 'lawang' then raise exception 'PRUEBA FALLA: el lead del bot no tiene empresa (seria invisible)'; end if;
  if not exists (select 1 from public.lead_estado where lead_id = v_lead and estado = 'nuevo') then raise exception 'PRUEBA FALLA: sin estado nuevo'; end if;
  v_ok := v_ok || 'upsert: invalido/creado/existente/idempotente, nombre saneado, empresa lawang, estado nuevo; ';

  -- 5.2 nota
  set local role bot_lawang;
  if public.bot_lead_nota(v_tel, '   ') <> 'vacio' then raise exception 'PRUEBA FALLA: nota vacia aceptada'; end if;
  if public.bot_lead_nota('99900000001', 'hola') <> 'sin_lead' then raise exception 'PRUEBA FALLA: nota a un telefono sin lead'; end if;
  if public.bot_lead_nota(v_tel, 'Quiere visitar Sumba Hills', 'wamid.n1') <> 'ok' then raise exception 'PRUEBA FALLA: nota'; end if;
  if public.bot_lead_nota(v_tel, 'Quiere visitar Sumba Hills', 'wamid.n1') <> 'ok' then raise exception 'PRUEBA FALLA: nota no idempotente'; end if;
  reset role;
  select count(*) into v_n from public.lead_notas where lead_id = v_lead and autor = 'bot';
  if v_n <> 1 then raise exception 'PRUEBA FALLA: % notas del bot (debia ser 1: idempotencia)', v_n; end if;
  v_ok := v_ok || 'nota: vacio/sin_lead/ok/idempotente (1 sola fila); ';

  -- 5.3 cita
  v_lunes   := to_char(date_trunc('week', now() at time zone 'Asia/Makassar') + interval '1 week' + interval '10 hours', 'YYYY-MM-DD"T"HH24:MI');
  v_domingo := to_char(date_trunc('week', now() at time zone 'Asia/Makassar') + interval '1 week' + interval '6 days 10 hours', 'YYYY-MM-DD"T"HH24:MI');
  set local role bot_lawang;
  if public.bot_lead_cita(v_tel, 'manana a las 10', 'llamada') <> 'fecha_invalida' then raise exception 'PRUEBA FALLA: acepto una fecha no ISO'; end if;
  if public.bot_lead_cita(v_tel, '2026-13-45T10:00', 'llamada') <> 'fecha_invalida' then raise exception 'PRUEBA FALLA: acepto un mes 13'; end if;
  if public.bot_lead_cita(v_tel, v_lunes, 'reunion') <> 'tipo_invalido' then raise exception 'PRUEBA FALLA: tipo raro'; end if;
  if public.bot_lead_cita(v_tel, '2020-01-06T10:00', 'llamada') <> 'pasada' then raise exception 'PRUEBA FALLA: acepto el pasado'; end if;
  if public.bot_lead_cita(v_tel, '2030-01-07T10:00', 'llamada') <> 'lejana' then raise exception 'PRUEBA FALLA: acepto > 60 dias'; end if;
  if public.bot_lead_cita(v_tel, v_domingo, 'llamada') <> 'fuera_horario' then raise exception 'PRUEBA FALLA: acepto un domingo'; end if;
  if public.bot_lead_cita(v_tel, replace(v_lunes, 'T10:00', 'T20:00'), 'llamada') <> 'fuera_horario' then raise exception 'PRUEBA FALLA: acepto las 20:00'; end if;
  if public.bot_lead_cita('99900000002', v_lunes, 'llamada') <> 'sin_lead' then raise exception 'PRUEBA FALLA: cita a un telefono sin lead'; end if;
  reset role;
  -- una tarea humana viva NO impide la cita (indices separados)
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por) values (v_lead, 'Llamar mañana', current_date + 1, 'x@x', 'x@x');
  set local role bot_lawang;
  if public.bot_lead_cita(v_tel, v_lunes, 'llamada', 'wamid.c1') <> 'propuesta' then raise exception 'PRUEBA FALLA: no creo la cita (con tarea viva)'; end if;
  if public.bot_lead_cita(v_tel, v_lunes, 'llamada', 'wamid.c1') <> 'propuesta' then raise exception 'PRUEBA FALLA: cita no idempotente'; end if;
  if public.bot_lead_cita(v_tel, replace(v_lunes, 'T10:00', 'T11:00'), 'visita', 'wamid.c2') <> 'reprogramada' then raise exception 'PRUEBA FALLA: no reprogramo'; end if;
  reset role;
  select count(*) into v_n from public.lead_accion where lead_id = v_lead and completada_en is null;
  if v_n <> 2 then raise exception 'PRUEBA FALLA: % acciones vivas (debian ser 2: tarea + cita)', v_n; end if;
  if not exists (select 1 from public.lead_accion where lead_id = v_lead and tipo = 'visita' and estado = 'propuesta' and origen = 'bot'
                   and creada_por = 'bot' and cuando_ts is not null) then raise exception 'PRUEBA FALLA: la cita no quedo propuesta/bot/visita'; end if;
  -- una cita ya confirmada por el equipo no la toca el bot
  update public.lead_accion set estado = 'confirmada' where lead_id = v_lead and tipo = 'visita';
  set local role bot_lawang;
  if public.bot_lead_cita(v_tel, replace(v_lunes, 'T10:00', 'T12:00'), 'llamada') <> 'ya_hay_cita' then raise exception 'PRUEBA FALLA: piso una cita confirmada'; end if;
  reset role;
  v_ok := v_ok || 'cita: invalida/pasada/lejana/domingo/20:00/sin_lead rechazadas; propuesta con tarea viva; idempotente; reprogramada; confirmada intocable; ';

  -- ── 6. duplicados: >1 lead con el mismo e164 -> ambiguo, nada se aplica, nota FIJA en cada ficha ──
  insert into public.leads (whatsapp, source) values ('+' || v_tel, 'prueba') returning id into v_lead2;
  set local role bot_lawang;
  if public.bot_lead_upsert(v_tel, 'X') <> 'ambiguo' then raise exception 'PRUEBA FALLA: upsert no devolvio ambiguo'; end if;
  if public.bot_lead_nota(v_tel, 'TEXTO DEL CLIENTE') <> 'ambiguo' then raise exception 'PRUEBA FALLA: nota no devolvio ambiguo'; end if;
  if public.bot_lead_cita(v_tel, v_lunes, 'llamada') <> 'ambiguo' then raise exception 'PRUEBA FALLA: cita no devolvio ambiguo'; end if;
  reset role;
  if exists (select 1 from public.lead_notas where lead_id in (v_lead, v_lead2) and texto like '%TEXTO DEL CLIENTE%') then
    raise exception 'PRUEBA FALLA: con ambiguedad se escribio texto del cliente en una ficha';
  end if;
  select count(*) into v_n from public.lead_notas where lead_id = v_lead2 and autor = 'bot' and texto like 'Bot: este telefono figura en 2 fichas%';
  if v_n < 1 then raise exception 'PRUEBA FALLA: no hay nota fija de ambiguedad'; end if;
  delete from public.leads where id = v_lead2;
  v_ok := v_ok || 'duplicado -> ambiguo en las 3, nota fija sin texto del cliente; ';

  -- ── 7. tope de notas por lead y dia ────────────────────────────────────────
  set local role bot_lawang;
  for i in 1..40 loop
    v_r := public.bot_lead_nota(v_tel, 'nota ' || i);
    exit when v_r = 'tope';
  end loop;
  reset role;
  if v_r <> 'tope' then raise exception 'PRUEBA FALLA: no hubo tope de notas'; end if;
  v_ok := v_ok || 'tope de notas por lead/dia; ';

  -- ── 8. el log es de solo anadir y no tiene telefono ───────────────────────
  begin update public.bot_acciones_log set resultado = 'x'; raise exception 'PRUEBA FALLA: se pudo modificar el log';
  exception when insufficient_privilege then null; end;
  begin delete from public.bot_acciones_log; raise exception 'PRUEBA FALLA: se pudo borrar del log';
  exception when insufficient_privilege then null; end;
  begin truncate public.bot_acciones_log; raise exception 'PRUEBA FALLA: se pudo vaciar el log';
  exception when insufficient_privilege then null; end;
  if exists (select 1 from public.bot_acciones_log where coalesce(detalle, '') || coalesce(msg_id, '') || resultado like '%' || v_tel || '%') then
    raise exception 'PRUEBA FALLA: el log guarda el telefono';
  end if;
  v_ok := v_ok || 'log append-only (update/delete/truncate) y sin telefono; ';

  raise exception 'PRUEBA OK (rollback): %', v_ok;
end $t$;
