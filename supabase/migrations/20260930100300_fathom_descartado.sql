-- destructivo-ok: owner 30-sep-2026 («si, aplica»): Fathom descartado, 2 tablas con 0 filas y 1 funcion; backup datos hecho 09:51
-- 30-sep-2026 · Fathom DESCARTADO por el owner. Se retira todo lo que colgaba de el (0 filas en las dos tablas).
-- Orden: primero se quita la unica dependencia viva de lead_closer (el respaldo de responsable de crm_lead_accion_poner,
-- que leia lead_closer; con la tabla vacia nunca aportaba nada), y solo despues se borra funcion y tablas.
-- Antes: responsable = lead_estado.responsable, si no el closer de lead_closer, si no quien pone la accion.
-- Ahora: lead_estado.responsable, si no quien pone la accion. Nada mas cambia en la funcion.
-- Inversa: contracts/sql/inversa_limpieza_superficie_20260930.sql
create or replace function public.crm_lead_accion_poner(p_lead uuid, p_que text, p_cuando date, p_responsable text default null::text)
 returns table(id uuid, lead_id uuid, que text, cuando date, responsable text)
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
$function$;

revoke execute on function public.crm_lead_fathom(uuid) from public, anon, authenticated;
drop function public.crm_lead_fathom(uuid);
drop table public.fathom_call_insights;
drop table public.lead_closer;
