-- Prueba de la edge bot-api (S4) contra la BASE REAL, con el rol real bot_lawang. Complementa a bot_s3.sql: aqui se prueba lo que la edge
-- da por hecho de la base — que repetir una llamada con el mismo id de mensaje no duplica nada.
-- Se ejecuta con el MCP (execute_sql) o psql como postgres. NO deja rastro: todo ocurre en un DO que acaba SIEMPRE en una excepcion
-- (equivale a ROLLBACK). Si todo va bien, el mensaje empieza por «PRUEBA OK»; si algo falla, por «PRUEBA FALLA».
--
-- PARTE 1 (este fichero, bloque A): repeticion secuencial con el mismo msg_id = un solo lead y una sola nota.
-- PARTE 2 (bloque B, ejecutar en DOS sesiones a la vez): serializacion por telefono. Cada sesion hace upsert del MISMO telefono y msg_id, duerme
--   2 s con el bloqueo tomado y acaba en excepcion. La segunda tiene que tardar >= ~2 s MAS que la primera (espera al bloqueo de la
--   primera). Medido en la propia prueba y devuelto en el mensaje. Lo que NO se puede probar sin dejar rastro es el caso en que la primera
--   CONFIRMA y la segunda lo ve: eso es el modo sombra de S10 (el log es append-only y no se limpia).

-- ═══ BLOQUE A ═════════════════════════════════════════════════════════════════════════════════════════════
do $t$
declare
  v_ok text := '';
  v_tel constant text := '99955500011';
  v_r1 text; v_r2 text; v_n int; v_n2 int;
begin
  -- como el rol real del bot
  set local role bot_lawang;
  v_r1 := public.bot_lead_upsert(v_tel, 'Prueba S4', 'bot-whatsapp-lawang', 'wamid.PRUEBA-S4-A');
  v_r2 := public.bot_lead_upsert(v_tel, 'Prueba S4', 'bot-whatsapp-lawang', 'wamid.PRUEBA-S4-A');
  reset role;
  if v_r1 <> 'creado' or v_r2 <> 'creado' then raise exception 'PRUEBA FALLA: upsert repetido devolvio % / % (esperaba creado / creado)', v_r1, v_r2; end if;
  select count(*) into v_n from public.leads where public._lw_tel_e164(whatsapp) = public._bot_e164(v_tel);
  if v_n <> 1 then raise exception 'PRUEBA FALLA: % leads tras repetir el upsert (esperaba 1)', v_n; end if;
  v_ok := v_ok || 'upsert x2 mismo msg_id = 1 lead; ';

  -- otro msg_id con el mismo telefono: el lead ya existe
  set local role bot_lawang;
  v_r1 := public.bot_lead_upsert(v_tel, null, 'bot-whatsapp-lawang', 'wamid.PRUEBA-S4-B');
  reset role;
  if v_r1 <> 'existente' then raise exception 'PRUEBA FALLA: segundo mensaje devolvio % (esperaba existente)', v_r1; end if;
  select count(*) into v_n from public.leads where public._lw_tel_e164(whatsapp) = public._bot_e164(v_tel);
  if v_n <> 1 then raise exception 'PRUEBA FALLA: % leads tras segundo mensaje', v_n; end if;
  v_ok := v_ok || 'otro msg_id = el mismo lead; ';

  -- nota x2 con el mismo msg_id = una sola nota
  set local role bot_lawang;
  v_r1 := public.bot_lead_nota(v_tel, 'Quiere visita el sabado', 'wamid.PRUEBA-S4-N');
  v_r2 := public.bot_lead_nota(v_tel, 'Quiere visita el sabado', 'wamid.PRUEBA-S4-N');
  reset role;
  if v_r1 <> 'ok' or v_r2 <> 'ok' then raise exception 'PRUEBA FALLA: nota repetida devolvio % / %', v_r1, v_r2; end if;
  select count(*) into v_n from public.lead_notas n join public.leads l on l.id = n.lead_id
   where public._lw_tel_e164(l.whatsapp) = public._bot_e164(v_tel) and n.autor = 'bot';
  if v_n <> 1 then raise exception 'PRUEBA FALLA: % notas tras repetir la nota (esperaba 1)', v_n; end if;
  v_ok := v_ok || 'nota x2 mismo msg_id = 1 nota; ';

  -- cita x2: una sola accion viva
  set local role bot_lawang;
  v_r1 := public.bot_lead_cita(v_tel, to_char((now() at time zone 'Asia/Makassar') + interval '3 days', 'YYYY-MM-DD') || 'T10:00', 'llamada', 'wamid.PRUEBA-S4-C');
  v_r2 := public.bot_lead_cita(v_tel, to_char((now() at time zone 'Asia/Makassar') + interval '3 days', 'YYYY-MM-DD') || 'T10:00', 'llamada', 'wamid.PRUEBA-S4-C');
  reset role;
  if v_r1 not in ('propuesta', 'fuera_horario') or v_r2 <> v_r1 then raise exception 'PRUEBA FALLA: cita repetida devolvio % / %', v_r1, v_r2; end if;
  select count(*) into v_n from public.lead_accion a join public.leads l on l.id = a.lead_id
   where public._lw_tel_e164(l.whatsapp) = public._bot_e164(v_tel) and a.completada_en is null and a.tipo in ('llamada', 'visita');
  if v_n > 1 then raise exception 'PRUEBA FALLA: % citas vivas tras repetir (esperaba <=1)', v_n; end if;
  v_ok := v_ok || 'cita x2 mismo msg_id = <=1 cita viva (' || v_r1 || '); ';

  -- el rol del bot NO puede leer leads ni notas (la edge solo recibe una palabra, nunca una fila)
  set local role bot_lawang;
  begin perform 1 from public.leads limit 1; raise exception 'PRUEBA FALLA: bot_lawang leyo leads';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.lead_notas limit 1; raise exception 'PRUEBA FALLA: bot_lawang leyo lead_notas';
  exception when insufficient_privilege then null; end;
  reset role;
  v_ok := v_ok || 'bot_lawang no lee leads ni notas; ';

  raise exception 'PRUEBA OK (bloque A): %', v_ok;
end $t$;

-- ═══ BLOQUE B (lanzar en DOS sesiones a la vez; mismo telefono y msg_id) ═══════════════════════════════════════
-- Cada sesion toma el bloqueo por telefono con un upsert, duerme 2 s y acaba en excepcion que devuelve cuanto tardo.
-- Esperado: una tarda ~2 s y la otra ~4 s (espera a que la primera suelte el bloqueo).
-- do $t$ declare t0 timestamptz := clock_timestamp(); r text;
-- begin
--   set local role bot_lawang;
--   r := public.bot_lead_upsert('99955500022', 'Prueba S4 B', 'bot-whatsapp-lawang', 'wamid.PRUEBA-S4-PAR');
--   perform pg_sleep(2);
--   raise exception 'PRUEBA B: % tras % ms', r, round(extract(milliseconds from clock_timestamp() - t0));
-- end $t$;
-- RESULTADO 9-oct-2026: lanzadas por el MCP, las dos tardaron ~2008 ms (el MCP las ejecuto sin solaparse): INCONCLUYENTE. La serializacion
-- queda fijada de forma estructural (bot_api.test.js: el bloqueo va antes que la consulta al log, en las tres funciones) y por el bloque A.
-- La prueba con mensajes simultaneos de verdad es la de S10 (modo sombra), con dos conexiones psql reales.
