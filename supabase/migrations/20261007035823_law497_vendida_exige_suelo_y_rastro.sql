-- LAW-497 (7-oct-2026). Bonian Village C5 volvio a «vendida» con el 51 % del suelo cobrado,
-- despues de que el owner la bajara a «bloqueada» el 23-sep, y unidades_log no tenia ni una fila.
--
-- Por donde subio (logs de la API del 6-oct, aritmetica con contrato_cobrado):
--   06:53 guardar_recibi REC00156 (20.100) · 07:02 guardar_recibi REC00157 (20.123)
--   -> 1.000 (CR00020) + 20.100 + 20.123 = 41.223 >= 41.200 de suelo -> avanza_unidad_por_cobro
--   la pasa a «vendida» con la regla correcta · 07:03 factura_anula (el log no dice de que
--   documento; REC00156, el duplicado, es el unico anulado del contrato que cuadra)
--   -> el cobro baja a 21.123 pero la escalera nunca baja, y nada lo apunta.
-- Reproducido en una transaccion deshecha el 7-oct: con REC00156 viva C5 sube a «vendida»;
-- al anularla se queda en «vendida».
-- Ninguna otra funcion escribe «vendida»: sincroniza_unidad_contrato la conserva, unidad_guarda
-- solo deja poner a mano disponible / no_disponible / bloqueada, unidades_importa no toca el estado.
--
-- Lo que hace esta migracion (construye; no cambia el estado de ninguna parcela):
--   1. unidad_cumple_estado(): la condicion del owner en UN sitio. avanza_unidad_por_cobro la usa
--      y la guarda de abajo tambien, para que no puedan divergir (si divergen, la guarda tumba
--      el guardado de un recibi).
--   2. trg_unidad_vendida_exige_cobro: ninguna via -- funcion nueva, SQL a mano, lo que venga --
--      ENTRA en «vendida» sin el suelo cobrado entero ni en «cobrada» sin el total. Solo mira la
--      ENTRADA: las parcelas que ya estan en «vendida» (Tamarind, Mejan A2, C5) se editan igual.
--      Excepcion decidida por el owner: solo desde una sesion directa a la base (nunca desde la
--      API) con `set local app.unidad_estado_excepcion = 'on'`, y queda en el historial.
--   3. trg_unidad_estado_al_historial: todo cambio de estado deja fila en unidades_log, venga de
--      donde venga (avanza, sincroniza, SQL). Es diferido para no duplicar la fila que ya
--      escriben unidad_guarda ('ficha') y unidades_importa ('csv') en la misma transaccion.
--
-- Lo que NO hace: bajar «vendida» cuando un cobro se anula. Eso cambia el estado de parcelas
-- reales (C5 en el siguiente movimiento de RP00140) y lo decide el owner (pregunta del 7-oct).

create or replace function public.unidad_cumple_estado(
  p_unidad uuid, p_estado text, p_precio numeric, p_precio_suelo numeric)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_estado
    when 'cobrada' then coalesce(p_precio, 0) > 0
         and coalesce((select x.cobrado_suelo + x.cobrado_obra
                         from public.unidad_parte_cobrada_interno(p_unidad) x), 0) >= p_precio
    when 'vendida' then coalesce(p_precio_suelo, 0) > 0
         and coalesce((select x.cobrado_suelo
                         from public.unidad_parte_cobrada_interno(p_unidad) x), 0) >= p_precio_suelo
    else true
  end;
$$;

revoke all on function public.unidad_cumple_estado(uuid, text, numeric, numeric) from public, anon, authenticated;

-- Misma funcion que la viva (leida el 7-oct), solo cambian las dos condiciones de subida, que
-- ahora salen de unidad_cumple_estado con los mismos valores.
create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz_id uuid;
  v_mon     text;
  v_nmon    int;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  if exists (select 1 from public.contratos where id = v_raiz_id and liberado_en is not null) then
    return;
  end if;

  select min(u.moneda), count(distinct u.moneda)
    into v_mon, v_nmon
    from public.unidades u where u.contrato_id = v_raiz_id;
  if coalesce(v_nmon, 0) > 1 then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from v_mon
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from v_mon
  ) into v_mezcla;
  if v_mezcla then return; end if;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when public.unidad_cumple_estado(u.id, 'cobrada', u.precio, u.precio_suelo) then 'cobrada'
           when public.unidad_cumple_estado(u.id, 'vendida', u.precio, u.precio_suelo) then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end;
$function$;

create or replace function public.trg_unidad_vendida_exige_cobro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado in ('vendida', 'cobrada')
     and (tg_op = 'INSERT' or new.estado is distinct from old.estado)
     and not (session_user <> 'authenticator'
              and coalesce(current_setting('app.unidad_estado_excepcion', true), '') = 'on')
     and not public.unidad_cumple_estado(new.id, new.estado, new.precio, new.precio_suelo) then
    raise exception 'La parcela % de % no puede pasar a «%»: %.',
      coalesce(new.codigo, '?'), coalesce(new.proyecto, '?'), new.estado,
      case new.estado when 'vendida' then 'el suelo no está cobrado entero'
                      else 'el precio no está cobrado entero' end
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.trg_unidad_vendida_exige_cobro() from public, anon, authenticated;

create trigger trg_unidad_vendida_exige_cobro
  before insert or update of estado on public.unidades
  for each row execute function public.trg_unidad_vendida_exige_cobro();

create or replace function public.trg_unidad_estado_al_historial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- unidad_guarda y unidades_importa ya escriben su fila (con motivo) en esta transaccion.
  if exists (select 1 from public.unidades_log l
              where l.unidad_id = new.id and l.en = now()
                and l.despues->>'estado' is not distinct from new.estado) then
    return null;
  end if;
  insert into public.unidades_log (unidad_id, antes, despues, motivo, via)
  values (new.id, to_jsonb(old), to_jsonb(new),
          case when coalesce(current_setting('app.unidad_estado_excepcion', true), '') = 'on'
               then 'excepcion decidida por el owner' end,
          case when session_user = 'authenticator' then 'automatico' else 'sql directo' end);
  return null;
end;
$$;

revoke all on function public.trg_unidad_estado_al_historial() from public, anon, authenticated;

create constraint trigger trg_unidad_estado_al_historial
  after update of estado on public.unidades
  deferrable initially deferred
  for each row
  when (old.estado is distinct from new.estado)
  execute function public.trg_unidad_estado_al_historial();
