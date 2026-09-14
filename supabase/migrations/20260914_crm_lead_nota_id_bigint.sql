-- crm_lead_nota declaraba `id uuid` pero lead_notas.id es bigserial (bigint): cada
-- alta reventaba con "structure of query does not match function result type".
-- CREATE OR REPLACE no permite cambiar el tipo de salida -> DROP + CREATE.
-- destructivo-ok: DROP de una FUNCION (no de datos) para corregir su tipo de retorno; se recrea a continuacion en la misma migracion.
drop function if exists public.crm_lead_nota(uuid, text);

create function public.crm_lead_nota(p_lead uuid, p_texto text)
returns table (id bigint, texto text, autor text, created_at timestamptz)
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

revoke execute on function public.crm_lead_nota(uuid, text) from public, anon;
grant execute on function public.crm_lead_nota(uuid, text) to authenticated;
