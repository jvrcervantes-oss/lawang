-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2A · migracion 1/6 (7-oct-2026): dos ayudas de alcance. NO cambian nada visible por si solas (nadie las llama aun).
--   _ve_empresa(empresa): ¿la ficha del que llama deja ver una cosa de esa empresa? global con lista de empresas vacia (los 34 de hoy) = si a todo, incluida
--     la empresa nula (Karana); global con lista = solo esas; rol de empresa = solo las suyas; empresa nula + lista no vacia = NO (nace cerrado).
--     NO da permiso por si sola: es un FILTRO que se suma al permiso que ya tenia cada funcion. Solo la llaman otras funciones DEFINER (sin EXECUTE para nadie).
--   proyecto_en_alcance(proyecto): lo mismo sobre la empresa de ese proyecto; la llama directamente la policy de facturas (por eso lleva EXECUTE).
-- destructivo-ok: solo crea dos funciones nuevas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2a.sql
create or replace function public._ve_empresa(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo
       and ((u.ambito = 'global' and (cardinality(u.empresas) = 0 or p_empresa = any (u.empresas)))
         or (u.ambito = 'empresa' and p_empresa = any (u.empresas))))
$$;
revoke all on function public._ve_empresa(text) from public, anon, authenticated, lw_lector;

create or replace function public.proyecto_en_alcance(p_proyecto_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._ve_empresa((select p.empresa from public.proyectos p where p.id = p_proyecto_id))
$$;
revoke all on function public.proyecto_en_alcance(uuid) from public, anon;
grant execute on function public.proyecto_en_alcance(uuid) to authenticated, lw_lector;
