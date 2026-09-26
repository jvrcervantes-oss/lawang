-- destructivo-ok: quita PERMISOS de escritura directa de la pantalla (revoke); no borra ni cambia ninguna fila. Permiso de migraciones del owner (27-sep); pieza 8 publicada y verificada.
-- Frontera (LAW-336) pieza 8, cierre. Desde b1a1cd78/2eac8fe5 ninguna pantalla escribe directo en estas tablas
-- (grep del repo: 0) y ninguna función SECURITY INVOKER las escribe. Verificado después con sesión de admin:
-- update/insert directo fallan, `unidad_guarda` va; authenticated sin grants de escritura (tabla ni columna).
revoke insert, update, delete on public.unidades       from authenticated;
revoke insert, update, delete on public.proyectos      from authenticated;
revoke insert, update, delete on public.tipos_vivienda from authenticated;
