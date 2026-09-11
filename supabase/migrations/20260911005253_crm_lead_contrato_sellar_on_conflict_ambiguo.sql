-- Arreglo del mismo dia: `on conflict (lead_id, contrato_id)` era AMBIGUO. `lead_id` y
-- `contrato_id` son tambien los nombres de los parametros de salida de la funcion, y en el
-- destino de un ON CONFLICT no se puede cualificar con el alias de la tabla. Postgres no lo
-- avisa al crear la funcion: revienta en tiempo de ejecucion con «column reference "lead_id"
-- is ambiguous», que es justo lo que caza la prueba de camino completo.
-- Se apunta al constraint por su nombre, que no admite ambiguedad posible.
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

revoke execute on function public.crm_lead_contrato_sellar(uuid, uuid) from public, anon;
grant execute on function public.crm_lead_contrato_sellar(uuid, uuid) to authenticated;
