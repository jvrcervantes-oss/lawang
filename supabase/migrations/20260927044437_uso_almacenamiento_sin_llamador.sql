-- uso_almacenamiento(bigint,bigint) se queda SIN LLAMADOR (27-sep-2026): la única pantalla que lo
-- pedía era el medidor de la Documentación clásica (/intranet/documentacion/), retirada ese día
-- (copia 0927-1158-permisos-v4-docs; revisor de código). Buscado antes: ninguna pantalla v4, edge,
-- herramienta de tools/ ni panel del estudio lo llama; ninguna función de la base tampoco.
-- Reducir la exposición: se revoca EXECUTE a public/anon/authenticated y NO se borra la función —
-- el aviso diario (cron `revisar-almacenamiento` → revisar_almacenamiento()) usa `_uso_almacenamiento()`,
-- que ya estaba cerrado, y si el medidor vuelve a una pantalla v4 basta con un grant.
revoke all on function public.uso_almacenamiento(bigint, bigint) from public, anon, authenticated;
;
