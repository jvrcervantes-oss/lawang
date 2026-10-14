-- «Primero la parcela, luego la obra» — 2.ª parte: lo que encontró el revisor de código sobre 20261014024234.
--
-- 1 · EL ESTADO SE REVISA TAMBIÉN CUANDO CAMBIA EL CONTRATO (ALTA del revisor). Desde la migración anterior «vendida» y
--     «cobrada» se miden contra el precio de CONTRATO, y nada revisaba la parcela al firmar un Bloqueo o cambiar su
--     precio: solo al entrar un cobro (o al cambiar el precio de catálogo, que ya no manda). Trigger nuevo en
--     `contratos`. Era una regresión de la migración anterior, no una mejora.
-- 2 · UN BORRADOR NO DECIDE. El precio de un Bloqueo sin firmar lo escribe el agente en el formulario. Sigue poniendo
--     el tope del reparto que se ENSEÑA, pero estado y comisiones solo se fían del precio de un Bloqueo FIRMADO
--     (`suelo_de_contrato`); sin él, comparan con el catálogo, como antes del 14-oct.
-- 3 · Una parcela con precio 0 ya no puede darse por «vendida» con 0 cobrado.
-- 4 · `unidad_cobro_reparto` deja de devolver precio a quien pregunta por una unidad sin contrato (antes la función a
--     la que sustituye devolvía 0/0/false; el precio de catálogo lo da la vista, que sí pasa por la RLS).
-- 5 · Pesos sin NULL y ventas con cobros en dos monedas fuera de la cascada.
--
-- Vuelta atrás: supabase/vivo/20261014_cobro_primero_parcela/vuelta.sql (deshace las dos migraciones).
-- Prueba: supabase/pruebas/cobro_primero_parcela.sql y supabase/pruebas/cobro_primero_parcela_contrato.sql

-- 1 · LA CASCADA (mismo cuerpo que 20261014024234 con los cambios de los puntos 2 y 5) ------------------------------
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
           -- «de contrato» = el precio de la parcela sale de un Bloqueo FIRMADO. El de un borrador pone el tope del
           -- reparto (es lo mejor que se sabe y es lo que se enseña), pero NO decide estados ni comisiones: lo escribe
           -- el agente desde el formulario y aún puede cambiarlo (revisor de código, 14-oct-2026; «no te creas nada
           -- del front-end»). Quien decide algo mira esta columna.
           coalesce(v.suelo_contrato, 0) > 0 and not (select v from mezcla)
             and not exists (select 1 from vigentes g where not g.obra and not g.firmado) as de_contrato
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

-- 2 · LA PUERTA DE LA PANTALLA: una unidad sin contrato no tiene nada cobrado ni precio pactado ---------------------
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
          or public.es_suyo(c0.creado_por)
          or public.puede_ver_contrato(c0.id)
          or public.es_admin_de(public.empresa_de_unidad(p_unidad)))
    into v_existe, v_contrato, v_ok
    from public.unidades u0
    left join public.contratos c0 on c0.id = u0.contrato_id
   where u0.id = p_unidad;
  if not coalesce(v_existe, false) or not coalesce(v_ok, false) then
    -- «no he podido mirar», no «0 cobrado» (LAW-186)
    return query select null::numeric, null::numeric, null::boolean, null::numeric, null::numeric;
  elsif v_contrato is null then
    -- Sin contrato: 0 cobrado y NINGÚN precio. Esta función es definer y llamable por RPC: devolver aquí el precio de
    -- catálogo se lo daba a cualquier usuario con sesión que supiera el id de la unidad, saltándose la RLS de
    -- `unidades`. La pantalla cae sola al precio de catálogo que trae la vista (que sí pasa por la RLS).
    return query select 0::numeric, 0::numeric, false, null::numeric, null::numeric;
  else
    return query select x.cobrado_suelo, x.cobrado_obra, x.obra_firmada, x.suelo_precio, x.obra_precio
                   from public._unidad_cobro_cascada(p_unidad) x;
  end if;
end
$function$;

-- 3 · EL ESTADO: solo se fía del precio de un Bloqueo firmado, y nunca de un precio 0 --------------------------------
-- «vendida»: con Bloqueo firmado, suelo cobrado >= su precio (> 0). Sin él, lo cobrado en la venta tiene que cubrir el
-- MAYOR entre el precio de catálogo y el del borrador: bajar el precio de un borrador no acerca la parcela a
-- «vendida», y subirlo la aleja. Se compara el total de la parcela (suelo + obra) y no su suelo, porque el suelo ya
-- viene topado en el precio del borrador (Tamarind W3-B7: borrador 23.275, catálogo 30.625, 67.775 cobrados).
-- «cobrada»: suelo + obra. La obra cuenta a su precio de contrato solo si está firmada; si no, al mayor entre lo que
-- diga su borrador y lo que le queda al catálogo (precio - suelo).
create or replace function public.unidad_cumple_estado(p_unidad uuid, p_estado text, p_precio numeric, p_precio_suelo numeric)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case p_estado
    when 'cobrada' then coalesce((
      select case when x.suelo_de_contrato
                  then x.suelo_precio > 0
                       and x.cobrado_suelo + x.cobrado_obra >= x.suelo_precio
                           + case when x.obra_firmada then coalesce(x.obra_precio, 0)
                                  else greatest(coalesce(x.obra_precio, 0), coalesce(p_precio, 0) - coalesce(p_precio_suelo, 0), 0) end
                  else coalesce(p_precio, 0) > 0 and x.cobrado_suelo + x.cobrado_obra >= p_precio end
        from public._unidad_cobro_cascada(p_unidad) x), false)
    when 'vendida' then coalesce((
      select case when x.suelo_de_contrato
                  then x.suelo_precio > 0 and x.cobrado_suelo >= x.suelo_precio
                  else coalesce(p_precio_suelo, 0) > 0
                       and x.cobrado_suelo + x.cobrado_obra >= greatest(p_precio_suelo, coalesce(x.suelo_precio, 0)) end
        from public._unidad_cobro_cascada(p_unidad) x), false)
    else true
  end;
$function$;

-- 4 · EL DISPARADOR QUE FALTABA: cambia el contrato → se revisa su parcela ------------------------------------------
-- avanza_unidad_por_cobro() es la única que mueve el estado (sube, y baja con Bloqueo firmado: LAW-497c) y es
-- idempotente; aquí solo se la llama cuando cambia algo de lo que ahora depende: el precio, la firma, la liberación,
-- la moneda o el tipo de un contrato de la venta, o cuando un contrato nuevo se cuelga de una venta. Un contrato raíz
-- recién creado no tiene cobros ni parcela atada todavía: no hay nada que revisar.
-- Se llama trg_zz_… para ir DESPUÉS de trg_sincroniza_unidad (los AFTER de una misma fila van por orden alfabético):
-- primero se ata o se suelta la parcela, luego se mide.
create or replace function public.trg_revalua_unidad_por_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
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
  after insert or update of precio_total, bloqueado, liberado_en, moneda, tipo on public.contratos
  for each row execute function public.trg_revalua_unidad_por_contrato();

-- 5 · COMISIONES (regla anterior al 1-nov): el denominador del «% cobrado del suelo» es el precio del Bloqueo solo si
-- está FIRMADO; si no, el de catálogo. Misma técnica que en 20261014024234: una marca de UNA línea sobre la viva.
do $parche$
declare
  v_def text;
  m1 text := 'coalesce(sum(coalesce(cp.suelo_precio, u.precio_suelo)), 0)';
  r1 text := 'coalesce(sum(case when cp.suelo_de_contrato then cp.suelo_precio else u.precio_suelo end), 0)';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'comisiones_evaluar_contrato';
  if v_def is null then
    raise exception 'cobro_primero_parcela_2: no existe public.comisiones_evaluar_contrato';
  end if;
  if position(r1 in v_def) > 0 then
    return;   -- ya aplicado
  end if;
  if (length(v_def) - length(replace(v_def, m1, ''))) / length(m1) <> 1 then
    raise exception 'cobro_primero_parcela_2: comisiones_evaluar_contrato no tiene la marca una vez; revisar a mano';
  end if;
  execute replace(v_def, m1, r1);
end
$parche$;
