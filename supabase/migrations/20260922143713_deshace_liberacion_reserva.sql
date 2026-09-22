-- ════════════════════════════════════════════════════════════════════════════
-- DESHACER LIBERACIÓN DE UNA CARTA DE RESERVA — 22-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Owner: el cron del 22-sep (04:00, sin gracia todavía) liberó B3 (CR00024) y
-- S1-H9 (CR00049) con los compradores aún en ello; el equipo puso las parcelas
-- a mano en «reservada» sin contrato detrás, y una Carta liberada no se puede
-- prorrogar. Salida elegida: «deshacer liberación», solo admin, que devuelve la
-- Carta a viva, re-engancha sus parcelas y, en el MISMO acto, la prorroga (si
-- no, volvería a estar vencida y el cron la liberaría otra vez tras la gracia).
-- Solo si ninguna de sus parcelas la ocupa hoy otro contrato vivo (C1/CR00060
-- ya es el Bloqueo RP00198: ahí no hay nada que deshacer).
-- Aplicado el mismo día a CR00024 y CR00049 (15 días de prórroga cada una).
-- destructivo-ok: el CHECK de contrato_eventos se recrea con la lista viva +
-- 'reserva_liberacion_deshecha'; no se borra ningún dato.
-- ════════════════════════════════════════════════════════════════════════════
alter table public.contrato_eventos drop constraint if exists contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array['creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta',
    'firma_recogida','firma_anulada','firmado_del_todo','desbloqueado','traspaso',
    'editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear',
    'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha','factura_borrada',
    'contrato_borrado','reserva_liberada','reserva_prorrogada','reserva_liberacion_deshecha']));

create or replace function public.deshace_liberacion(
  p_contrato_id uuid, p_motivo text, p_dias int default null, p_comunicado boolean default false
)
returns date
language plpgsql security definer set search_path to '' as $$
declare
  c        public.contratos%rowtype;
  v_ocup   text;
  v_n      int;
  v_vence  date;
  v_hasta  date;
  v_quien  text;
  v_ids    uuid[];
begin
  if not public.es_admin() then
    raise exception 'Deshacer una liberación exige admin.' using errcode = '42501';
  end if;
  if p_motivo is null or length(btrim(p_motivo)) < 6 then
    raise exception 'Deshacer una liberación exige un motivo (para el histórico del contrato).' using errcode = '23514';
  end if;
  select * into c from public.contratos where id = p_contrato_id;
  if c.id is null then raise exception 'Contrato no encontrado.' using errcode = 'P0002'; end if;
  if c.liberado_en is null then
    raise exception 'Esta reserva no está liberada.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.contrato_tipo_etapa e
                  where e.tipo = c.tipo and e.etapa = 'reserva' and e.tipo <> 'reserva_parcela') then
    raise exception 'Solo se deshace la liberación de una Carta de Reserva.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('prorroga:' || p_contrato_id::text));

  -- las parcelas que ESTA Carta soltó; si otro contrato vivo ocupa alguna, no hay vuelta atrás
  select string_agg(u.proyecto || ' ' || u.codigo || ' → ' || coalesce(o.numero, o.id::text), ', ')
    into v_ocup
    from public.unidades u
    join public.contratos o on o.id = u.contrato_id and o.liberado_en is null
   where u.contrato_liberado_id = p_contrato_id;
  if v_ocup is not null then
    raise exception 'No se puede deshacer: otra operación ocupa ya la parcela (%).', v_ocup using errcode = '23514';
  end if;
  select array_agg(u.id) into v_ids from public.unidades u where u.contrato_liberado_id = p_contrato_id;
  select count(*) into v_n from public.unidades u where u.contrato_liberado_id = p_contrato_id;
  if coalesce(v_n, 0) = 0 then
    raise exception 'Esta Carta no tiene ninguna parcela que recuperar (la liberación no dejó rastro en unidades).' using errcode = '22023';
  end if;

  v_quien := coalesce(public._quien_actua(), (select auth.uid())::text);

  -- 1) las parcelas vuelven a la Carta (también si alguien las dejó «reservada» a mano sin contrato)
  update public.unidades u
     set contrato_id = p_contrato_id,
         contrato_liberado_id = null,
         estado = 'reservada'
   where u.id = any (v_ids)
     and u.contrato_id is null;

  -- 2) la Carta vuelve a viva (contraseña del trigger de blindaje, solo esta transacción)
  perform set_config('app.via_libera_reserva', 'on', true);
  update public.contratos
     set liberado_en = null, liberado_motivo = null
   where id = p_contrato_id;

  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'reserva_liberacion_deshecha',
          jsonb_build_object('motivo', btrim(p_motivo), 'unidades_ids', to_jsonb(v_ids),
                             'liberada_el', c.liberado_en, 'liberado_motivo', c.liberado_motivo),
          v_quien);

  -- 3) que no vuelva a estar vencida: prórroga en el mismo acto si hace falta
  v_vence := public.reserva_vence_el(p_contrato_id);
  if v_vence is not null and v_vence <= current_date then
    if p_dias is null or p_dias < 1 then
      raise exception 'La reserva venció el %: indica los días de prórroga para que no se vuelva a liberar.', v_vence using errcode = '22023';
    end if;
    v_hasta := public.prorroga_reserva(p_contrato_id, p_dias, 'Al deshacer la liberación: ' || btrim(p_motivo), coalesce(p_comunicado, false));
    return v_hasta;
  end if;
  if p_dias is not null and p_dias >= 1 then
    return public.prorroga_reserva(p_contrato_id, p_dias, 'Al deshacer la liberación: ' || btrim(p_motivo), coalesce(p_comunicado, false));
  end if;
  return v_vence;
end $$;
revoke all on function public.deshace_liberacion(uuid, text, int, boolean) from public, anon;
grant execute on function public.deshace_liberacion(uuid, text, int, boolean) to authenticated;
