-- F2 de «primero la parcela, luego la obra» (owner, 14-oct-2026; encargo agencia encargos/20261014_lawang_cobro_primero_parcela.md).
-- Los lectores que deciden cobro, deuda o facturación (Vencimientos, Finanzas, Obra, previsión de comisión de
-- administración) leían lo cobrado POR DOCUMENTO: el recibí cuenta en el contrato del que cuelga. El 14-oct, en 30 de
-- 130 ventas eso ponía 725.200 € en el contrato equivocado (SH-1: 41.620 en un Bloqueo de 25.000 y la obra a 0, así
-- que sus hitos de obra salían «vencidos» con el dinero en caja).
--
-- Aquí NO se reescribe la regla: sigue viviendo solo en _unidad_cobro_cascada (por parcela). Esto la lleva a CONTRATO:
--   Bloqueo raíz           = el suelo cobrado de sus parcelas (+ la obra que no tiene contrato de obra donde ponerse
--                            + los céntimos del redondeo por parcela)
--   contrato de obra       = la obra cobrada de SU parcela (solo parcelas de la propia venta: CC00064 y CC00066 apuntan
--                            a una parcela de otra venta y se tratan como obra sin parcela — Backend, revisión #335).
--                            Varios en una parcela: los VIGENTES de la cascada (los firmados; si no hay, el borrador más
--                            reciente), la misma regla que fija obra_precio; a partes por precio si hay varios firmados
--   obra sin parcela propia = la obra de las parcelas sin contrato de obra propio, a partes por precio
--   Cartas y demás hijos   = 0 (su dinero ya está en la bolsa de la venta)
-- Venta que la cascada no reparte (sin precio de parcela, monedas mezcladas, sin parcela, nieto): lo de siempre.
-- Invariante: en cada venta, la suma de lo atribuido = la suma de lo cobrado por documento.
-- Es una vista de gestión: no se mueve ningún recibí ni factura (Administración, revisión #329).

create or replace function public._venta_cobro_atribuido(p_raiz uuid)
 returns table(contrato_id uuid, cobrado_doc numeric, cobrado_regla numeric, atribuida boolean)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
begin
  -- Solo una raíz de verdad: la cascada no mete a los nietos en ninguna bolsa, y aquí tampoco.
  if not exists (select 1 from public.contratos r where r.id = p_raiz and r.contrato_padre_id is null) then
    return;
  end if;
  return query
  with
  fam as (
    select c.id, c.tipo, c.unidad_id, coalesce(c.bloqueado, false) as firmado, c.precio_total, c.moneda, c.created_at,
           c.liberado_en, (c.id = p_raiz) as es_raiz,
           public._comisiones_parte_obra(c.tipo, e.es_obra) as es_obra,
           coalesce(public.contrato_cobrado(c.id), 0) as cobrado
      from public.contratos c
      left join public.contrato_tipo_etapa e on e.tipo = c.tipo
     where c.id = p_raiz or c.contrato_padre_id = p_raiz
  ),
  her as (select u.id, u.moneda, u.precio_suelo from public.unidades u where u.contrato_id = p_raiz),
  mon as (select min(h.moneda) as v, count(distinct h.moneda) as n, count(*) as k,
                 coalesce(sum(h.precio_suelo), 0) as suelo_catalogo from her h),
  cas as (select h.id, x.cobrado_suelo, x.cobrado_obra, x.suelo_de_contrato
            from her h cross join lateral public._unidad_cobro_cascada(h.id) x
           where (select k from mon) > 0 and (select n from mon) <= 1),
  -- La cascada reparte (hay tope) si no hay dinero en otra moneda y hay precio de parcela: del Bloqueo raíz o, si no,
  -- del catálogo. Es la misma condición que su `tope`, medida aquí a nivel de venta.
  modo as (
    select (select k from mon) > 0 and (select n from mon) <= 1
       and not exists (select 1 from fam f where f.cobrado > 0 and f.moneda is distinct from (select v from mon))
       and (exists (select 1 from cas where cas.suelo_de_contrato) or (select suelo_catalogo from mon) > 0) as v
  ),
  obras as (
    select f.id, f.firmado, f.precio_total, f.created_at,
           case when f.unidad_id in (select h.id from her h) then f.unidad_id end as parcela
      from fam f
     where not f.es_raiz and f.es_obra and f.tipo is distinct from 'reserva_parcela'
       and f.liberado_en is null and coalesce(f.precio_total, 0) > 0
       and f.moneda is not distinct from (select v from mon)
  ),
  marc as (
    select o.id, o.firmado, o.precio_total, o.parcela,
           bool_or(o.firmado) over (partition by o.parcela) as hay_firmado,
           row_number() over (partition by o.parcela order by o.created_at desc) as orden
      from obras o
  ),
  vig as (select m.id, m.parcela, m.precio_total from marc m
           where (m.hay_firmado and m.firmado) or (not m.hay_firmado and m.orden = 1)),
  a_propia as (
    select v.id, sum(c.cobrado_obra * v.precio_total / t.tot) as imp
      from vig v
      join cas c on c.id = v.parcela
      join (select vv.parcela, sum(vv.precio_total) as tot from vig vv where vv.parcela is not null group by vv.parcela) t
        on t.parcela = v.parcela
     group by v.id
  ),
  pool as (select coalesce(sum(c.cobrado_obra), 0) as v from cas c
            where not exists (select 1 from vig v where v.parcela = c.id)),
  a_pool as (
    select v.id, (select p.v from pool p) * v.precio_total / sum(v.precio_total) over () as imp
      from vig v where v.parcela is null
  ),
  asign as (select a.id, round(a.imp, 2) as imp from a_propia a
            union all
            select a.id, round(a.imp, 2) from a_pool a),
  bolsa as (select coalesce(sum(f.cobrado), 0) as v from fam f)
  select f.id, f.cobrado,
         case when not (select v from modo) then f.cobrado
              when f.es_raiz then (select b.v from bolsa b) - coalesce((select sum(a.imp) from asign a), 0)
              else coalesce((select sum(a.imp) from asign a where a.id = f.id), 0) end,
         (select v from modo)
    from fam f;
end
$function$;

revoke all on function public._venta_cobro_atribuido(uuid) from public, anon, authenticated;
grant execute on function public._venta_cobro_atribuido(uuid) to service_role;

-- Lo cobrado de UN contrato contando su venta: con la regla si su venta la reparte; si no, lo de siempre (lo suyo más
-- lo de sus Cartas hijas, que es dinero entregado a cuenta de la misma operación). Interna: la llaman obra_datos_cobro
-- y comision_admin_prevision, que ya pasaron su propia puerta.
create or replace function public._contrato_cobrado_venta(p_contrato uuid)
 returns numeric
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_padre uuid; v_regla numeric;
begin
  select c.contrato_padre_id into v_padre from public.contratos c where c.id = p_contrato;
  select a.cobrado_regla into v_regla
    from public._venta_cobro_atribuido(coalesce(v_padre, p_contrato)) a
   where a.contrato_id = p_contrato and a.atribuida;
  if v_regla is not null then return v_regla; end if;
  return coalesce(public.contrato_cobrado(p_contrato), 0) + coalesce((
    select sum(coalesce(public.contrato_cobrado(h.id), 0))
      from public.contratos h
     where h.contrato_padre_id = p_contrato and h.tipo like 'carta_reserva%'), 0);
end
$function$;

revoke all on function public._contrato_cobrado_venta(uuid) from public, anon, authenticated;
grant execute on function public._contrato_cobrado_venta(uuid) to service_role;

-- La RPC de las pantallas que deciden cobro (Vencimientos y Finanzas de la v4). Misma puerta que
-- contratos_cobrado_equipo y, además, la cifra de la regla SOLO a quien ve la venta entera: la de un contrato sale de
-- la bolsa de toda la venta, y puede_ver_contrato va por documento (7 ventas con contratos de autores distintos el
-- 14-oct; Seguridad, revisión #335). A quien no la ve entera se le da lo de siempre, que no enseña nada nuevo.
-- `cobrado_doc` va al lado para que la pantalla marque lo que la regla movió. Llamadores: datos.js (Vencimientos) y
-- panel-finanzas.js. Cuando el maestro del ERP tenga la regla, las pantallas dejan de caer a contratos_cobrado_equipo.
create or replace function public.contratos_cobrado_regla_equipo()
 returns table(contrato_id uuid, cobrado numeric, cobrado_doc numeric)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
begin
  if not public.es_agente() then return; end if;
  return query
  with
  vis as (select c.id, c.contrato_padre_id from public.contratos c where public.puede_ver_contrato(c.id)),
  raices as (
    select distinct coalesce(v.contrato_padre_id, v.id) as id from vis v
  ),
  enteras as (
    select r.id from raices r
     where exists (select 1 from public.contratos x where x.id = r.id and x.contrato_padre_id is null)
       and (public.es_admin_de(public.empresa_de_contrato(r.id))
            or not exists (select 1 from public.contratos h
                            where (h.id = r.id or h.contrato_padre_id = r.id)
                              and not public.puede_ver_contrato(h.id)))
  ),
  atr as (select a.contrato_id, a.cobrado_regla from enteras e cross join lateral public._venta_cobro_atribuido(e.id) a
           where a.atribuida)
  select v.id, coalesce(a.cobrado_regla, d.doc), d.doc
    from vis v
    cross join lateral (select coalesce(public.contrato_cobrado(v.id), 0) as doc) d
    left join atr a on a.contrato_id = v.id;
end
$function$;

revoke all on function public.contratos_cobrado_regla_equipo() from public, anon, authenticated;
grant execute on function public.contratos_cobrado_regla_equipo() to authenticated, service_role;

-- Obra: lo cobrado de cada Construcción, con la regla. Antes: lo suyo + sus Cartas hijas (que es lo que sigue dando
-- _contrato_cobrado_venta cuando la venta no se reparte). Misma firma, misma puerta.
create or replace function public.obra_datos_cobro(p_proyecto_id uuid, p_fase_masterplan text, p_zona_masterplan text, p_fase_nueva text)
 returns table(contrato_id uuid, numero text, moneda text, precio_total numeric, cobrado numeric, vencimientos jsonb)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_proyecto_nombre text;
begin
  select nombre into v_proyecto_nombre from public.proyectos where id = p_proyecto_id;
  if v_proyecto_nombre is null then
    raise exception 'Proyecto no encontrado';
  end if;
  -- Mismo gate, palabra por palabra, que obra_contratos_afectados().
  if not (public._puede_herr_o_super_empresa('obra') and public.puede_proyecto(v_proyecto_nombre)) then
    raise exception 'Sin permiso sobre este proyecto' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.numero,
    c.moneda,
    c.precio_total,
    -- Lo cobrado de esta Construcción contando su venta: primero la parcela, luego la obra (owner, 14-oct-2026).
    -- La puerta de arriba es por proyecto y ninguna venta tiene contratos en dos proyectos (Seguridad, 14-oct).
    public._contrato_cobrado_venta(c.id),
    coalesce((
      select jsonb_agg(jsonb_build_object('orden', cv.orden, 'pct', cv.pct,
                                          'monto', cv.monto, 'fecha', cv.fecha)
                       order by cv.orden)
        from public.contrato_vencimientos cv where cv.contrato_id = c.id
    ), '[]'::jsonb)
  from public.contratos c
  join public.unidades u on u.id = c.unidad_id
   and u.proyecto_id = p_proyecto_id
   and u.fase_masterplan = p_fase_masterplan
   and u.zona_masterplan = p_zona_masterplan
  where c.tipo = 'construccion' and c.bloqueado = true;
end;
$function$;

-- Previsión de comisión de administración: el pendiente de cada contrato con la regla. Sale el campo
-- `carta_cobrado_importe` del formulario: era el cobrado de la Carta hija COPIADO (6 Bloqueos el 14-oct; en uno,
-- desfasado: 2.000 frente a 47.038,82) y ese dinero ya entra por sus recibís (Administración, Backend y Seguridad,
-- revisión #335). Un campo de formulario no es dinero.
create or replace function public.comision_admin_prevision()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_pct numeric;
  v_out jsonb;
begin
  if not public.es_super_admin() then
    raise exception 'comision_admin_prevision: solo super_admin';
  end if;

  select t.pct into v_pct
    from public.comision_admin_tarifas t join public.empresas e on e.clave = t.empresa
   where t.efectivo_desde <= current_date
   order by e.orden, t.efectivo_desde desc
   limit 1;

  with vivos as (
    select coalesce(c.moneda, 'EUR') as moneda,
           c.bloqueado as firmado,
           coalesce(public._empresa_de_contrato_int(c.id), 'lawang') as emp,
           greatest(coalesce(c.precio_total, 0) - public._contrato_cobrado_venta(c.id), 0) as pendiente
      from public.contratos c
     where c.liberado_en is null
       and c.tipo not like 'carta_reserva%'
       and coalesce(c.precio_total, 0) > 0
       and (c.bloqueado or public.contrato_firma_viva(c.id))
  ), con_pct as (
    select v.*, (select t.pct from public.comision_admin_tarifas t
                  where t.empresa = v.emp and t.efectivo_desde <= current_date
                  order by t.efectivo_desde desc limit 1) as pct
      from vivos v
  ), por_moneda as (
    select moneda,
           count(*) filter (where firmado)                          as n_firmados,
           coalesce(sum(pendiente) filter (where firmado), 0)       as pend_firmados,
           count(*) filter (where not firmado)                      as n_en_firma,
           coalesce(sum(pendiente) filter (where not firmado), 0)   as pend_en_firma,
           bool_or(pct is null)                                     as falta_tarifa,
           coalesce(sum(pendiente * pct / 100), 0)                  as com_total,
           coalesce(sum(pendiente * pct / 100) filter (where firmado), 0) as com_firmados
      from con_pct group by moneda
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moneda', moneda,
           'n_firmados', n_firmados, 'pendiente_firmados', pend_firmados,
           'n_en_firma', n_en_firma, 'pendiente_en_firma', pend_en_firma,
           'pendiente', pend_firmados + pend_en_firma,
           'comision', case when falta_tarifa then null else round(com_total, 2) end,
           'comision_firmados', case when falta_tarifa then null else round(com_firmados, 2) end
         ) order by moneda), '[]'::jsonb)
    into v_out
    from por_moneda;

  return jsonb_build_object('pct', v_pct, 'monedas', v_out);
end;
$function$;
