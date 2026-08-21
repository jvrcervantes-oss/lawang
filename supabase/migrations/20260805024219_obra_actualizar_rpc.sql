-- La herramienta Obra toca SOLO las columnas de obra de `unidades`. Sin esta RPC
-- haría falta el permiso de Unidades entero (precios incluidos) para cambiar una fase.
create or replace function public.obra_actualizar(p_unidad uuid, p_fase text, p_fecha date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (es_agente() and puede('obra')) then
    raise exception 'sin permiso para obra' using errcode = '42501';
  end if;
  update unidades
     set obra_fase = nullif(btrim(coalesce(p_fase, '')), ''),
         obra_fecha_entrega = p_fecha,
         obra_actualizado = now()
   where id = p_unidad;
  if not found then
    raise exception 'unidad inexistente';
  end if;
end $$;
revoke execute on function public.obra_actualizar(uuid, text, date) from public;
revoke execute on function public.obra_actualizar(uuid, text, date) from anon;
grant execute on function public.obra_actualizar(uuid, text, date) to authenticated;;
