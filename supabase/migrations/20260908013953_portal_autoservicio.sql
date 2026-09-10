-- Fuente única y comentada: contracts/sql/portal_autoservicio.sql
-- El acceso al portal deja de concederse a mano: tener ficha de comprador con
-- ese correo + al menos un contrato = acceso. Revocado manda sobre la regla,
-- el equipo no entra por aquí, y portal_accesos sigue siendo la fuente única
-- (esta función solo la siembra).
create or replace function public.portal_autoservicio(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_creadas int  := 0;
  v_activos int  := 0;
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('elegible', false, 'motivo', 'email_invalido');
  end if;

  if exists (select 1 from public.usuarios u where lower(btrim(u.email)) = v_email) then
    return jsonb_build_object('elegible', false, 'motivo', 'equipo');
  end if;

  if exists (select 1 from public.portal_accesos pa where pa.email = v_email and not pa.activo) then
    return jsonb_build_object('elegible', false, 'motivo', 'revocado');
  end if;

  insert into public.portal_accesos (email, client_id, activo, creado_por)
  select v_email, c.id, true, 'autoservicio'
    from public.clients c
   where lower(btrim(coalesce(c.email, ''))) = v_email
     and exists (select 1 from public.contrato_compradores cc where cc.client_id = c.id)
  on conflict (email, client_id) do nothing;
  get diagnostics v_creadas = row_count;

  select count(*) into v_activos
    from public.portal_accesos pa where pa.email = v_email and pa.activo;

  if v_activos = 0 then
    return jsonb_build_object('elegible', false, 'motivo', 'sin_ficha');
  end if;

  return jsonb_build_object('elegible', true, 'creadas', v_creadas, 'accesos', v_activos);
end
$$;

comment on function public.portal_autoservicio(text) is
  'Decide si un correo tiene derecho al portal (ficha de comprador con contrato, no del equipo, no revocado) y siembra sus filas en portal_accesos. La llama la Edge portal-acceso con service_role; no crea la cuenta de Auth ni envia nada.';

revoke execute on function public.portal_autoservicio(text) from public;
revoke execute on function public.portal_autoservicio(text) from anon;
revoke execute on function public.portal_autoservicio(text) from authenticated;
grant  execute on function public.portal_autoservicio(text) to service_role;;
