-- destructivo-ok: solo reemplaza la firma de bot_citas_recordar (drop + create de una funcion sin datos); anade una columna de salida `nombre`. No borra ni vacia filas. Reversion: supabase/reversion_bot_sin_redis_s6a/REVERSION.sql.
-- ============================================================================
-- LAWANG — BOT SIN REDIS — S6a: el recordatorio necesita el NOMBRE de pila del lead (10-oct-2026)
-- Encargo: encargos/20261009_lawang_bot_sin_redis.md (LAW-507), «Recordatorio de cita 1 h antes».
-- La plantilla de Meta lawang_cita_recordatorio lleva {{1}} = nombre de pila; bot_citas_recordar() no lo devolvia. Se anade UNA columna de salida
-- (`nombre`: leads.name, o el nombre del perfil de WhatsApp si el lead no lo tiene; recortado a 80). El resto no cambia: SIN parametro (la ventana de
-- 60 min sigue fijada aqui), solo `confirmada` de tipo llamada/visita, maximo 20, reclamo atomico con SKIP LOCKED, reintento a los 10 min (una vez),
-- sin telefonos con baja. Cambia el tipo de retorno, asi que create or replace no vale: drop + create y se reponen los privilegios (solo bot_lawang).
-- ============================================================================

drop function if exists public.bot_citas_recordar();

create function public.bot_citas_recordar()
returns table (accion_id uuid, tel text, tipo text, cuando_ts timestamptz, ultimo_entrante_en timestamptz, nombre text)
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
  select t.id, public._bot_tel(l.whatsapp), t.tipo, t.cuando_ts, c.ultimo_entrante_en,
         left(coalesce(nullif(btrim(l.name), ''), nullif(btrim(c.nombre_perfil), '')), 80)
    from tomadas t
    join public.leads l on l.id = t.lead_id
    left join public.bot_chat c on c.tel = public._bot_tel(l.whatsapp)
$f$;

revoke all on function public.bot_citas_recordar() from public, anon, authenticated, service_role;
grant execute on function public.bot_citas_recordar() to bot_lawang;
