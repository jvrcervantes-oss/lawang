-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 4/6 (7-oct-2026): FACTURAS (y recibis) + justificantes de storage (agente_ve_justificante -> documento_visible).
--   Rol de empresa = las facturas cuyo proyecto es de SUS empresas (ademas de las de contratos que ya ve). Factura sin proyecto: solo global.
--   Agente/PM: lo de siempre Y el proyecto de la factura dentro de su alcance (lista vacia = sin restriccion = hoy).
--   Lo emitido NO se reetiqueta: se usa el proyecto_id que ya tiene cada factura.
--   Las ramas «autor» y «PM» solo pagan el filtro de empresa cuando casan (cortocircuito): el coste por fila del caso normal no sube.
-- destructivo-ok: create or replace de documento_visible y alter policy (misma expresion salvo el filtro nuevo); sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public.documento_visible(p_autor text, p_proyecto_id uuid, p_contrato_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  -- Por fila en facturas y recibís: autor y PM en línea (mismas reglas que es_suyo y
  -- es_manager_de) para no encadenar llamadas DEFINER; la venta, por la puerta.
  select public.es_admin()
      or (coalesce(p_autor = (select auth.email()), false) and public.proyecto_en_alcance(p_proyecto_id))
      or (p_proyecto_id is not null and exists (
            select 1 from public.usuarios u
             where u.user_id = (select auth.uid()) and u.activo
               and u.rol = 'project_manager'
               and p_proyecto_id = any (u.proyectos_supervisados))
          and public.proyecto_en_alcance(p_proyecto_id))
      or (p_proyecto_id is not null and exists (
            select 1 from public.usuarios u
              join public.proyectos pr on pr.id = p_proyecto_id
             where u.user_id = (select auth.uid()) and u.activo
               and u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa')
               and pr.empresa = any (u.empresas)))
      or (p_contrato_id is not null and public.puede_ver_contrato(p_contrato_id))
$$;

alter policy "agentes leen sus facturas" on public.facturas
  using ((( SELECT es_agente() AS es_agente) AND (( SELECT es_admin() AS es_admin)
     OR ((COALESCE((creado_por = ( SELECT auth.email() AS email)), false)
         OR (proyecto_id = ANY (( SELECT mis_proyectos_supervisados() AS mis_proyectos_supervisados)::uuid[]))
         OR (contrato_id = ANY (( SELECT mis_contratos_visibles() AS mis_contratos_visibles)::uuid[]))) AND proyecto_en_alcance(proyecto_id))
     OR (proyecto_id IS NOT NULL AND es_admin_de(empresa_de_proyecto(proyecto_id))))));
