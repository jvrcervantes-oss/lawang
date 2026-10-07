-- LAW-497c (7-oct-2026). Decision del owner sobre LAW-497: «Si, si tiene Bloqueo firmado».
-- Cuando se anula un cobro (o baja el cobrado) y una parcela en «vendida» deja de tener el suelo
-- cobrado entero, vuelve sola a «bloqueada» SOLO si su Bloqueo de Parcela esta firmado
-- (contrato reserva_parcela con bloqueado). Sin Bloqueo firmado (Tamarind W3-C1/C2/C3, Mejan
-- S7 A2) no cambia: lo avisa el chequeo de salud. «cobrada» sigue como estaba: si cae el total
-- pero el suelo sigue entero baja a «vendida» (ya era asi); nunca salta a «bloqueada».
--
-- La condicion es la de siempre, unidad_cumple_estado(): la subida, la guarda y la bajada leen
-- la misma regla y no pueden divergir.
--
-- Medido el 7-oct antes de aplicar: ninguna parcela cambiaria hoy. Las cuatro «vendida» sin el
-- suelo cobrado no tienen Bloqueo firmado, y C5 de Bonian ya lo tiene cobrado entero (REC00158).
-- Esta migracion no recalcula nada: la regla actua la proxima vez que se mueva un cobro.
--
-- Que mueve el cobro y ahora dispara la revision (antes solo el alta/cambio del recibi):
--   · un recibi anulado, cambiado de importe o de tipo (ya estaba);
--   · un recibi movido a otro contrato: se revisa tambien el contrato de ORIGEN (antes no);
--   · un recibi borrado (si tiene aplicaciones, solo super admin: trg_guarda_antes_de_borrar) (antes no);
--   · una aplicacion de cobro borrada o cambiada (antes solo el alta).
-- El historial (unidades_log) apunta el motivo de la bajada; lo deduce el propio trigger viendo
-- el paso vendida -> bloqueada sin el suelo cubierto (es diferido: una variable de sesion se
-- leeria en el commit y etiquetaria otros cambios de la misma transaccion).
-- Prueba repetible: supabase/pruebas/law497c_bajada_por_anulacion.sql.

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
           -- LAW-497c (owner 7-oct): la escalera BAJA un peldano, y solo este: «vendida» que ya no
           -- tiene el suelo cobrado vuelve a «bloqueada» si su Bloqueo de Parcela esta firmado
           -- (mismo exists que la rama de «bloqueada» de arriba). Sin Bloqueo firmado, o sin precio de
           -- suelo puesto (no hay nada que medir), no se toca.
           when u.estado = 'vendida' and coalesce(u.precio_suelo, 0) > 0 and exists (
                  select 1 from public.contratos c3
                   where c3.id = u.contrato_id
                     and c3.tipo = 'reserva_parcela' and coalesce(c3.bloqueado, false)
                ) then 'bloqueada'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end;
$function$;

revoke all on function public.avanza_unidad_por_cobro(uuid) from public, anon, authenticated;

create or replace function public.trg_avanza_por_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op <> 'DELETE' and new.tipo = 'recibi' then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  -- el contrato que PIERDE el cobro: recibi borrado, movido de contrato o que deja de ser recibi
  if tg_op <> 'INSERT' and old.tipo = 'recibi'
     and (tg_op = 'DELETE'
          or new.contrato_id is distinct from old.contrato_id
          or new.tipo is distinct from 'recibi') then
    perform public.avanza_unidad_por_cobro(old.contrato_id);
  end if;
  return coalesce(new, old);
end
$$;

revoke all on function public.trg_avanza_por_recibi() from public, anon, authenticated;

create or replace trigger trg_avanza_por_recibi
  after insert or update of anulada, total, contrato_id, tipo or delete on public.facturas
  for each row execute function public.trg_avanza_por_recibi();

create or replace function public.trg_avanza_por_aplicacion()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_contrato_id uuid;
begin
  if tg_op <> 'DELETE' then
    select f.contrato_id into v_contrato_id from public.facturas f where f.id = new.factura_id;
    perform public.avanza_unidad_por_cobro(v_contrato_id);
  end if;
  if tg_op <> 'INSERT' then
    -- la factura y el recibi de la aplicacion que se va (si se borran en cascada ya no estan)
    for v_contrato_id in
      select distinct f.contrato_id from public.facturas f
       where f.id in (old.factura_id, old.recibi_id) and f.contrato_id is not null
    loop
      perform public.avanza_unidad_por_cobro(v_contrato_id);
    end loop;
  end if;
  return coalesce(new, old);
end
$$;

revoke all on function public.trg_avanza_por_aplicacion() from public, anon, authenticated;

create or replace trigger trg_avanza_por_aplicacion
  after insert or update or delete on public.recibi_aplicaciones
  for each row execute function public.trg_avanza_por_aplicacion();

-- Igual que 20261007040457 salvo el motivo de la bajada automatica.
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
               then 'excepcion decidida por el owner'
               when v_antes_estado = 'vendida' and new.estado = 'bloqueada'
                    and not public.unidad_cumple_estado(new.id, 'vendida', new.precio, new.precio_suelo)
               then 'vuelve a bloqueada: el suelo cobrado ya no llega al precio del suelo (LAW-497, owner 7-oct)'
          end,
          case when session_user = 'authenticator' then 'automatico'
               when current_setting('application_name', true) = 'pg_cron' then 'tarea programada'
               else 'sql directo' end);
  return null;
end;
$$;

revoke all on function public.trg_unidad_estado_al_historial() from public, anon, authenticated;
