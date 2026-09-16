-- El REVOKE FROM PUBLIC de la migracion anterior no basto: este proyecto
-- tiene privilegios por defecto que conceden EXECUTE a anon/authenticated
-- en cualquier funcion nueva del esquema public, y se aplicaron DESPUES
-- del REVOKE explicito. Verificado con information_schema.routine_privileges
-- tras el CREATE: anon y authenticated seguian con EXECUTE. Esta funcion
-- expone el cobro real de CUALQUIER unidad sin el gate de permiso -- no
-- puede quedar alcanzable por nadie que no sea el propio trigger.
REVOKE EXECUTE ON FUNCTION public.unidad_parte_cobrada_interno(uuid) FROM PUBLIC, anon, authenticated;
