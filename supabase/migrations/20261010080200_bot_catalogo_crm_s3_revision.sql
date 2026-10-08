-- destructivo-ok: drop function crm_leads() solo para recrearla con 4 columnas mas (cita_*), mismos permisos; accion_* conserva su contrato (solo la TAREA). Sin datos que perder.
-- S3 (9-oct-2026), tercera parte, tras la revision del revisor de codigo:
--   1. crm_leads: accion_* es SIEMPRE la tarea (el formulario de la intranet la precarga y la guarda con crm_lead_accion_poner); la cita del bot sale aparte en cita_id/cita_tipo/cita_cuando_ts/cita_estado.
--   2. service_role pierde el EXECUTE de las funciones del bot (el llamador con nombre es solo bot_lawang).
--   3. bot_lead_upsert: tope por lead y dia de 40 -> 500 (el upsert queda registrado en cada mensaje; con 40 un chat largo dejaba de reconocerse).

drop function if exists public.crm_leads();
create function public.crm_leads()
returns table (id uuid, created_at timestamptz, source text, name text, campaign_id text, respuestas jsonb, tiene_email boolean,
               tiene_whatsapp boolean, estado text, estado_desde timestamptz, responsable text, notas bigint, sugerencia text,
               sugerencia_contrato text, accion_id uuid, accion_que text, accion_cuando date, accion_responsable text,
               contrato_id uuid, contrato_numero text, dueno text, dueno_nombre text, dueno_activo boolean,
               cita_id uuid, cita_tipo text, cita_cuando_ts timestamptz, cita_estado text)
language sql stable security definer set search_path = '' as $f$
  select l.id, l.created_at, l.source, l.name, l.campaign_id,
         coalesce((select jsonb_object_agg(k, v)
                     from jsonb_each(coalesce(l.respuestas, '{}'::jsonb)) as r(k, v)
                    where k in ('budget_range','buy_timeline','budget','purpose')),
                  '{}'::jsonb),
         nullif(btrim(coalesce(l.email, '')), '') is not null,
         nullif(btrim(coalesce(l.whatsapp, '')), '') is not null,
         coalesce(e.estado, 'nuevo'),
         coalesce(e.estado_desde, l.created_at),
         e.responsable,
         (select count(*) from public.lead_notas n where n.lead_id = l.id),
         s.etapa, s.contrato_numero,
         a.id, a.que, a.cuando, a.responsable,
         v.contrato_id, v.numero,
         e.responsable, u.nombre,
         case when e.responsable is null then null else coalesce(u.activo, false) end,
         c.id, c.tipo, c.cuando_ts, c.estado
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join public.lead_sugerencia s on s.lead_id = l.id
    left join public.lead_accion a on a.lead_id = l.id and a.completada_en is null and a.tipo = 'tarea'
    left join public.lead_accion c on c.lead_id = l.id and c.completada_en is null and c.tipo in ('llamada', 'visita')
    left join public.usuarios u on lower(u.email) = lower(e.responsable)
    left join lateral (
      select k.contrato_id, c2.numero
        from public.lead_contrato k
        join public.contratos c2 on c2.id = k.contrato_id
       where k.lead_id = l.id order by k.cuando desc limit 1
    ) v on true
   where public.puede('leads')
     -- El alcance se aplica AQUI y no en el navegador: filtrar en el cliente es ensenar
     -- menos, no entregar menos, y los 108 seguirian viajando al navegador de quien solo
     -- debe ver 49.
     and public.lead_a_mi_alcance(l.id);
$f$;

revoke all on function public.crm_leads() from public, anon;
grant execute on function public.crm_leads() to authenticated;

revoke all on function public.bot_catalogo_leer() from service_role;
revoke all on function public.bot_lead_upsert(text, text, text, text) from service_role;
revoke all on function public.bot_lead_nota(text, text, text) from service_role;
revoke all on function public.bot_lead_cita(text, text, text, text) from service_role;
revoke all on function public._bot_e164(text) from service_role;
revoke all on function public._bot_log(text, uuid, text, text, text) from service_role;
revoke all on function public._bot_nota_ambiguo(uuid[], text) from service_role;
revoke all on function public.proyectos_bot_publico_sello() from service_role;
revoke all on function public.bot_acciones_log_solo_anade() from service_role;

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
         where l.lead_id = v_lead and l.accion = 'upsert' and l.cuando > now() - interval '24 hours') >= 500 then
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
