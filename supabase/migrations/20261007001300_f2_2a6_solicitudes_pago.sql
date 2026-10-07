-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 6/6 (7-oct-2026): SOLICITUDES DE PAGO. Una solicitud cuelga de un contrato. Un rol de empresa con la herramienta «comisiones»
--   (los de empresa no son es_super_admin(), asi que la herramienta se le da a mano) ve las de contratos de SUS empresas. Lo propio y lo del beneficiario, igual.
--   admin_de_contrato(contrato): ¿administra la empresa del proyecto de ese contrato? Contrato sin proyecto o nulo: false (solo es_admin() pasa, por la rama de siempre).
-- destructivo-ok: funcion nueva + alter policy (misma expresion salvo la rama nueva); sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public.admin_de_contrato(p_contrato_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.usuarios u
      join public.contratos c on c.id = p_contrato_id
      join public.proyectos p on p.id = c.proyecto_id
     where u.user_id = (select auth.uid()) and u.activo
       and u.ambito = 'empresa' and u.rol in ('admin_empresa','super_admin_empresa')
       and p.empresa = any (u.empresas))
$$;
revoke all on function public.admin_de_contrato(uuid) from public, anon;
grant execute on function public.admin_de_contrato(uuid) to authenticated, lw_lector;

alter policy "solicitudes: cada uno lee las suyas, admin con casilla todas" on public.solicitudes_pago
  using ((((es_admin() OR admin_de_contrato(contrato_id)) AND puede('comisiones'::text)) OR ((creado_por = ( SELECT auth.uid() AS uid)) AND (origen IS DISTINCT FROM 'comision_automatica'::text)) OR (beneficiario_email = ( SELECT auth.email() AS email))));
