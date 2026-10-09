-- Vuelve a la firma de S1 (sin `nombre`). Aplicar SOLO si hay que deshacer 20261010160000_bot_sin_redis_s6a_recordar_nombre.sql.
-- La edge y el bot de S6a toleran la ausencia de `nombre` (usan la formula neutra), asi que no hay orden estricto.
drop function if exists public.bot_citas_recordar();
create function public.bot_citas_recordar()
returns table (accion_id uuid, tel text, tipo text, cuando_ts timestamptz, ultimo_entrante_en timestamptz)
language sql security definer set search_path = '' as $f$
  with cand as (
    select a.id
      from public.lead_accion a
      join public.leads l on l.id = a.lead_id
     where a.estado = 'confirmada' and a.tipo in ('llamada', 'visita') and a.completada_en is null
       and a.cuando_ts > now() and a.cuando_ts <= now() + interval '60 minutes'
       and (a.recordatorio_en is null
            or (a.recordatorio_res is null and a.recordatorio_intentos < 2 and a.recordatorio_en < now() - interval '10 minutes'))
       and public._bot_tel(l.whatsapp) is not null
       and not exists (select 1 from public.bot_chat c where c.tel = public._bot_tel(l.whatsapp) and c.baja_en is not null)
     order by a.cuando_ts
     limit 20
     for update of a skip locked),
  tomadas as (
    update public.lead_accion a
       set recordatorio_en = now(), recordatorio_res = null, recordatorio_intentos = a.recordatorio_intentos + 1
      from cand
     where a.id = cand.id
    returning a.id, a.lead_id, a.tipo, a.cuando_ts)
  select t.id, public._bot_tel(l.whatsapp), t.tipo, t.cuando_ts, c.ultimo_entrante_en
    from tomadas t
    join public.leads l on l.id = t.lead_id
    left join public.bot_chat c on c.tel = public._bot_tel(l.whatsapp)
$f$;
revoke all on function public.bot_citas_recordar() from public, anon, authenticated, service_role;
grant execute on function public.bot_citas_recordar() to bot_lawang;
