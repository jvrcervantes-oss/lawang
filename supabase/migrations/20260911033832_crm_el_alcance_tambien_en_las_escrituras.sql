-- Segunda mitad del arreglo del alcance (ver 20260911033720). Filtrar solo la LECTURA habria
-- dejado el resto abierto: con el id de un lead ajeno se podia mover su tarjeta, escribirle
-- una nota, reclamarlo como propio o —lo peor— sacar su nombre y su telefono por
-- `crm_lead_para_contrato`. Un alcance que solo esta en el listado no es un alcance.
-- Todas comparten la MISMA regla (`lead_a_mi_alcance`), escrita una sola vez.
--
-- VERIFICADO con la sesion real de Andrea (1 campana, 49 de 108 leads): contacto de lead
-- ajeno PT403, nombre+telefono de lead ajeno PT403, reclamar lead ajeno PT403, hilo de lead
-- ajeno 0 eventos. Y sobre los suyos, todo sigue funcionando.

create or replace function public.crm_lead_para_contrato(p_lead uuid)
returns table (
  nombre text, email text, whatsapp text,
  ficha_existente uuid, ficha_existente_nombre text, otros_leads_igual int
)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_email text;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  -- La mas importante de todas: esta funcion entrega nombre, correo y telefono.
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  insert into public.lead_acceso_log (lead_id, quien, que) values (p_lead, v_quien, 'contrato');
  select lower(btrim(coalesce(l.email, ''))) into v_email from public.leads l where l.id = p_lead;

  return query
    select l.name,
           nullif(btrim(coalesce(l.email, '')), ''),
           nullif(btrim(coalesce(l.whatsapp, '')), ''),
           f.id, f.full_name,
           (select count(*)::int from public.leads o
             where o.id <> l.id and v_email <> ''
               and lower(btrim(coalesce(o.email, ''))) = v_email)
      from public.leads l
      left join public.clients f
        on v_email <> '' and lower(f.email) = v_email and f.tipo = 'persona'
     where l.id = p_lead;
end;
$$;

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
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
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

create or replace function public.crm_lead_mover(
  p_lead uuid, p_estado text, p_desde timestamptz
)
returns table (lead_id uuid, estado text, estado_desde timestamptz, responsable text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien  text := coalesce((select auth.email()), '');
  v_actual text; v_desde timestamptz; v_alta timestamptz;
  v_ahora  timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
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
     set estado = p_estado, estado_desde = v_ahora, actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, estado_desde, actualizado)
         values (p_lead, p_estado, v_ahora, v_ahora);
  end if;

  insert into public.lead_estado_log (lead_id, de, a, autor)
       values (p_lead, v_actual, p_estado, v_quien);

  return query
    select e.lead_id, e.estado, e.estado_desde, e.responsable
      from public.lead_estado e where e.lead_id = p_lead;
end;
$$;

create or replace function public.crm_lead_asignar(
  p_lead uuid, p_email text, p_previo text default null
)
returns table (lead_id uuid, responsable text, asignado_por text, asignado_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien   text := coalesce((select auth.email()), '');
  v_destino text := nullif(btrim(coalesce(p_email, '')), '');
  v_actual  text;
  v_ahora   timestamptz := now();
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  -- Sin esto, cualquiera con la casilla podia reclamar como suyo un lead de una campana
  -- que no atiende, y de paso meterselo en su propio alcance para siempre.
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  if v_destino is not null then
    if not exists (
      select 1 from public.usuarios u
       where lower(u.email) = lower(v_destino) and u.activo
         and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
    ) then
      raise exception 'Esa persona no esta activa o no tiene acceso al CRM de leads'
        using errcode = 'PT400';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  select e.responsable into v_actual from public.lead_estado e where e.lead_id = p_lead;

  if v_actual is distinct from p_previo then
    raise exception 'Este lead ya no esta como lo tenias: alguien lo ha cambiado'
      using errcode = 'PT409';
  end if;

  if v_actual is not null
     and lower(v_actual) <> lower(v_quien)
     and not public.es_admin() then
    raise exception 'Ese lead lo lleva otra persona. Solo un administrador puede reasignarlo'
      using errcode = 'PT403';
  end if;

  update public.lead_estado e
     set responsable = v_destino, asignado_por = v_quien, asignado_en = v_ahora,
         actualizado = v_ahora
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, estado_desde, actualizado,
                                    responsable, asignado_por, asignado_en)
         values (p_lead, 'nuevo',
                 (select l.created_at from public.leads l where l.id = p_lead),
                 v_ahora, v_destino, v_quien, v_ahora);
  end if;

  insert into public.lead_dueno_log (lead_id, de, a, autor)
       values (p_lead, v_actual, v_destino, v_quien);

  return query
    select e.lead_id, e.responsable, e.asignado_por, e.asignado_en
      from public.lead_estado e where e.lead_id = p_lead;
end;
$$;

create or replace function public.crm_lead_accion_poner(
  p_lead uuid, p_que text, p_cuando date, p_responsable text default null
)
returns table (id uuid, lead_id uuid, que text, cuando date, responsable text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_que   text := btrim(coalesce(p_que, ''));
  v_resp  text := nullif(btrim(coalesce(p_responsable, '')), '');
  v_id    uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if v_que = '' then
    raise exception 'La accion esta vacia' using errcode = 'PT400';
  end if;
  if length(v_que) > 280 then
    raise exception 'La accion es demasiado larga' using errcode = 'PT400';
  end if;
  if p_cuando is null then
    raise exception 'Falta la fecha de la accion' using errcode = 'PT400';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  if v_resp is not null then
    if not exists (
      select 1 from public.usuarios u
       where lower(u.email) = lower(v_resp) and u.activo
         and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
    ) then
      raise exception 'Esa persona no esta activa o no tiene acceso al CRM de leads'
        using errcode = 'PT400';
    end if;
  else
    select e.responsable into v_resp from public.lead_estado e where e.lead_id = p_lead;
    if v_resp is null then
      select lc.closer_email into v_resp from public.lead_closer lc where lc.lead_id = p_lead;
    end if;
    v_resp := coalesce(v_resp, v_quien);
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 1));

  update public.lead_accion a
     set que = v_que, cuando = p_cuando, responsable = v_resp
   where a.lead_id = p_lead and a.completada_en is null
   returning a.id into v_id;

  if v_id is null then
    insert into public.lead_accion (lead_id, que, cuando, responsable, creada_por)
         values (p_lead, v_que, p_cuando, v_resp, v_quien)
      returning lead_accion.id into v_id;
  end if;

  return query
    select a.id, a.lead_id, a.que, a.cuando, a.responsable
      from public.lead_accion a where a.id = v_id;
end;
$$;

-- Esta recibe el id de la ACCION, no el del lead: la comprobacion va por el lead al que
-- cuelga. Sin ese rodeo no habria forma de saber si la tarea es de una campana propia.
create or replace function public.crm_lead_accion_completar(p_accion uuid)
returns table (id uuid, lead_id uuid, completada_en timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_lead  uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  select a.lead_id into v_lead from public.lead_accion a where a.id = p_accion;
  if v_lead is not null and not public.lead_a_mi_alcance(v_lead) then
    raise exception 'Esa tarea es de un lead que no es de tus campanas' using errcode = 'PT403';
  end if;

  return query
    update public.lead_accion a
       set completada_en = now(), completada_por = v_quien
     where a.id = p_accion and a.completada_en is null
    returning a.id, a.lead_id, a.completada_en;
end;
$$;

create or replace function public.crm_lead_ficha_crear(p_lead uuid)
returns table (client_id uuid, ya_existia boolean)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_nombre text; v_email text; v_tel text; v_id uuid;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  select btrim(coalesce(l.name, '')),
         nullif(lower(btrim(coalesce(l.email, ''))), ''),
         nullif(btrim(coalesce(l.whatsapp, '')), '')
    into v_nombre, v_email, v_tel
    from public.leads l where l.id = p_lead;

  if v_nombre is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;
  if v_nombre = '' then
    raise exception 'Ese lead no tiene nombre: no se puede abrir una ficha sin nombre' using errcode = 'PT400';
  end if;
  if v_email is null then
    raise exception 'Ese lead no dejo email: la ficha necesita un identificador' using errcode = 'PT400';
  end if;

  select c.id into v_id from public.clients c
   where c.email is not null and lower(c.email) = v_email and c.tipo = 'persona';
  if v_id is not null then
    return query select v_id, true;
    return;
  end if;

  insert into public.clients (full_name, email, phone, tipo, kyc_status, propietario, notes)
       values (upper(v_nombre), v_email, v_tel, 'persona', 'pending', v_quien,
               'Ficha abierta desde el CRM de leads el ' || to_char(now(), 'DD-MM-YYYY'))
    returning clients.id into v_id;

  return query select v_id, false;
end;
$$;

create or replace function public.crm_lead_contrato_sellar(p_lead uuid, p_contrato uuid)
returns table (lead_id uuid, contrato_id uuid, cuando timestamptz)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso sobre los leads' using errcode = 'PT403';
  end if;
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;
  if not exists (select 1 from public.leads l where l.id = p_lead) then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then
    raise exception 'Ese contrato no existe' using errcode = 'PT404';
  end if;

  insert into public.lead_contrato (lead_id, contrato_id, origen, quien)
       values (p_lead, p_contrato, 'crm', v_quien)
  on conflict on constraint lead_contrato_pkey do nothing;

  return query
    select k.lead_id, k.contrato_id, k.cuando
      from public.lead_contrato k
     where k.lead_id = p_lead and k.contrato_id = p_contrato;
end;
$$;
