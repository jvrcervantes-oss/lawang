-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 2 (DINERO) · migracion 0 (8-oct-2026): INSTANTANEA de lo que el bloque va a cambiar.
--   Guarda, tal y como estan VIVAS justo antes (pg_get_functiondef / pg_policies), las funciones y policies que tocan las migraciones 1..7 de este bloque.
--   La reversion (supabase/reversion_f2/REVERSION_f2_b2.sql) las reaplica de ahi: es la unica forma de que la vuelta atras sea exacta (los cuerpos tienen miles de caracteres).
--   Tabla sin ningun permiso (ni authenticated, ni anon, ni lw_lector): solo la lee quien administra la base. Se borra cuando el bloque lleve una semana estable (ultima linea de la reversion).
-- destructivo-ok: tabla nueva sin datos de negocio; sin borrar nada existente
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b2.sql
create table if not exists public._f2_b2_originales (
  nombre text primary key,
  tipo   text not null check (tipo in ('funcion','policy')),
  ddl    text not null,
  creado timestamptz not null default now()
);
alter table public._f2_b2_originales enable row level security;
revoke all on public._f2_b2_originales from public, anon, authenticated, lw_lector;

insert into public._f2_b2_originales (nombre, tipo, ddl)
select 'f:' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', 'funcion', pg_get_functiondef(p.oid)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in (
     '_factura_puede_editar','factura_borra','factura_reactiva','factura_anulada_solo_cambia_autor','_factura_tope_cadena','factura_guarda','guardar_recibi',
     '_solicitud_puede_tocar','_trg_solicitud_pago_transicion','_retencion_puerta','solicitud_pago_retencion_guarda',
     '_gasto_puede','gasto_guarda','gasto_anula','gasto_marca_pagado','gasto_pph_ingresado','gasto_anade_justificante','gasto_justificante_registra',
     'gasto_historial_datos','gastos_panel_datos','proveedor_guarda',
     '_bancos_puerta','bancos_conciliar','bancos_desconciliar','bancos_designorar','bancos_ignorar','bancos_importar','bancos_resumen','banco_perfil_guarda','panel_bancos_datos',
     'cuenta_bancaria_guarda','sociedad_guarda','cuentas_uso','sociedades_ajustes_datos')
on conflict (nombre) do nothing;

insert into public._f2_b2_originales (nombre, tipo, ddl)
select 'p:' || pp.schemaname || '.' || pp.tablename || ':' || pp.policyname, 'policy',
       format('alter policy %I on %I.%I using (%s)%s', pp.policyname, pp.schemaname, pp.tablename, pp.qual,
              case when pp.with_check is not null then format(' with check (%s)', pp.with_check) else '' end)
  from pg_policies pp
 where (pp.schemaname, pp.tablename, pp.policyname) in (
     ('public','recibi_aplicaciones','agentes leen aplicaciones de sus documentos'),
     ('public','solicitudes_pago','solicitudes: cada uno lee las suyas, admin con casilla todas'),
     ('public','solicitudes_pago_retencion','retencion: admin con casilla todas, el perceptor la suya'),
     ('public','gastos','gastos: leer'),
     ('public','gastos_log','gastos_log: leer'),
     ('public','proveedores','proveedores: leer'),
     ('public','gasto_categorias','categorias: leer'),
     ('public','bancos_movimientos','bancos_movimientos: leer'),
     ('public','bancos_conciliacion','bancos_conciliacion: leer'),
     ('public','bancos_perfiles','bancos_perfiles: leer'),
     ('public','sociedades_log','sociedades_log: leer solo super'),
     ('storage','objects','gastos: leer justificantes'))
on conflict (nombre) do nothing;

do $$
declare n_f int; n_p int;
begin
  select count(*) filter (where tipo = 'funcion'), count(*) filter (where tipo = 'policy') into n_f, n_p from public._f2_b2_originales;
  if n_f < 34 or n_p <> 12 then
    raise exception 'La instantanea no esta completa: % funciones (esperadas >=34) y % policies (esperadas 12)', n_f, n_p;
  end if;
end $$;
