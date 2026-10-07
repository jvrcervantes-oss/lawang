-- LAW-497b (7-oct-2026). Corrige el historial de estado de 20261007035823 (revisor de codigo):
--   1. `after update of estado` solo saltaba si la sentencia nombraba `estado` en su SET. Un
--      cambio hecho por un trigger BEFORE no quedaba apuntado: sincroniza_unidad_contrato hace
--      `set contrato_id = null` y libera_unidad_sin_contrato pasa la parcela a «disponible».
--      Ahora es `after update` sin lista de columnas; el WHEN ve el estado final.
--   2. Una alta (tambien la excepcion del owner directa a «vendida») no dejaba fila. Ahora hay
--      un trigger de alta.
--   3. El filtro de duplicados comparaba solo el estado final: ahora compara antes y despues.
--   4. `via` distingue la tarea programada (pg_cron, libera_reservas_vencidas) de una sesion SQL.
-- Prueba repetible: supabase/pruebas/law497_vendida_exige_suelo.sql.

create or replace function public.trg_unidad_estado_al_historial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes_estado text;
  v_antes        jsonb;
begin
  if tg_op = 'UPDATE' then
    v_antes_estado := old.estado;
    v_antes := to_jsonb(old);
  end if;
  -- unidad_guarda ('ficha', tambien su alta) y unidades_importa ('csv') ya escriben su fila,
  -- con motivo, en esta misma transaccion.
  if exists (select 1 from public.unidades_log l
              where l.unidad_id = new.id and l.en = now()
                and l.antes->>'estado' is not distinct from v_antes_estado
                and l.despues->>'estado' is not distinct from new.estado) then
    return null;
  end if;
  insert into public.unidades_log (unidad_id, antes, despues, motivo, via)
  values (new.id, v_antes, to_jsonb(new),
          case when coalesce(current_setting('app.unidad_estado_excepcion', true), '') = 'on'
               then 'excepcion decidida por el owner' end,
          case when session_user = 'authenticator' then 'automatico'
               when current_setting('application_name', true) = 'pg_cron' then 'tarea programada'
               else 'sql directo' end);
  return null;
end;
$$;

revoke all on function public.trg_unidad_estado_al_historial() from public, anon, authenticated;

-- destructivo-ok: recrea el trigger propio creado hoy en 20261007035823; no borra datos
drop trigger trg_unidad_estado_al_historial on public.unidades;

create constraint trigger trg_unidad_estado_al_historial
  after update on public.unidades
  deferrable initially deferred
  for each row
  when (old.estado is distinct from new.estado)
  execute function public.trg_unidad_estado_al_historial();

create constraint trigger trg_unidad_estado_al_historial_alta
  after insert on public.unidades
  deferrable initially deferred
  for each row
  execute function public.trg_unidad_estado_al_historial();
