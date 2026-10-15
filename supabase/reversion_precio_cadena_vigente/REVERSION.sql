-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015101833_precio_cadena_vigente.sql (15-oct-2026).
-- Vuelve LITERAL a los cuerpos vivos del 15-oct (md5(prosrc) en la guarda de la migración) de _cadena_saldo_en,
-- contrato_saldo, _unidad_cobro_cascada, _venta_cobro_atribuido y unidad_cobro_reparto: el precio de la venta vuelve a
-- sumar todas las obras, contrato_saldo pierde facturado_de_mas y a_cuenta, y la cascada vuelve a ser la de antes.
-- La vista vuelve a leer unidad_cobro_reparto; sus dos columnas nuevas NO se pueden quitar sin borrarla (CREATE OR
-- REPLACE VIEW no quita columnas), así que quedan AL FINAL como NULL. Las tres funciones nuevas quedan sin llamador y
-- cerradas (se les quita el permiso); borrarlas, si hace falta, es otro paso (DROP: pide al owner). La vieja
-- unidad_cobro_reparto recupera EXECUTE (authenticated, service_role, lw_lector) y su COMMENT de antes, ANTES de la vista.
-- ORDEN: si la ficha ya usa suelo_de_contrato/obra_de_contrato, NULL la deja como antes de esta migración (sin rótulo).
-- Precondición: que la viva sea la que dejó la migración (md5 de sus cuerpos), para no pisar un cambio posterior.
set local lock_timeout = '5s';

do $pre$
declare v_mal text;
begin
  select string_agg(x.f, ', ') into v_mal
    from (values
      ('public._cadena_saldo_en(uuid,text,uuid)', '50fe318e7a9f719977bda7a50b8b8e40'),
      ('public.contrato_saldo(uuid)', 'd1da71ed137fce927ef3c697673cc98b'),
      ('public._unidad_cobro_cascada(uuid)', 'cd5aaf79f54d0b427fecf273fcd1d1fb'),
      ('public._venta_cobro_atribuido(uuid)', 'a84b1689db1b99b498604aa5f0f435c1'),
      ('public.unidad_cobro_reparto(uuid)', '82899583443d38bdb0e56f8d850777fd')) as x(f, m)
   where (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(x.f)) is distinct from x.m;
  if v_mal is not null then
    raise exception 'REVERSION precio-cadena-vigente: no son las que dejó la migración (md5 distinto): %. Revertir a mano.', v_mal;
  end if;
end $pre$;

CREATE OR REPLACE FUNCTION public._unidad_cobro_cascada(p_unidad uuid)
 RETURNS TABLE(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean, suelo_precio numeric, obra_precio numeric, suelo_de_contrato boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
-- plpgsql y no `language sql` A PROPÓSITO: la vista llama a esto una vez por unidad, y una función SQL de este tamaño
-- se planifica entera en cada llamada (medido el 14-oct en el ensayo: la vista pasaba de 0,6 s a 2,2 s). En plpgsql el
-- plan se guarda en la sesión.
declare
  v_contrato uuid; v_suelo numeric; v_obra numeric;
begin
  select un.contrato_id, un.precio_suelo, un.precio_construccion into v_contrato, v_suelo, v_obra
    from public.unidades un where un.id = p_unidad;
  -- Sin contrato no hay nada cobrado ni precio pactado: el catálogo, y fuera (3 de cada 4 unidades).
  if v_contrato is null then
    return query select 0::numeric, 0::numeric, false, round(v_suelo, 2), round(v_obra, 2), false;
    return;
  end if;

  -- La cascada se hace a nivel de VENTA (contrato raíz + hijos) y después se reparte entre sus parcelas:
  --   bolsa  = todo lo cobrado en la venta, cuelgue del contrato que cuelgue
  --   suelo  = least(precio de la parcela, bolsa)        obra = bolsa - suelo
  -- Hacerla parcela a parcela dejaría, en un Bloqueo de varias parcelas, dinero en la obra de una con el suelo de su
  -- hermana sin pagar (revisión previa de Backend, 14-oct-2026). Cada lectura de `contratos` va por su clave.
  return query
  with
  u as (select id, codigo, contrato_id, precio, precio_suelo, precio_construccion, moneda
          from public.unidades where id = p_unidad),
  raiz as (select coalesce(c.contrato_padre_id, c.id) as id
             from public.contratos c where c.id = (select contrato_id from u)),
  fam as (
    select c.id, c.tipo, c.unidad_id, c.parcela_codigo, coalesce(c.bloqueado, false) as firmado, c.precio_total,
           c.moneda, c.created_at, c.liberado_en,
           (c.id = (select id from raiz)) as es_raiz,
           public._comisiones_parte_obra(c.tipo, e.es_obra) as es_obra,
           coalesce(e.es_obra, false) as es_obra_catalogo,
           e.etapa,
           coalesce(public.contrato_cobrado(c.id), 0) as cobrado
      from public.contratos c
      left join public.contrato_tipo_etapa e on e.tipo = c.tipo
     where c.id = (select id from raiz) or c.contrato_padre_id = (select id from raiz)
  ),
  hermanas as (select x.id, x.codigo, x.precio, x.precio_suelo from public.unidades x where x.contrato_id = (select contrato_id from u)),
  -- Reparto de siempre (hasta el 14-oct): se conserva para (a) las ventas sin precio de parcela, que no tienen
  -- contra qué hacer la cascada, y (b) saber a qué parcela corresponde el dinero de obra de una venta de varias.
  -- «Carta» = la etapa 'reserva' del catálogo, como la vista unidades_estado (F2, 14-oct-2026: por tipo exacto, una
  -- carta_reserva_pma caía aquí como obra).
  hijos_obra as (select f.unidad_id, f.cobrado from fam f where not f.es_raiz and f.etapa is distinct from 'reserva'),
  hijos_cr   as (select f.unidad_id, f.parcela_codigo, f.cobrado from fam f where not f.es_raiz and f.etapa = 'reserva'),
  asignadas as (select distinct hj.unidad_id as id from hijos_obra hj where hj.unidad_id is not null),
  hermanas_sin_asignar as (select h.id, h.precio from hermanas h where not exists (select 1 from asignadas a where a.id = h.id)),
  cobrado_raiz as (select coalesce(sum(f.cobrado), 0) as total from fam f where f.es_raiz),
  cobrado_sin_asignar as (select coalesce(sum(hj.cobrado), 0) as total from hijos_obra hj where hj.unidad_id is null),
  cr_con_parcela as (
    select cr.cobrado, coalesce(cr.unidad_id, (select h.id from hermanas h where h.codigo = cr.parcela_codigo limit 1)) as unidad
      from hijos_cr cr
  ),
  cobrado_cr_mio as (select coalesce(sum(c.cobrado), 0) as total from cr_con_parcela c where c.unidad = p_unidad),
  cobrado_cr_suelto as (
    select coalesce(sum(c.cobrado), 0) as total from cr_con_parcela c
     where c.unidad is null or not exists (select 1 from hermanas h where h.id = c.unidad)
  ),
  tot_hermanas as (select count(*) n, sum(precio) suma, sum(precio_suelo) suma_suelo,
                          count(*) filter (where coalesce(precio_suelo, 0) <= 0) sin_suelo from hermanas),
  tot_sin_asignar as (select count(*) n, sum(precio) suma from hermanas_sin_asignar),
  -- peso de cada parcela en el precio total de la venta (reparte lo cobrado en la raíz y las cartas sueltas)
  peso_precio as (
    select case when (select suma from tot_hermanas) > 0 then coalesce((select precio from u), 0) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0 then 1.0 / (select n from tot_hermanas) else 0 end as w
  ),
  -- lo cobrado en obra que corresponde a CADA parcela de la venta (el contrato de obra con su unidad; el que no la
  -- tiene, repartido por precio entre las parcelas sin contrato de obra propio)
  obra_de as (
    select h.id,
           coalesce((select sum(hj.cobrado) from hijos_obra hj where hj.unidad_id = h.id), 0)
           + case when not exists (select 1 from hermanas_sin_asignar s where s.id = h.id) then 0
                  when (select suma from tot_sin_asignar) > 0 then (select total from cobrado_sin_asignar) * coalesce(h.precio, 0) / (select suma from tot_sin_asignar)
                  when (select n from tot_sin_asignar) > 0 then (select total from cobrado_sin_asignar) / (select n from tot_sin_asignar)
                  else 0 end as v
      from hermanas h
  ),
  bruto as (
    select (select total from cobrado_raiz) * (select w from peso_precio) + (select total from cobrado_cr_mio)
             + (select total from cobrado_cr_suelto) * (select w from peso_precio) as suelo,
           coalesce((select o.v from obra_de o where o.id = p_unidad), 0) as obra
  ),
  -- Con los mismos filtros que obra_precio (F2, 14-oct-2026): sin liberados y en la moneda de la unidad.
  obra_firmada as (
    select exists (select 1 from fam f where not f.es_raiz and f.es_obra_catalogo and f.firmado
         and f.liberado_en is null and f.moneda is not distinct from (select moneda from u)
         and (f.unidad_id = p_unidad or (f.unidad_id is null and exists (select 1 from hermanas_sin_asignar where id = p_unidad)))) as v
  ),
  -- PRECIO DE CONTRATO. Parcela = el Bloqueo de Parcela que ES la venta: SOLO la raíz. Un Bloqueo colgado como hijo
  -- (de otro Bloqueo o de una Carta) NO cuenta: lo puede crear el agente de la venta desde el formulario y movería el
  -- precio de la parcela (Seguridad, 14-oct-2026). El 14-oct los 136 Bloqueos de Lawang son raíz; así la firma que
  -- mira comisiones (la de la raíz) es siempre la del Bloqueo cuyo precio cuenta (revisor, 2.ª vuelta).
  -- Obra = los contratos de obra (adenda = obra: _comisiones_parte_obra, la misma definición que usa comisiones).
  -- Por parte y unidad: los FIRMADOS si hay alguno; si no, el borrador más reciente (un borrador viejo junto a su
  -- sustituto firmado no suma dos veces: SH-36 tiene CC00062 sin firmar y CC00102 firmada). Liberados y sin precio,
  -- fuera; otra moneda que la de la unidad, fuera (no se mezclan divisas: se cae al catálogo).
  con_precio as (
    select f.unidad_id, f.firmado, f.precio_total, f.created_at, (f.tipo is distinct from 'reserva_parcela') as obra
      from fam f
     where f.liberado_en is null and coalesce(f.precio_total, 0) > 0
       and f.moneda is not distinct from (select moneda from u)
       and ((f.tipo = 'reserva_parcela' and f.es_raiz)
            or (f.tipo is distinct from 'reserva_parcela' and f.es_obra))
  ),
  marcados as (
    select k.unidad_id, k.firmado, k.precio_total, k.obra,
           bool_or(k.firmado) over (partition by k.obra, k.unidad_id) as hay_firmado,
           row_number() over (partition by k.obra, k.unidad_id order by k.created_at desc) as orden
      from con_precio k
  ),
  vigentes as (select m.unidad_id, m.precio_total, m.obra, m.firmado from marcados m
                where (m.hay_firmado and m.firmado) or (not m.hay_firmado and m.orden = 1)),
  -- peso de cada parcela en el SUELO de la venta: el precio del Bloqueo es de todas sus parcelas y se reparte por el
  -- suelo de cada una (si a alguna le falta, por el precio total; si tampoco, a partes iguales)
  peso_suelo as (
    select case when (select n from tot_hermanas) <= 1 then 1
      when (select sin_suelo from tot_hermanas) = 0 and (select suma_suelo from tot_hermanas) > 0
        then (select precio_suelo from u) / (select suma_suelo from tot_hermanas)
      else (select w from peso_precio) end as w
  ),
  peso_sin_asignar as (
    select case when not exists (select 1 from hermanas_sin_asignar where id = p_unidad) then 0
      when (select suma from tot_sin_asignar) > 0 then coalesce((select precio from u), 0) / (select suma from tot_sin_asignar)
      when (select n from tot_sin_asignar) > 0 then 1.0 / (select n from tot_sin_asignar) else 0 end as w
  ),
  venta as (
    select (select coalesce(sum(f.cobrado), 0) from fam f) as bolsa,
           (select sum(v.precio_total) from vigentes v where not v.obra) as suelo_contrato,
           (select sum(h.precio_suelo) from hermanas h) as suelo_catalogo,
           (select coalesce(sum(o.v), 0) from obra_de o) as obra_bruta
  ),
  -- Una venta con dinero cobrado en un contrato de OTRA moneda no se puede meter en una sola bolsa: se queda con el
  -- reparto de siempre y el precio de catálogo (avanza_unidad_por_cobro tampoco la mueve). Hoy no hay ninguna.
  mezcla as (
    select exists (select 1 from fam f where f.cobrado > 0 and f.moneda is distinct from (select moneda from u)) as v
  ),
  tope as (
    select case when (select v from mezcla) then null
                else coalesce(nullif(v.suelo_contrato, 0), nullif(v.suelo_catalogo, 0)) end as venta,
           -- «de contrato» = el precio de la parcela sale del Bloqueo de la venta, FIRMADO O NO (owner, 14-oct-2026:
           -- «aunque no estén firmados, coge el precio del contrato; el catálogo es una guía con descuentos máximos
           -- pero puede variar para cerrar una venta, por lo que manda el contrato»). Lo que sigue frenando a un
           -- borrador: la firma es la puerta del ESTADO (avanza_unidad_por_cobro no sube una parcela «bloqueada» sin
           -- Bloqueo firmado) y comisiones solo usa este precio si el Bloqueo está firmado (lo mira ella).
           coalesce(v.suelo_contrato, 0) > 0 and not (select v from mezcla) as de_contrato
      from venta v
  ),
  -- la parte de la obra de la venta que toca a esta parcela: en proporción a lo cobrado en SU obra; si en la venta
  -- no hay nada cobrado en contratos de obra (todo entró por el Bloqueo), por precio
  peso_obra as (
    select case when (select obra_bruta from venta) > 0 then (select obra from bruto) / (select obra_bruta from venta)
                else (select w from peso_precio) end as w
  ),
  obra_contrato as (
    select coalesce((select sum(v.precio_total) from vigentes v where v.obra and v.unidad_id = p_unidad), 0)
         + coalesce((select sum(v.precio_total) from vigentes v where v.obra and v.unidad_id is null), 0)
           * (select w from peso_sin_asignar) as v
  )
  select
    round(case when t.venta > 0 then least(t.venta, v.bolsa) * (select w from peso_suelo) else b.suelo end, 2) as cobrado_suelo,
    round(case when t.venta > 0 then (v.bolsa - least(t.venta, v.bolsa)) * (select w from peso_obra) else b.obra end, 2) as cobrado_obra,
    (select o.v from obra_firmada o) as obra_firmada,
    round(case when t.venta > 0 then t.venta * (select w from peso_suelo) else (select precio_suelo from u) end, 2) as suelo_precio,
    round(case when (select v from mezcla) then (select precio_construccion from u)
               else coalesce(nullif((select v from obra_contrato), 0), (select precio_construccion from u)) end, 2) as obra_precio,
    t.de_contrato as suelo_de_contrato
  from bruto b cross join venta v cross join tope t;
end
$function$;

CREATE OR REPLACE FUNCTION public.unidad_cobro_reparto(p_unidad uuid)
 RETURNS TABLE(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean, suelo_precio numeric, obra_precio numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_ok boolean; v_existe boolean := false; v_contrato uuid;
begin
  select true, u0.contrato_id,
         (u0.contrato_id is null
          or public.puede_ver_contrato(u0.contrato_id)
          or public.es_admin_de(public.empresa_de_unidad(p_unidad)))
    into v_existe, v_contrato, v_ok
    from public.unidades u0
   where u0.id = p_unidad;
  if not coalesce(v_existe, false) or not coalesce(v_ok, false) then
    -- «no he podido mirar», no «0 cobrado» (LAW-186)
    return query select null::numeric, null::numeric, null::boolean, null::numeric, null::numeric;
  elsif v_contrato is null then
    -- Sin contrato: 0 cobrado y NINGÚN precio (el de catálogo lo da la vista, que sí pasa por la RLS).
    return query select 0::numeric, 0::numeric, false, null::numeric, null::numeric;
  else
    return query select x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio
                   from public._unidad_cobro_cascada(p_unidad) x;
  end if;
end
$function$;

-- La migración le quitó EXECUTE a la vieja (sin llamador mientras la vista leía la v2). Se le devuelve ANTES de reponer la
-- vista: la vista es security_invoker y el lateral corre con el permiso de quien la lee; sin esto, la pantalla de
-- Proyectos caería con «permission denied for function unidad_cobro_reparto» en plena vuelta atrás. Los de antes del 15-oct.
grant execute on function public.unidad_cobro_reparto(uuid) to authenticated, service_role;
do $g$ begin
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    execute 'grant execute on function public.unidad_cobro_reparto(uuid) to lw_lector';
  end if;
end $g$;
comment on function public.unidad_cobro_reparto(uuid) is
  'Reparto de lo cobrado de una unidad (primero parcela, luego obra) con su precio de contrato, tras la puerta de permiso. Llamador: la vista unidades_estado.';

CREATE OR REPLACE FUNCTION public._venta_cobro_atribuido(p_raiz uuid)
 RETURNS TABLE(contrato_id uuid, cobrado_doc numeric, cobrado_regla numeric, atribuida boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- Contratos de obra de la venta. Con parcela PROPIA solo si es de esta venta (CC00064 y CC00066 apuntan a una de
  -- otra: se tratan como obra sin parcela). Vigentes = los firmados; si no hay, el borrador más reciente (la regla de
  -- obra_precio de la cascada).
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
  -- Bloqueo raíz = el resto de la bolsa: su suelo, la obra sin contrato de obra donde ponerse y los céntimos.
  select f.id, f.cobrado,
         case when not (select v from modo) then f.cobrado
              when f.es_raiz then (select b.v from bolsa b) - coalesce((select sum(a.imp) from asign a), 0)
              else coalesce((select sum(a.imp) from asign a where a.id = f.id), 0) end,
         (select v from modo)
    from fam f;
end
$function$;

CREATE OR REPLACE FUNCTION public._cadena_saldo_en(p_contrato uuid, p_moneda text, p_excluir uuid DEFAULT NULL::uuid)
 RETURNS TABLE(raiz uuid, raiz_numero text, moneda text, precio numeric, sin_precio boolean, facturado numeric, total_facturas numeric, cobrado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with r as (
    select coalesce(c.contrato_padre_id, c.id) as id from public.contratos c where c.id = p_contrato
  ), ro as (
    select c.id, c.numero from public.contratos c join r on r.id = c.id
  ), ca as (
    select c.id, c.tipo, c.precio_total,
           c.tipo not like 'carta\_reserva%'
           and not (c.id <> r.id and c.tipo in ('poa', 'hak_sewa_notario', 'adenda'))
           and c.moneda is not distinct from p_moneda as cuenta
      from public.contratos c, r
     where c.id = r.id or c.contrato_padre_id = r.id
  ), fa as (
    select f.id, f.total,
           coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total) as subtotal,
           coalesce((select sum(ra.importe_aplicado)
                       from public.recibi_aplicaciones ra
                       join public.facturas rc on rc.id = ra.recibi_id
                      where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0) as cobrado
      from public.facturas f
      join ca on ca.id = f.contrato_id
     where f.tipo = 'factura' and not coalesce(f.anulada, false)
       and f.moneda is not distinct from p_moneda
       and f.id is distinct from p_excluir
  )
  select ro.id, ro.numero, p_moneda,
         (select sum(ca.precio_total) from ca where ca.cuenta),
         coalesce((select bool_or(ca.precio_total is null) from ca where ca.cuenta), true),
         coalesce((select sum(fa.subtotal) from fa), 0),
         coalesce((select sum(fa.total) from fa), 0),
         coalesce((select sum(fa.cobrado) from fa), 0)
    from ro;
$function$;

CREATE OR REPLACE FUNCTION public.contrato_saldo(p_contrato uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s record; v_f jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  if not (public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) or (public.es_agente() and public.puede_ver_contrato(p_contrato))) then
    raise exception 'No puedes ver este contrato' using errcode = '42501';
  end if;
  select * into v_s from public._cadena_saldo(p_contrato, null);
  if v_s.raiz is null then
    raise exception 'Ese contrato ya no existe' using errcode = 'P0002';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'numero', f.numero, 'total', f.total,
           'subtotal', coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total),
           'cobrado', coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                  join public.facturas rc on rc.id = ra.recibi_id
                                 where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0),
           'lineas', coalesce((select jsonb_agg(jsonb_build_object(
                         'descripcion', l->>'descripcion',
                         'importe', public.lw_parse_importe(l->>'importe')))
                       from jsonb_array_elements(case when jsonb_typeof(f.datos->'lineas') = 'array'
                                                      then f.datos->'lineas' else '[]'::jsonb end) l), '[]'::jsonb))
         order by f.numero), '[]'::jsonb)
    into v_f
    from public.facturas f
   where f.contrato_id = p_contrato and f.tipo = 'factura' and not coalesce(f.anulada, false);
  return jsonb_build_object(
    'cadena', v_s.raiz_numero, 'moneda', v_s.moneda, 'precio', v_s.precio, 'sin_precio', v_s.sin_precio,
    'facturado', v_s.facturado, 'cobrado', v_s.cobrado,
    'por_cobrar', v_s.total_facturas - v_s.cobrado,
    'por_facturar', case when v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then null
                         else greatest(v_s.precio - v_s.facturado, 0) end,
    'facturas', v_f);
end $function$;

CREATE OR REPLACE VIEW public.unidades_estado WITH (security_invoker = true) AS
 SELECT u.id,
    u.codigo,
    u.proyecto,
    u.tipo,
    u.superficie_m2,
    COALESCE(u.precio, NULLIF((COALESCE(u.precio_suelo, (0)::numeric) + COALESCE(u.precio_construccion, (0)::numeric)), (0)::numeric)) AS precio,
    u.moneda,
    u.estado,
    u.contrato_id,
    u.notas,
    u.created_at,
    u.precio_suelo,
    u.precio_construccion,
    u.modelo,
    u.obra_fase,
    u.obra_fecha_entrega,
    u.obra_actualizado,
    c.numero AS contrato_numero,
    c.comprador_nombre,
    c.bloqueado AS contrato_firmado,
    (cp.cobrado_suelo + cp.cobrado_obra) AS facturado,
        CASE
            WHEN (cp.cobrado_suelo IS NULL) THEN NULL::numeric
            WHEN (COALESCE(u.precio, NULLIF((COALESCE(u.precio_suelo, (0)::numeric) + COALESCE(u.precio_construccion, (0)::numeric)), (0)::numeric)) > (0)::numeric) THEN round((((cp.cobrado_suelo + cp.cobrado_obra) / COALESCE(u.precio, NULLIF((COALESCE(u.precio_suelo, (0)::numeric) + COALESCE(u.precio_construccion, (0)::numeric)), (0)::numeric))) * (100)::numeric), 1)
            ELSE NULL::numeric
        END AS pct_cobrado,
    u.fase_masterplan,
    u.zona_masterplan,
    u.precio AS precio_guardado,
    c.creado_por AS contrato_creado_por,
    cp.cobrado_suelo,
    cp.cobrado_obra,
    cp.obra_firmada,
    u.codigo_orden,
    ((c.id IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM public.contrato_tipo_etapa e
          WHERE ((e.tipo = c.tipo) AND (e.etapa = 'reserva'::text) AND (e.tipo <> 'reserva_parcela'::text))))) AS contrato_es_carta,
    u.proyecto_id,
    cp.suelo_precio AS suelo_pactado,
    cp.obra_precio AS obra_pactada,
    NULL::boolean AS suelo_de_contrato,
    NULL::boolean AS obra_de_contrato
   FROM ((public.unidades u
     LEFT JOIN public.contratos c ON ((c.id = u.contrato_id)))
     LEFT JOIN LATERAL public.unidad_cobro_reparto(u.id) cp(cobrado_suelo, cobrado_obra, obra_firmada, suelo_precio, obra_precio) ON (true));

-- La vista: security_invoker y sus permisos, repuestos aquí aunque CREATE OR REPLACE los conserve (lección de Backend
-- del 2-sep: se perdieron tres veces). Los mismos que tenía: SELECT para authenticated y lw_lector; nada para anon.
alter view public.unidades_estado set (security_invoker = true);
revoke all on public.unidades_estado from anon, public;
grant select on public.unidades_estado to authenticated;
do $g$ begin
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    execute 'grant select on public.unidades_estado to lw_lector';
  end if;
end $g$;

-- las nuevas, sin llamador: cerradas
revoke all on function public.unidad_cobro_reparto_v2(uuid) from public, anon, authenticated, service_role;
do $g$ begin
  if exists (select 1 from pg_roles where rolname = 'lw_lector') then
    execute 'revoke all on function public.unidad_cobro_reparto_v2(uuid) from lw_lector';
  end if;
end $g$;

do $post$
begin
  if (select string_agg(md5(p.prosrc), ',' order by p.proname collate "C") from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('_cadena_saldo_en', 'contrato_saldo', '_unidad_cobro_cascada', '_venta_cobro_atribuido', 'unidad_cobro_reparto'))
     <> 'b094521e67c8fd736dbf77e8ef18c2a6,69b0bf975b030fa77e08a966a0b8c133,0d66c0ba123bd8ebdaf11aa9cfe92d7a,2370617522d53c7d3b006e19b1283f89,26c727388896032ddc0094e67cde6351' then
    raise exception 'REVERSION precio-cadena-vigente: los cuerpos repuestos no son los del 15-oct (md5)';
  end if;
  -- la vista vuelve a la vieja: quien lee la vista tiene que poder ejecutarla (roles sacados de pg_roles: en una rama
  -- lw_lector no existe)
  if exists (select 1 from pg_roles r where r.rolname in ('authenticated', 'lw_lector')
               and not has_function_privilege(r.oid, 'public.unidad_cobro_reparto(uuid)'::regprocedure, 'execute')) then
    raise exception 'REVERSION precio-cadena-vigente: la vieja unidad_cobro_reparto no la ejecuta authenticated o lw_lector, y la vista la llama';
  end if;
end $post$;
