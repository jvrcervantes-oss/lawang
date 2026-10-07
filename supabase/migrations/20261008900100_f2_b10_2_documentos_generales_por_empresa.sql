-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- BLOQUE 10 · 2/2 (Fase 2, prueba final de aislamiento, 7-oct-2026). Los documentos «generales» (general = true: NIB, NPWP, Akta y Sertifikat de PT Tepi Sungai, con su carpeta de Drive)
--   los leia CUALQUIER agente, tambien el admin de la otra empresa. Se les da dueno: columna `empresa` (nula = sin dueno = solo los no acotados) y el reparto de hoy: los 4 son de Lawang
--   (proyecto «Lawang (general)», carpeta «PT TEPI SUN GAI»). Un rol de empresa ve los generales de SUS empresas; los 34 usuarios de hoy siguen viendo todos.
--   `agente_ve_documento_proyecto` (storage) aplica lo mismo. Pendiente con dueno: una pantalla/RPC para fijar la empresa de un general nuevo (hoy solo lo crea un admin global y nace sin dueno = cerrado a los roles de empresa).
-- destructivo-ok: anade una columna nullable y la rellena en 4 filas; no borra nada
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b10.sql
alter table public.documentos_proyecto add column if not exists empresa text references public.empresas (clave);
update public.documentos_proyecto set empresa = 'lawang' where general and empresa is null and (proyecto = 'Lawang (general)' or carpeta = 'PT TEPI SUN GAI');

drop policy if exists "documentacion: leer" on public.documentos_proyecto;
create policy "documentacion: leer" on public.documentos_proyecto for select to authenticated, lw_lector
  using (public.es_agente() and (
           (general and (not (select public.alcance_restringido()) or (documentos_proyecto.empresa is not null and public.empresa_en_alcance(documentos_proyecto.empresa))))
        or public.puede_proyecto(proyecto, proyecto_id)));

create or replace function public.agente_ve_documento_proyecto(p_name text) returns boolean
 language sql stable security definer set search_path to ''
as $function$
  select public.es_agente() and exists (
    select 1
      from public.documentos_proyecto dp
     where dp.path = p_name
       and ((dp.general and (not public.alcance_restringido() or (dp.empresa is not null and public.empresa_en_alcance(dp.empresa))))
            or public.puede_proyecto(dp.proyecto, dp.proyecto_id)))
$function$;
