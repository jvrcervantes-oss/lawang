-- Prueba de precio-cadena-vigente (15-oct-2026, migración 20261015171500_precio_cadena_vigente.sql).
-- El precio de una venta solo suma la obra VIGENTE de cada parcela (la regla única de _venta_obras_vigentes); las facturas no
-- se tocan; contrato_saldo da facturado_de_mas y a_cuenta; la vista unidades_estado trae suelo_de_contrato y obra_de_contrato.
--   V1  R1 (la forma de RP00101): Bloqueo 25.000 + obra borrador 44.000 sustituida por otra firmada de 44.000, y la parcela
--       facturada dos veces (69.000 sobre el borrador + 25.000 sobre el Bloqueo). contrato_saldo, con el agente que ve la
--       raíz: precio 69.000 (antes 113.000), facturado 94.000 (la factura del borrador SIGUE contando), facturado_de_mas
--       25.000, por_facturar 0, cobrado 300 (un recibí aplicado a la factura del borrador sigue contando) y a_cuenta 400.
--   V2  el mismo agente NO ve la obra (la creó otro): contrato_saldo de la obra = 42501; el otro agente, que sí la ve, recibe
--       la misma cadena (precio 69.000).
--   V3  por la RPC que emite (factura_guarda, rol real): sobre R1 ya no se puede facturar ni 1 EUR (23514); SI de al lado:
--       sobre R2 entra justo hasta su precio vigente y el euro siguiente se rechaza.
--   V4  R2: dos parcelas y un grupo sin parcela. U2: firmada 20.000 + borrador 30.000 más nuevo → solo la firmada. U3: dos
--       borradores 15.000 y 16.000 → el más reciente. Sin unidad: borrador 5.000 cuenta; uno liberado de 7.000 no; uno en IDR
--       no. Precio = 10.000 + 20.000 + 16.000 + 5.000 = 51.000 (antes 103.000).
--       V4d-g ADENDA (Administración): FIJA el comportamiento de hoy, no lo aprueba. Una adenda firmada (R5), o una en
--       borrador más reciente (R4), desplaza a la construcción en borrador de su parcela y la obra desaparece del precio.
--   V5  la vista: suelo_de_contrato / obra_de_contrato (contrato, catálogo, sin contrato, sin permiso = null), las dos AL
--       FINAL, security_invoker, SELECT para authenticated y nada para anon. Las funciones nuevas: la regla y la cascada v2
--       no las ejecuta authenticated, anon, service_role ni lw_lector; unidad_cobro_reparto_v2 sí authenticated (la lee la
--       vista) y no anon ni service_role; la vieja unidad_cobro_reparto ya no la ejecuta authenticated (V5e).
--   V6  la cascada (v2 y su envoltorio) y unidad_cobro_reparto dan lo mismo que la v2 en todas las unidades de la prueba; el
--       precio de la cadena = Bloqueo raíz + obras vigentes de la regla; y contra la cascada cuadra salvo la obra sin parcela
--       de una venta cuyas parcelas tienen todas obra propia (la cascada no la reparte; hoy 0 en la viva).
--   V7  la PUERTA de unidad_cobro_reparto_v2 (Seguridad): un no agente (comprador del portal: sin ficha en usuarios) pide
--       una unidad sin contrato y recibe todo NULL, igual que una que no existe; un agente que ve el proyecto recibe
--       (0,0,f,null,null,f,f). Con canario: es_agente() falso para él y verdadero, con unidad_visible, para el agente.
--   V8  tiempo de `select * from unidades_estado` antes (la vista vieja reconstruida con la cascada y la puerta de antes en
--       pg_temp) y después, con las claims del admin; mismas filas y mismo cobrado. Con las filas de montaje el número NO
--       se compara con los 0,6 → 2,2 s de la viva: solo dice que no se dispara.
-- Rol REAL en cada llamada (`set local role authenticated` + claims; pg_temp.val de cliente_notas.sql).
-- !! CREA CONTRATOS, FACTURAS Y USUARIOS (gasta numeración): SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015171500_precio_cadena_vigente.sql --prueba precio_cadena_vigente.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada línea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-PV.
-- destructivo-ok: prueba en transacción que termina en raise (rollback); solo en rama
-- ============================================================ las funciones de ANTES, para medir la vista vieja (V8)
-- Cuerpo literal de la cascada y la puerta de antes (el de supabase/reversion_precio_cadena_vigente/REVERSION.sql), como
-- pg_temp: --aplica corre antes que --prueba, y sin ellas no hay «antes» que medir en la rama.
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

create temp table _tp (et text primary key, uid uuid, em text);
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
create or replace function pg_temp.val(p_uid uuid, p_email text, p_sql text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare t text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else
          json_build_object('sub', p_uid, 'role', p_rol, 'email', p_email)::text end, true);
  execute 'set local role ' || p_rol;
  begin execute p_sql into t;
  exception when others then t := 'ERR' || sqlstate || ':' || left(sqlerrm, 200); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(t, '(null)');
end $f$;
-- el p_factura de la pantalla para factura_guarda (una línea de p_importe, sin impuesto)
create or replace function pg_temp.doc(p_contrato uuid, p_importe numeric) returns jsonb language sql stable as $f$
  select jsonb_build_object('tipo', 'factura', 'sociedad', 'zz_pv', 'contrato_id', p_contrato, 'moneda', 'EUR',
           'total', p_importe::text, 'cliente_nombre', 'ZZ-PV',
           'contrato_numero', (select c.numero from public.contratos c where c.id = p_contrato),
           'proyecto_nombre', 'ZZ-PV Proyecto', 'fecha_emision', '2026-10-15',
           'datos', jsonb_build_object('lineas', jsonb_build_array(jsonb_build_object('descripcion', 'ZZ-PV', 'importe', p_importe::text)),
                                       'fields', '{}'::jsonb))
$f$;
create or replace function pg_temp.saldo(p_uid uuid, p_email text, p_contrato uuid) returns text language sql as $f$
  select pg_temp.val(p_uid, p_email, format('select public.contrato_saldo(%L::uuid)::text', p_contrato))
$f$;
create or replace function pg_temp.emite(p_uid uuid, p_email text, p_contrato uuid, p_importe numeric) returns text language sql as $f$
  select pg_temp.val(p_uid, p_email, format('select (select g.id from public.factura_guarda(null, %L::jsonb) g)::text', pg_temp.doc(p_contrato, p_importe)))
$f$;

insert into _tp values ('A',  gen_random_uuid(), 'zz-pv-agente@prueba.invalid'),
                       ('B',  gen_random_uuid(), 'zz-pv-agente-obra@prueba.invalid'),
                       ('AD', gen_random_uuid(), 'zz-pv-admin@prueba.invalid'),
                       ('N',  gen_random_uuid(), 'zz-pv-comprador@prueba.invalid');   -- no agente: sin ficha en usuarios

do $todo$
declare
  r text := ''; v text; s jsonb; n bigint;
  a _tp; b _tp; ad _tp; nn _tp;
  pL uuid; u1 uuid; u2 uuid; u3 uuid; u4 uuid; u5 uuid; u6 uuid; u7 uuid;
  r1 uuid; cb uuid; cf uuid; f1 uuid; f2 uuid; rc1 uuid; rc2 uuid; rc3 uuid;
  r2 uuid; o2a uuid; o2b uuid; o3a uuid; o3b uuid; o4 uuid; o5 uuid; o6 uuid; r3 uuid; r4 uuid; r5 uuid;
  t0 timestamptz; ms_antes numeric; ms_despues numeric; n_antes bigint; n_despues bigint; s_antes numeric; s_despues numeric;
  c_fin constant text := 'FIN DE PRUEBAS PRECIO CADENA VIGENTE (se deshace todo):%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS PRECIO CADENA VIGENTE:%', E'\nP0 esta prueba crea contratos, facturas y usuarios: solo corre en rama → FALLA';
  end if;
  select * into a from _tp where et = 'A'; select * into b from _tp where et = 'B'; select * into ad from _tp where et = 'AD';
  select * into nn from _tp where et = 'N';

  -- ============================================================ P. montaje (como postgres, SIN sesión)
  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.empresas (clave, nombre) values ('zz_pv', 'ZZ-PV Empresa');
    insert into public.sociedades (clave, label, razon, domicilio) values ('zz_pv', 'ZZ-PV', 'ZZ-PV PT', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    update public.empresas set sociedad_clave = 'zz_pv' where clave = 'zz_pv';
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-PV Proyecto', 'zz-pv-proyecto', 'zz_pv', true) returning id into pL;
    -- la rama nace de la ESTRUCTURA: los catálogos que siembran las migraciones vienen vacíos. Las mismas filas que la viva.
    insert into public.contrato_tipo_etapa (tipo, etapa, es_obra) values
      ('reserva_parcela', 'reserva', false), ('construccion', 'contrato', true), ('carta_reserva', 'reserva', false),
      ('adenda', 'ninguna', false)
      on conflict do nothing;
    insert into public.tipos_vivienda (clave, etiqueta) values ('parcela', 'Parcela') on conflict (clave) do nothing;
    insert into auth.users (id, instance_id, email, aud, role)
      select t.uid, '00000000-0000-0000-0000-000000000000', t.em, 'authenticated', 'authenticated' from _tp t;
    insert into public.usuarios (user_id, email, nombre, rol, ambito, empresas, proyectos, proyectos_supervisados, herramientas, tipos_contrato, activo) values
      (a.uid,  a.em,  'ZZ-PV Agente',      'agente', 'global', array['zz_pv'], array[pL],    '{}'::uuid[], '{contratos,facturas,unidades}'::text[], '{reserva_parcela,construccion}'::text[], true),
      (b.uid,  b.em,  'ZZ-PV Agente obra', 'agente', 'global', array['zz_pv'], array[pL],    '{}'::uuid[], '{contratos,facturas,unidades}'::text[], '{reserva_parcela,construccion}'::text[], true),
      (ad.uid, ad.em, 'ZZ-PV Admin',       'admin',  'global', '{}'::text[],   '{}'::uuid[], '{}'::uuid[], '{contratos,facturas,unidades}'::text[], '{}'::text[], true);
    -- parcelas, contratos y documentos SIN disparadores (como invitacion_portal.sql): en la rama no hay inventario, series
    -- ni cobros con los que cuadren, y aquí solo importan las columnas que leen las funciones. Lo que rellenarían va a mano.
    execute 'set local session_replication_role = replica';
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-1', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 30000, 50000, 80000) returning id into u1;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-2', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 6000, 25000, 31000) returning id into u2;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-3', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 4000, 18000, 22000) returning id into u3;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-4', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 9000, 40000, 49000) returning id into u4;   -- sin contrato
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-5', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 12000, 60000, 72000) returning id into u5;  -- Bloqueo sin obra

    -- R1 = la forma de RP00101 (Bloqueo de A; las dos obras las creó B: A ve la raíz y no la obra)
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R1', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 25000, true, '{"hitos":[]}', a.em, '2026-08-26 10:00+00') returning id into r1;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at)
      values ('ZZ-PV-CB', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 44000, false, r1, u1, '{"hitos":[]}', b.em, '2026-08-26 11:00+00') returning id into cb;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at)
      values ('ZZ-PV-CF', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 44000, true, r1, u1, '{"hitos":[]}', b.em, '2026-09-16 10:00+00') returning id into cf;
    update public.unidades set contrato_id = r1 where id = u1;
    -- la parcela facturada dos veces: 69.000 sobre el borrador sustituido y 25.000 sobre el Bloqueo
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PV-F1', 'zz_pv', cb, 69000, 'EUR', b.em, 'ZZ-PV', '{"fields": {}}'::jsonb) returning id into f1;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos)
      values ('factura', 'ZZ-PV-F2', 'zz_pv', r1, 25000, 'EUR', a.em, 'ZZ-PV', '{"fields": {}}'::jsonb) returning id into f2;
    -- recibís (históricos, sin justificante: los CHECK solo lo admiten antes del 11-ago-2026). RC1 400 sin aplicar (a
    -- cuenta); RC2 300 aplicado a F1, la factura del borrador (sigue siendo cobrado); RC3 999 anulado (no cuenta).
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-PV-RC1', 'zz_pv', r1, 400, 'EUR', a.em, 'ZZ-PV', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rc1;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at)
      values ('recibi', 'ZZ-PV-RC2', 'zz_pv', cb, 300, 'EUR', b.em, 'ZZ-PV', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00') returning id into rc2;
    insert into public.facturas (tipo, numero, sociedad, contrato_id, total, moneda, creado_por, cliente_nombre, datos, historico_sin_justificante, created_at, anulada)
      values ('recibi', 'ZZ-PV-RC3', 'zz_pv', r1, 999, 'EUR', a.em, 'ZZ-PV', '{"fields": {}}'::jsonb, true, '2026-07-01 10:00+00', true) returning id into rc3;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado) values (rc2, f1, 300);

    -- R2: dos parcelas y obras sin parcela (todo de A)
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R2', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 10000, true, '{"hitos":[]}', a.em, '2026-09-01 10:00+00') returning id into r2;
    update public.unidades set contrato_id = r2 where id in (u2, u3);
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at, liberado_en) values
      ('ZZ-PV-O2A', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 20000, true,  r2, u2,   '{"hitos":[]}', a.em, '2026-09-02 10:00+00', null),
      ('ZZ-PV-O2B', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 30000, false, r2, u2,   '{"hitos":[]}', a.em, '2026-09-05 10:00+00', null),
      ('ZZ-PV-O3A', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 15000, false, r2, u3,   '{"hitos":[]}', a.em, '2026-09-02 10:00+00', null),
      ('ZZ-PV-O3B', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 16000, false, r2, u3,   '{"hitos":[]}', a.em, '2026-09-06 10:00+00', null),
      ('ZZ-PV-O4',  'construccion', pL, 'ZZ-PV Proyecto', 'EUR',  5000, false, r2, null, '{"hitos":[]}', a.em, '2026-09-03 10:00+00', null),
      ('ZZ-PV-O5',  'construccion', pL, 'ZZ-PV Proyecto', 'EUR',  7000, false, r2, null, '{"hitos":[]}', a.em, '2026-09-07 10:00+00', '2026-09-08 10:00+00'),
      ('ZZ-PV-O6',  'construccion', pL, 'ZZ-PV Proyecto', 'IDR',     9, false, r2, null, '{"hitos":[]}', a.em, '2026-09-08 10:00+00', null);
    select id into o2a from public.contratos where numero = 'ZZ-PV-O2A'; select id into o2b from public.contratos where numero = 'ZZ-PV-O2B';
    select id into o3a from public.contratos where numero = 'ZZ-PV-O3A'; select id into o3b from public.contratos where numero = 'ZZ-PV-O3B';
    select id into o4 from public.contratos where numero = 'ZZ-PV-O4';   select id into o5 from public.contratos where numero = 'ZZ-PV-O5';
    -- R3: Bloqueo sin obra (la obra de U5 sale del catálogo)
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R3', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 11000, false, '{"hitos":[]}', a.em, '2026-09-10 10:00+00') returning id into r3;
    update public.unidades set contrato_id = r3 where id = u5;
    -- R4 y R5: la ADENDA (V4d-g), cada una en su venta y su parcela para no mover los números de R1-R3.
    --   R4 (U6): construcción en borrador 40.000 (10-sep) y adenda en borrador 3.000 MÁS RECIENTE (12-sep).
    --   R5 (U7): adenda FIRMADA 2.000 (10-sep) y construcción en borrador 50.000 más reciente (12-sep).
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-6', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 8000, 40000, 48000) returning id into u6;
    insert into public.unidades (codigo, proyecto, proyecto_id, tipo, moneda, precio_suelo, precio_construccion, precio) values
      ('ZZ-PV-7', 'ZZ-PV Proyecto', pL, 'parcela', 'EUR', 9000, 50000, 59000) returning id into u7;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R4', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 8000, true, '{"hitos":[]}', a.em, '2026-09-09 10:00+00') returning id into r4;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, datos, creado_por, created_at)
      values ('ZZ-PV-R5', 'reserva_parcela', pL, 'ZZ-PV Proyecto', 'EUR', 9000, true, '{"hitos":[]}', a.em, '2026-09-09 10:00+00') returning id into r5;
    update public.unidades set contrato_id = r4 where id = u6;
    update public.unidades set contrato_id = r5 where id = u7;
    insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, bloqueado, contrato_padre_id, unidad_id, datos, creado_por, created_at) values
      ('ZZ-PV-C4', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 40000, false, r4, u6, '{"hitos":[]}', a.em, '2026-09-10 10:00+00'),
      ('ZZ-PV-A4', 'adenda',       pL, 'ZZ-PV Proyecto', 'EUR',  3000, false, r4, u6, '{"hitos":[]}', a.em, '2026-09-12 10:00+00'),
      ('ZZ-PV-A5', 'adenda',       pL, 'ZZ-PV Proyecto', 'EUR',  2000, true,  r5, u7, '{"hitos":[]}', a.em, '2026-09-10 10:00+00'),
      ('ZZ-PV-C5', 'construccion', pL, 'ZZ-PV Proyecto', 'EUR', 50000, false, r5, u7, '{"hitos":[]}', a.em, '2026-09-12 10:00+00');
    execute 'set local session_replication_role = origin';
    r := r || pg_temp.l(true, 'P montaje: 4 usuarios (A ve las raíces, B creó las obras de R1, admin, N no agente), R1 (forma de RP00101), R2 (2 parcelas + sin parcela), R3, R4 y R5 (adenda)');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ C0 canario: el rol y las claims surten efecto
  v := pg_temp.val(a.uid, a.em, 'select current_user || ''|'' || coalesce(auth.uid()::text, ''-'')');
  r := r || pg_temp.l(v = 'authenticated|' || a.uid::text, 'C0 canario: authenticated con el uid de A (' || left(v, 60) || ')');

  -- ============================================================ V1 contrato_saldo de R1 con el agente que ve la raíz
  v := pg_temp.saldo(a.uid, a.em, r1);
  if v ~ '^ERR' then
    r := r || pg_temp.l(false, 'V1 contrato_saldo(R1) como A: ' || left(v, 160));
  else
    s := v::jsonb;
    r := r || pg_temp.l((s->>'precio')::numeric = 69000, 'V1a precio = Bloqueo 25.000 + obra VIGENTE 44.000 = 69.000; el borrador sustituido no suma (' || coalesce(s->>'precio', 'null') || ')');
    r := r || pg_temp.l((s->>'facturado')::numeric = 94000, 'V1b facturado 94.000: la factura del borrador sustituido SIGUE contando (' || coalesce(s->>'facturado', 'null') || ')');
    r := r || pg_temp.l((s->>'facturado_de_mas')::numeric = 25000 and (s->>'por_facturar')::numeric = 0,
                        'V1c facturado_de_mas 25.000 y por_facturar 0 (' || coalesce(s->>'facturado_de_mas', 'null') || ' / ' || coalesce(s->>'por_facturar', 'null') || ')');
    r := r || pg_temp.l((s->>'cobrado')::numeric = 300 and (s->>'por_cobrar')::numeric = 93700,
                        'V1d cobrado 300 (recibí aplicado a la factura del borrador) y por_cobrar 93.700 (' || coalesce(s->>'cobrado', 'null') || ' / ' || coalesce(s->>'por_cobrar', 'null') || ')');
    r := r || pg_temp.l((s->>'a_cuenta')::numeric = 400, 'V1e a_cuenta 400: RC1 sin aplicar; RC2 aplicado y RC3 anulado no (' || coalesce(s->>'a_cuenta', 'null') || ')');
    r := r || pg_temp.l(jsonb_array_length(s->'facturas') = 1 and s#>>'{facturas,0,numero}' = 'ZZ-PV-F2',
                        'V1f la lista de facturas es la del contrato pedido (solo F2)');
  end if;
  -- a_cuenta con la fórmula de _contrato_cobrado_interno: lo cobrado por la venta menos lo aplicado a sus facturas
  select coalesce(sum(public._contrato_cobrado_interno(c.id, 'EUR')), 0)
         - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                       join public.facturas rr on rr.id = ra.recibi_id join public.facturas ff on ff.id = ra.factura_id
                      where ff.contrato_id in (r1, cb, cf) and not coalesce(rr.anulada, false) and not coalesce(ff.anulada, false)), 0)
    into n from public.contratos c where c.id in (r1, cb, cf);
  r := r || pg_temp.l(n = 400, 'V1g a_cuenta = Σ _contrato_cobrado_interno de la venta − lo aplicado a sus facturas (' || n || ')');
  v := pg_temp.saldo(ad.uid, ad.em, r3);
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb->>'facturado_de_mas')::numeric = 0 and (v::jsonb->>'a_cuenta')::numeric = 0,
                      'V1h una venta sin exceso ni recibís: facturado_de_mas 0 y a_cuenta 0 (' || left(v, 120) || ')');

  -- ============================================================ V2 quien no ve la obra no ve su saldo; quien la ve, la misma cadena
  v := pg_temp.saldo(a.uid, a.em, cb);
  r := r || pg_temp.l(v like 'ERR42501:%', 'V2a A (ve la raíz, no la obra) pide el saldo de la obra: 42501 (' || left(v, 70) || ')');
  v := pg_temp.saldo(b.uid, b.em, cb);
  r := r || pg_temp.l(v !~ '^ERR' and (v::jsonb->>'precio')::numeric = 69000 and (v::jsonb->>'facturado')::numeric = 94000,
                      'V2b SI: B (creó la obra) recibe la misma cadena: precio 69.000, facturado 94.000 (' || left(v, 100) || ')');
  v := pg_temp.saldo(null, null, r1);
  r := r || pg_temp.l(v like 'ERR42501:%', 'V2c sin sesión: 42501 (' || left(v, 60) || ')');

  -- ============================================================ V3 por la RPC que emite: R1 ya no deja facturar; R2 hasta su precio
  select count(*) into n from public.facturas where contrato_id in (r1, cb, cf);
  v := pg_temp.emite(a.uid, a.em, r1, 1);
  r := r || pg_temp.l(v like 'ERR23514:%Quedan 0%' and (select count(*) from public.facturas where contrato_id in (r1, cb, cf)) = n,
                      'V3a factura_guarda de 1 EUR sobre R1 (94.000 facturados, precio 69.000): 23514 y nada nuevo (' || left(v, 110) || ')');
  v := pg_temp.emite(a.uid, a.em, r2, 51000);
  r := r || pg_temp.l(v !~ '^ERR', 'V3b SI: sobre R2 entra justo su precio vigente, 51.000 (' || left(v, 90) || ')');
  v := pg_temp.emite(a.uid, a.em, r2, 1);
  r := r || pg_temp.l(v like 'ERR23514:%Quedan 0%', 'V3c y el euro siguiente se rechaza: con la regla vieja (103.000) entraba (' || left(v, 110) || ')');

  -- ============================================================ V4 la regla por parcela, vista desde la propia función y la cadena
  select string_agg(c.numero, ',' order by c.numero) into v
    from public._venta_obras_vigentes(r2, 'EUR') o join public.contratos c on c.id = o.contrato_id;
  r := r || pg_temp.l(v = 'ZZ-PV-O2A,ZZ-PV-O3B,ZZ-PV-O4', 'V4a vigentes de R2: la firmada de U2, el borrador más reciente de U3 y el sin parcela no liberado (' || coalesce(v, 'null') || ')');
  select string_agg(c.numero, ',' order by c.numero) into v
    from public._venta_obras_vigentes(r1, 'EUR') o join public.contratos c on c.id = o.contrato_id;
  r := r || pg_temp.l(v = 'ZZ-PV-CF', 'V4b vigentes de R1: solo la firmada (' || coalesce(v, 'null') || ')');
  select s2.precio into n from public._cadena_saldo(o3a, null) s2;
  r := r || pg_temp.l(n = 51000, 'V4c el precio de la cadena pedido desde un hijo (el borrador sustituido O3A) es el de la venta: 51.000 (' || coalesce(n::text, 'null') || ')');
  -- ADENDA: pendiente de decidir si una adenda suma o sustituye; hoy hay 0 adendas en Lawang (15-oct, medido:
  -- count(*) de contratos con tipo like 'adenda%' = 0). Ningún chequeo avisa todavía con la primera: tools/salud_lawang.py
  -- no tiene ese invariante (15-oct; queda con el CEO, fuera de esta copia). Estas cuatro líneas FIJAN lo de hoy, no lo
  -- aprueban: la adenda es obra para la regla (_comisiones_parte_obra: tipo like 'adenda%') y le gana la parcela a la
  -- construcción en borrador, pero la cadena no suma una adenda hija (ca.cuenta), así que la obra desaparece del precio.
  select string_agg(c.numero, ',' order by c.numero) into v
    from public._venta_obras_vigentes(r4, 'EUR') o join public.contratos c on c.id = o.contrato_id;
  r := r || pg_temp.l(v = 'ZZ-PV-A4', 'V4d adenda en borrador MÁS RECIENTE que la construcción en borrador: la vigente de U6 es solo la adenda (' || coalesce(v, 'null') || ')');
  select s2.precio into n from public._cadena_saldo(r4, null) s2;
  r := r || pg_temp.l(n = 8000, 'V4e y el precio de R4 es solo el Bloqueo, 8.000: la construcción (40.000) no es vigente y la adenda no suma (' || coalesce(n::text, 'null') || ')');
  select string_agg(c.numero, ',' order by c.numero) into v
    from public._venta_obras_vigentes(r5, 'EUR') o join public.contratos c on c.id = o.contrato_id;
  r := r || pg_temp.l(v = 'ZZ-PV-A5', 'V4f adenda FIRMADA y construcción en borrador más reciente: la vigente de U7 es solo la adenda (' || coalesce(v, 'null') || ')');
  select s2.precio into n from public._cadena_saldo(r5, null) s2;
  r := r || pg_temp.l(n = 9000, 'V4g y el precio de R5 es solo el Bloqueo, 9.000: la construcción (50.000) desaparece del precio (' || coalesce(n::text, 'null') || ')');

  -- ============================================================ V5 la vista y los permisos
  select count(*) into n from (
    select k.column_name, k.ordinal_position, max(k.ordinal_position) over () as ultima
      from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'unidades_estado') x
   where (x.column_name = 'suelo_de_contrato' and x.ordinal_position = x.ultima - 1)
      or (x.column_name = 'obra_de_contrato' and x.ordinal_position = x.ultima);
  r := r || pg_temp.l(n = 2, 'V5a suelo_de_contrato y obra_de_contrato son las DOS ÚLTIMAS columnas de la vista');
  r := r || pg_temp.l((select c.reloptions::text from pg_class c where c.oid = 'public.unidades_estado'::regclass) like '%security_invoker=true%',
                      'V5b la vista sigue siendo security_invoker');
  r := r || pg_temp.l(has_table_privilege('authenticated', 'public.unidades_estado', 'select')
                      and not has_table_privilege('anon', 'public.unidades_estado', 'select')
                      and not has_table_privilege('authenticated', 'public.unidades_estado', 'insert')
                      and not has_table_privilege('authenticated', 'public.unidades_estado', 'truncate'),
                      'V5c vista: SELECT para authenticated, nada más; nada para anon');
  -- roles sacados de pg_roles: en la rama lw_lector no existe y has_function_privilege con un rol que no existe aborta
  select count(*) into n from (values ('public._venta_obras_vigentes(uuid,text)'::regprocedure), ('public._unidad_cobro_cascada_v2(uuid)'::regprocedure)) f(x)
   cross join pg_roles q
   where q.rolname in ('authenticated', 'anon', 'service_role', 'lw_lector')
     and has_function_privilege(q.oid, f.x, 'execute');
  r := r || pg_temp.l(n = 0, 'V5d la regla y la cascada v2: ni authenticated, ni anon, ni service_role, ni lw_lector si existe (' || n || ' permisos)');
  select count(*) into n from pg_roles q
   where q.rolname in ('authenticated', 'anon', 'service_role', 'lw_lector')
     and has_function_privilege(q.oid, 'public.unidad_cobro_reparto(uuid)'::regprocedure, 'execute');
  r := r || pg_temp.l(n = 0 and has_function_privilege('authenticated', 'public.unidad_cobro_reparto_v2(uuid)', 'execute')
                      and not has_function_privilege('anon', 'public.unidad_cobro_reparto_v2(uuid)', 'execute')
                      and not has_function_privilege('service_role', 'public.unidad_cobro_reparto_v2(uuid)', 'execute'),
                      'V5e la vieja unidad_cobro_reparto no la ejecuta nadie (' || n || ' roles); la v2 sí authenticated (la vista) y no anon ni service_role');
  v := pg_temp.val(a.uid, a.em, 'select count(*)::text from public.unidad_cobro_reparto(gen_random_uuid())');
  r := r || pg_temp.l(v like 'ERR42501:%', 'V5e2 A llama a la vieja directamente: 42501 (' || left(v, 70) || ')');
  r := r || pg_temp.l((select p.prosecdef from pg_proc p where p.oid = 'public._venta_obras_vigentes(uuid,text)'::regprocedure) = false
                      and (select 'search_path=""' = any(p.proconfig) from pg_proc p where p.oid = 'public._venta_obras_vigentes(uuid,text)'::regprocedure),
                      'V5f la regla es INVOKER con search_path vacío');
  v := pg_temp.val(ad.uid, ad.em, format(
         'select string_agg(e.codigo || ''='' || coalesce(e.suelo_de_contrato::text, ''null'') || ''/'' || coalesce(e.obra_de_contrato::text, ''null'')'
         || ' || ''/'' || coalesce(e.obra_pactada::text, ''null''), '','' order by e.codigo) from public.unidades_estado e where e.id in (%L, %L, %L, %L)', u2, u3, u4, u5));
  r := r || pg_temp.l(v = 'ZZ-PV-2=true/true/20000.00,ZZ-PV-3=true/true/16000.00,ZZ-PV-4=false/false/null,ZZ-PV-5=true/false/60000.00',
                      'V5g la vista como admin: U2 y U3 suelo y obra de contrato (20.000 y 16.000, el sin parcela no va a parcelas con obra propia), U4 sin contrato false/false, U5 obra de catálogo (' || left(v, 200) || ')');
  v := pg_temp.val(b.uid, b.em, format('select coalesce(string_agg(coalesce(e.suelo_de_contrato::text, ''null'') || ''/'' || coalesce(e.obra_de_contrato::text, ''null''), '',''), ''sin fila'') from public.unidades_estado e where e.id = %L', u1));
  r := r || pg_temp.l(v in ('null/null', 'sin fila'), 'V5h B no ve el contrato de U1: las marcas salen null (o no ve la fila), nunca false (' || left(v, 60) || ')');

  -- ============================================================ V6 la cascada, sus envoltorios y el invariante de la venta
  select count(*) into n
    from public.unidades u
    cross join lateral public._unidad_cobro_cascada(u.id) x
    cross join lateral public._unidad_cobro_cascada_v2(u.id) y
   where u.id in (u1, u2, u3, u4, u5)
     and (x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio, x.suelo_de_contrato)
         is distinct from (y.cobrado_suelo, y.cobrado_obra, y.obra_firmada, y.suelo_precio, y.obra_precio, y.suelo_de_contrato);
  r := r || pg_temp.l(n = 0, 'V6a el envoltorio _unidad_cobro_cascada = las 6 primeras columnas de la v2 (' || n || ' distintas)');
  -- la vieja ya no la ejecuta authenticated (V5e): se compara como postgres con las claims del admin, que es como la
  -- llamaría una función DEFINER del dueño (la puerta mira las claims, no el rol)
  perform set_config('request.jwt.claims', json_build_object('sub', ad.uid, 'role', 'authenticated', 'email', ad.em)::text, true);
  select count(*) into n from public.unidades u cross join lateral public.unidad_cobro_reparto(u.id) x cross join lateral public.unidad_cobro_reparto_v2(u.id) y
   where u.id in (u1, u2, u3, u4, u5) and (x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio)
         is distinct from (y.cobrado_suelo, y.cobrado_obra, y.obra_firmada, y.suelo_precio, y.obra_precio);
  perform set_config('request.jwt.claims', '', true);
  r := r || pg_temp.l(n = 0, 'V6b con las claims del admin, el envoltorio unidad_cobro_reparto = la v2 (' || n || ' distintas)');
  -- el criterio del encargo: precio de la cadena = Bloqueo raíz + obras vigentes de la regla, sin catálogo
  select count(*) into n
    from public.contratos rz
    cross join lateral public._cadena_saldo(rz.id, null) c
   where rz.id in (r1, r2, r3)
     and c.precio is distinct from rz.precio_total + coalesce((select sum(o.precio) from public._venta_obras_vigentes(rz.id, rz.moneda) o), 0);
  r := r || pg_temp.l(n = 0, 'V6c precio de la cadena = Bloqueo raíz + obras vigentes de la regla en R1, R2 y R3 (' || n || ' que no cuadran)');
  -- y contra la cascada (lo que mira el invariante de las 141 ventas): cuadra salvo la obra SIN parcela de una venta cuyas
  -- parcelas tienen todas obra propia, que la cascada no reparte (regla de siempre, peso_sin_asignar = 0). Hoy en la viva
  -- no hay ninguna (medido el 15-oct: las 141 cuadran); aquí R2 la tiene a propósito y la diferencia es exactamente O4.
  select string_agg(x.numero || '=' || (coalesce(c.precio, 0) - coalesce(x.s, 0) - coalesce(x.o, 0))::text, ',' order by x.numero) into v
    from (select k.numero, k.id, sum(y.suelo_precio) filter (where y.suelo_de_contrato) as s,
                 sum(y.obra_precio) filter (where y.obra_de_contrato) as o
            from public.unidades u join public.contratos k on k.id = u.contrato_id
            cross join lateral public._unidad_cobro_cascada_v2(u.id) y
           where u.id in (u1, u2, u3, u5) group by k.numero, k.id) x
   cross join lateral public._cadena_saldo(x.id, null) c;
  r := r || pg_temp.l(v = 'ZZ-PV-R1=0.00,ZZ-PV-R2=5000.00,ZZ-PV-R3=0.00',
                      'V6d cadena − (suelo + obra de contrato de la cascada): 0 en R1 y R3; en R2, los 5.000 de O4 (sin parcela, todas con obra propia) (' || coalesce(v, 'null') || ')');

  -- ============================================================ V7 la puerta de unidad_cobro_reparto_v2 (Seguridad)
  -- canario: sin él, el NULL de N podría venir de otro sitio (un rol sin permiso, una función que falla)
  v := pg_temp.val(nn.uid, nn.em, format('select public.es_agente()::text || ''/'' || public.unidad_visible(%L::uuid)::text', pL));
  r := r || pg_temp.l(v = 'false/false', 'V7a canario: N (sin ficha en usuarios, como un comprador del portal) no es agente ni ve el proyecto (' || left(v, 40) || ')');
  v := pg_temp.val(a.uid, a.em, format('select public.es_agente()::text || ''/'' || public.unidad_visible(%L::uuid)::text', pL));
  r := r || pg_temp.l(v = 'true/true', 'V7b canario: A es agente y ve el proyecto (' || left(v, 40) || ')');
  v := pg_temp.val(nn.uid, nn.em, format(
         'select concat_ws(''|'', coalesce(x.cobrado_suelo::text, ''null''), coalesce(x.cobrado_obra::text, ''null''), coalesce(x.obra_firmada::text, ''null''),'
         || ' coalesce(x.suelo_precio::text, ''null''), coalesce(x.obra_precio::text, ''null''), coalesce(x.suelo_de_contrato::text, ''null''),'
         || ' coalesce(x.obra_de_contrato::text, ''null'')) from public.unidad_cobro_reparto_v2(%L::uuid) x', u4));
  r := r || pg_temp.l(v = 'null|null|null|null|null|null|null', 'V7c N pide el reparto de U4 (sin contrato): todo NULL, ya no (0,0,f,…) (' || left(v, 60) || ')');
  v := pg_temp.val(nn.uid, nn.em,
         'select concat_ws(''|'', coalesce(x.cobrado_suelo::text, ''null''), coalesce(x.obra_de_contrato::text, ''null'')) from public.unidad_cobro_reparto_v2(gen_random_uuid()) x');
  r := r || pg_temp.l(v = 'null|null', 'V7d y una unidad que no existe le da lo mismo: no distingue «no existe» de «existe sin vender» (' || left(v, 40) || ')');
  v := pg_temp.val(a.uid, a.em, format(
         'select concat_ws(''|'', coalesce(x.cobrado_suelo::text, ''null''), coalesce(x.cobrado_obra::text, ''null''), coalesce(x.obra_firmada::text, ''null''),'
         || ' coalesce(x.suelo_precio::text, ''null''), coalesce(x.obra_precio::text, ''null''), coalesce(x.suelo_de_contrato::text, ''null''),'
         || ' coalesce(x.obra_de_contrato::text, ''null'')) from public.unidad_cobro_reparto_v2(%L::uuid) x', u4));
  r := r || pg_temp.l(v = '0|0|false|null|null|false|false', 'V7e SI: A (agente que ve el proyecto) pide U4: (0,0,f,null,null,f,f) (' || left(v, 60) || ')');

  -- ============================================================ V8 tiempo de la vista, antes y después
  -- Como postgres con las claims del admin (la puerta mira las claims; postgres es dueño de unidades y no pasa por la RLS,
  -- igual en los dos lados). «Antes» = la vista vieja, con la cascada y la puerta de antes en pg_temp. Cada consulta corre
  -- dos veces y se mide la segunda (el plan de plpgsql ya en caché). Con las filas de montaje el tiempo NO se compara con
  -- los 0,6 → 2,2 s de la viva; lo que sí se exige: mismas filas y mismo cobrado.
  perform set_config('request.jwt.claims', json_build_object('sub', ad.uid, 'role', 'authenticated', 'email', ad.em)::text, true);
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
                      format('V8 select * from unidades_estado: antes %s ms, después %s ms (%s filas; cobrado+pactado %s / %s)',
                             ms_antes, ms_despues, n_despues, s_antes, s_despues));

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
