-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 1 · migracion 3 (8-oct-2026): un super_admin_empresa no necesita casillas de herramienta en SU empresa.
--   puede('x') solo salta las casillas al super_admin GLOBAL; el owner dijo «poderes de superadmin para toda su empresa». Las 5 puertas de mi bloque que exigen herramienta
--   (contrato_guarda, contrato_poder_vincula, _contrato_anexo_check -> 'contratos'; unidad_guarda, unidades_importa -> 'unidades') aceptan ademas a un super_admin_empresa.
--   Solo abre la casilla: lo que se toca sigue acotado a su empresa por las comprobaciones de objeto de cada funcion (es_manager_de, puede_ver_contrato, puede_proyecto_de).
--   Un admin_empresa NO salta casillas (igual que un admin global). Funcion nueva con llamador con nombre: _puede_herr_o_super_empresa (las 5 funciones; sin EXECUTE para nadie).
-- destructivo-ok: create or replace de funciones; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b1.sql (PARTE 3)

create or replace function pg_temp.parchea(p_f regprocedure, p_old text, p_new text, p_n int default 1) returns void language plpgsql as $f$
declare v text; v_c int;
begin
  v := pg_get_functiondef(p_f);
  v_c := (length(v) - length(replace(v, p_old, ''))) / length(p_old);
  if v_c <> p_n then
    raise exception 'parche f2_b1: «%» aparece % veces en %, esperaba %', p_old, v_c, p_f, p_n;
  end if;
  execute replace(v, p_old, p_new);
end $f$;

create function public._puede_herr_o_super_empresa(p_herr text)
 returns boolean language sql stable security definer set search_path = '' as $$
  select public.puede(p_herr) or exists (
    select 1 from public.usuarios u
     where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa' and u.rol = 'super_admin_empresa')
$$;
revoke all on function public._puede_herr_o_super_empresa(text) from public, anon, authenticated, lw_lector;

select pg_temp.parchea('public.contrato_guarda(uuid,jsonb)'::regprocedure,
  $q$public.puede('contratos')$q$, $q$public._puede_herr_o_super_empresa('contratos')$q$);
select pg_temp.parchea('public.contrato_poder_vincula(uuid)'::regprocedure,
  $q$public.puede('contratos')$q$, $q$public._puede_herr_o_super_empresa('contratos')$q$);
select pg_temp.parchea('public._contrato_anexo_check(uuid)'::regprocedure,
  $q$public.puede('contratos')$q$, $q$public._puede_herr_o_super_empresa('contratos')$q$);
select pg_temp.parchea('public.unidad_guarda(uuid,jsonb,text)'::regprocedure,
  $q$public.puede('unidades')$q$, $q$public._puede_herr_o_super_empresa('unidades')$q$);
select pg_temp.parchea('public.unidades_importa(jsonb)'::regprocedure,
  $q$public.puede('unidades')$q$, $q$public._puede_herr_o_super_empresa('unidades')$q$);
