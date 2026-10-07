-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 4 · migracion 3 (8-oct-2026): PUERTAS DE LAS COMISIONES YA DEVENGADAS Y DE LAS VENTAS «POR SU CUENTA» POR EMPRESA.
--   «Administrador con el reparto de comisiones» era `es_admin() and puede('comisiones_reparto')`. Pasa a public.puede_reparto_de(<empresa de la venta>):
--   admin de ESA empresa con la casilla comisiones_reparto, o super de ESA empresa (el super de empresa no pasa puede() solo, a diferencia del super global),
--   o un admin/super global como siempre. La empresa se deduce SIEMPRE en el servidor de la venta (contrato -> proyecto -> empresa), nunca de lo que mande el navegador.
--   Una venta de un proyecto sin empresa (Karana) solo la gobierna un global: nace cerrada.
--   Funciones: comision_visible (y con ella la policy de comisiones_devengadas y de comisiones_diferencias), comision_trazabilidad, _comision_devengo_admin_puede
--   (de ahi cuelgan comision_devengo_ajustar y comision_devengo_anular), comision_marca_pagada, comision_devengo_anular_lawang, comision_diferencia_resolver
--   (la que paga Lawang pide es_admin_de; la del manager, puede_reparto_de), comision_rol_asignar, comision_recalcular (super de la empresa),
--   _trg_contrato_padre_con_comisiones (super de la empresa), venta_modo_admin, venta_objecion_resolver, venta_propia_resolver, ventas_por_su_cuenta_cuota,
--   ventas_por_su_cuenta_equipo. venta_objecion_crear avisa tambien a los administradores de la empresa de la venta.
--   Un global (admin/super) pasa exactamente por la misma puerta que antes: la foto de las 34 fichas es identica.
-- destructivo-ok: create or replace de 14 funciones por parche con marca (cada marca debe salir las veces esperadas o aborta); sin DDL que destruya datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b4.sql

create or replace function pg_temp.parchea(p_sig regprocedure, p_pares text[]) returns void language plpgsql as $f$
declare d text; i int := 1; v_old text; v_new text; v_n int; v_esp int;
begin
  d := pg_get_functiondef(p_sig);
  while i <= array_length(p_pares, 1) loop
    v_old := p_pares[i]; v_new := p_pares[i + 1]; v_esp := p_pares[i + 2]::int;
    v_n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
    if v_n <> v_esp then
      raise exception 'parchea %: la marca «%» sale % veces y se esperaban %', p_sig, left(v_old, 90), v_n, v_esp;
    end if;
    d := replace(d, v_old, v_new);
    i := i + 3;
  end loop;
  execute d;
end $f$;

-- ---------------------------------------------------------------- devengos
select pg_temp.parchea('public.comision_visible(text,text,uuid,uuid)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz))$n$, '1']);
select pg_temp.parchea('public.comision_trazabilidad(uuid)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))$n$, '1']);
select pg_temp.parchea('public._comision_devengo_admin_puede(uuid)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))$n$, '1']);
select pg_temp.parchea('public.comision_marca_pagada(uuid)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(v.contrato_raiz_id))$n$, '1']);
select pg_temp.parchea('public.comision_devengo_anular_lawang(uuid,text)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int((select x.contrato_raiz_id from public.comisiones_devengadas x where x.id = p_id)))$n$, '1']);
select pg_temp.parchea('public.comision_diferencia_resolver(uuid,text,text)'::regprocedure, array[
  $o$if not public.es_admin() then$o$,
  $n$if not public.es_admin_de(public._empresa_de_contrato_int(d.contrato_raiz_id)) then$n$, '1',
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))$n$, '1']);
select pg_temp.parchea('public.comision_rol_asignar(uuid,text,text)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz))$n$, '1',
  $o$and not public.es_super_admin() then$o$,
  $n$and not public.es_super_admin_de(public._empresa_de_contrato_int(p_raiz)) then$n$, '1']);
select pg_temp.parchea('public.comision_recalcular(uuid,text)'::regprocedure, array[
  $o$if not public.es_super_admin() then$o$,
  $n$if not public.es_super_admin_de(public._empresa_de_contrato_int(p_raiz)) then$n$, '1']);
select pg_temp.parchea('public._trg_contrato_padre_con_comisiones()'::regprocedure, array[
  $o$or public.es_super_admin() then return new; end if;$o$,
  $n$or public.es_super_admin_de(public._empresa_de_contrato_int(new.id)) then return new; end if;$n$, '1']);

-- ---------------------------------------------------------------- ventas «por su cuenta»
select pg_temp.parchea('public.venta_modo_admin(uuid,text,text)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(p_raiz))$n$, '1']);
select pg_temp.parchea('public.venta_objecion_resolver(uuid,text,text)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int((select rv.contrato_raiz_id from public.reclamaciones_venta_propia rv where rv.id = p_id)))$n$, '1']);
select pg_temp.parchea('public.venta_propia_resolver(uuid,boolean,text)'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(r.contrato_raiz_id))$n$, '1']);
select pg_temp.parchea('public.ventas_por_su_cuenta_cuota()'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(k.contrato_id))$n$, '1']);
select pg_temp.parchea('public.ventas_por_su_cuenta_equipo()'::regprocedure, array[
  $o$(public.es_admin() and public.puede('comisiones_reparto'))$o$,
  $n$public.puede_reparto_de(public._empresa_de_contrato_int(k.contrato_id))$n$, '1']);
select pg_temp.parchea('public.venta_objecion_crear(uuid,text)'::regprocedure, array[
  $o$u.rol in ('admin', 'super_admin')$o$,
  $n$(u.rol in ('admin', 'super_admin') or (u.rol in ('admin_empresa', 'super_admin_empresa') and public._empresa_de_contrato_int(p_raiz) = any (u.empresas)))$n$, '1']);
