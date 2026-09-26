-- Frontera frontend/backend — PROVEEDORES por el servidor (26-sep-2026, LAW-336 pieza 3).
-- Solo los campos del formulario; autoría la pone _proveedores_autoria. Permiso = policies de hoy.
-- Probado: el autor y `activo` que mande el formulario en el alta se ignoran; un agente, 42501.
create or replace function public.proveedor_guarda(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public._gasto_puede() then raise exception 'Proveedores exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if p_id is null then
    insert into public.proveedores as p (nombre, tipo, npwp, contacto, telefono, email, notas)
    values (btrim(coalesce(p_datos->>'nombre', '')), coalesce(nullif(p_datos->>'tipo', ''), 'proveedor'),
            nullif(btrim(coalesce(p_datos->>'npwp', '')), ''), nullif(btrim(coalesce(p_datos->>'contacto', '')), ''),
            nullif(btrim(coalesce(p_datos->>'telefono', '')), ''), nullif(btrim(coalesce(p_datos->>'email', '')), ''),
            nullif(btrim(coalesce(p_datos->>'notas', '')), ''))
    returning p.id into v_id;
  else
    update public.proveedores p set
      nombre = btrim(coalesce(p_datos->>'nombre', '')), tipo = coalesce(nullif(p_datos->>'tipo', ''), p.tipo),
      npwp = nullif(btrim(coalesce(p_datos->>'npwp', '')), ''), contacto = nullif(btrim(coalesce(p_datos->>'contacto', '')), ''),
      telefono = nullif(btrim(coalesce(p_datos->>'telefono', '')), ''), email = nullif(btrim(coalesce(p_datos->>'email', '')), ''),
      notas = nullif(btrim(coalesce(p_datos->>'notas', '')), ''),
      activo = case when p_datos ? 'activo' then coalesce((p_datos->>'activo')::boolean, p.activo) else p.activo end
    where p.id = p_id returning p.id into v_id;
    if v_id is null then raise exception 'Ese proveedor ya no existe' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end $$;
revoke all on function public.proveedor_guarda(uuid, jsonb) from public, anon;
grant execute on function public.proveedor_guarda(uuid, jsonb) to authenticated;
