-- Prueba en la BASE VIVA de precio-cadena-vigente (15-oct-2026, migración 20261015171500_precio_cadena_vigente.sql).
-- SE LANZA DESPUÉS DE APLICAR, por execute_sql (o el SQL Editor), y TERMINA CON UN RAISE a propósito: no deja rastro (las
-- funciones pg_temp, el cambio de rol y los claims se deshacen con él).
-- «Antes» y «después» EN EL MISMO INSTANTE: las funciones de antes de la migración van aquí como pg_temp, con su cuerpo literal
-- (el de supabase/reversion_precio_cadena_vigente/REVERSION.sql, md5 comprobado en la guarda de la migración), y se comparan
-- con las vivas sobre TODAS las unidades y TODAS las raíces.
--   W1  la cascada nueva (v2 y su envoltorio) = la de antes, columna a columna, en todas las unidades
--   W1c la puerta de la v2 (Seguridad): un `sub` que no es agente pide una unidad sin contrato y recibe todo NULL (antes
--       (0,0,f,…)); W1d SI: la identidad de W5 pide una unidad sin contrato que ve y recibe (0,0,f,null,null,f,f)
--   W2  el reparto del cobro (_venta_cobro_atribuido) = el de antes en todas las raíces
--   W3  el precio de la cadena solo cambia en las ventas con una obra no vigente (medido el 15-oct: RP00045, RP00101,
--       RP00197, RP00209, RP00255, RP00259) y NINGÚN documento sale: sin_precio, facturado, total y cobrado iguales
--   W3b sin depender de la función vieja: en cada raíz, facturado = suma de subtotales y cobrado = suma de lo aplicado de las
--       facturas VIVAS de la raíz y sus hijos en su moneda (ningún documento vivo sale, sea de un contrato vigente o no)
--   W4  el invariante de las 141 ventas: precio de la cadena = suelo + obra de contrato de la cascada (y, aparte, cuántas
--       ventas tienen una obra sin parcela que la cascada no reparte: 0 el 15-oct)
--   W5  RP00101 por la RPC y con el rol real (el agente que creó la venta, o el admin global si no está activo): contrato_saldo
--       da precio 69.000 y facturado_de_mas 25.000. W5c, el tope, SIN DDL (Seguridad, 15-oct): se llama directamente a
--       public._factura_tope_cadena(null, RP00101, 'EUR', 1, 'factura') como postgres (es la única que la ejecuta) con las
--       claims de esa identidad, y tiene que dar 23514. Ya no pasa por factura_guarda: ni disparador de numeración temporal
--       ni el falso 42501 de la sociedad. Solo se llama si el canario W5a dice que la identidad NO es super admin de la
--       empresa (si lo fuera, el tope apuntaría el privilegio con registra_privilegio, que escribe, y no daría 23514).
--   W6  RP00025: a_cuenta = 39.220 por contrato_saldo con el rol real
--   W7  la vista: las dos columnas nuevas al final, security_invoker y SELECT solo para authenticated
--   W7b la identidad de W5 lee unidades_estado sin error y con tantas filas como `unidades` con el mismo rol (la vista es
--       security_invoker sobre unidades: el «mismo número que antes» de un fichero que corre después de aplicar), ya sin
--       permiso sobre la vieja unidad_cobro_reparto; y obra_cifras_datos() (DEFINER de lw_lector, lee la vista) responde:
--       la cadena vista → v2 funciona con authenticated y con lw_lector
--   W8  tiempo de `select * from unidades_estado`: la vista vieja (cascada y puerta de antes en pg_temp) y la de ahora,
--       con las claims del admin, en la viva; mismas filas y mismo cobrado
--   W9  ninguna serie se movió: foto de pg_sequences (esquema public) al principio y al final. Una venta real que se emita
--       en esos segundos movería su serie: si W9 falla, mirar cuál antes de dar nada por roto.
-- Identidades resueltas desde la base (ningún uid ni email en el fichero: el repo de Lawang es público).
-- Cada línea acaba en «→ ok» o «→ FALLA»; la última es «FIN DE PRUEBAS».
-- NO ESCRIBE EN LA BASE (comprobado con grep el 15-oct): los únicos CREATE son funciones pg_temp de la sesión; no hay
-- insert, update, delete ni alter. Lo único que retiene: el cerrojo consultivo del tope sobre RP00101
-- (pg_advisory_xact_lock en _factura_tope_cadena) hasta el raise del final; una factura de RP00101 que se emita en esos
-- segundos espera. Se lanza con turno.
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo funciones pg_temp

-- ============================================================ las funciones de ANTES (cuerpo literal, como pg_temp)
CREATE OR REPLACE FUNCTION pg_temp.casc_vieja(p_unidad uuid)
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

CREATE OR REPLACE FUNCTION pg_temp.reparto_viejo(p_unidad uuid)
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
                   from pg_temp.casc_vieja(p_unidad) x;
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION pg_temp.atr_viejo(p_raiz uuid)
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
            from her h cross join lateral pg_temp.casc_vieja(h.id) x
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

CREATE OR REPLACE FUNCTION pg_temp.cad_vieja(p_contrato uuid, p_moneda text, p_excluir uuid DEFAULT NULL::uuid)
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

create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;

do $todo$
declare
  r text := ''; v text; s jsonb; n bigint; m bigint;
  v_uid uuid; v_mail text; v_rp101 uuid; v_rp25 uuid; v_libre uuid; v_ad uuid; v_ad_mail text;
  v_seq0 jsonb; v_seq1 jsonb; t0 timestamptz; ms_antes numeric; ms_despues numeric;
  n_antes bigint; n_despues bigint; s_antes numeric; s_despues numeric;
  c_fin constant text := 'FIN DE PRUEBAS PRECIO CADENA VIGENTE EN LA VIVA (se deshace todo):%';
begin
  -- W9 (foto inicial): todas las series de public; al final tienen que seguir igual
  select coalesce(jsonb_object_agg(s.sequencename, s.last_value), '{}'::jsonb) into v_seq0 from pg_sequences s where s.schemaname = 'public';
  select c.id into v_rp101 from public.contratos c where c.numero = 'RP00101' and c.contrato_padre_id is null;
  select c.id into v_rp25 from public.contratos c where c.numero = 'RP00025' and c.contrato_padre_id is null;
  -- la identidad de W5 (y de W1d y W7b): el agente que creó RP00101, o el admin global más antiguo si no está activo
  select u.user_id, u.email into v_uid, v_mail
    from public.usuarios u
   where u.activo and 'facturas' = any(u.herramientas)
     and (u.email = (select c.creado_por from public.contratos c where c.id = v_rp101) or u.rol = 'admin')
   order by (u.email = (select c.creado_por from public.contratos c where c.id = v_rp101)) desc, u.creado_en
   limit 1;

  -- ============================================================ W1 la cascada, antes y después
  select count(*), count(*) filter (where (a.cobrado_suelo, a.cobrado_obra, a.obra_firmada, a.suelo_precio, a.obra_precio, a.suelo_de_contrato)
                                    is distinct from (b.cobrado_suelo, b.cobrado_obra, b.obra_firmada, b.suelo_precio, b.obra_precio, b.suelo_de_contrato))
    into m, n
    from public.unidades u
    cross join lateral pg_temp.casc_vieja(u.id) a
    cross join lateral public._unidad_cobro_cascada_v2(u.id) b;
  r := r || pg_temp.l(n = 0 and m > 0, 'W1a cascada v2 = la de antes en las ' || m || ' unidades (' || n || ' distintas)');
  select count(*) into n
    from public.unidades u
    cross join lateral public._unidad_cobro_cascada(u.id) a
    cross join lateral public._unidad_cobro_cascada_v2(u.id) b
   where (a.cobrado_suelo, a.cobrado_obra, a.obra_firmada, a.suelo_precio, a.obra_precio, a.suelo_de_contrato)
         is distinct from (b.cobrado_suelo, b.cobrado_obra, b.obra_firmada, b.suelo_precio, b.obra_precio, b.suelo_de_contrato);
  r := r || pg_temp.l(n = 0, 'W1b el envoltorio _unidad_cobro_cascada = la v2 (' || n || ' distintas)');

  -- W1c / W1d la puerta de la v2: una unidad sin contrato que la identidad de W5 ve (claims puestas como postgres, sin
  -- cambiar de rol: solo para elegirla)
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated', 'email', v_mail)::text, true);
  select u.id into v_libre from public.unidades u
   where u.contrato_id is null and public.es_agente() and public.unidad_visible(u.proyecto_id)
   order by u.id limit 1;
  perform set_config('request.jwt.claims', '', true);
  v := pg_temp.val(gen_random_uuid(), null, format(
         'select public.es_agente()::text || ''|'' || concat_ws(''|'', coalesce(x.cobrado_suelo::text, ''null''), coalesce(x.cobrado_obra::text, ''null''),'
         || ' coalesce(x.obra_firmada::text, ''null''), coalesce(x.suelo_precio::text, ''null''), coalesce(x.obra_precio::text, ''null''),'
         || ' coalesce(x.suelo_de_contrato::text, ''null''), coalesce(x.obra_de_contrato::text, ''null'')) from public.unidad_cobro_reparto_v2(%L::uuid) x', v_libre));
  r := r || pg_temp.l(v_libre is not null and v = 'false|null|null|null|null|null|null|null',
                      'W1c un sub que no es agente (es_agente false) pide una unidad sin contrato: todo NULL, ya no (0,0,f,…) (' || left(coalesce(v, 'sin unidad libre'), 60) || ')');
  v := pg_temp.val(v_uid, v_mail, format(
         'select concat_ws(''|'', coalesce(x.cobrado_suelo::text, ''null''), coalesce(x.cobrado_obra::text, ''null''), coalesce(x.obra_firmada::text, ''null''),'
         || ' coalesce(x.suelo_precio::text, ''null''), coalesce(x.obra_precio::text, ''null''), coalesce(x.suelo_de_contrato::text, ''null''),'
         || ' coalesce(x.obra_de_contrato::text, ''null'')) from public.unidad_cobro_reparto_v2(%L::uuid) x', v_libre));
  r := r || pg_temp.l(v = '0|0|false|null|null|false|false',
                      'W1d SI: la identidad de W5 (agente que ve el proyecto) pide la misma unidad: (0,0,f,null,null,f,f) (' || left(coalesce(v, 'null'), 60) || ')');

  -- ============================================================ W2 el reparto del cobro, antes y después
  select count(*), count(*) filter (where exists ((select * from public._venta_cobro_atribuido(c.id)) except (select * from pg_temp.atr_viejo(c.id)))
                                       or exists ((select * from pg_temp.atr_viejo(c.id)) except (select * from public._venta_cobro_atribuido(c.id))))
    into m, n
    from public.contratos c where c.contrato_padre_id is null;
  r := r || pg_temp.l(n = 0 and m > 0, 'W2 _venta_cobro_atribuido = el de antes en las ' || m || ' raíces (' || n || ' distintas)');

  -- ============================================================ W3 el precio de la cadena y los documentos
  with d as (
    select c.numero, a.precio pv, b.precio pn, a.sin_precio sv, b.sin_precio sn,
           (a.facturado, a.total_facturas, a.cobrado) is distinct from (b.facturado, b.total_facturas, b.cobrado) as docs,
           exists (select 1 from public.contratos h left join public.contrato_tipo_etapa e on e.tipo = h.tipo
                    where h.contrato_padre_id = c.id and h.tipo is distinct from 'reserva_parcela'
                      and public._comisiones_parte_obra(h.tipo, e.es_obra) and coalesce(h.precio_total, 0) > 0
                      and h.moneda is not distinct from c.moneda
                      and h.id not in (select o.contrato_id from public._venta_obras_vigentes(c.id, c.moneda) o)) as hay_no_vigente
      from public.contratos c
      cross join lateral pg_temp.cad_vieja(c.id, c.moneda, null) a
      cross join lateral public._cadena_saldo_en(c.id, c.moneda, null) b
     where c.contrato_padre_id is null
  )
  select coalesce(string_agg(numero, ',' order by numero) filter (where pv is distinct from pn), '-')
         || ' | cambia sin obra no vigente: ' || count(*) filter (where pv is distinct from pn and not hay_no_vigente)
         || ' | sin_precio distinto: ' || count(*) filter (where sv is distinct from sn)
         || ' | documentos distintos: ' || count(*) filter (where docs),
         count(*) filter (where (pv is distinct from pn and not hay_no_vigente) or sv is distinct from sn or docs)
    into v, n from d;
  r := r || pg_temp.l(n = 0, 'W3 precio distinto solo con obra no vigente; sin_precio y documentos iguales: ' || v);
  -- W3b: facturado y cobrado contra las facturas vivas de la venta, sin la función vieja
  with d as (
    select c.numero, s.facturado, s.cobrado,
           (select coalesce(sum(coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total)), 0)
              from public.facturas f join public.contratos h on h.id = f.contrato_id
             where (h.id = c.id or h.contrato_padre_id = c.id) and f.tipo = 'factura' and not coalesce(f.anulada, false)
               and f.moneda is not distinct from c.moneda) as fact_docs,
           (select coalesce(sum(ra.importe_aplicado), 0)
              from public.recibi_aplicaciones ra
              join public.facturas rc on rc.id = ra.recibi_id
              join public.facturas f on f.id = ra.factura_id
              join public.contratos h on h.id = f.contrato_id
             where (h.id = c.id or h.contrato_padre_id = c.id) and f.tipo = 'factura' and not coalesce(f.anulada, false)
               and not coalesce(rc.anulada, false) and f.moneda is not distinct from c.moneda) as cobr_docs
      from public.contratos c
      cross join lateral public._cadena_saldo_en(c.id, c.moneda, null) s
     where c.contrato_padre_id is null
  )
  select count(*) filter (where facturado <> fact_docs or cobrado <> cobr_docs),
         coalesce(string_agg(numero, ',') filter (where facturado <> fact_docs or cobrado <> cobr_docs), '-')
    into n, v from d;
  r := r || pg_temp.l(n = 0, 'W3b facturado y cobrado = facturas vivas de la raíz y sus hijos, en todas las raíces (distintas: ' || v || ')');

  -- ============================================================ W4 el invariante de las 141 ventas
  with por_venta as (
    select u.contrato_id raiz, count(*) k,
           sum(x.suelo_precio) filter (where x.suelo_de_contrato) suelo,
           sum(x.obra_precio) filter (where x.obra_de_contrato) obra
      from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
     where u.contrato_id is not null group by u.contrato_id
  )
  select count(*), count(*) filter (where abs(coalesce(s.precio, 0) - coalesce(p.suelo, 0) - coalesce(p.obra, 0)) > 0.01 * p.k),
         coalesce(string_agg(rz.numero, ',') filter (where abs(coalesce(s.precio, 0) - coalesce(p.suelo, 0) - coalesce(p.obra, 0)) > 0.01 * p.k), '-')
    into m, n, v
    from por_venta p join public.contratos rz on rz.id = p.raiz
    cross join lateral public._cadena_saldo_en(rz.id, rz.moneda, null) s;
  r := r || pg_temp.l(n = 0 and m > 0, 'W4a precio de la cadena = suelo + obra de contrato de la cascada en las ' || m || ' ventas con parcela (no cuadran: ' || v || ')');
  select count(*) into n
    from public.contratos rz
   where rz.contrato_padre_id is null
     and exists (select 1 from public._venta_obras_vigentes(rz.id, rz.moneda) o where o.parcela is null and not o.es_raiz)
     and exists (select 1 from public.unidades u where u.contrato_id = rz.id)
     and not exists (select 1 from public.unidades u where u.contrato_id = rz.id
                       and not exists (select 1 from public.contratos h left join public.contrato_tipo_etapa e on e.tipo = h.tipo
                                        where h.contrato_padre_id = rz.id and h.unidad_id = u.id and e.etapa is distinct from 'reserva'));
  r := r || pg_temp.l(n = 0, 'W4b ventas con obra sin parcela y TODAS sus parcelas con obra propia (la cascada no la reparte): ' || n);

  -- ============================================================ W5 RP00101 por la RPC, con el rol real
  v := pg_temp.val(v_uid, v_mail, format('select (public.es_super_admin_de(public.empresa_de_contrato(%L::uuid)) or not public.puede_ver_contrato(%L::uuid))::text', v_rp101, v_rp101));
  r := r || pg_temp.l(v_rp101 is not null and v = 'false', 'W5a canario: la identidad ve RP00101 y NO es super admin de su empresa (' || coalesce(v, 'sin identidad') || ')');
  v := pg_temp.val(v_uid, v_mail, format('select public.contrato_saldo(%L::uuid)::text', v_rp101));
  if v ~ '^ERR' or v = '(null)' then
    r := r || pg_temp.l(false, 'W5b contrato_saldo(RP00101): ' || left(v, 120));
  else
    s := v::jsonb;
    r := r || pg_temp.l((s->>'precio')::numeric = 69000 and (s->>'facturado')::numeric = 94000
                        and (s->>'facturado_de_mas')::numeric = 25000 and (s->>'por_facturar')::numeric = 0,
                        'W5b contrato_saldo(RP00101): precio ' || coalesce(s->>'precio', 'null') || ', facturado ' || coalesce(s->>'facturado', 'null')
                        || ', facturado_de_mas ' || coalesce(s->>'facturado_de_mas', 'null') || ', por_facturar ' || coalesce(s->>'por_facturar', 'null'));
  end if;
  -- W5c el tope, SIN DDL y sin factura_guarda (Seguridad, 15-oct): la función del tope directamente, como postgres (su único
  -- EXECUTE) y con las claims de la identidad, que no es super admin (W5a). Si no se puede asegurar que no lo es, no se
  -- llama: el super admin pasa el tope apuntando el privilegio (registra_privilegio escribe) y no daría 23514.
  if v_rp101 is not null and v_uid is not null
     and pg_temp.val(v_uid, v_mail, format('select public.es_super_admin_de(public._empresa_doc(null::uuid, %L::uuid))::text', v_rp101)) = 'false' then
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated', 'email', v_mail)::text, true);
    begin
      perform public._factura_tope_cadena(null::uuid, v_rp101, 'EUR', 1::numeric, 'factura');
      v := 'sin error';
    exception when others then v := 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
    end;
    perform set_config('request.jwt.claims', '', true);
    r := r || pg_temp.l(v like 'ERR23514:%Quedan 0%',
                        'W5c _factura_tope_cadena(null, RP00101, EUR, 1, factura) con las claims de la identidad: 23514 (' || left(v, 120) || ')');
  else
    r := r || pg_temp.l(false, 'W5c no se llama al tope: sin RP00101, sin identidad o la identidad es super admin de la empresa (pasaría apuntando el privilegio)');
  end if;

  -- ============================================================ W6 RP00025: a cuenta
  select u.user_id, u.email into v_ad, v_ad_mail from public.usuarios u
   where u.activo and u.rol = 'admin' order by u.creado_en limit 1;
  v := pg_temp.val(v_ad, v_ad_mail, format('select (public.contrato_saldo(%L::uuid))->>''a_cuenta'' ', v_rp25));
  r := r || pg_temp.l(v ~ '^[0-9.]+$' and v::numeric = 39220, 'W6 a_cuenta de RP00025 por contrato_saldo con el admin: ' || left(v, 80));

  -- ============================================================ W7 la vista
  select count(*) into n from (
    select k.column_name, k.ordinal_position, max(k.ordinal_position) over () as ultima
      from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'unidades_estado') x
   where (x.column_name = 'suelo_de_contrato' and x.ordinal_position = x.ultima - 1)
      or (x.column_name = 'obra_de_contrato' and x.ordinal_position = x.ultima);
  r := r || pg_temp.l(n = 2
                      and (select c.reloptions::text from pg_class c where c.oid = 'public.unidades_estado'::regclass) like '%security_invoker=true%'
                      and has_table_privilege('authenticated', 'public.unidades_estado', 'select')
                      and not has_table_privilege('anon', 'public.unidades_estado', 'select')
                      and not has_table_privilege('authenticated', 'public.unidades_estado', 'truncate'),
                      'W7 vista: las dos columnas nuevas al final, security_invoker, SELECT solo para authenticated');
  -- W7b la cadena vista → v2 sin el permiso viejo: la identidad de W5 lee la vista entera (el lateral corre con SU permiso)
  -- y obtiene tantas filas como `unidades` con el mismo rol (la vista es security_invoker sobre unidades)
  v := pg_temp.val(v_uid, v_mail,
         'select (select count(*) from (select * from public.unidades_estado) e)::text || ''/'' || (select count(*) from public.unidades)::text'
         || ' || ''/'' || (select count(*) from public.unidades_estado e where e.obra_fecha_entrega is not null)::text');
  n := case when v ~ '^\d+/\d+/\d+$' then split_part(v, '/', 3)::bigint end;
  r := r || pg_temp.l(v ~ '^\d+/\d+/\d+$' and split_part(v, '/', 1) = split_part(v, '/', 2) and split_part(v, '/', 1)::bigint > 0
                      and not has_function_privilege('authenticated', 'public.unidad_cobro_reparto(uuid)', 'execute'),
                      'W7b la identidad de W5 lee unidades_estado sin error, tantas filas como unidades con su rol (vista/unidades/con entrega: ' || left(v, 80) || '), sin EXECUTE sobre la vieja');
  -- W7c el camino de lw_lector: obra_cifras_datos() es DEFINER de lw_lector y cuenta filas de la vista
  v := pg_temp.val(v_uid, v_mail, 'select public.obra_cifras_datos()->>''entregas_con_fecha''');
  r := r || pg_temp.l(v ~ '^\d+$' and v::bigint = n,
                      'W7c obra_cifras_datos() (lw_lector → vista → v2) responde con la identidad de W5 y cuenta lo mismo que la vista: ' || left(v, 80) || ' / ' || coalesce(n::text, 'null'));

  -- ============================================================ W8 tiempo de la vista, antes y después (viva)
  -- Como postgres con las claims del admin (postgres no pasa por la RLS: igual en los dos lados). «Antes» = la vista vieja,
  -- con la cascada y la puerta de antes en pg_temp. Cada consulta corre dos veces y se mide la segunda.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ad, 'role', 'authenticated', 'email', v_ad_mail)::text, true);
  for i in 1..2 loop
    t0 := clock_timestamp();
    select count(*), coalesce(sum(coalesce(q.cobrado_suelo, 0) + coalesce(q.cobrado_obra, 0) + coalesce(q.suelo_pactado, 0) + coalesce(q.obra_pactada, 0)), 0)
      into n_antes, s_antes
      from (SELECT u.id, u.codigo, u.proyecto, u.tipo, u.superficie_m2,
                   COALESCE(u.precio, NULLIF((COALESCE(u.precio_suelo, (0)::numeric) + COALESCE(u.precio_construccion, (0)::numeric)), (0)::numeric)) AS precio,
                   u.moneda, u.estado, u.contrato_id, u.notas, u.created_at, u.precio_suelo, u.precio_construccion, u.modelo, u.obra_fase,
                   u.obra_fecha_entrega, u.obra_actualizado, c.numero AS contrato_numero, c.comprador_nombre, c.bloqueado AS contrato_firmado,
                   (cp.cobrado_suelo + cp.cobrado_obra) AS facturado,
                   u.fase_masterplan, u.zona_masterplan, u.precio AS precio_guardado, c.creado_por AS contrato_creado_por,
                   cp.cobrado_suelo, cp.cobrado_obra, cp.obra_firmada, u.codigo_orden,
                   ((c.id IS NOT NULL) AND (EXISTS (SELECT 1 FROM public.contrato_tipo_etapa e
                      WHERE ((e.tipo = c.tipo) AND (e.etapa = 'reserva'::text) AND (e.tipo <> 'reserva_parcela'::text))))) AS contrato_es_carta,
                   u.proyecto_id, cp.suelo_precio AS suelo_pactado, cp.obra_precio AS obra_pactada
              FROM ((public.unidades u
                LEFT JOIN public.contratos c ON ((c.id = u.contrato_id)))
                LEFT JOIN LATERAL pg_temp.reparto_viejo(u.id) cp(cobrado_suelo, cobrado_obra, obra_firmada, suelo_precio, obra_precio) ON (true))) q;
    ms_antes := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
    t0 := clock_timestamp();
    select count(*), coalesce(sum(coalesce(e.cobrado_suelo, 0) + coalesce(e.cobrado_obra, 0) + coalesce(e.suelo_pactado, 0) + coalesce(e.obra_pactada, 0)), 0)
      into n_despues, s_despues
      from (select * from public.unidades_estado) e;
    ms_despues := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  end loop;
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l(n_antes = n_despues and n_antes > 0 and s_antes = s_despues,
                      format('W8 select * from unidades_estado en la viva: antes %s ms, después %s ms (%s filas; cobrado+pactado %s / %s)',
                             ms_antes, ms_despues, n_despues, s_antes, s_despues));

  -- ============================================================ W9 ninguna serie se movió
  select coalesce(jsonb_object_agg(s.sequencename, s.last_value), '{}'::jsonb) into v_seq1 from pg_sequences s where s.schemaname = 'public';
  select string_agg(k, ', ') into v from jsonb_object_keys(v_seq0 || v_seq1) k where v_seq0 -> k is distinct from v_seq1 -> k;
  r := r || pg_temp.l(v is null, 'W9 pg_sequences de public igual al principio y al final (' || (select count(*) from jsonb_object_keys(v_seq0)) || ' series; movidas: ' || coalesce(v, 'ninguna') || ')');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
