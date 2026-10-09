-- Prueba de la migracion 20261010180000_bot_pausa_manual_72h (LAW-515, 9-oct-2026). Se ejecuta como postgres DESPUES de aplicar la migracion.
-- Todo dentro de un DO que acaba SIEMPRE en excepcion (rollback). «PRUEBA OK: ...» si todo va bien; «PRUEBA FALLA: ...» si no.
-- Telefonos sembrados 999777003xx. La llamada de /humano se hace con el rol real bot_lawang.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); los update/delete (incluida bot_purga) se deshacen.
do $t$
declare
  v_ok text := ''; j jsonb; h timestamptz; r timestamptz; n int; v_cfg int;
  t1 constant text := '99977700301'; t2 constant text := '99977700302'; t3 constant text := '99977700303';
  t4 constant text := '99977700304'; t5 constant text := '99977700305'; t6 constant text := '99977700306'; t7 constant text := '99977700307';
begin
  if (select prosrc from pg_proc where proname = 'bot_purga' and pronamespace = 'public'::regnamespace) not like '%consent_estado%' then
    raise exception 'PRUEBA FALLA: bot_purga viva no es la de S12'; end if;
  select pausa_horas into v_cfg from public.bot_config;
  update public.bot_config set pausa_horas = 0;
  insert into public.bot_chat (tel, actividad_en) values (t1, now()), (t2, now()), (t3, now()), (t7, now());
  insert into public.bot_chat (tel, actividad_en, baja_en, baja_acuse_en, pausado, pausa_por) values (t4, now(), now(), now(), true, 'baja');
  insert into public.bot_chat (tel, actividad_en, pausado, pausa_hasta, pausa_por) values (t5, now(), true, null, 'heredada');

  -- A. persona desde la intranet, con el rol real, pausa_horas = 0 -> 72 h
  set local role bot_lawang;
  j := public.bot_pausar_humano(t1, 'pausar', 'ana@x');
  reset role;
  r := (j->>'hasta')::timestamptz;
  if not (j->>'pausado')::boolean or r is null or r < now() + interval '71 hours 59 minutes' or r > now() + interval '72 hours 1 minute' then
    raise exception 'PRUEBA FALLA: pausar con pausa_horas=0 no da 72 h: %', j; end if;
  set local role bot_lawang;
  j := public.bot_pausar_humano(t1, 'quitar', 'ana@x');
  reset role;
  if (j->>'pausado')::boolean or (j->>'hasta') is not null then raise exception 'PRUEBA FALLA: quitar: %', j; end if;
  v_ok := v_ok || 'pausar manual = 72 h y quitar la libera; ';

  -- B. tope y config propia (respeta lo que el owner configuro)
  update public.bot_config set pausa_horas = 10;
  j := public.bot_pausar_humano(t1, 'pausar', 'ana@x');
  if (j->>'hasta')::timestamptz > now() + interval '10 hours 1 minute' or (j->>'hasta')::timestamptz < now() + interval '9 hours 59 minutes' then
    raise exception 'PRUEBA FALLA: no respeta pausa_horas=10: %', j; end if;
  update public.bot_config set pausa_horas = 0;
  v_ok := v_ok || 'respeta pausa_horas configurado; ';

  -- C. eco de la operadora (via _bot_pausa_humana)
  h := public._bot_pausa_humana(t2, null, 'op');
  if h < now() + interval '71 hours 59 minutes' or h > now() + interval '72 hours 1 minute' then raise exception 'PRUEBA FALLA: eco 0 -> %', h; end if;
  r := public._bot_pausa_humana(t2, 1, 'op');
  if r < h then raise exception 'PRUEBA FALLA: un eco acorto una pausa vigente'; end if;
  h := public._bot_pausa_humana(t3, 5, 'op');
  if h > now() + interval '5 hours 1 minute' or h < now() + interval '4 hours 59 minutes' then raise exception 'PRUEBA FALLA: p_horas=5 -> %', h; end if;
  h := public._bot_pausa_humana(t7, 0, 'op');
  if h < now() + interval '71 hours 59 minutes' then raise exception 'PRUEBA FALLA: p_horas=0 explicito sigue indefinido'; end if;
  v_ok := v_ok || 'eco 72 h, no acorta, p_horas explicito vale; ';

  -- D. la baja no se toca; la pausa fija heredada tampoco
  if public._bot_pausa_humana(t4, null, 'op') is not null then raise exception 'PRUEBA FALLA: toco una baja'; end if;
  j := public.bot_pausar_humano(t4, 'quitar', 'ana@x');
  if not exists (select 1 from public.bot_chat where tel = t4 and pausado and pausa_hasta is null and baja_en is not null) then raise exception 'PRUEBA FALLA: la baja cambio'; end if;
  if public._bot_pausa_humana(t5, null, 'op') is not null or exists (select 1 from public.bot_chat where tel = t5 and pausa_hasta is not null) then
    raise exception 'PRUEBA FALLA: el eco volvio caducable una pausa fija heredada'; end if;
  v_ok := v_ok || 'baja intacta, pausa fija heredada intacta; ';

  -- E. purga: pausa caducada ya no se conserva; baja si (reducida a marca)
  insert into public.bot_chat (tel, nombre_perfil, ultimo_mensaje, actividad_en, pausado, pausa_hasta, pausa_por) values (t6, 'Cad', 'hola', now() - interval '400 days', true, now() - interval '300 days', 'ana@x');
  update public.bot_chat set actividad_en = now() - interval '400 days', nombre_perfil = 'Baja', ultimo_mensaje = 'stop' where tel = t4;
  update public.bot_chat set actividad_en = now() - interval '400 days' where tel = t5;
  perform public.bot_purga();
  if exists (select 1 from public.bot_chat where tel = t6) then raise exception 'PRUEBA FALLA: la purga conservo una pausa caducada'; end if;
  if exists (select 1 from public.bot_chat where tel = t5) then raise exception 'PRUEBA FALLA: la purga conservo una pausa fija inactiva 400 d'; end if;
  if not exists (select 1 from public.bot_chat where tel = t4 and baja_en is not null and nombre_perfil is null and ultimo_mensaje is null) then
    raise exception 'PRUEBA FALLA: la baja no quedo como marca reducida'; end if;
  v_ok := v_ok || 'purga: solo bajas (reducidas), pausas no; ';

  raise exception 'PRUEBA OK: %', v_ok;
end $t$;
