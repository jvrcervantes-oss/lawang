-- «Primero la parcela, luego la obra» — una sola regla para pantalla, estado de la parcela y comisiones.
--
-- REGLA (owner, 14-oct-2026): todo lo cobrado en una venta —el contrato raíz y sus hijos, cuelgue el recibí del
-- contrato que cuelgue— paga PRIMERO la parcela hasta el 100 % de su PRECIO DE CONTRATO (el Bloqueo de Parcela), y
-- solo el resto es obra. El precio de catálogo (unidades.precio_suelo) queda de respaldo cuando la venta aún no tiene
-- Bloqueo con precio («usa el precio del contrato, el precio final, no el del catálogo», owner, mismo día).
--
-- POR QUÉ. Hasta hoy el reparto dependía de A QUÉ CONTRATO se colgó el recibí: lo de la raíz era «suelo» y lo de un
-- hijo era «obra». Medido el 14-oct: SH-1 (Sumba Hills) con 41.620 cobrados contra RP00021 (25.000) y la obra a 0;
-- SH-2 y otras 18 con todo cobrado contra la Construcción y la parcela a 0. 35 unidades de 6 proyectos mal repartidas.
-- Administración registra UN recibí por pago y el sistema lo reparte al leerlo; no se mueve ningún recibí ni factura.
--
-- FUENTE ÚNICA. La regla vive en _unidad_cobro_cascada(). Antes había DOS copias del reparto
-- (unidad_parte_cobrada_split para la pantalla, unidad_parte_cobrada_interno para estados y comisiones) que ya
-- divergían (la carta hija por parcela solo estaba en la segunda). Ahora las dos son envoltorios de la misma función.
--
-- QUIÉN LEE (todos de la misma función):
--   pantalla    unidades_estado  ->  unidad_cobro_reparto()  (puerta de permiso + cascada)
--   estados     unidad_cumple_estado()  (avanza_unidad_por_cobro, trg_unidad_vendida_exige_cobro)
--   comisiones  comisiones_evaluar_contrato()  (regla anterior al 1-nov: «% cobrado del suelo»)
--   La regla de comisiones del 1-nov (_comisiones_bases_firmadas) NO va en esta migración: su batería necesita la
--   válvula del owner. Queda escrita en supabase/vivo/20261014_cobro_primero_parcela/siguiente_comisiones_1nov.sql.
--
-- Vuelta atrás: supabase/vivo/20261014_cobro_primero_parcela/vuelta.sql
-- Prueba (solo lectura): supabase/pruebas/cobro_primero_parcela.sql

-- 1 · LA CASCADA -----------------------------------------------------------------------------------------------------
create or replace function public._unidad_cobro_cascada(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean,
               suelo_precio numeric, obra_precio numeric, suelo_de_contrato boolean)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
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
           coalesce(public.contrato_cobrado(c.id), 0) as cobrado
      from public.contratos c
      left join public.contrato_tipo_etapa e on e.tipo = c.tipo
     where c.id = (select id from raiz) or c.contrato_padre_id = (select id from raiz)
  ),
  hermanas as (select x.id, x.codigo, x.precio, x.precio_suelo from public.unidades x where x.contrato_id = (select contrato_id from u)),
  -- Reparto de siempre (hasta el 14-oct): se conserva para (a) las ventas sin precio de parcela, que no tienen
  -- contra qué hacer la cascada, y (b) saber a qué parcela corresponde el dinero de obra de una venta de varias.
  hijos_obra as (select f.unidad_id, f.cobrado from fam f where not f.es_raiz and f.tipo is distinct from 'carta_reserva'),
  hijos_cr   as (select f.unidad_id, f.parcela_codigo, f.cobrado from fam f where not f.es_raiz and f.tipo = 'carta_reserva'),
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
    select case when (select suma from tot_hermanas) > 0 then (select precio from u) / (select suma from tot_hermanas)
      when (select n from tot_hermanas) > 0 then 1.0 / (select n from tot_hermanas) else 0 end as w
  ),
  -- lo cobrado en obra que corresponde a CADA parcela de la venta (el contrato de obra con su unidad; el que no la
  -- tiene, repartido por precio entre las parcelas sin contrato de obra propio)
  obra_de as (
    select h.id,
           coalesce((select sum(hj.cobrado) from hijos_obra hj where hj.unidad_id = h.id), 0)
           + case when not exists (select 1 from hermanas_sin_asignar s where s.id = h.id) then 0
                  when (select suma from tot_sin_asignar) > 0 then (select total from cobrado_sin_asignar) * h.precio / (select suma from tot_sin_asignar)
                  when (select n from tot_sin_asignar) > 0 then (select total from cobrado_sin_asignar) / (select n from tot_sin_asignar)
                  else 0 end as v
      from hermanas h
  ),
  bruto as (
    select (select total from cobrado_raiz) * (select w from peso_precio) + (select total from cobrado_cr_mio)
             + (select total from cobrado_cr_suelto) * (select w from peso_precio) as suelo,
           coalesce((select o.v from obra_de o where o.id = p_unidad), 0) as obra
  ),
  obra_firmada as (
    select exists (select 1 from fam f where not f.es_raiz and f.es_obra_catalogo and f.firmado
         and (f.unidad_id = p_unidad or (f.unidad_id is null and exists (select 1 from hermanas_sin_asignar where id = p_unidad)))) as v
  ),
  -- PRECIO DE CONTRATO. Parcela = el Bloqueo de Parcela de la venta (raíz, o hijo cuando la raíz es una Carta);
  -- obra = los contratos de obra (adenda = obra: _comisiones_parte_obra, la misma definición que usa comisiones).
  -- Por parte y unidad: los FIRMADOS si hay alguno; si no, el borrador más reciente (un borrador viejo junto a su
  -- sustituto firmado no suma dos veces: SH-36 tiene CC00062 sin firmar y CC00102 firmada). Liberados y sin precio,
  -- fuera; otra moneda que la de la unidad, fuera (no se mezclan divisas: se cae al catálogo).
  con_precio as (
    select f.unidad_id, f.firmado, f.precio_total, f.created_at, (f.tipo is distinct from 'reserva_parcela') as obra
      from fam f
     where f.liberado_en is null and coalesce(f.precio_total, 0) > 0
       and f.moneda is not distinct from (select moneda from u)
       and (f.tipo = 'reserva_parcela' or f.es_obra)
  ),
  marcados as (
    select k.unidad_id, k.firmado, k.precio_total, k.obra,
           bool_or(k.firmado) over (partition by k.obra, k.unidad_id) as hay_firmado,
           row_number() over (partition by k.obra, k.unidad_id order by k.created_at desc) as orden
      from con_precio k
  ),
  vigentes as (select m.unidad_id, m.precio_total, m.obra from marcados m
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
      when (select suma from tot_sin_asignar) > 0 then (select precio from u) / (select suma from tot_sin_asignar)
      when (select n from tot_sin_asignar) > 0 then 1.0 / (select n from tot_sin_asignar) else 0 end as w
  ),
  venta as (
    select (select coalesce(sum(f.cobrado), 0) from fam f) as bolsa,
           (select sum(v.precio_total) from vigentes v where not v.obra) as suelo_contrato,
           (select sum(h.precio_suelo) from hermanas h) as suelo_catalogo,
           (select coalesce(sum(o.v), 0) from obra_de o) as obra_bruta
  ),
  tope as (
    select coalesce(nullif(v.suelo_contrato, 0), nullif(v.suelo_catalogo, 0)) as venta,
           coalesce(v.suelo_contrato, 0) > 0 as de_contrato
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
    round(coalesce(nullif((select v from obra_contrato), 0), (select precio_construccion from u)), 2) as obra_precio,
    t.de_contrato as suelo_de_contrato
  from bruto b cross join venta v cross join tope t;
end
$function$;

revoke all on function public._unidad_cobro_cascada(uuid) from public, anon, authenticated;
grant execute on function public._unidad_cobro_cascada(uuid) to service_role;

comment on function public._unidad_cobro_cascada(uuid) is
  'Fuente única del reparto de lo cobrado de una unidad: primero la parcela hasta su precio de contrato, el resto obra (owner, 14-oct-2026). Sin puerta de permiso: solo la llaman funciones definer.';

-- 2 · ENVOLTORIOS: las dos funciones de siempre dejan de ser dos copias ---------------------------------------------
create or replace function public.unidad_parte_cobrada_interno(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select x.cobrado_suelo, x.cobrado_obra, x.obra_firmada from public._unidad_cobro_cascada(p_unidad) x;
$function$;

-- La que lee la pantalla: la MISMA puerta que tenía unidad_parte_cobrada_split (unidad sin contrato, contrato propio,
-- contrato visible o admin de la empresa) y dos columnas más: el precio de contrato de cada parte. Sin permiso, todo
-- NULL («no he podido mirar», no «0 cobrado»: LAW-186) y la cascada ni se calcula.
create or replace function public.unidad_cobro_reparto(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean, suelo_precio numeric, obra_precio numeric)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_ok boolean;
begin
  select (u0.contrato_id is null
          or public.es_suyo(c0.creado_por)
          or public.puede_ver_contrato(c0.id)
          or public.es_admin_de(public.empresa_de_unidad(p_unidad)))
    into v_ok
    from public.unidades u0
    left join public.contratos c0 on c0.id = u0.contrato_id
   where u0.id = p_unidad;
  if coalesce(v_ok, false) then
    return query select x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio
                   from public._unidad_cobro_cascada(p_unidad) x;
  else
    return query select null::numeric, null::numeric, null::boolean, null::numeric, null::numeric;
  end if;
end
$function$;

revoke all on function public.unidad_cobro_reparto(uuid) from public, anon;
grant execute on function public.unidad_cobro_reparto(uuid) to authenticated, lw_lector, service_role;

comment on function public.unidad_cobro_reparto(uuid) is
  'Reparto de lo cobrado de una unidad (primero parcela, luego obra) con su precio de contrato, tras la puerta de permiso. Llamador: la vista unidades_estado.';

create or replace function public.unidad_parte_cobrada_split(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select x.cobrado_suelo, x.cobrado_obra, x.obra_firmada from public.unidad_cobro_reparto(p_unidad) x;
$function$;

-- unidad_parte_cobrada_split ya no tiene llamador: la vista lee unidad_cobro_reparto, y unidad_parte_cobrada (la suma)
-- tampoco lo tiene (revisión previa de Backend, 14-oct: 0 llamadas en la base y en el repo). Se quedan como
-- envoltorios CERRADOS de la misma cascada; retirarlas del todo es un drop, que es del owner.
revoke execute on function public.unidad_parte_cobrada_split(uuid) from authenticated, lw_lector;

-- 3 · LA VISTA: mismas columnas y orden; al final, el precio de contrato de cada parte ------------------------------
create or replace view public.unidades_estado with (security_invoker = true) as
 SELECT u.id,
    u.codigo,
    u.proyecto,
    u.tipo,
    u.superficie_m2,
    COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) AS precio,
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
    cp.cobrado_suelo + cp.cobrado_obra AS facturado,
        CASE
            WHEN cp.cobrado_suelo IS NULL THEN NULL::numeric
            WHEN COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) > 0::numeric THEN round((cp.cobrado_suelo + cp.cobrado_obra) / COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) * 100::numeric, 1)
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
    c.id IS NOT NULL AND (EXISTS ( SELECT 1
           FROM public.contrato_tipo_etapa e
          WHERE e.tipo = c.tipo AND e.etapa = 'reserva'::text AND e.tipo <> 'reserva_parcela'::text)) AS contrato_es_carta,
    u.proyecto_id,
    cp.suelo_precio AS suelo_pactado,
    cp.obra_precio AS obra_pactada
   FROM public.unidades u
     LEFT JOIN public.contratos c ON c.id = u.contrato_id
     LEFT JOIN LATERAL public.unidad_cobro_reparto(u.id) cp(cobrado_suelo, cobrado_obra, obra_firmada, suelo_precio, obra_precio) ON true;

-- 4 · EL ESTADO DE LA PARCELA mide contra el mismo precio que la cascada --------------------------------------------
-- «vendida» = la parcela está cobrada entera. Con el tope en el precio de CONTRATO, comparar contra el de catálogo
-- bajaría a «bloqueada» una parcela pagada cuyo contrato es más barato que el catálogo (Tamarind W3.1-D6: Bloqueo
-- 15.000 firmado y cobrado, catálogo 18.750). Sin Bloqueo con precio se compara con lo que pasa quien llama, como
-- hasta ahora. «cobrada» = suelo + obra de contrato (cada parte con su respaldo de catálogo).
create or replace function public.unidad_cumple_estado(p_unidad uuid, p_estado text, p_precio numeric, p_precio_suelo numeric)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case p_estado
    when 'cobrada' then coalesce((
      select case when x.suelo_de_contrato
                  then x.cobrado_suelo + x.cobrado_obra >= x.suelo_precio + coalesce(x.obra_precio, 0)
                  else coalesce(p_precio, 0) > 0 and x.cobrado_suelo + x.cobrado_obra >= p_precio end
        from public._unidad_cobro_cascada(p_unidad) x), false)
    when 'vendida' then coalesce((
      select case when x.suelo_de_contrato
                  then x.cobrado_suelo >= x.suelo_precio
                  else coalesce(p_precio_suelo, 0) > 0 and x.cobrado_suelo >= p_precio_suelo end
        from public._unidad_cobro_cascada(p_unidad) x), false)
    else true
  end;
$function$;

-- 5 · COMISIONES, regla anterior al 1-nov: el motor lee la cascada y mide el % contra el precio de contrato ---------
-- comisiones_evaluar_contrato tiene ~600 líneas y la definición viva no lleva comentarios: se parchea la viva con tres
-- marcas de código de UNA línea (cada una aparece una vez; si no, se para). Ningún tramo usa hoy las bases
-- precio_suelo / precio_construccion (24 condiciones sobre precio_total, 12 por tramo firmado): cambia el DENOMINADOR
-- del «% cobrado del suelo», no el importe de ninguna comisión.
do $parche$
declare
  v_def text;
  m1 text := 'public.unidad_parte_cobrada_interno(u.id) cp';
  r1 text := 'public._unidad_cobro_cascada(u.id) cp';
  m2 text := 'coalesce(sum(u.precio_suelo), 0)';
  r2 text := 'coalesce(sum(coalesce(cp.suelo_precio, u.precio_suelo)), 0)';
  m3 text := 'coalesce(sum(u.precio_construccion), 0)';
  r3 text := 'coalesce(sum(coalesce(cp.obra_precio, u.precio_construccion)), 0)';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'comisiones_evaluar_contrato';
  if v_def is null then
    raise exception 'cobro_primero_parcela: no existe public.comisiones_evaluar_contrato';
  end if;
  if position(r1 in v_def) > 0 and position(r2 in v_def) > 0 and position(r3 in v_def) > 0 then
    return;   -- ya aplicado
  end if;
  if (length(v_def) - length(replace(v_def, m1, ''))) / length(m1) <> 1
     or (length(v_def) - length(replace(v_def, m2, ''))) / length(m2) <> 1
     or (length(v_def) - length(replace(v_def, m3, ''))) / length(m3) <> 1 then
    raise exception 'cobro_primero_parcela: comisiones_evaluar_contrato no tiene las tres marcas una vez cada una; revisar a mano';
  end if;
  execute replace(replace(replace(v_def, m1, r1), m2, r2), m3, r3);
end
$parche$;
