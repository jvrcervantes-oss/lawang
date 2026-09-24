-- Creatividades v4, D2 (owner 24-sep-2026: «comerciales descargan lo aprobado»).
-- La casilla nueva `creatividades_ver` se da a los comerciales activos (agente,
-- sales_manager, project_manager). Solo VE lo aprobado o publicado: la RLS de
-- `creatividades` y de storage no le da escritura en ningún sitio.
-- Mismo patrón que 20260923180500_permisos_propios: se ejecuta como el super_admin
-- owner porque el trigger usuarios_bloquea_cambio_rol_herramientas solo deja a un
-- super_admin tocar herramientas. Ensayado en ROLLBACK: 27 filas. Aplicado: 20
-- agentes + 6 sales_manager + 1 project_manager.
select set_config('request.jwt.claims', json_build_object('sub',
  (select user_id from public.usuarios where email = 'jvr.cervantes@gmail.com' and rol = 'super_admin'),
  'role', 'authenticated')::text, true);
update public.usuarios u set herramientas = array_append(coalesce(u.herramientas, '{}'::text[]), 'creatividades_ver')
 where u.rol in ('agente', 'sales_manager', 'project_manager') and u.activo
   and not ('creatividades_ver' = any(coalesce(u.herramientas, '{}'::text[])));
