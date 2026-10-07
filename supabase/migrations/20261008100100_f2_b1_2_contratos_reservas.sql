-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · cierre · bloque 1 · migracion 2 (8-oct-2026): contratos, reservas y atribucion de ventas por empresa.
--   Mismo criterio que la migracion 1: la empresa sale SIEMPRE del contrato (o de su proyecto) en el servidor; sin empresa (proyecto sin empresa) solo pasa un admin/super global.
--   Un admin_empresa hace en su empresa lo que un admin global; un super_admin_empresa, lo que un super global (incluido borrar, desbloquear, anular firmas dadas, ver todos los eventos).
--   Funciones: libera_reserva, prorroga_reserva, deshace_liberacion, carta_cobrado_recalcula, contrato_calendario_aplica, contrato_guarda, contrato_desbloquea, contrato_firmas_anula, contrato_poder_vincula, contrato_saldo,
--   _contrato_anexo_check, borrar_operacion (el super de empresa solo borra una cadena si TODOS sus contratos son de sus empresas), triggers de contratos (_contrato_pdf_firmado_fijo,
--   clausulas_negociadas_rol, descuento_comercial_rol/suelo/construccion) y la policy de contrato_eventos (super de empresa ve los eventos completos de sus contratos).
--   Ya convertidas por el bloque 4 (f2_b4_3), no se tocan aqui: venta_modo_admin, venta_objecion_resolver, venta_propia_resolver, ventas_por_su_cuenta_cuota/equipo, crm_contrato_closer_set.
--   NO se convierten (decision escrita en el informe): contratos_diseno_guarda (diseno compartido por tipo de contrato, sin empresa: nace cerrado hasta duplicarlo por empresa),
--   reasigna_autor (mezcla contratos y facturas: lo hace el bloque 2), trg_guarda_antes_de_borrar (rama de facturas: bloque 2), resolver_aviso_reserva/resolver_solicitud_cambio (aprobadores de Telegram: solo super global).
--   Funciones nuevas con llamador con nombre: _empresa_fila_contrato (triggers de contratos, sin EXECUTE para nadie), super_de_contrato (policy de contrato_eventos).
-- destructivo-ok: create or replace de funciones y alter policy; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b1.sql (PARTE 2)

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

-- 0. ayudas
-- empresa de la fila de un contrato que aun puede no tener proyecto_id (los triggers que lo fijan van despues alfabeticamente): por id, y si no hay, por nombre
create function public._empresa_fila_contrato(p_proyecto_id uuid, p_nombre text)
 returns text language sql stable security definer set search_path = '' as $$
  select pr.empresa from public.proyectos pr
   where pr.id = p_proyecto_id or (p_proyecto_id is null and pr.nombre = p_nombre)
   order by (pr.id = p_proyecto_id) desc nulls last limit 1
$$;
revoke all on function public._empresa_fila_contrato(uuid, text) from public, anon, authenticated, lw_lector;
-- ¿es super_admin_empresa de la empresa de este contrato? (la usa la policy de contrato_eventos)
create function public.super_de_contrato(p_contrato_id uuid)
 returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.usuarios u
      join public.contratos c on c.id = p_contrato_id
      join public.proyectos p on p.id = c.proyecto_id
     where u.user_id = (select auth.uid()) and u.activo
       and u.ambito = 'empresa' and u.rol = 'super_admin_empresa'
       and p.empresa = any (u.empresas))
$$;
revoke all on function public.super_de_contrato(uuid) from public, anon;
grant execute on function public.super_de_contrato(uuid) to authenticated, lw_lector;

-- 1. reservas
select pg_temp.parchea('public.libera_reserva(uuid,uuid,text,text)'::regprocedure,
  $q$public.es_admin()$q$, $q$public.es_admin_de(public.empresa_de_contrato(p_contrato_id))$q$);
select pg_temp.parchea('public.prorroga_reserva(uuid,integer,text,boolean)'::regprocedure,
  $q$v_es_admin := public.es_admin();$q$, $q$v_es_admin := public.es_admin_de(public.empresa_de_contrato(p_contrato_id));$q$);
select pg_temp.parchea('public.deshace_liberacion(uuid,text,integer,boolean)'::regprocedure,
  $q$if not public.es_admin() then$q$, $q$if not public.es_admin_de(public.empresa_de_contrato(p_contrato_id)) then$q$);
select pg_temp.parchea('public.carta_cobrado_recalcula(uuid)'::regprocedure,
  $q$if not public.es_admin() then$q$, $q$if not public.es_admin_de(public.empresa_de_contrato(p_contrato_id)) then$q$);
select pg_temp.parchea('public.contrato_calendario_aplica(jsonb,jsonb,numeric,date,uuid)'::regprocedure,
  $q$v_admin   boolean := public.es_admin();$q$,
  $q$v_admin   boolean := public.es_admin_de(coalesce(public.empresa_de_contrato(p_contrato_id), (select pr.empresa from public.proyectos pr where pr.nombre = p_datos->'fields'->>'proyecto_nombre' limit 1)));$q$);

-- 2. (atribucion de ventas y reparto: venta_modo_admin, venta_objecion_resolver, venta_propia_resolver, ventas_por_su_cuenta_*, crm_contrato_closer_set ya las convirtio el bloque 4
--    con puerta_reparto_de(empresa) en su migracion f2_b4_3; aqui no se tocan, regla 10 de la especificacion)

-- 3. contratos: guardar, desbloquear, anular firmas, vincular poder, saldo, anexos
select pg_temp.parchea('public.contrato_guarda(uuid,jsonb)'::regprocedure,
  $q$public.es_super_admin()$q$, $q$public.es_super_admin_de(public.empresa_de_contrato(coalesce(v_row.id, v_old.id)))$q$, 3);
select pg_temp.parchea('public.contrato_desbloquea(uuid)'::regprocedure,
  $q$if not public.es_super_admin() then$q$, $q$if not public.es_super_admin_de(public.empresa_de_contrato(p_id)) then$q$);
select pg_temp.parchea('public.contrato_firmas_anula(uuid,text,boolean,text)'::regprocedure,
  $q$if not public.es_super_admin() then$q$, $q$if not public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) then$q$);
select pg_temp.parchea('public.contrato_poder_vincula(uuid)'::regprocedure,
  $q$(public.es_super_admin()$q$, $q$(public.es_super_admin_de(public.empresa_de_contrato(c.id))$q$);
select pg_temp.parchea('public.contrato_saldo(uuid)'::regprocedure,
  $q$if not (public.es_super_admin() or$q$, $q$if not (public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) or$q$);
select pg_temp.parchea('public._contrato_anexo_check(uuid)'::regprocedure,
  $q$public.es_super_admin()$q$, $q$public.es_super_admin_de(public.empresa_de_contrato(p_contrato))$q$, 2);

-- 4. borrar una operacion: el super de empresa solo borra la cadena entera si TODOS sus contratos son de sus empresas (la raiz y sus hijos)
select pg_temp.parchea('public.borrar_operacion(uuid)'::regprocedure,
  $q$if not public.es_super_admin() then$q$,
  $q$if not (public.es_super_admin() or not exists (
       select 1 from public.contratos c2 left join public.proyectos p2 on p2.id = c2.proyecto_id
        where c2.id = any (ids) and not public.es_super_admin_de(p2.empresa))) then$q$);

-- 5. triggers de contratos
select pg_temp.parchea('public._contrato_pdf_firmado_fijo()'::regprocedure,
  $q$or public.es_super_admin() then return new;$q$,
  $q$or public.es_super_admin_de((select pr.empresa from public.proyectos pr where pr.id = new.proyecto_id or pr.nombre = new.proyecto_nombre order by (pr.id = new.proyecto_id) desc limit 1)) then return new;$q$);
-- (_trg_contrato_padre_con_comisiones ya la convirtio el bloque 4 con empresa_de_contrato_int)
select pg_temp.parchea('public.clausulas_negociadas_rol()'::regprocedure,
  $q$if v_rol in ('super_admin', 'admin') then return new; end if;$q$,
  $q$if v_rol in ('super_admin', 'admin') or public.es_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre)) then return new; end if;$q$);
select pg_temp.parchea('public.descuento_comercial_rol()'::regprocedure,
  $q$if v_rol in ('super_admin', 'admin', 'sales_manager') then return new; end if;$q$,
  $q$if v_rol in ('super_admin', 'admin', 'sales_manager') or public.es_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre)) then return new; end if;$q$);
select pg_temp.parchea('public.descuento_comercial_suelo_valido()'::regprocedure,
  $q$if not coalesce(v_super, false) then$q$,
  $q$if not (coalesce(v_super, false) or public.es_super_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre))) then$q$);
select pg_temp.parchea('public.descuento_comercial_construccion_valido()'::regprocedure,
  $q$if not coalesce(v_super, false) then$q$,
  $q$if not (coalesce(v_super, false) or public.es_super_admin_de(public._empresa_fila_contrato(new.proyecto_id, new.proyecto_nombre))) then$q$);

-- 6. lectura: el super de empresa ve los eventos COMPLETOS de los contratos de su empresa (los demas, solo los normales de sus contratos, como antes)
alter policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos
  using (
    (select es_super_admin())
    or ((select es_agente())
        and (evento <> all (array['editado_estando_firmado'::text, 'desbloqueado_estando_firmado'::text, 'factura_sin_bloquear'::text,
                                  'cobro_a_factura_huerfana'::text, 'cobro_a_otro_comprador'::text, 'comprador_sin_ficha'::text])
             or public.super_de_contrato(contrato_id))
        and contrato_id is not null
        and ((select es_admin()) or contrato_id = any ((select mis_contratos_visibles())::uuid[]))));
