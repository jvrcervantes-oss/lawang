create or replace function public.renombrar_proyecto(p_antiguo text, p_nuevo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unidades int; v_contratos int; v_facturas int; v_documentos int; v_modelos int;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede renombrar un proyecto';
  end if;
  if p_antiguo is null or trim(p_antiguo) = '' or p_nuevo is null or trim(p_nuevo) = '' then
    raise exception 'Nombre de proyecto vacío';
  end if;
  if p_antiguo = p_nuevo then
    return jsonb_build_object('sin_cambios', true);
  end if;
  if exists (select 1 from public.proyectos where nombre = p_nuevo) then
    raise exception 'Ya existe un proyecto llamado "%"', p_nuevo;
  end if;

  update public.proyectos set nombre = p_nuevo where nombre = p_antiguo;

  update public.unidades set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_unidades = row_count;

  update public.contratos set proyecto_nombre = p_nuevo where proyecto_nombre = p_antiguo;
  get diagnostics v_contratos = row_count;
  update public.contratos
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and bloqueado = false
     and datos #>> '{fields,proyecto_nombre}' = p_antiguo;

  update public.facturas set proyecto_nombre = p_nuevo where proyecto_nombre = p_antiguo;
  get diagnostics v_facturas = row_count;
  update public.facturas
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and not anulada
     and datos #>> '{fields,proyecto_nombre}' = p_antiguo;

  update public.documentos_proyecto set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_documentos = row_count;

  update public.modelos_villa set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_modelos = row_count;

  return jsonb_build_object(
    'unidades', v_unidades, 'contratos', v_contratos, 'facturas', v_facturas,
    'documentos_proyecto', v_documentos, 'modelos_villa', v_modelos
  );
end;
$$;

revoke all on function public.renombrar_proyecto(text, text) from public;
grant execute on function public.renombrar_proyecto(text, text) to authenticated;
;
