-- Color del moanito de «Mi perfil» (9-oct-2026, owner): cada cliente elige el color de su icono desde el portal.
-- La lista cerrada vive AQUÍ (check + función), no en el navegador: el front manda una clave y la base decide si vale
-- («no te creas nada del front-end»). Se guarda en preferencias_comprador, que ya es de «lo que el comprador ajusta».
-- Dos funciones propias en vez de tocar portal_situacion (una sola función enorme que otras sesiones editan a la vez).

alter table public.preferencias_comprador
  add column if not exists avatar_color text
  check (avatar_color is null or avatar_color in ('petroleo','selva','oliva','arena','oceano','ciruela','tinta','carbon'));

comment on column public.preferencias_comprador.avatar_color is
  'Clave del color del moanito del portal (petroleo por defecto si es null). Se escribe solo vía portal_set_color_avatar().';

create or replace function public.portal_get_color_avatar()
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare v text;
begin
  if not public.es_portal() then raise exception 'solo portal' using errcode = '42501'; end if;
  select pc.avatar_color into v
    from public.preferencias_comprador pc
    join public.portal_accesos pa on pa.client_id = pc.client_id
   where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
   order by pc.actualizado_en desc limit 1;
  return coalesce(v, 'petroleo');
end $$;

create or replace function public.portal_set_color_avatar(p_color text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.es_portal() then raise exception 'solo portal' using errcode = '42501'; end if;
  if p_color is null or p_color not in ('petroleo','selva','oliva','arena','oceano','ciruela','tinta','carbon') then
    raise exception 'color no válido' using errcode = '22023';
  end if;
  insert into public.preferencias_comprador (client_id, avatar_color)
    select pa.client_id, p_color
      from public.portal_accesos pa
     where pa.activo and pa.email = lower(coalesce(auth.email(), ''))
  on conflict (client_id) do update
    set avatar_color = excluded.avatar_color, actualizado_en = now();
end $$;

revoke execute on function public.portal_get_color_avatar() from public, anon;
revoke execute on function public.portal_set_color_avatar(text) from public, anon;
grant execute on function public.portal_get_color_avatar() to authenticated;
grant execute on function public.portal_set_color_avatar(text) to authenticated;
