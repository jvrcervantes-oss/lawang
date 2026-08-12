-- Petición del owner (12-ago-2026): "Permíteme borrar proyectos, sólo a
-- super admin". Hasta ahora `proyectos` solo tenía alta (cualquier agente) y
-- una policy de UPDATE sin usar en la UI ("admin desactiva proyectos",
-- es_admin() = admin o super_admin) — ningún borrado real, ni duro ni
-- blando. Esto es distinto y más estricto: DELETE de verdad, restringido a
-- super_admin (no admin), tal como se pidió.
--
-- `proyecto`/`proyecto_nombre` es texto libre en 6 tablas (mismo motivo que
-- documenta renombrar_proyecto.sql). Borrar el catálogo no rompe nada en
-- contratos/facturas (proyecto_nombre es una foto impresa, no una consulta
-- en vivo), así que esas dos NO bloquean. unidades/modelos_villa/
-- documentos_proyecto SÍ: borrar el catálogo con eso colgando los dejaría
-- huérfanos de verdad, así que se exige vaciarlos antes.
create or replace function public.borrar_proyecto(p_nombre text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unidades int; v_modelos int; v_documentos int;
begin
  if not public.es_super_admin() then
    raise exception 'solo un super_admin puede borrar un proyecto' using errcode = '42501';
  end if;

  select count(*) into v_unidades from public.unidades where proyecto = p_nombre;
  if v_unidades > 0 then
    raise exception 'el proyecto tiene % unidad(es) dadas de alta — bórralas o muévelas primero', v_unidades using errcode = '23503';
  end if;

  select count(*) into v_modelos from public.modelos_villa where proyecto = p_nombre;
  if v_modelos > 0 then
    raise exception 'el proyecto tiene % modelo(s) de villa — bórralos primero', v_modelos using errcode = '23503';
  end if;

  select count(*) into v_documentos from public.documentos_proyecto where proyecto = p_nombre;
  if v_documentos > 0 then
    raise exception 'el proyecto tiene % documento(s) subido(s) — bórralos primero', v_documentos using errcode = '23503';
  end if;

  delete from public.proyectos where nombre = p_nombre;
  if not found then
    raise exception 'no existe un proyecto con ese nombre' using errcode = '23503';
  end if;
end;
$$;

revoke all on function public.borrar_proyecto(text) from public, anon;
grant execute on function public.borrar_proyecto(text) to authenticated;
