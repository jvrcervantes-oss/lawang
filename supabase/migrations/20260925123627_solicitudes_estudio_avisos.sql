-- ════════════════════════════════════════════════════════════════════════════
-- «AL ESTUDIO»: CERRAR EL CÍRCULO POR TELEGRAM — 25-sep-2026
-- Encargo: encargos/20260925_lawang_al_estudio_circulo.md (repo del estudio).
--
-- Owner: «Cuando hago desde Telegram un "Al estudio", ¿hace algo eso?». Hacía la mitad:
-- la petición pasaba a la sesión del estudio, y el owner no volvía a saber de ella. Ahora
-- panel-web le avisa, colgado del mensaje original, cuando el estudio la TOMA y cuando la
-- CIERRA (hecha o rechazada, con la nota).
--
-- · `estudio_avisado`: el último estado del estudio que ya se avisó. La pregunta «¿qué falta
--   por avisar?» es `estudio_avisado is distinct from estado`, así que si entre dos vueltas
--   se tomó y se cerró, sale solo el cierre.
-- · Relleno: lo cerrado por el estudio hace más de un día se da por avisado (no se manda
--   historia vieja al desplegar). SC-24, cerrada hoy, NO: es el primer aviso real.
-- · Dos RPC solo service_role, como el resto del circuito: la tabla no se abre a nadie.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.solicitudes_cambio add column if not exists estudio_avisado text;
-- mismos valores que puede ver el aviso: otro valor nunca casaría con `estado` y avisaría en bucle (Datos #97)
alter table public.solicitudes_cambio add constraint sc_estudio_avisado_valido
  check (estudio_avisado is null or estudio_avisado in ('en_estudio', 'ejecutada', 'rechazada'));

update public.solicitudes_cambio
   set estudio_avisado = estado
 where accion = 'manual' and resuelto_via = 'estudio'
   and resuelto_en < now() - interval '1 day'
   and estudio_avisado is null;

-- Lo que falta por avisar. La nota la escribió una sesión del estudio (≤300, sin PII por
-- regla); panel-web la cita igualmente con su red de PII antes de mandarla.
create or replace function public.solicitudes_estudio_por_avisar()
returns table (id uuid, numero bigint, estado text, telegram_msg_id bigint, nota text)
language sql
stable
security definer
set search_path to ''
as $$
  select s.id, s.numero, s.estado, s.telegram_msg_id, s.resultado->>'nota'
    from public.solicitudes_cambio s
   where s.accion = 'manual'
     and (s.estado = 'en_estudio'
          or (s.estado in ('ejecutada', 'rechazada') and s.resuelto_via = 'estudio'))
     and s.estudio_avisado is distinct from s.estado
   order by s.numero
   limit 20
$$;
revoke execute on function public.solicitudes_estudio_por_avisar() from public, anon, authenticated;
grant execute on function public.solicitudes_estudio_por_avisar() to service_role;

-- Marcar avisado SOLO si el estado sigue siendo el que se avisó: si la cerraron mientras
-- salía el «la está mirando», el cierre queda pendiente para la vuelta siguiente.
create or replace function public.marcar_estudio_avisado(p_id uuid, p_estado text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare v_n int;
begin
  update public.solicitudes_cambio
     set estudio_avisado = p_estado
   where id = p_id and estado = p_estado and accion = 'manual';
  get diagnostics v_n = row_count;
  return v_n = 1;
end
$$;
revoke execute on function public.marcar_estudio_avisado(uuid, text) from public, anon, authenticated;
grant execute on function public.marcar_estudio_avisado(uuid, text) to service_role;
