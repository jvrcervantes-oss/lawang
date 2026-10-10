-- Reconstruida el 10-oct-2026 desde supabase_migrations.schema_migrations.statements (version y nombre exactos; ya APLICADA en produccion, no se vuelve a aplicar). Su cambio ya esta fundido en: 20260928230000_documento_borra_admin.sql
-- destructivo-ok: el DELETE es el cuerpo ya existente de la función (borra UNA fila cuando la llama la edge); aplicar esto no borra nada
create or replace function public.documento_proyecto_borra(p_uid uuid, p_id uuid, p_solo_comprobar boolean default false)
returns text
language plpgsql security definer set search_path = '' as $$
declare v_d public.documentos_proyecto%rowtype;
begin
  perform public._actua_como(p_uid);
  if not (public.es_admin() and public.puede('documentacion')) then
    raise exception 'Borrar documentación lo hace administración con la herramienta «Documentación»' using errcode = '42501';
  end if;
  select * into v_d from public.documentos_proyecto d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;
  if not (v_d.general or public.puede_proyecto(v_d.proyecto, v_d.proyecto_id)) then
    raise exception 'Ese documento no es de tus proyectos' using errcode = '42501';
  end if;
  if not coalesce(p_solo_comprobar, false) then delete from public.documentos_proyecto where id = p_id; end if;
  return v_d.path;
end $$;;
