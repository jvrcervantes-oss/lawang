-- Prueba de la edge bot-api S2 (rutas /estado, /recordatorio y /humano) contra la BASE REAL, con el rol real bot_lawang.
-- Ejecuta LITERALMENTE las 14 sentencias SQL de supabase/functions/bot-api/index.ts (el test bot_api.test.js comprueba que siguen
-- siendo identicas) con parametros de tipo texto, que es como las manda el driver, y comprueba que la forma de cada respuesta es la
-- que la edge espera. Lo que un doble de la base no ve: una firma o un cast equivocado solo falla aqui.
-- Se ejecuta con el MCP (execute_sql) o psql como postgres, en UNA sola llamada. NO deja rastro: todo ocurre en un DO que acaba SIEMPRE en
-- una excepcion (rollback). Si todo va bien el mensaje empieza por «PRUEBA OK»; si algo falla, por «PRUEBA FALLA» y dice cual.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo toca filas sembradas aqui mismo.
do $t$
declare
  v_ok text := '';
  j jsonb; r text; rec record; n int;
  t constant text := '99966600001';
  l uuid; a uuid; hasta bigint;
begin
  -- /estado · mensaje_recibir
  set local role bot_lawang;
  execute 'select public.bot_mensaje_recibir($1::text, $2::text, $3::text, $4::text::jsonb) as r' into j
    using t, 'wamid.S2-1', 'Prueba S2', '{"texto":"hola quiero una villa","media":null,"ts":1760000000}';
  reset role;
  if not (j ? 'duplicado' and j ? 'procesado') or (j->>'duplicado')::boolean then raise exception 'PRUEBA FALLA: mensaje_recibir devolvio %', j; end if;
  v_ok := v_ok || 'mensaje_recibir; ';

  -- el lead lo crea la ruta /crm (ya probada en bot_api_s4.sql): aqui solo hace falta que exista para el resumen y el recordatorio
  set local role bot_lawang;
  execute 'select public.bot_lead_upsert($1::text, $2::text, $3::text, $4::text) as r' into r using t, 'Prueba S2', 'bot-whatsapp-lawang', 'wamid.S2-1';
  reset role;
  if r not in ('creado', 'existente') then raise exception 'PRUEBA FALLA: lead_upsert devolvio %', r; end if;

  -- turno_estado
  set local role bot_lawang;
  execute 'select public.bot_turno_estado($1::text, $2::boolean) as r' into j using t, 'true';
  reset role;
  if not (j ? 'baja' and j ? 'pausado' and j ? 'esperando' and j ? 'avisar_testing' and j ? 'primer_turno' and j ? 'historial' and j ? 'config') then
    raise exception 'PRUEBA FALLA: turno_estado sin las claves que la edge exige: %', j; end if;
  if not (j->'config' ? 'extra' and j->'config' ? 'bienvenida' and j->'config' ? 'pausa_horas' and j->'config' ? 'resumen_cada_n'
          and j->'config' ? 'fallos_alarma' and j->'config' ? 'version' and j->'config' ? 'actualizado_en') then
    raise exception 'PRUEBA FALLA: turno_estado.config incompleta: %', j->'config'; end if;
  v_ok := v_ok || 'turno_estado; ';

  -- turno_cerrar
  set local role bot_lawang;
  execute 'select public.bot_turno_cerrar($1::text, $2::text, $3::text::jsonb, $4::text, $5::text, $6::boolean, $7::boolean) as r' into j
    using t, 'wamid.S2-1', '[{"texto":"Hola, soy el asistente","media":null,"wamid":"wamid.S2-OUT1"}]', 'interested', 'interested', 'false', 'true';
  reset role;
  if not (j ? 'avisar' and j ? 'resumir' and j ? 'repetido') or (j->>'repetido')::boolean then raise exception 'PRUEBA FALLA: turno_cerrar devolvio %', j; end if;
  set local role bot_lawang;
  execute 'select public.bot_turno_cerrar($1::text, $2::text, $3::text::jsonb, $4::text, $5::text, $6::boolean, $7::boolean) as r' into j
    using t, 'wamid.S2-1', '[]', null::text, null::text, 'false', 'false';
  reset role;
  if not (j->>'repetido')::boolean then raise exception 'PRUEBA FALLA: el cierre repetido no se reconoce: %', j; end if;
  v_ok := v_ok || 'turno_cerrar x2; ';

  -- eco_operadora (horas como texto -> int)
  set local role bot_lawang;
  execute 'select public.bot_eco_operadora($1::text, $2::text, $3::text, $4::int) as r' into j using t, 'wamid.S2-ECO', 'te llamo ahora', '2';
  reset role;
  if not (j ? 'duplicado' and j ? 'estaba_pausado') then raise exception 'PRUEBA FALLA: eco_operadora devolvio %', j; end if;
  v_ok := v_ok || 'eco_operadora; ';

  -- pausar (/estado)
  set local role bot_lawang;
  execute 'select public.bot_pausar($1::text, $2::text, $3::int) as r' into j using t, 'quitar', null::text;
  reset role;
  if not (j ? 'pausado' and j ? 'hasta') then raise exception 'PRUEBA FALLA: pausar devolvio %', j; end if;
  v_ok := v_ok || 'pausar; ';

  -- entrega_fallida (texto)
  set local role bot_lawang;
  execute 'select public.bot_entrega_fallida($1::text, $2::text, $3::text) as r' into r using t, '131047', 'Re-engagement message';
  reset role;
  if r <> 'ok' then raise exception 'PRUEBA FALLA: entrega_fallida devolvio %', r; end if;
  v_ok := v_ok || 'entrega_fallida; ';

  -- escalar + escalacion_tomar (excepcion 1)
  set local role bot_lawang;
  execute 'select public.bot_escalar($1::text, $2::text, $3::text, $4::text) as r' into j using t, 'Prueba S2', 'cuanto cuesta la parcela 3?', 'wamid.S2-AVISO';
  reset role;
  if not (j ? 'id') or j->>'id' is null then raise exception 'PRUEBA FALLA: escalar devolvio %', j; end if;
  set local role bot_lawang;
  execute 'select public.bot_escalacion_tomar($1::text) as r' into j using 'wamid.S2-AVISO';
  reset role;
  if j->>'tel' <> t or not (j ? 'nombre' and j ? 'pregunta') then raise exception 'PRUEBA FALLA: escalacion_tomar devolvio %', j; end if;
  set local role bot_lawang;
  execute 'select public.bot_escalacion_tomar($1::text) as r' into j using null::text;
  reset role;
  if j <> '{}'::jsonb then raise exception 'PRUEBA FALLA: sin escalaciones abiertas esperaba {} y devolvio %', j; end if;
  v_ok := v_ok || 'escalar+tomar; ';

  -- lead_resumen (hasta_id como texto -> bigint)
  select max(id) into hasta from public.bot_mensaje where tel = t;
  set local role bot_lawang;
  execute 'select public.bot_lead_resumen($1::text, $2::text, $3::bigint) as r' into r using t, 'Quiere una villa; pidio precio.', hasta::text;
  reset role;
  if r <> 'ok' then raise exception 'PRUEBA FALLA: lead_resumen devolvio % (esperaba ok)', r; end if;
  set local role bot_lawang;
  execute 'select public.bot_lead_resumen($1::text, $2::text, $3::bigint) as r' into r using t, 'Quiere una villa; pidio precio.', hasta::text;
  reset role;
  if r <> 'ya_hecho' then raise exception 'PRUEBA FALLA: lead_resumen repetido devolvio % (esperaba ya_hecho)', r; end if;
  v_ok := v_ok || 'lead_resumen; ';

  -- baja (STOP)
  set local role bot_lawang;
  execute 'select public.bot_baja($1::text, $2::text) as r' into j using '99966600002', 'wamid.S2-STOP';
  reset role;
  if j->>'baja' not in ('nueva', 'ya_dada') or not (j ? 'pausado') then raise exception 'PRUEBA FALLA: baja devolvio %', j; end if;
  v_ok := v_ok || 'baja; ';

  -- /recordatorio · una cita confirmada dentro de la proxima hora del lead de arriba
  select id into l from public.leads where public._bot_tel(whatsapp) = t order by created_at limit 1;
  insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen)
  values (l, 'cita S2', current_date, 'x@x', 'x@x', 'llamada', now() + interval '30 minutes', 'confirmada', 'humano') returning id into a;
  set local role bot_lawang;
  execute 'select accion_id, tel, tipo, cuando_ts, ultimo_entrante_en, nombre from public.bot_citas_recordar()' into rec;
  reset role;
  if rec.accion_id is distinct from a or rec.tel <> t or rec.tipo <> 'llamada' or rec.cuando_ts is null or length(coalesce(rec.nombre, '')) > 80 then raise exception 'PRUEBA FALLA: citas_recordar devolvio %', rec; end if;
  set local role bot_lawang;
  execute 'select public.bot_cita_recordatorio_res($1::uuid, $2::text) as r' into r using a::text, 'enviado';
  reset role;
  if r <> 'ok' then raise exception 'PRUEBA FALLA: cita_recordatorio_res devolvio %', r; end if;
  v_ok := v_ok || 'citas_recordar+res; ';

  -- /humano · el usuario llega como texto (el del JWT verificado)
  set local role bot_lawang;
  execute 'select public.bot_pausar_humano($1::text, $2::text, $3::text) as r' into j using t, 'pausar', 'ana@lawang.com';
  reset role;
  if not (j ? 'pausado' and j ? 'hasta') then raise exception 'PRUEBA FALLA: pausar_humano devolvio %', j; end if;
  select count(*) into n from public.bot_chat where tel = t and pausa_por = 'ana@lawang.com' and pausado;
  if n <> 1 then raise exception 'PRUEBA FALLA: la pausa no quedo a nombre del usuario recibido'; end if;
  set local role bot_lawang;
  execute 'select public.bot_envio_humano($1::text, $2::text, $3::text, $4::text::jsonb, $5::text) as r' into j
    using t, 'Hola, soy Ana', 'wamid.S2-HUM1', '{"tipo":"document","id":"m-9"}', 'ana@lawang.com';
  reset role;
  if (j->>'ok')::boolean is not true then raise exception 'PRUEBA FALLA: envio_humano devolvio %', j; end if;
  select count(*) into n from public.bot_mensaje where tel = t and por = 'humano' and por_usuario = 'ana@lawang.com' and media = '{"tipo":"document","id":"m-9"}'::jsonb;
  if n <> 1 then raise exception 'PRUEBA FALLA: el mensaje humano no quedo a nombre del usuario recibido'; end if;
  v_ok := v_ok || 'humano pausar+enviar; ';

  raise exception 'PRUEBA OK (rollback): %', v_ok;
end $t$;
