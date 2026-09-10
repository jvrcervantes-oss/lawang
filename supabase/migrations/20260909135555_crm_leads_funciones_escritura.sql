-- CRM de leads — escritura. La herramienta del cliente NUNCA escribe en `leads`: esa
-- tabla la mantiene R13 (la recogida automatica de Meta, cada 4 h) con su propio upsert.
-- El estado y las notas viven en tablas aparte, y se tocan solo desde aqui.

-- 1. MOVER UNA TARJETA ---------------------------------------------------------------
-- Concurrencia, en dos capas:
--   a) cerrojo de aviso por lead durante la transaccion, para que dos operadores que
--      sueltan la misma tarjeta a la vez se serialicen en vez de leer los dos el estado
--      viejo. Se usa un cerrojo de aviso y no uno de fila porque la fila de estado
--      puede no existir todavia, y sobre una fila inexistente no hay nada que bloquear.
--   b) el cliente manda el `estado_desde` que TENIA pintado: si no coincide con el de
--      la base, alguien la movio entre medias y esto falla en vez de pisarlo en
--      silencio. El codigo 'PT409' lo traduce PostgREST a un HTTP 409, que es como lo
--      reconoce el navegador.
-- Estado e historial, en la MISMA transaccion: si el historial falla, no hay movimiento.
create or replace function public.crm_lead_mover(
  p_lead uuid, p_estado text, p_desde timestamptz
)
returns table (lead_id uuid, estado text, estado_desde timestamptz, responsable text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien  text := coalesce((select auth.email()), '');
  v_actual text;
  v_desde  timestamptz;
  v_alta   timestamptz;
  v_ahora  timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if p_estado not in ('nuevo','contactado','visita','reserva','contrato','perdido') then
    raise exception 'Estado desconocido: %', p_estado using errcode = 'PT400';
  end if;

  select l.created_at into v_alta from public.leads l where l.id = p_lead;
  if v_alta is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  -- La fila de estado puede faltar: el 'nuevo' del tablero es un COALESCE, no un dato
  -- guardado. Cuando falta, la referencia de concurrencia es la fecha de alta.
  select e.estado, e.estado_desde into v_actual, v_desde
    from public.lead_estado e where e.lead_id = p_lead;
  v_actual := coalesce(v_actual, 'nuevo');
  v_desde  := coalesce(v_desde, v_alta);

  if p_desde is null or v_desde is distinct from p_desde then
    raise exception 'La tarjeta la ha movido otra persona' using errcode = 'PT409';
  end if;

  if v_actual = p_estado then
    return query select p_lead, v_actual, v_desde,
                        (select e.responsable from public.lead_estado e where e.lead_id = p_lead);
    return;
  end if;

  update public.lead_estado e
     set estado = p_estado, responsable = v_quien,
         estado_desde = v_ahora, actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, responsable, estado_desde, actualizado)
         values (p_lead, p_estado, v_quien, v_ahora, v_ahora);
  end if;

  insert into public.lead_estado_log (lead_id, de, a, autor)
       values (p_lead, v_actual, p_estado, v_quien);

  return query
    select e.lead_id, e.estado, e.estado_desde, e.responsable
      from public.lead_estado e where e.lead_id = p_lead;
end;
$$;

-- 2. ANADIR UNA NOTA -------------------------------------------------------------------
-- El autor se sella aqui con la identidad de la sesion; no llega como parametro, para
-- que nadie pueda firmar una nota con el nombre de otro.
create or replace function public.crm_lead_nota(p_lead uuid, p_texto text)
returns table (id uuid, texto text, autor text, created_at timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_texto text := btrim(coalesce(p_texto, ''));
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_texto = '' then
    raise exception 'La nota esta vacia' using errcode = 'PT400';
  end if;
  if length(v_texto) > 4000 then
    raise exception 'La nota es demasiado larga' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  return query
    insert into public.lead_notas (lead_id, texto, autor)
         values (p_lead, v_texto, v_quien)
      returning lead_notas.id, lead_notas.texto, lead_notas.autor, lead_notas.created_at;
end;
$$;

revoke execute on function public.crm_lead_mover(uuid, text, timestamptz) from public, anon;
revoke execute on function public.crm_lead_nota(uuid, text) from public, anon;
grant execute on function public.crm_lead_mover(uuid, text, timestamptz) to authenticated;
grant execute on function public.crm_lead_nota(uuid, text) to authenticated;;
