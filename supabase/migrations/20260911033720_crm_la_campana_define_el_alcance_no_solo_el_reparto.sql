-- EL ALCANCE DEL CRM PASA A SEGUIR A LA CAMPANA. 11-sep-2026, fallo reportado por el owner:
-- "Andrea ha entrado sin tener campana asignada y veia 108 leads. He asignado una y seguia
-- viendo 108 en vez de 49."
--
-- QUE ESTABA MAL, Y ES UN ERROR DE CONCEPTO MIO. `reparto_closer` se construyo como "quien
-- RECIBE los leads nuevos de esta campana", y el owner lo pidio —con mejor criterio— como
-- "que leads le TOCAN a esta persona". Mientras tanto la visibilidad seguia siendo la de
-- siempre: `puede('leads')` y ves los 108. Verificado antes de tocar nada: Andrea es
-- sales_manager, tiene 'leads', no tiene 'ranking' ni 'reparto', y esta asignada a
-- meta-sumbahills (49 leads).
--
-- LA REGLA, EN UN SOLO SITIO. Se escribe una vez en `lead_a_mi_alcance()` y la usan TODAS las
-- funciones del CRM (las de escritura, en la migracion siguiente). Filtrar solo el listado
-- habria sido peor que no filtrar: la pantalla ensenaria 49 y `crm_lead_contacto` seguiria
-- entregando el telefono de los otros 59 a quien supiera pedirlo desde la consola. Un filtro
-- que solo esta en la vista no es un alcance, es un adorno.
--
--   · Gestor del CRM (`ranking` o `reparto`, o super_admin) -> lo ve todo. Lo necesita: no se
--     puede repartir ni hacer un ranking sobre lo que no se ve.
--   · Con campanas asignadas -> los leads de SUS campanas, mas cualquier lead del que sea
--     responsable aunque sea de otra campana (si alguien se lo cedio, tiene que poder
--     trabajarlo; si no, un lead cedido desapareceria de la vista de quien lo recibe).
--   · Con 'leads' pero sin campanas y sin gestion -> solo los suyos. Antes veia los 108.
--     ⚠️ Este es el cambio que se notara: una persona con la casilla y sin campana pasa de
--     ver 108 a ver los que le hayan asignado, que hoy pueden ser cero. Es lo correcto y es
--     lo que pidio el owner, pero la pantalla tiene que DECIRLO en vez de quedarse en blanco
--     — de ahi `crm_mi_alcance()` y el aviso de la cabecera del CRM.
--
-- VERIFICADO con sesiones reales, sin tocar nada (todo revertido donde hubo escritura):
--   · Andrea (1 campana)      -> 49 leads, solo de meta-sumbahills
--   · owner (super_admin)     -> 108
--   · casilla pero sin campana-> 0 (antes 108)
--   · contacto / nombre+telefono / reclamar / hilo de un lead ajeno -> PT403 y 0 eventos
create or replace function public.lead_a_mi_alcance(p_lead uuid)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select case
    when public.puede('ranking') or public.puede('reparto') then true
    when not public.puede('leads') then false
    else exists (
      select 1
        from public.leads l
        left join public.lead_estado e on e.lead_id = l.id
       where l.id = p_lead
         and (
              lower(coalesce(e.responsable, '')) = lower(coalesce((select auth.email()), '@'))
           or exists (select 1 from public.reparto_closer k
                       where k.source = l.source
                         and lower(k.closer_email) = lower(coalesce((select auth.email()), '@')))
         )
    )
  end;
$$;

-- Cuantas campanas tengo asignadas: lo usa la pantalla para distinguir "no hay leads" de
-- "no te han dado ninguna campana", que para quien mira son cosas muy distintas.
create or replace function public.crm_mi_alcance()
returns table (es_gestor boolean, campanas text[], leads_visibles bigint)
language sql stable security definer set search_path to ''
as $$
  select (public.puede('ranking') or public.puede('reparto')),
         coalesce((select array_agg(k.source order by k.source) from public.reparto_closer k
                    where lower(k.closer_email) = lower(coalesce((select auth.email()), '@'))), '{}'),
         (select count(*) from public.leads l where public.lead_a_mi_alcance(l.id))
   where public.puede('leads') or public.puede('ranking') or public.puede('reparto');
$$;

-- ============== EL LISTADO ==============
create or replace function public.crm_leads()
returns table (
  id uuid, created_at timestamptz, source text, name text, campaign_id text,
  respuestas jsonb, tiene_email boolean, tiene_whatsapp boolean,
  estado text, estado_desde timestamptz, responsable text, notas bigint,
  sugerencia text, sugerencia_contrato text,
  accion_id uuid, accion_que text, accion_cuando date, accion_responsable text,
  contrato_id uuid, contrato_numero text,
  dueno text, dueno_nombre text, dueno_activo boolean
)
language sql stable security definer set search_path to ''
as $$
  select l.id, l.created_at, l.source, l.name, l.campaign_id,
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
         s.etapa, s.contrato_numero,
         a.id, a.que, a.cuando, a.responsable,
         v.contrato_id, v.numero,
         e.responsable, u.nombre,
         case when e.responsable is null then null else coalesce(u.activo, false) end
    from public.leads l
    left join public.lead_estado e on e.lead_id = l.id
    left join public.lead_sugerencia s on s.lead_id = l.id
    left join public.lead_accion a on a.lead_id = l.id and a.completada_en is null
    left join public.usuarios u on lower(u.email) = lower(e.responsable)
    left join lateral (
      select k.contrato_id, c.numero
        from public.lead_contrato k
        join public.contratos c on c.id = k.contrato_id
       where k.lead_id = l.id order by k.cuando desc limit 1
    ) v on true
   where public.puede('leads')
     -- El alcance se aplica AQUI y no en el navegador: filtrar en el cliente es ensenar
     -- menos, no entregar menos, y los 108 seguirian viajando al navegador de quien solo
     -- debe ver 49.
     and public.lead_a_mi_alcance(l.id);
$$;

-- ============== EL CONTACTO (lo que de verdad importa) ==============
create or replace function public.crm_lead_contacto(p_lead uuid, p_que text default 'contacto')
returns table (email text, whatsapp text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_quien text := coalesce((select auth.email()), '');
  v_dueno text;
  v_motivo text;
begin
  if not public.puede('leads') then
    raise exception 'Sin permiso para ver contactos de leads' using errcode = 'PT403';
  end if;
  -- Sin esto, el filtro del listado seria cosmetico: bastaria con saber el id de un lead
  -- ajeno para pedir su telefono.
  if not public.lead_a_mi_alcance(p_lead) then
    raise exception 'Ese lead no es de ninguna de tus campanas' using errcode = 'PT403';
  end if;
  if p_que not in ('contacto','whatsapp','email','contrato') then
    raise exception 'Motivo de acceso no valido: %', p_que using errcode = 'PT400';
  end if;
  if v_quien = '' then
    raise exception 'Sesion sin identidad' using errcode = 'PT403';
  end if;

  select e.responsable into v_dueno from public.lead_estado e where e.lead_id = p_lead;
  v_motivo := case
    when p_que = 'contacto' and v_dueno is not null and lower(v_dueno) <> lower(v_quien)
      then 'contacto_ajeno' else p_que end;

  insert into public.lead_acceso_log (lead_id, quien, que) values (p_lead, v_quien, v_motivo);

  return query
    select nullif(btrim(coalesce(l.email, '')), ''),
           nullif(btrim(coalesce(l.whatsapp, '')), '')
      from public.leads l where l.id = p_lead;
end;
$$;

-- ============== EL HILO ==============
create or replace function public.crm_lead_hilo(p_lead uuid)
returns table (tipo text, cuando timestamptz, autor text, texto text, extra text)
language sql stable security definer set search_path to ''
as $$
  select 'alta', l.created_at, null::text, l.source, null::text
    from public.leads l
   where l.id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'estado', g.cuando, g.autor, g.a, g.de
    from public.lead_estado_log g
   where g.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'nota', n.created_at, n.autor, n.texto, null::text
    from public.lead_notas n
   where n.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'tarea', a.creada_en, a.creada_por, a.que, to_char(a.cuando, 'DD-MM-YYYY')
    from public.lead_accion a
   where a.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'tarea_hecha', a.completada_en, a.completada_por, a.que, null::text
    from public.lead_accion a
   where a.lead_id = p_lead and a.completada_en is not null
     and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
  union all
  select 'dueno', d.cuando, d.autor, coalesce(d.a, ''), coalesce(d.de, '')
    from public.lead_dueno_log d
   where d.lead_id = p_lead and public.puede('leads') and public.lead_a_mi_alcance(p_lead)
   order by 2 asc;
$$;

-- ============== LA AGENDA DE HOY ==============
create or replace function public.crm_agenda(p_solo_mias boolean default false)
returns table (
  accion_id uuid, lead_id uuid, nombre text, source text,
  que text, cuando date, responsable text, dias_de_retraso int
)
language sql stable security definer set search_path to ''
as $$
  select a.id, a.lead_id, l.name, l.source, a.que, a.cuando, a.responsable,
         ((now() at time zone 'Asia/Makassar')::date - a.cuando)::int
    from public.lead_accion a
    join public.leads l on l.id = a.lead_id
   where public.puede('leads')
     and public.lead_a_mi_alcance(a.lead_id)
     and a.completada_en is null
     and a.cuando <= (now() at time zone 'Asia/Makassar')::date
     and (not coalesce(p_solo_mias, false) or a.responsable = (select auth.email()))
   order by a.cuando asc;
$$;

grant execute on function public.lead_a_mi_alcance(uuid) to authenticated;
grant execute on function public.crm_mi_alcance() to authenticated;
revoke execute on function public.lead_a_mi_alcance(uuid) from public, anon;
revoke execute on function public.crm_mi_alcance() from public, anon;
revoke execute on function public.crm_leads() from public, anon;
revoke execute on function public.crm_lead_contacto(uuid, text) from public, anon;
revoke execute on function public.crm_lead_hilo(uuid) from public, anon;
revoke execute on function public.crm_agenda(boolean) from public, anon;
grant execute on function public.crm_leads() to authenticated;
grant execute on function public.crm_lead_contacto(uuid, text) to authenticated;
grant execute on function public.crm_lead_hilo(uuid) to authenticated;
grant execute on function public.crm_agenda(boolean) to authenticated;
