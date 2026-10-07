-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 · 7 (7-oct-2026): gasto_ruta_visible acepta el uuid de la ruta en mayusculas o minusculas (~*). Aplicada como migracion aparte (f2_b2_7_gasto_ruta_case);
--   el mismo texto ya esta en 20261008201000_f2_b2_1_ayudas_empresa_dinero.sql: este fichero lo repite para que el nombre aplicado tenga su texto (LAW-496). Idempotente, texto identico al vivo.
-- destructivo-ok: create or replace con el mismo cuerpo; sin borrar datos
-- REVERTIR: no hace falta (identico al vivo)
create or replace function public.gasto_ruta_visible(p_ruta text) returns boolean
language sql stable security definer set search_path = '' as $$
  select case when split_part(p_ruta, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then public.gasto_id_visible(split_part(p_ruta, '/', 1)::uuid) else false end $$;
