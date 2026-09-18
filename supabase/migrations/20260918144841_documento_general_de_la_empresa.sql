-- ============================================================================
-- El documento de la EMPRESA existe, y ahora lo dice la fila. 18-sep-2026.
--
-- QUE ROMPI ESTA MAÑANA. Al cerrar el agujero de `puede_proyecto` (migracion
-- `20260918021123`) desaparecio de la pantalla de Documentacion una familia de
-- documentos que NO es de ningun proyecto: los cuatro papeles de la sociedad
-- —NPWP, Akta, Sertifikat y NIB— guardados bajo el proyecto de mentira «Lawang
-- (general)». Se veian porque la puerta vieja ABRIA cuando el nombre no casaba
-- con ningun proyecto; o sea, se veian por el mismo fallo que habia que cerrar.
--
-- Medido despues del cambio, simulando sesiones reales: los 29 usuarios activos
-- perdieron esos 4 documentos, y para CINCO agentes (josealacid99, david,
-- santiblanes23, tikiencanarias, blueicrm) eran los UNICOS que veian — su
-- pantalla de Documentacion se quedo vacia.
--
-- POR QUE NO SE ARREGLA DEVOLVIENDO LA PUERTA. Porque el caso es legitimo y el
-- agujero no: hay documentos que son de la empresa y no de un proyecto. Lo que
-- faltaba no era permiso, era la categoria. Mismo patron que `es_escrow` en
-- `cuentas_bancarias` y `es_indonesia` en `sociedades`: lo dice la FILA, no como
-- este escrito su nombre.
--
-- Y de paso deja de ser cierto que cualquiera con la herramienta pueda EDITAR
-- los papeles de la sociedad: leer, todo el equipo; tocar, solo un admin.
--
-- destructivo-ok: el unico DROP es `drop policy` + `create policy` de las tres
-- politicas de `documentos_proyecto`, en la misma transaccion. No se borra
-- ninguna fila; se anade una columna y se marcan 4 filas.
-- ============================================================================

alter table public.documentos_proyecto
  add column if not exists general boolean not null default false;

comment on column public.documentos_proyecto.general is
  'Documento de la EMPRESA, no de un proyecto (NPWP, Akta, Sertifikat, NIB). Lo lee todo el equipo; lo edita solo un admin. Lo dice esta columna, nunca el texto de `proyecto`.';

-- Las cuatro que hoy viven bajo el proyecto de mentira. Se marcan por lo que
-- SON (sin proyecto real que las reclame), no por el literal del nombre.
update public.documentos_proyecto
   set general = true
 where proyecto_id is null
   and not exists (select 1 from public.proyectos p where p.nombre = btrim(documentos_proyecto.proyecto));

drop policy if exists "documentacion: leer" on public.documentos_proyecto;
create policy "documentacion: leer"
  on public.documentos_proyecto for select to authenticated
  using (es_agente() and (general or puede_proyecto(proyecto, proyecto_id)));

drop policy if exists "documentacion: subir" on public.documentos_proyecto;
create policy "documentacion: subir"
  on public.documentos_proyecto for insert to authenticated
  with check (
    es_agente() and puede('documentacion')
    and (case when general then es_admin() else puede_proyecto(proyecto, proyecto_id) end));

drop policy if exists "documentacion: editar" on public.documentos_proyecto;
create policy "documentacion: editar"
  on public.documentos_proyecto for update to authenticated
  using (
    es_agente() and puede('documentacion')
    and (case when general then es_admin() else puede_proyecto(proyecto, proyecto_id) end))
  with check (
    es_agente() and puede('documentacion')
    and (case when general then es_admin() else puede_proyecto(proyecto, proyecto_id) end));

-- El PDF en Storage NO se arregla solo: `agente_ve_documento_proyecto` resuelve
-- el objeto contra esta tabla, pero preguntando por el proyecto. Sin esta
-- segunda mitad la fila volveria a verse y el fichero seguiria sin descargarse
-- — la pantalla enseñaria cuatro documentos que no se abren, que es peor que no
-- enseñarlos. La politica del bucket no cambia; cambia a quien deja pasar.
create or replace function public.agente_ve_documento_proyecto(p_name text)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_agente() and exists (
    select 1
      from public.documentos_proyecto dp
     where dp.path = p_name
       and (dp.general or public.puede_proyecto(dp.proyecto, dp.proyecto_id)))
$$;
