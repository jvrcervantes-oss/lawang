-- destructivo-ok: el DELETE borra una fila que crea la propia prueba, y todo el bloque se revierte.
-- PRUEBA de lead_publico_alta (27-sep-2026; rehecha el 2-oct-2026 para el reintento de Sumba Hills, migración
-- 20261002053848). Todo se revierte: el bloque acaba en `raise exception 'RES: …'`. Cada punto debe decir «ok».
-- Ejecutar como postgres (execute_sql o `npx supabase db query --linked -f`). Para no necesitar el secreto real, el
-- bloque cambia el hash del Vault por el de 'prueba' (se deshace con todo lo demás) y manda esa cabecera.
do $$
declare
  r text := '';
  e text := 'prueba.lead.' || floor(random() * 1e9)::text || '@example.invalid';
  t timestamptz := date_trunc('second', now() - interval '2 hours');
  n int; v record; v_id uuid; d_alta timestamptz; d_llega timestamptz;
begin
  perform vault.update_secret((select id from vault.secrets where name = 'lead_publico_alta_secreto_sha256'),
                              encode(sha256(convert_to('prueba', 'UTF8')), 'hex'));
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.headers', '{"x-lead-secreto":"prueba"}', true);
  set local role anon;

  -- 1 alta normal (sin p_creado, como el lead.php de antes): entra con ref y recibido_en
  perform public.lead_publico_alta(e, 'Ana Prueba', '+62 812-000', 'sumbahills-web', 'Sumba Hills', '203.0.113.7');
  reset role;
  select l.* into v from public.leads l where l.email = e;
  r := r || '1 ' || case when v.id is not null and v.ref is not null and v.recibido_en is not null and v.whatsapp = '+62812000'
                         then 'ok' else 'FALLO' end || '; ';

  -- 2 reintento con su fecha original: entra con ESA fecha; el segundo envío idéntico no duplica
  set local role anon;
  perform public.lead_publico_alta('r.' || e, 'Reintento', null, 'sumba-hills-qr', null, null, t);
  perform public.lead_publico_alta('r.' || e, 'Reintento', null, 'sumba-hills-qr', null, null, t);
  reset role;
  select count(*), min(created_at), min(recibido_en) into n, d_alta, d_llega from public.leads where email = 'r.' || e;
  r := r || '2 ' || case when n = 1 and d_alta = t and d_llega > now() - interval '1 minute' then 'ok' else 'FALLO n=' || n end || '; ';

  -- 3 gemelo de antes del ref (fila sin ref a 40 s): se le estampa la huella, no se inserta otra
  insert into public.leads (email, source, created_at) values ('g.' || e, 'sumbahills-web', t + interval '40 seconds') returning id into v_id;
  set local role anon;
  perform public.lead_publico_alta('g.' || e, null, null, 'sumbahills-web', null, null, t);
  reset role;
  select count(*) into n from public.leads where email = 'g.' || e;
  r := r || '3 ' || case when n = 1 and (select ref from public.leads where id = v_id) is not null then 'ok' else 'FALLO n=' || n end || '; ';

  -- 4 borrado a propósito: deja tumba y el reintento no lo resucita
  delete from public.leads where id = v_id;
  set local role anon;
  perform public.lead_publico_alta('g.' || e, null, null, 'sumbahills-web', null, null, t);
  reset role;
  select count(*) into n from public.leads where email = 'g.' || e;
  r := r || '4 ' || case when n = 0 then 'ok' else 'FALLO resucita' end || '; ';

  set local role anon;
  -- 5 fecha fuera de rango: se rechaza (LP001), por viejo y por futuro
  begin perform public.lead_publico_alta('v.' || e, null, null, null, null, null, now() - interval '60 days'); r := r || '5a FALLO; ';
  exception when others then r := r || '5a ' || case when sqlstate = 'LP001' then 'ok' else 'FALLO(' || sqlstate || ')' end || '; '; end;
  begin perform public.lead_publico_alta('v.' || e, null, null, null, null, null, now() + interval '1 hour'); r := r || '5b FALLO; ';
  exception when others then r := r || '5b ' || case when sqlstate = 'LP001' then 'ok' else 'FALLO(' || sqlstate || ')' end || '; '; end;

  -- 6 email inválido (22023)
  begin perform public.lead_publico_alta('no-es-un-email'); r := r || '6 FALLO; ';
  exception when others then r := r || '6 ' || case when sqlstate = '22023' then 'ok' else 'FALLO(' || sqlstate || ')' end || '; '; end;

  -- 7 ráfaga real (54000): 3 llegadas del mismo email en la última hora, aunque cada una diga una fecha distinta
  perform public.lead_publico_alta('f.' || e, null, null, null, null, null, t);
  perform public.lead_publico_alta('f.' || e, null, null, null, null, null, t - interval '1 day');
  perform public.lead_publico_alta('f.' || e, null, null, null, null, null, t - interval '2 days');
  begin perform public.lead_publico_alta('f.' || e, null, null, null, null, null, t - interval '3 days'); r := r || '7 FALLO; ';
  exception when others then r := r || '7 ' || case when sqlstate = '54000' then 'ok' else 'FALLO(' || sqlstate || ')' end || '; '; end;

  -- 8 cuarta alta en la hora de SU alta (LP002), aunque haya llegado hace rato: definitivo
  reset role;
  insert into public.leads (email, source, created_at, recibido_en)
  select 'h.' || e, 'sumbahills-web', t - (i || ' minutes')::interval, now() - interval '3 hours' from generate_series(1, 3) i;
  set local role anon;
  begin perform public.lead_publico_alta('h.' || e, null, null, 'sumba-hills-qr', null, null, t); r := r || '8 FALLO; ';
  exception when others then r := r || '8 ' || case when sqlstate = 'LP002' then 'ok' else 'FALLO(' || sqlstate || ')' end || '; '; end;

  -- 9 canal en lista cerrada: uno que imita a Meta queda como «desconocido»
  perform public.lead_publico_alta('c.' || e, null, null, 'meta-sumbahills');
  reset role;
  r := r || '9 ' || case when (select source from public.leads where email = 'c.' || e) = 'sumbahills-desconocido' then 'ok' else 'FALLO' end || '; ';

  -- 10 sin secreto: 42501
  perform set_config('request.headers', '{}', true);
  set local role anon;
  begin perform public.lead_publico_alta('s.' || e); r := r || '10 FALLO; ';
  exception when others then r := r || '10 ' || case when sqlstate = '42501' then 'ok' else 'FALLO(' || sqlstate || ')' end || '; '; end;

  -- 11 anon no escribe en leads a pelo ni lee las tumbas
  begin insert into public.leads (email, campaign_id) values ('directo.' || e, 'falsa'); r := r || '11a FALLO abierto; ';
  exception when others then r := r || '11a ok; '; end;
  begin perform 1 from public.leads_borrados limit 1; r := r || '11b FALLO lee tumbas; ';
  exception when others then r := r || '11b ok; '; end;

  -- 12 authenticated no ejecuta la RPC
  reset role;
  set local role authenticated;
  begin perform public.lead_publico_alta('auth.' || e); r := r || '12 FALLO; ';
  exception when others then r := r || '12 ok; '; end;

  -- 13 alta SIN fecha (huella con el now() de la base) y reintento con la marca del CSV un segundo antes: es el
  --    mismo alta, no un duplicado (revisor-codigo 2-oct; daba n=2 antes de 20261002054801)
  reset role;
  perform set_config('request.headers', '{"x-lead-secreto":"prueba"}', true);
  set local role anon;
  perform public.lead_publico_alta('s1.' || e, null, null, 'sumbahills-web');
  reset role;
  select created_at into d_alta from public.leads where email = 's1.' || e;
  set local role anon;
  perform public.lead_publico_alta('s1.' || e, null, null, 'sumbahills-web', null, null, d_alta - interval '1 second');
  reset role;
  select count(*) into n from public.leads where email = 's1.' || e;
  r := r || '13 ' || case when n = 1 then 'ok' else 'FALLO n=' || n end || '; ';

  raise exception 'RES: %', r;
end $$;
