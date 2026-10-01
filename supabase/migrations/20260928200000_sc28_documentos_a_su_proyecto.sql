-- SC-28 (petición del equipo, decisión del owner 28-sep-2026): 15 documentos estaban archivados como
-- «Lawang (general)» con general=false, así que salían en «Empresa (general)» aunque su carpeta dice de qué
-- proyecto son (Bonian Village 7, Palm Field 4, Horizon S1 4). Pasan al proyecto de su carpeta.
--   · Carpeta «Palm Field» → proyecto «Palm Field W5»: precedente, 5 documentos de ese proyecto ya viven en esa carpeta.
--   · proyecto_id lo pone el trigger documentos_resuelve_proyecto (nombre exacto → id); aquí no se escriben ids.
--   · `confidencial` se deja como está. OJO: en Lawang `confidencial` NO restringe la lectura (la RLS y la
--     descarga del bucket miran solo general / puede_proyecto). El owner acepta que el equipo de cada proyecto
--     los vea y descargue (28-sep). Una marca «solo admin» real queda en pendientes.
--   · «Empresa (general)» se queda con los 4 generales de verdad (carpeta «PT TEPI SUN GAI», general=true).
-- Sin DELETE. Guardas: exactamente 15 filas, ninguna sin proyecto_id tras el cambio, y nada más en «(general)».
-- Vuelta atrás (las 15 filas, medidas antes de aplicar): update public.documentos_proyecto
--   set proyecto = 'Lawang (general)', proyecto_id = null where id in (
--   0dfc04ef-8fa6-4b7b-99d4-cebf27c72d14, 0eced78f-cfc2-48b9-a182-fb498c9b4a7b, 304f0ae5-9b85-4ba8-b227-2b6dd20b50cb,
--   334a8889-e9e7-4714-ac4e-0698584ccc7b, 43858139-5b8c-4962-a2c6-cbb3b81b310d, 7c0258c2-a063-440a-86cb-03abc882421d,
--   830e8911-30c8-4950-8db3-cdfd2cab79ff, 92d2bb99-8063-422e-9c2a-a25d42e51a1a, baaadf2f-8771-4c7a-ba24-17878afab372,
--   d71bc1d1-110d-4681-bda2-90c94c52e66a, dbd7ba2c-f198-429c-a34b-92b5ceea75b7, dd7830c1-f278-485b-90b8-6b097d90172d,
--   e114e7c6-0e2b-4d44-a5be-54c749f2af2c, e4095d88-44a7-4d94-b6e0-ccebbb486758, f06bfa40-e465-4f3b-8390-d3c16d96053e)  (ids entre comillas)
-- erp-ok: Lawang independiente (owner 28-sep)
do $$
declare n int; resto int; huerfanos int;
begin
  update public.documentos_proyecto d
     set proyecto = case d.carpeta when 'Bonian Village' then 'Bonian Village'
                                   when 'Palm Field'     then 'Palm Field W5'
                                   when 'Horizon S1'     then 'Horizon S1' end
   where d.proyecto = 'Lawang (general)'
     and d.carpeta in ('Bonian Village', 'Palm Field', 'Horizon S1')
     and d.proyecto_id is null
     and d.general = false;
  get diagnostics n = row_count;
  if n <> 15 then raise exception 'SC-28: esperaba 15 filas, afectadas %', n; end if;

  select count(*) into huerfanos from public.documentos_proyecto
   where proyecto in ('Bonian Village', 'Palm Field W5', 'Horizon S1') and proyecto_id is null;
  if huerfanos > 0 then raise exception 'SC-28: % filas sin proyecto_id tras el cambio', huerfanos; end if;

  select count(*) into resto from public.documentos_proyecto
   where proyecto in ('Lawang (general)', 'Sumba (general)')
     and not (carpeta = 'PT TEPI SUN GAI' and general);
  if resto > 0 then raise exception 'SC-28: quedan % filas en «(general)» que no son las 4 generales', resto; end if;
end $$;
