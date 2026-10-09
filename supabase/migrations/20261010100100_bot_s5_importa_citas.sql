-- destructivo-ok: solo construye (1 funcion nueva, sin EXECUTE para nadie salvo el propietario de la base). No toca datos existentes.
-- ============================================================================
-- LAWANG — BOT CON CATALOGO EN VIVO Y GESTION DEL CRM — S5 (9-oct-2026): importacion UNICA de las citas vivas de Redis
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261008_lawang_bot_catalogo_crm.md, subtarea S5. Sigue a 20261010100000_bot_s5_agenda_postgres.
--
-- QUE ES: public._bot_importa_citas(p jsonb) recibe la lista que devuelve el bot en GET /admin/api/appts (ids, telefono, cuando, titulo,
-- closer, notas) y crea en lead_accion las que SE PUEDEN casar sin adivinar. Devuelve una fila por cita con el resultado; no inventa nada:
--   sin_telefono · fecha_invalida · ya_importada · pasada (no se importa: no esta viva) · sin_lead · ambiguo (>1 lead con ese telefono: no se elige)
--   · lead_ya_tiene_cita · importada.
--
-- EL DATO TIENE UN DUEÑO: desde el corte, la cita es de lead_accion. La importacion es una COPIA UNICA con marca de origen:
--   origen = 'importado', importada_en = ahora, ref_origen = 'redis:<id de la cita en Redis>'. Esa clave (indice unico parcial
--   lead_accion_ref_origen) hace la funcion REPETIBLE: se ejecuta ahora y otra vez justo antes de encender BOT_CRM=on, y lo ya importado
--   no se duplica. Despues del corte Redis deja de recibir citas del bot y esta funcion ya no tiene nada que hacer.
-- Estado: con closer (la agendo una persona) -> 'confirmada'; sin closer (la agendo el bot con [APPT]) -> 'propuesta'. Tipo: 'visita' si el titulo
--   lo dice, 'llamada' si no. La hora de Redis no lleva zona: se lee como hora de Bali, igual que la pantalla y el bot.
--
-- LLAMADOR CON NOMBRE: supabase/functions/bot-api/importa_citas.py (lo ejecuta una persona con el propietario de la base: MCP o psql).
--   Nace cerrada: sin EXECUTE para anon, authenticated ni service_role.
-- ROLLBACK: drop function public._bot_importa_citas(jsonb);  (las filas importadas se reconocen por origen='importado' y ref_origen 'redis:%')
-- ============================================================================
create or replace function public._bot_importa_citas(p jsonb)
returns table (ref text, resultado text)
language plpgsql security definer set search_path = '' as $f$
declare
  c        jsonb;
  v_ref    text;
  v_e164   text;
  v_s      text;
  v_ts     timestamptz;
  v_loc    timestamp;
  v_ids    uuid[];
  v_lead   uuid;
  v_closer text;
  v_que    text;
  v_resp   text;
begin
  if p is null or jsonb_typeof(p) <> 'array' then
    raise exception 'Se esperaba una lista de citas' using errcode = 'PT400';
  end if;
  for c in select * from jsonb_array_elements(p) loop
    v_ref := 'redis:' || coalesce(nullif(btrim(c->>'id'), ''), '?');
    ref := v_ref;
    v_e164 := public._bot_e164(c->>'phone');
    if v_e164 is null then resultado := 'sin_telefono'; return next; continue; end if;

    v_s := btrim(coalesce(c->>'when', ''));
    if v_s !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)?$' then
      resultado := 'fecha_invalida'; return next; continue;
    end if;
    begin
      if v_s ~ '(Z|[+-]\d{2}(:?\d{2})?)$' then v_ts := v_s::timestamptz;
      else v_ts := v_s::timestamp at time zone 'Asia/Makassar'; end if;
    exception when others then
      resultado := 'fecha_invalida'; return next; continue;
    end;
    v_loc := v_ts at time zone 'Asia/Makassar';

    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bot:' || v_e164, 0));
    if exists (select 1 from public.lead_accion a where a.ref_origen = v_ref) then
      resultado := 'ya_importada'; return next; continue;
    end if;
    if v_ts <= now() then resultado := 'pasada'; return next; continue; end if;

    select coalesce(array_agg(l.id order by l.created_at), '{}') into v_ids
      from public.leads l where public._lw_tel_e164(l.whatsapp) = v_e164;
    if cardinality(v_ids) = 0 then resultado := 'sin_lead'; return next; continue; end if;
    if cardinality(v_ids) > 1 then resultado := 'ambiguo'; return next; continue; end if;
    v_lead := v_ids[1];
    if exists (select 1 from public.lead_accion a
                where a.lead_id = v_lead and a.completada_en is null and a.tipo in ('llamada', 'visita')) then
      resultado := 'lead_ya_tiene_cita'; return next; continue;
    end if;

    v_closer := nullif(btrim(coalesce(c->>'closer', '')), '');
    v_que := left(coalesce(nullif(btrim(regexp_replace(coalesce(c->>'notes', ''), '[[:cntrl:]]', ' ', 'g')), ''),
                           nullif(btrim(regexp_replace(coalesce(c->>'title', ''), '[[:cntrl:]]', ' ', 'g')), ''),
                           'Cita importada del bot'), 280);
    select e.responsable into v_resp from public.lead_estado e where e.lead_id = v_lead;

    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por, tipo, cuando_ts, estado, origen,
                                    decidida_por, decidida_en, ref_origen, importada_en)
    values (v_lead, v_que, v_loc::date, coalesce(v_closer, v_resp, 'bot'), 'importacion-redis',
            case when coalesce(c->>'title', '') ~* '(visita|visit)' then 'visita' else 'llamada' end,
            v_ts, case when v_closer is null then 'propuesta' else 'confirmada' end, 'importado',
            case when v_closer is null then null else v_closer end, case when v_closer is null then null else now() end,
            v_ref, now());
    resultado := 'importada'; return next;
  end loop;
end $f$;

revoke all on function public._bot_importa_citas(jsonb) from public, anon, authenticated, service_role;
