-- ════════════════════════════════════════════════════════════════════════════
-- LAW-259 — libera_reserva solo liberaba 1 parcela por contrato — 22-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Un contrato puede tener varias unidades reservadas a la vez (CR00025 tiene
-- hoy 3, RP00159 tiene 5). El guard de idempotencia (`contratos.liberado_en`)
-- se estampaba tras liberar la PRIMERA unidad, así que la 2ª/3ª llamada
-- (el cron `libera-reservas-vencidas` itera una vez por unidad reservada, no
-- una vez por contrato) devolvía éxito mudo sin tocar nada — y el edge
-- function la contaba como "emitida" cuando seguía 'reservada' en la base.
--
-- Verificado antes de este fix: 0 eventos 'reserva_liberada' existen hoy y 0
-- contratos tienen liberado_en con parcelas aún reservadas colgando — el bug
-- no ha mordido todavía. CR00025 vence el 2026-09-24 (fecha_pago_reserva
-- 2026-08-24 + validez_meses 1): sin este fix, el 24-sep el cron liberaría 1
-- de sus 3 parcelas y contaría las otras 2 como liberadas sin estarlo.
--
-- Fix: UN UPDATE atómico libera TODAS las unidades 'reservada' del contrato a
-- la vez, ANTES de estampar liberado_en. El NOT EXISTS de blindaje contra un
-- Bloqueo de Parcela vivo se conserva tal cual, correlacionado por fila (ya lo
-- era; sigue siéndolo con varias filas en el mismo UPDATE). El permiso de
-- 'desistida' se valida contra el proyecto_id de CADA unidad que el UPDATE
-- toca de verdad (antes solo contra la unidad pasada en p_unidad_id) — hoy 0
-- contratos mezclan proyectos, pero nada lo garantizaba. El detalle del
-- evento 'reserva_liberada' pasa a llevar el array completo de unidades.
--
-- p_unidad_id se mantiene en la firma por compatibilidad con los llamantes
-- existentes (app.html, el edge function) pero deja de usarse para acotar el
-- UPDATE: ahora cualquier llamada sobre un contrato libera TODO lo suyo, así
-- que el cron, al iterar unidad por unidad del mismo contrato, hace el trabajo
-- real en la 1ª pasada y las siguientes caen en la idempotencia — ya sin
-- mentir, porque para entonces todo está genuinamente liberado.
--
-- Verificado en transacción ROLLBACK contra CR00025 (3 parcelas reales,
-- Palm Field W5): manager de OTRO proyecto → rechazado, 3 siguen 'reservada';
-- manager del proyecto correcto → las 3 pasan a 'disponible' en una sola
-- llamada, 1 solo evento con los 3 ids; una 2ª llamada sobre una unidad
-- hermana (simulando el resto del bucle del cron) no duplica el evento.
create or replace function public.libera_reserva(p_unidad_id uuid, p_contrato_id uuid, p_motivo text, p_nota text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_quien  text;
  v_ids    uuid[];
begin
  if p_motivo not in ('vencida_reserva', 'desistida') then
    raise exception 'Motivo de liberación no reconocido: %', p_motivo using errcode = '22023';
  end if;

  -- idempotencia: ya liberado, no hay nada más que hacer (ni falla ni repite)
  if exists (select 1 from public.contratos where id = p_contrato_id and liberado_en is not null) then
    return;
  end if;

  if p_motivo = 'vencida_reserva' then
    if (select auth.uid()) is not null then
      raise exception 'vencida_reserva solo la aplica el automatismo (cron); esto es una sesión de usuario.'
        using errcode = '42501';
    end if;
  else -- desistida
    if p_nota is null or btrim(p_nota) = '' then
      raise exception 'Liberar por desistimiento exige una nota.' using errcode = '23514';
    end if;

    -- el permiso se valida contra el proyecto de CADA unidad que este
    -- contrato tiene reservada de verdad, no solo la que se pasó por parámetro
    if not (
      public.es_admin()
      or (
        exists (
          select 1 from public.usuarios uu
           where uu.user_id = (select auth.uid()) and uu.activo and uu.rol = 'sales_manager'
        )
        and not exists (
          select 1 from public.unidades u2
           where u2.contrato_id = p_contrato_id
             and u2.estado = 'reservada'
             and not public.es_manager_de(u2.proyecto_id)
        )
      )
    ) then
      raise exception 'No tienes permiso para liberar esta reserva por desistimiento.' using errcode = '42501';
    end if;
  end if;

  v_quien := coalesce(public._quien_actua(), 'cron:libera-reservas-vencidas');

  -- la contraseña que abre el candado del trigger de blindaje (_protege_liberado_contrato),
  -- solo para el UPDATE de contratos de más abajo, solo esta transacción
  perform set_config('app.via_libera_reserva', 'on', true);

  -- ── el UPDATE que valida Y libera TODAS las unidades del contrato a la vez ──
  with liberadas as (
    update public.unidades u
       set estado = 'disponible',
           contrato_liberado_id = p_contrato_id,
           contrato_id = null
     where u.contrato_id = p_contrato_id
       and u.estado = 'reservada'
       and not exists (
         select 1 from public.contratos rp
          where rp.tipo = 'reserva_parcela'
            and rp.liberado_en is null
            and rp.id in (
              u.contrato_id,
              (select c2.contrato_padre_id from public.contratos c2 where c2.id = p_contrato_id)
            )
       )
     returning u.id
  )
  select array_agg(id) into v_ids from liberadas;

  if v_ids is null or array_length(v_ids, 1) is null then
    raise exception
      'No se pudo liberar ninguna unidad del contrato %: no hay parcelas reservadas por él, o existe un Bloqueo de Parcela vivo sobre ellas.',
      p_contrato_id using errcode = 'P0001';
  end if;

  update public.contratos
     set liberado_en = now(),
         liberado_motivo = p_motivo
   where id = p_contrato_id;

  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'reserva_liberada',
          jsonb_build_object('motivo', p_motivo, 'nota', p_nota, 'unidades_ids', to_jsonb(v_ids)),
          v_quien);
end;
$$;
