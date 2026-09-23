-- Permisos de VISTA propios (23-sep-2026, owner: «hay herramientas que no se
-- controla la vista desde usuarios como las demás» -> «separa todo»).
-- Reservas, Modelos, Asistente y Recibos colgaban de operaciones / unidades /
-- contratos / facturas: no se podían quitar sin quitar la madre. Ahora tienen
-- casilla propia. Para que nadie pierda nada, la hija se da a quien ya tenía
-- la madre (mismo criterio que 'vencimientos' el 18-ago). Guardar en la base
-- sigue pidiendo el permiso madre (policies de contratos/facturas/unidades).
-- De paso se quita el literal 'on' que la ficha clásica de Usuarios metía
-- por cada casilla del espejo de proyectos supervisados (arreglado el mismo
-- día); no daba ni quitaba acceso.
-- Se ejecuta como el super_admin owner: el trigger
-- usuarios_bloquea_cambio_rol_herramientas solo deja a un super_admin tocar
-- herramientas, y el cambio lo pidió él. Ensayado en ROLLBACK: asistente 32 =
-- contratos 32, recibos 28 = facturas 28, modelos 31 = unidades 31,
-- reservas 25 = operaciones 25, 'on' 0.
select set_config('request.jwt.claims', json_build_object('sub',
  (select user_id from public.usuarios where email = 'jvr.cervantes@gmail.com' and rol = 'super_admin'),
  'role', 'authenticated')::text, true);

update public.usuarios u set herramientas = coalesce((
  select array_agg(distinct h order by h) from unnest(
    array_remove(u.herramientas, 'on')
    || case when 'contratos'   = any(u.herramientas) then array['asistente'] else '{}'::text[] end
    || case when 'facturas'    = any(u.herramientas) then array['recibos']   else '{}'::text[] end
    || case when 'unidades'    = any(u.herramientas) then array['modelos']   else '{}'::text[] end
    || case when 'operaciones' = any(u.herramientas) then array['reservas']  else '{}'::text[] end) h), '{}'::text[])  -- coalesce: una fila con solo {'on'} quedaría NULL (Seguridad, consulta de deploy)
where u.herramientas && array['contratos', 'facturas', 'unidades', 'operaciones', 'on'];
