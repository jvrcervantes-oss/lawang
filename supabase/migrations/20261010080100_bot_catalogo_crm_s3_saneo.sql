-- destructivo-ok: solo construye. Reemplaza con create or replace (misma firma, mismos permisos) bot_lead_upsert y bot_lead_nota para colapsar espacios repetidos tras quitar los caracteres de control, y concede a postgres el SET ROLE bot_lawang para poder probar con el rol real (no da ningun permiso nuevo al bot).
-- S3 (9-oct-2026), segunda parte: lo que la prueba supabase/pruebas/bot_s3.sql sacó a la luz.
grant bot_lawang to postgres with set true;

create or replace function public.bot_lead_upsert(
  p_tel text, p_nombre text default null, p_origen text default 'bot-whatsapp-lawang', p_msg_id text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164   text := public._bot_e164(p_tel);
  v_msg    text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_nombre text := nullif(left(btrim(regexp_replace(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', ' ', 'g'), ' {2,}', ' ', 'g')), 80), '');
  v_origen text := case when p_origen in ('bot-whatsapp-lawang', 'bot-whatsapp-sumbahills') then p_origen else 'bot-whatsapp-lawang' end;
  v_prev   text;
  v_ids    uuid[];
  v_lead   uuid;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if v_msg is not null then
    select l.resultado into v_prev from public.bot_acciones_log l where l.accion = 'upsert' and l.msg_id = v_msg;
    if found then return v_prev; end if;
  end if;

  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
    from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;

  if cardinality(v_ids) > 1 then
    perform public._bot_nota_ambiguo(v_ids, 'alta');
    perform public._bot_log('upsert', null, v_msg, 'ambiguo', 'n=' || cardinality(v_ids));
    return 'ambiguo';
  end if;

  if cardinality(v_ids) = 1 then
    v_lead := v_ids[1];
    if (select count(*) from public.bot_acciones_log l
         where l.lead_id = v_lead and l.accion = 'upsert' and l.cuando > now() - interval '24 hours') >= 40 then
      return 'tope';
    end if;
    if v_nombre is not null then
      update public.leads set name = v_nombre where id = v_lead and name is null;   -- solo rellena un hueco, nunca pisa
    end if;
    perform public._bot_log('upsert', v_lead, v_msg, 'existente');
    return 'existente';
  end if;

  if (select count(*) from public.bot_acciones_log l
       where l.accion = 'upsert' and l.resultado = 'creado' and l.cuando > now() - interval '1 hour') >= 60 then
    return 'tope';
  end if;
  insert into public.leads (whatsapp, name, source) values (v_e164, v_nombre, v_origen) returning id into v_lead;
  perform public._bot_log('upsert', v_lead, v_msg, 'creado');
  return 'creado';
end $f$;

create or replace function public.bot_lead_nota(p_tel text, p_texto text, p_msg_id text default null)
returns text language plpgsql security definer set search_path = '' as $f$
declare
  v_e164  text := public._bot_e164(p_tel);
  v_msg   text := nullif(left(btrim(coalesce(p_msg_id, '')), 120), '');
  v_texto text := left(btrim(regexp_replace(regexp_replace(coalesce(p_texto, ''), '[[:cntrl:]]', ' ', 'g'), ' {2,}', ' ', 'g')), 500);
  v_prev  text;
  v_ids   uuid[];
  v_lead  uuid;
begin
  if v_e164 is null then return 'telefono_invalido'; end if;
  if v_texto = '' then return 'vacio'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
  if v_msg is not null then
    select l.resultado into v_prev from public.bot_acciones_log l where l.accion = 'nota' and l.msg_id = v_msg;
    if found then return v_prev; end if;
  end if;

  select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
    from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;
  if cardinality(v_ids) = 0 then return 'sin_lead'; end if;
  if cardinality(v_ids) > 1 then
    perform public._bot_nota_ambiguo(v_ids, 'nota');
    perform public._bot_log('nota', null, v_msg, 'ambiguo', 'n=' || cardinality(v_ids));
    return 'ambiguo';
  end if;

  v_lead := v_ids[1];
  if (select count(*) from public.bot_acciones_log l
       where l.lead_id = v_lead and l.accion = 'nota' and l.resultado = 'ok' and l.cuando > now() - interval '24 hours') >= 30 then
    return 'tope';
  end if;
  insert into public.lead_notas (lead_id, texto, autor) values (v_lead, v_texto, 'bot');
  perform public._bot_log('nota', v_lead, v_msg, 'ok');
  return 'ok';
end $f$;
