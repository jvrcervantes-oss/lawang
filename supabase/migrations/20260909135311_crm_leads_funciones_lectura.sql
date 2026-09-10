-- CRM de leads — lectura. Todo sale por funcion, nunca por policy sobre `leads`.
-- Cada funcion: SECURITY DEFINER + search_path vacio + revalidacion de permiso dentro,
-- y columnas escritas a mano una a una. Si manana alguien anade una columna a `leads`,
-- NO aparece aqui sola: hay que venir a escribirla, que es justo lo que se quiere.

-- 1. EL TABLERO --------------------------------------------------------------------
-- Devuelve lo que se pinta en una tarjeta. NO devuelve email ni telefono ni `ip`: el
-- contacto se pide aparte y ese momento queda registrado (crm_lead_contacto).
-- `respuestas` se recorta a las cuatro claves de opcion cerrada -- las otras tres
-- (full_name, email, phone_number) son el contacto por otra puerta, y una pregunta de
-- texto libre puede llevar dentro cualquier cosa que el lead haya tecleado.
create or replace function public.crm_leads()
returns table (
  id uuid, created_at timestamptz, source text, name text, campaign_id text,
  respuestas jsonb, tiene_email boolean, tiene_whatsapp boolean,
  estado text, estado_desde timestamptz, responsable text, notas bigint,
  sugerencia text, sugerencia_contrato text
)
language sql stable security definer set search_path to ''
as $$
  with sug as (
    -- "Firmo" = contrato BLOQUEADO, no `fecha_firma`. La fecha se rellena al CREAR el
    -- contrato, asi que 137 del alta de historico la llevan sin estar firmados: por
    -- fecha, el tablero acabaria diciendo que firmo alguien que no ha firmado
    -- (contexto/suite_lawang.md, 26-ago-2026).
    select l.id as lead_id,
           case when bool_or(e.etapa = 'contrato') then 'contrato'
                when bool_or(e.etapa = 'reserva')  then 'reserva' end as etapa,
           min(c.numero) as numero
      from public.leads l
      join public.contratos c on coalesce(c.bloqueado, false) = true
      join lateral unnest(public.contrato_identificadores(c.datos)) ident(ident) on true
      join public.contrato_tipo_etapa e on e.tipo = c.tipo and e.etapa <> 'ninguna'
     where nullif(btrim(l.email), '') is not null
       and lower(btrim(ident.ident)) = lower(btrim(l.email))
     group by l.id
  )
  select l.id,
         l.created_at,
         l.source,
         l.name,
         l.campaign_id,
         coalesce((select jsonb_object_agg(k, v)
                     from jsonb_each(coalesce(l.respuestas, '{}'::jsonb)) as r(k, v)
                    where k in ('budget_range','buy_timeline','budget','purpose')),
                  '{}'::jsonb),
         nullif(btrim(coalesce(l.email, '')), '') is not null,
         nullif(btrim(coalesce(l.whatsapp, '')), '') is not null,
         coalesce(e.estado, 'nuevo'),
         coalesce(e.estado_desde, l.created_at),
         e.responsable,
         (select count(*) from public.lead_notas n where n.lead_id = l.id),
         s.etapa,
         s.numero
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join sug s on s.lead_id = l.id
   where public.puede('leads');
$$;

-- 2. EL CONTACTO, DE UNO EN UNO Y DEJANDO RASTRO ------------------------------------
-- El registro se escribe DENTRO de la funcion que entrega el dato, no con un insert
-- desde el navegador: ese se salta apagando el JavaScript, y entonces la traza solo
-- registraria a quien no tiene nada que ocultar.
create or replace function public.crm_lead_contacto(p_lead uuid, p_que text default 'contacto')
returns table (email text, whatsapp text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso para ver contactos de leads' using errcode = 'PT403';
  end if;
  if p_que not in ('contacto','whatsapp','email') then
    raise exception 'Motivo de acceso no valido: %', p_que using errcode = 'PT400';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  insert into public.lead_acceso_log (lead_id, quien, que) values (p_lead, v_quien, p_que);

  return query
    select nullif(btrim(coalesce(l.email, '')), ''),
           nullif(btrim(coalesce(l.whatsapp, '')), '')
      from public.leads l
     where l.id = p_lead;
end;
$$;

-- 3. EL HILO DE UN LEAD --------------------------------------------------------------
-- Alta + cambios de estado + notas, en una sola lista ordenada. Es lo que hay de verdad:
-- los leads de Lawang llegan por formulario, no por una conversacion entrante, asi que
-- aqui no se finge ningun mensaje recibido.
create or replace function public.crm_lead_hilo(p_lead uuid)
returns table (tipo text, cuando timestamptz, autor text, texto text, extra text)
language sql stable security definer set search_path to ''
as $$
  select 'alta', l.created_at, null::text, l.source, null::text
    from public.leads l
   where l.id = p_lead and public.puede('leads')
  union all
  select 'estado', g.cuando, g.autor, g.a, g.de
    from public.lead_estado_log g
   where g.lead_id = p_lead and public.puede('leads')
  union all
  select 'nota', n.created_at, n.autor, n.texto, null::text
    from public.lead_notas n
   where n.lead_id = p_lead and public.puede('leads')
   order by 2 asc;
$$;

revoke execute on function public.crm_leads() from public, anon;
revoke execute on function public.crm_lead_contacto(uuid, text) from public, anon;
revoke execute on function public.crm_lead_hilo(uuid) from public, anon;
grant execute on function public.crm_leads() to authenticated;
grant execute on function public.crm_lead_contacto(uuid, text) to authenticated;
grant execute on function public.crm_lead_hilo(uuid) to authenticated;;
