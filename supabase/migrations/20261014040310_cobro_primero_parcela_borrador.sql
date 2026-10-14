-- «Primero la parcela, luego la obra» — 3.ª parte (14-oct-2026).
--
-- 1 · EL PRECIO DEL CONTRATO MANDA AUNQUE EL BLOQUEO NO ESTÉ FIRMADO. Decisión del owner, que deja sin efecto el punto 2
--     de 20261014032925 («un borrador no decide»): «Aunque no estén firmados, coge el precio del contrato. El catálogo
--     es una guía con descuentos máximos pero puede variar para cerrar una venta, por lo que manda el contrato».
--     Lo que sigue frenando a un precio de borrador, que el agente aún puede cambiar:
--       · el ESTADO: una parcela «bloqueada» sin Bloqueo firmado no sube (avanza_unidad_por_cobro, sin cambios);
--       · la COMISIÓN: el «% cobrado del suelo» y la base se miden con el precio FIRMADO (punto 5).
--     Medido el 14-oct antes de aplicar: 92 ventas con Bloqueo sin firmar; con su precio, 2 pasan del 50 % de la
--     parcela (RP00071 sin equipo, RP00160 sin nada firmado). Y la comisión no se mueve (punto 5).
-- 2 · SOLO CUENTA EL BLOQUEO DE LA VENTA (Seguridad): un Bloqueo colgado como hijo de otro Bloqueo no mueve el precio.
-- 3 · La puerta de unidad_cobro_reparto no es más ancha que la RLS de `contratos` (Seguridad).
-- 4 · Borrar un contrato hijo revisa la parcela (Seguridad).
-- 5 · Comisiones: el «% cobrado del suelo» sigue contra el precio FIRMADO (Backend): la decisión 1 no adelanta ninguna.
-- La parte de OBRA no cambia: «cobrada» con obra sin firmar sigue midiendo contra el mayor entre su borrador y lo que
-- le queda al catálogo (decisión por defecto del CEO, 14-oct: el owner habló del Bloqueo; se revierte cambiando la
-- rama «cobrada» de unidad_cumple_estado).
--
-- Vuelta atrás: supabase/vivo/20261014_cobro_primero_parcela/vuelta.sql (deshace las tres migraciones).
-- Prueba: supabase/pruebas/cobro_primero_parcela.sql y supabase/pruebas/cobro_primero_parcela_contrato.sql

-- 1 · LA CASCADA (mismo cuerpo que 20261014032925 con los cambios de los puntos 1 y 2) ------------------------------
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
  obra_firmada as (
    select exists (select 1 from fam f where not f.es_raiz and f.es_obra_catalogo and f.firmado
         and (f.unidad_id = p_unidad or (f.unidad_id is null and exists (select 1 from hermanas_sin_asignar where id = p_unidad)))) as v
  ),
  -- PRECIO DE CONTRATO. Parcela = el Bloqueo de Parcela que ES la venta (la raíz; o un hijo solo si la raíz es una
  -- Carta, caso que hoy no existe). Un Bloqueo colgado como hijo de otro Bloqueo NO cuenta: lo puede crear el agente
  -- de la venta desde el formulario y movería el precio de la parcela (Seguridad, 14-oct-2026; hoy 0 filas así).
  -- Obra = los contratos de obra (adenda = obra: _comisiones_parte_obra, la misma definición que usa comisiones).
  -- Por parte y unidad: los FIRMADOS si hay alguno; si no, el borrador más reciente (un borrador viejo junto a su
  -- sustituto firmado no suma dos veces: SH-36 tiene CC00062 sin firmar y CC00102 firmada). Liberados y sin precio,
  -- fuera; otra moneda que la de la unidad, fuera (no se mezclan divisas: se cae al catálogo).
  con_precio as (
    select f.unidad_id, f.firmado, f.precio_total, f.created_at, (f.tipo is distinct from 'reserva_parcela') as obra
      from fam f
     where f.liberado_en is null and coalesce(f.precio_total, 0) > 0
       and f.moneda is not distinct from (select moneda from u)
       and ((f.tipo = 'reserva_parcela'
             and (f.es_raiz or (select r.tipo from fam r where r.es_raiz) like 'carta_reserva%'))
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

-- 2 · LA PUERTA DE LA PANTALLA, NO MÁS ANCHA QUE LA RLS DE `contratos` -------------------------------------------
-- Fuera `es_suyo(creado_por)`: solo mira el correo del autor, no si la cuenta sigue activa ni si sigue en la empresa
-- del proyecto, y ahora la función da también el PRECIO de contrato (Seguridad, 14-oct-2026: una cuenta desactivada
-- que no está bloqueada sacaba por RPC directa el precio de sus 2 ventas). `puede_ver_contrato` ya cubre al autor
-- activo dentro de su empresa y al admin.
create or replace function public.unidad_cobro_reparto(p_unidad uuid)
 returns table(cobrado_suelo numeric, cobrado_obra numeric, obra_firmada boolean, suelo_precio numeric, obra_precio numeric)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
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

-- 3 · BORRAR UN CONTRATO DE LA VENTA TAMBIÉN REVISA LA PARCELA ------------------------------------------------------
-- borrar_operacion borra contratos hijos (con su precio) y el disparador solo miraba altas y cambios (Seguridad,
-- 14-oct-2026). Al borrar un hijo se revisa la venta por su raíz: el hijo ya no existe. Borrar la raíz no hace nada:
-- avanza_unidad_por_cobro no la encuentra y sale.
create or replace function public.trg_revalua_unidad_por_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    if old.contrato_padre_id is not null then
      perform public.avanza_unidad_por_cobro(old.contrato_padre_id);
    end if;
    return old;
  elsif tg_op = 'INSERT' then
    if new.contrato_padre_id is not null then
      perform public.avanza_unidad_por_cobro(new.id);
    end if;
  elsif new.precio_total is distinct from old.precio_total
     or new.bloqueado is distinct from old.bloqueado
     or new.liberado_en is distinct from old.liberado_en
     or new.moneda is distinct from old.moneda
     or new.tipo is distinct from old.tipo then
    perform public.avanza_unidad_por_cobro(new.id);
  end if;
  return new;
end;
$function$;

revoke all on function public.trg_revalua_unidad_por_contrato() from public, anon, authenticated;

create or replace trigger trg_zz_revalua_unidad_por_contrato
  after insert or update of precio_total, bloqueado, liberado_en, moneda, tipo or delete on public.contratos
  for each row execute function public.trg_revalua_unidad_por_contrato();

-- 4 · COMISIONES: SIGUEN CON EL PRECIO FIRMADO ---------------------------------------------------------------------
-- La decisión del owner es sobre el reparto y el estado de la parcela; la comisión es dinero y su regla («sin contrato
-- firmado no hay comisión», 28-sep) no cambia (consulta de Backend, 14-oct-2026). Desde el punto 1 `suelo_de_contrato`
-- es cierto también con un Bloqueo sin firmar, así que el «% cobrado del suelo» se mide contra el precio del Bloqueo
-- solo si la raíz de la venta (que ES el Bloqueo) está firmada: v_contrato_firmado, que la función ya lee de la raíz
-- antes de este punto. Si no, contra el catálogo, como antes. Marca de UNA línea sobre el cuerpo vivo, con guarda de
-- md5 del cuerpo de partida (20261014012527 + los reemplazos de 20261014024234 y 20261014032925).
do $parche$
declare
  v_def text; v_src text;
  m1 text := 'coalesce(sum(case when cp.suelo_de_contrato then cp.suelo_precio else u.precio_suelo end), 0)';
  r1 text := 'coalesce(sum(case when cp.suelo_de_contrato and v_contrato_firmado then cp.suelo_precio else u.precio_suelo end), 0)';
begin
  select pg_get_functiondef(p.oid), p.prosrc into v_def, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'comisiones_evaluar_contrato';
  if v_def is null then
    raise exception 'cobro_primero_parcela_3: no existe public.comisiones_evaluar_contrato';
  end if;
  if position(r1 in v_def) > 0 then
    return;   -- ya aplicado
  end if;
  if md5(v_src) <> '2c53ec51477c97ac5e2f934eee4956ed' then
    raise exception 'cobro_primero_parcela_3: comisiones_evaluar_contrato no es el cuerpo de partida (md5 %); revisar a mano', md5(v_src);
  end if;
  if (length(v_def) - length(replace(v_def, m1, ''))) / length(m1) <> 1 then
    raise exception 'cobro_primero_parcela_3: comisiones_evaluar_contrato no tiene la marca una vez; revisar a mano';
  end if;
  execute replace(v_def, m1, r1);
end
$parche$;
