-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 1 (8-oct-2026): AYUDAS para que las puertas del dinero decidan por empresa.
--   * proveedores.empresa (nula = global: solo admin/super global; las filas nuevas de un rol de empresa la fijan en el servidor). La tabla esta vacia: nada que rellenar.
--   * Ayudas PRIVADAS (sin EXECUTE para nadie salvo el propietario de la base: las llaman otras funciones DEFINER):
--       _rol_empresa()            ficha activa con ambito empresa (admin_empresa o super_admin_empresa)
--       _super_empresa_alguna()   ficha activa super_admin_empresa
--       _puede_herr(herr)         agente con la herramienta, o super_admin_empresa (que no necesita casillas: es «todo lo de un super» en su empresa)
--       _puede_herr_admin(herr)   puerta GRUESA de panel: admin global con la herramienta, o rol de empresa (super sin casilla, admin con ella)
--       _puede_admin_de(emp,herr) puerta FINA: super de esa empresa, o admin de esa empresa con la herramienta. Con empresa nula = solo global (nace cerrado)
--       _empresa_doc(proyecto, contrato)  empresa de una factura/recibi: la de su proyecto; si no tiene proyecto, la del proyecto de su contrato; si no, NULA.
--                                          (NO se usa empresa_de_factura para autorizar: cae a la sociedad y daria a INV00001-3 y REC00012 una empresa que el owner aun no ha decidido, LAW-E1)
--       _empresa_cuenta(clave) · _empresa_sociedad(clave) · _empresa_gasto(sociedad, proyecto) · _empresa_movimiento(mov) · _empresa_comision(devengo)
--   * Envoltorios con EXECUTE minimo (los llaman policies, leccion G1): gasto_visible, gasto_id_visible, proveedor_visible, banco_cuenta_visible, banco_movimiento_visible,
--     gasto_ruta_visible, gastos_acceso, sociedad_super_de, solicitud_admin_de_contrato, retencion_admin_de_solicitud. Cada uno solo contesta true/false sobre el que llama.
--   Nada cambia todavia para nadie: solo se crean. Los 34 usuarios de hoy: sin cambio.
-- destructivo-ok: add column nullable y funciones nuevas; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql
alter table public.proveedores add column if not exists empresa text references public.empresas(clave);

create or replace function public._rol_empresa() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa'
                    and u.rol in ('admin_empresa','super_admin_empresa')) $$;

create or replace function public._super_empresa_alguna() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo and u.ambito = 'empresa' and u.rol = 'super_admin_empresa') $$;

create or replace function public._puede_herr(p_herr text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_agente() and (public.puede(p_herr) or public._super_empresa_alguna()) $$;

create or replace function public._puede_herr_admin(p_herr text) returns boolean
language sql stable security definer set search_path = '' as $$
  select (public.es_admin() or public._rol_empresa()) and (public.puede(p_herr) or public._super_empresa_alguna()) $$;

create or replace function public._puede_admin_de(p_empresa text, p_herr text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_super_admin_de(p_empresa) or (public.es_admin_de(p_empresa) and public.puede(p_herr)) $$;

create or replace function public._empresa_doc(p_proyecto uuid, p_contrato uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
           when p_proyecto is not null then (select pr.empresa from public.proyectos pr where pr.id = p_proyecto)
           else (select pr.empresa from public.contratos c join public.proyectos pr on pr.id = c.proyecto_id where c.id = p_contrato)
         end $$;

create or replace function public._empresa_cuenta(p_clave text) returns text
language sql stable security definer set search_path = '' as $$
  select c.empresa from public.cuentas_bancarias c where c.clave = p_clave $$;

create or replace function public._empresa_sociedad(p_clave text) returns text
language sql stable security definer set search_path = '' as $$
  select e.clave from public.empresas e where e.sociedad_clave = p_clave $$;

create or replace function public._empresa_gasto(p_sociedad text, p_proyecto uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when p_proyecto is not null then (select pr.empresa from public.proyectos pr where pr.id = p_proyecto)
              else public._empresa_sociedad(p_sociedad) end $$;

create or replace function public._empresa_movimiento(p_mov uuid) returns text
language sql stable security definer set search_path = '' as $$
  select public._empresa_cuenta(m.cuenta_clave) from public.bancos_movimientos m where m.id = p_mov $$;

create or replace function public._empresa_comision(p_devengo uuid) returns text
language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.comisiones_devengadas d
    join public.contratos c on c.id = d.contrato_raiz_id
    join public.proyectos pr on pr.id = c.proyecto_id
   where d.id = p_devengo $$;

-- Envoltorios para policies: cada uno solo dice si el que llama puede, sin devolver datos.
create or replace function public.gasto_visible(p_sociedad text, p_proyecto uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_admin_de(public._empresa_gasto(p_sociedad, p_proyecto), 'gastos') $$;

create or replace function public.gasto_id_visible(p_gasto uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.gastos g where g.id = p_gasto and public.gasto_visible(g.sociedad, g.proyecto_id)) $$;

create or replace function public.gasto_ruta_visible(p_ruta text) returns boolean
language sql stable security definer set search_path = '' as $$
  select split_part(p_ruta, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.gasto_id_visible(split_part(p_ruta, '/', 1)::uuid) $$;

create or replace function public.proveedor_visible(p_empresa text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_admin_de(p_empresa, 'gastos') $$;

create or replace function public.banco_cuenta_visible(p_cuenta text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_admin_de(public._empresa_cuenta(p_cuenta), 'bancos') $$;

create or replace function public.banco_movimiento_visible(p_mov uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_admin_de(public._empresa_movimiento(p_mov), 'bancos') $$;

create or replace function public.gastos_acceso() returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_herr_admin('gastos') $$;

create or replace function public.sociedad_super_de(p_clave text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_super_admin_de(public._empresa_sociedad(p_clave)) $$;

create or replace function public.solicitud_admin_de_contrato(p_contrato uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_admin_de(public.empresa_de_contrato(p_contrato), 'comisiones') $$;

create or replace function public.retencion_admin_de_solicitud(p_solicitud uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public._puede_admin_de(public.empresa_de_solicitud_pago(p_solicitud), 'comisiones') $$;

do $$
declare f text;
begin
  -- privadas: nadie por la API
  foreach f in array array[
    '_rol_empresa()','_super_empresa_alguna()','_puede_herr(text)','_puede_herr_admin(text)','_puede_admin_de(text,text)','_empresa_doc(uuid,uuid)',
    '_empresa_cuenta(text)','_empresa_sociedad(text)','_empresa_gasto(text,uuid)','_empresa_movimiento(uuid)','_empresa_comision(uuid)',
    'gasto_visible(text,uuid)','gasto_id_visible(uuid)','gasto_ruta_visible(text)','proveedor_visible(text)','banco_cuenta_visible(text)',
    'banco_movimiento_visible(uuid)','gastos_acceso()','sociedad_super_de(text)','solicitud_admin_de_contrato(uuid)','retencion_admin_de_solicitud(uuid)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated, lw_lector', f);
  end loop;
  -- los que llaman las policies (rol que lee = rol que ejecuta)
  grant execute on function public.gasto_visible(text,uuid) to authenticated, lw_lector;
  grant execute on function public.gasto_id_visible(uuid) to lw_lector;
  grant execute on function public.gasto_ruta_visible(text) to authenticated;
  grant execute on function public.proveedor_visible(text) to lw_lector;
  grant execute on function public.banco_cuenta_visible(text) to lw_lector;
  grant execute on function public.banco_movimiento_visible(uuid) to lw_lector;
  grant execute on function public.gastos_acceso() to authenticated, lw_lector;
  grant execute on function public.sociedad_super_de(text) to authenticated, lw_lector;
  grant execute on function public.solicitud_admin_de_contrato(uuid) to authenticated, lw_lector;
  grant execute on function public.retencion_admin_de_solicitud(uuid) to authenticated;
end $$;
