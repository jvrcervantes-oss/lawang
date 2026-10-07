-- LAW-497d (7-oct-2026). Correcciones del revisor de codigo sobre 20261007051127 (law497c):
--   1. «cobrada» que pierde el cobro (ni total ni suelo) se quedaba en «cobrada» para siempre. Ahora
--      sigue la misma regla que «vendida»: con Bloqueo firmado vuelve a «bloqueada» (la decision del
--      owner es «si deja de tener el suelo pagado y tiene Bloqueo firmado, vuelve a bloqueada»).
--      Medido antes de aplicar: ninguna «cobrada» esta hoy sin su cobro.
--   2. La bajada no actua si quien dispara la revision no ve el cobro (contrato_cobrado le da 0).
--   3. Mas movimientos que revisan el estado: anular/mover/borrar una factura que NO es recibi
--      (sus aplicaciones dejan de contar) revisa su contrato y el de los recibis aplicados; el alta o
--      cambio de una aplicacion revisa tambien el contrato del recibi; cambiar precio_suelo revisa.
-- Prueba repetible: supabase/pruebas/law497c_bajada_por_anulacion.sql (casos 8 y 10-12).

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
  v_ve_cobro boolean;
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

  -- LAW-497d: contrato_cobrado() devuelve 0 a quien no puede verlo (authenticated que no es agente
  -- ni portal). Antes un 0 falso solo frenaba una subida; ahora bajaria una parcela que esta bien.
  -- Misma condicion que contrato_cobrado: sin JWT (postgres, pg_cron) o service_role, si lo ve.
  v_ve_cobro := coalesce(not ((select auth.role()) <> 'service_role'
                              and not (public.es_agente() or public.es_portal())), true);

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
           -- LAW-497c/d (owner 7-oct): «vendida» o «cobrada» que ya no tiene el suelo cobrado vuelve a
           -- «bloqueada» si su Bloqueo de Parcela esta firmado (mismo exists que la rama de arriba).
           -- «cobrada» con el suelo entero ya bajaba a «vendida» en la rama anterior. Sin Bloqueo
           -- firmado, sin precio de suelo o si quien llama no ve el cobro, no se toca.
           when u.estado in ('vendida', 'cobrada') and v_ve_cobro and coalesce(u.precio_suelo, 0) > 0 and exists (
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
declare
  v_c uuid;
begin
  -- cualquier tipo: un recibi suma por si mismo; una factura suma por sus aplicaciones
  if tg_op <> 'DELETE' then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  -- el contrato que PIERDE el cobro: borrada, movida de contrato o cambiada de tipo
  if tg_op <> 'INSERT'
     and (tg_op = 'DELETE'
          or new.contrato_id is distinct from old.contrato_id
          or new.tipo is distinct from old.tipo) then
    perform public.avanza_unidad_por_cobro(old.contrato_id);
  end if;
  -- una factura (no recibi) anulada o reactivada: sus aplicaciones dejan de contar o vuelven, y
  -- con ellas cambia lo que el recibi deja sin aplicar en SU contrato
  if tg_op = 'UPDATE' and new.tipo <> 'recibi' and new.anulada is distinct from old.anulada then
    for v_c in
      select distinct r.contrato_id from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
       where ra.factura_id = new.id and r.contrato_id is not null
    loop
      perform public.avanza_unidad_por_cobro(v_c);
    end loop;
  end if;
  return coalesce(new, old);
end
$$;

revoke all on function public.trg_avanza_por_recibi() from public, anon, authenticated;

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
    for v_contrato_id in
      select distinct f.contrato_id from public.facturas f
       where f.id in (new.factura_id, new.recibi_id) and f.contrato_id is not null
    loop
      perform public.avanza_unidad_por_cobro(v_contrato_id);
    end loop;
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

create or replace function public.trg_revalua_unidad_por_precio()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if (new.precio is distinct from old.precio or new.precio_suelo is distinct from old.precio_suelo)
     and new.contrato_id is not null then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  return new;
end;
$$;

revoke all on function public.trg_revalua_unidad_por_precio() from public, anon, authenticated;

create or replace trigger trg_revalua_unidad_por_precio
  after update of precio, precio_suelo on public.unidades
  for each row execute function public.trg_revalua_unidad_por_precio();

-- Igual que 20261007051127, con el motivo tambien en la bajada desde «cobrada».
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
               when v_antes_estado in ('vendida', 'cobrada') and new.estado = 'bloqueada'
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
