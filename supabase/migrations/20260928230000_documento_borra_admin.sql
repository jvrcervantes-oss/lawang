-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
--
-- Borrar enlaces y documentos de la documentación de un proyecto: también el rol ADMIN, no solo super admin
-- (owner, 28-sep-2026: «necesito botón para borrar enlaces subidos a Enlaces del proyecto… aplicarlo a la
-- categoría admin»). La puerta sigue siendo esta RPC (la llama la edge `ficheros`, que quita fichero y ficha
-- juntos). Además de ser admin, el documento tiene que estar a su alcance: uno general de la empresa, o de un
-- proyecto que ese admin puede ver (misma regla que editarlo en documento_proyecto_guarda).

-- destructivo-ok: el DELETE es el cuerpo ya existente de la función (borra UNA fila cuando la llama la edge); aplicar esto no borra nada
create or replace function public.documento_proyecto_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false)
returns text
language plpgsql security definer set search_path = '' as $$
declare v_d public.documentos_proyecto%rowtype;
begin
  perform public._actua_como(p_uid);
  if not public.es_admin() then raise exception 'Borrar documentación lo hace administración' using errcode = '42501'; end if;
  select * into v_d from public.documentos_proyecto d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
  if not (v_d.general or public.puede_proyecto(v_d.proyecto, v_d.proyecto_id)) then
    raise exception 'Ese documento no es de tus proyectos' using errcode = '42501';
  end if;
  if not coalesce(p_solo_comprobar, false) then delete from public.documentos_proyecto where id = p_id; end if;
  return v_d.path;
end $$;
