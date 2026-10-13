-- VUELTA ATRÁS de supabase/migrations/20261013230000_comisiones_regla_1nov.sql (comisiones desde el 1-nov-2026).
-- Deja el esquema y los datos de comisiones como estaban el 13-oct-2026 antes de aplicarla: misma definición (md5) de
-- las 11 funciones que fotografió su bloque 0, mismos CHECK, sin la columna condicion_tramos.base_calculo, sin el
-- trigger condiciones_comision_tramos_suma, sin las 5 funciones nuevas, y las 12 condiciones genéricas abiertas otra vez.
-- Las funciones se reponen con el texto EXACTO de supabase/vivo/20261013_comisiones_1nov/ (pg_get_functiondef del
-- 13-oct, copiado aquí byte a byte: este fichero no depende de leer otro). Todo en UNA transacción: si cualquier
-- comprobación falla, no cambia nada.
--
-- CUÁNDO DEJA DE SER LIMPIA: en cuanto una de las 12 sucesoras (ids c0a11010-1101-4a10-…) tenga un devengo (el
-- primero llegará con la primera venta de noviembre que cobre el 50 % de la parcela). Ese devengo es comisión debida a
-- una persona con la regla nueva: no se puede borrar (FK de comisiones_devengadas a la condición y al tramo) ni
-- recalcular con la vieja sin decidirlo el owner. Por eso el bloque (a) PARA. Qué hacer entonces: NO ejecutar esta
-- vuelta; arreglar hacia delante con otra migración —cerrar las sucesoras (vigente_hasta = el día de la decisión) y
-- crear desde el editor las condiciones que se quieran (sustituye_a = la sucesora)—, con los devengos ya generados
-- colgando de su condición. El esquema nuevo (columna, CHECK ampliados, funciones) se queda: los snapshots de esos
-- devengos usan sus bases y el reconciliador las necesita. Si el owner decide anular alguno, se anula por el camino
-- normal (con motivo), nunca borrando la fila.
-- También para si alguien tocó lo que dejó la migración (una sucesora editada, desactivada o sustituida; una condición
-- o un tramo nuevos con valores que los CHECK viejos no admiten; un tramo con base propia): eso se resuelve a mano
-- antes, porque devolverlo «a como estaba» borraría trabajo del equipo.
--
-- Lo que NO se deshace: las filas de condiciones_comision_log que escribió la migración (historial: se añaden las de la
-- vuelta) y un posible aviso multimoneda en comisiones_interruptor.ultimo_error (se limpia como cualquier otro, desde
-- salud_lawang.py). Ningún devengo, diferencia ni solicitud se toca (el bloque (a) garantiza que no hay ninguno colgando
-- de lo que se borra).
--
-- destructivo-ok: (necesita además la marca del owner ~/.axisworks/destructivo-ok; tools/no_destruir.py). Borra: las 24
-- filas de condicion_tramos de las 12 sucesoras y las 12 sucesoras de condiciones_comision (sin devengos: lo comprueba
-- (a)); actualiza vigente_hasta (a null) en las 12 condiciones viejas; quita y repone ESTRECHOS los tres CHECK
-- (condiciones_comision_base_calculo_check, condicion_tramos_disparador_tipo_check, condicion_tramos_umbral_coherente);
-- quita la columna condicion_tramos.base_calculo (solo si está vacía fuera de las sucesoras: lo comprueba (d)), el
-- trigger condiciones_comision_tramos_suma y las 5 funciones nuevas; quita y crea mi_condicion_comision (vuelve a su
-- RETURNS TABLE sin tramos).
--
-- Cómo se aplica: igual que la migración, con la válvula del owner abierta. Se ha comprobado solo en seco (sintaxis con
-- pglast 8.5, sin ejecutarla: la migración aún no está aplicada).

begin;

-- (a) guarda: se puede volver sin dejar dinero colgando
do $$
declare v_n int; v_t text;
begin
  select count(*) into v_n from public.condiciones_comision where id::text like 'c0a11010-1101-4a10-8000-0000000000%';
  if v_n <> 12 then
    raise exception 'vuelta comisiones 1-nov: se esperaban las 12 sucesoras y hay % (¿la migración no está aplicada?)', v_n;
  end if;

  select count(*), string_agg(distinct d.condicion_id::text, ', ') into v_n, v_t
    from public.comisiones_devengadas d
   where d.condicion_id::text like 'c0a11010-1101-4a10-8000-0000000000%'
      or d.tramo_id in (select t.id from public.condicion_tramos t
                         where t.condicion_id::text like 'c0a11010-1101-4a10-8000-0000000000%');
  if v_n > 0 then
    raise exception 'vuelta comisiones 1-nov: las sucesoras ya tienen % devengo(s) (%). La vuelta ya no es limpia: no se ejecuta; arreglar hacia delante (ver cabecera)', v_n, v_t;
  end if;

  -- las sucesoras y las viejas siguen como las dejó la migración
  select string_agg(s.id::text, ', ') into v_t
    from public.condiciones_comision s
    left join public.condiciones_comision v on v.id = s.sustituye_a
   where s.id::text like 'c0a11010-1101-4a10-8000-0000000000%'
     and (not s.activo or s.vigente_hasta is not null or s.base_calculo <> 'por_tramo' or s.closer_email is not null
          or s.vigente_desde <> date '2026-11-01'
          or v.id is null or not v.activo or v.vigente_hasta is distinct from date '2026-10-31'
          or (select count(*) from public.condicion_tramos t where t.condicion_id = s.id) <> 2
          or exists (select 1 from public.condiciones_comision x where x.sustituye_a = s.id));
  if v_t is not null then
    raise exception 'vuelta comisiones 1-nov: estas sucesoras (o su vieja) se han tocado después de la migración: %. Resolver a mano antes', v_t;
  end if;
end $$;

-- (b) se borran los 24 tramos y las 12 sucesoras, cada una con su línea en el log
do $$
declare v record; v_n int;
begin
  for v in select s.* from public.condiciones_comision s
            where s.id::text like 'c0a11010-1101-4a10-8000-0000000000%' order by s.id
  loop
    insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo, por)
    values (v.id, to_jsonb(v) || jsonb_build_object('tramos', (select jsonb_agg(to_jsonb(t) order by t.orden)
                                                              from public.condicion_tramos t where t.condicion_id = v.id)),
            null, false,
            'Vuelta atrás de la migración comisiones_regla_1nov: se borra esta sucesora (sin devengos) y su condición vieja ' || v.sustituye_a || ' vuelve a valer sin fecha de fin.',
            'vuelta comisiones_regla_1nov');
  end loop;

  delete from public.condicion_tramos where condicion_id::text like 'c0a11010-1101-4a10-8000-0000000000%';
  get diagnostics v_n = row_count;
  if v_n <> 24 then raise exception 'vuelta comisiones 1-nov: se esperaban 24 tramos borrados y han sido %', v_n; end if;

  -- trg_condicion_borrada_reabre (AFTER DELETE) reabre la vieja de cada una: le copia activo/vigente_hasta de la
  -- borrada (true / null, comprobado en (a)) y escribe su propia línea «reabierta» en condiciones_comision_log.
  delete from public.condiciones_comision where id::text like 'c0a11010-1101-4a10-8000-0000000000%';
  get diagnostics v_n = row_count;
  if v_n <> 12 then raise exception 'vuelta comisiones 1-nov: se esperaban 12 sucesoras borradas y han sido %', v_n; end if;
end $$;

-- los triggers diferidos (condicion_tramos_suma_100, FK sustituye_a) se disparan YA: con eventos pendientes Postgres no
-- deja hacer ALTER TABLE en (d)/(e) («cannot ALTER TABLE … because it has pending trigger events»)
set constraints all immediate;

-- (c) las 12 viejas, abiertas (lo hizo el trigger de (b); esto lo comprueba y lo deja escrito)
do $$
declare v_t text;
begin
  select string_agg(c.id::text, ', ') into v_t
    from public.condiciones_comision c
   where c.id in ('22de941a-7d34-4894-8b79-cafbe05d1d56', '4a1c0fe1-f3b1-49b7-a513-328939f0ec1b',
                  'ac9f7557-dbf6-44a4-8ae2-fa31c8d68153', 'eab39fea-b874-43dd-87a6-eec94c34efd1',
                  '4a1036e7-58d0-4b81-b5fd-ab0de41dcee1', '3f774dde-e4f1-4086-85f9-c3942acc06ae',
                  '491d8acd-182a-4906-916d-433940a376e5', 'c7ac56ca-c0a4-4e76-82bb-6086eccdb4c9',
                  'ddb805c1-335a-409b-9ad7-93ba78bd9619', '57f7369f-3801-4f77-9091-d87fd7db0268',
                  '286adb02-4369-4a39-94a7-6e7735440a40', 'bbca7a81-f529-4be9-99d6-feed49228009')
     and (not c.activo or c.vigente_hasta is not null);
  if v_t is not null then
    raise exception 'vuelta comisiones 1-nov: estas condiciones viejas no se reabrieron: %', v_t;
  end if;
  if (select count(*) from public.condiciones_comision_log l
       where l.motivo = 'reabierta: se borró la condición que la sustituía' and l.en = now()
         and l.condicion_id in ('22de941a-7d34-4894-8b79-cafbe05d1d56', '4a1c0fe1-f3b1-49b7-a513-328939f0ec1b',
                                'ac9f7557-dbf6-44a4-8ae2-fa31c8d68153', 'eab39fea-b874-43dd-87a6-eec94c34efd1',
                                '4a1036e7-58d0-4b81-b5fd-ab0de41dcee1', '3f774dde-e4f1-4086-85f9-c3942acc06ae',
                                '491d8acd-182a-4906-916d-433940a376e5', 'c7ac56ca-c0a4-4e76-82bb-6086eccdb4c9',
                                'ddb805c1-335a-409b-9ad7-93ba78bd9619', '57f7369f-3801-4f77-9091-d87fd7db0268',
                                '286adb02-4369-4a39-94a7-6e7735440a40', 'bbca7a81-f529-4be9-99d6-feed49228009')) <> 12 then
    raise exception 'vuelta comisiones 1-nov: faltan líneas «reabierta» en condiciones_comision_log';
  end if;
  if exists (select 1 from public.condiciones_comision c
              where c.id in ('22de941a-7d34-4894-8b79-cafbe05d1d56', '4a1c0fe1-f3b1-49b7-a513-328939f0ec1b',
                             'ac9f7557-dbf6-44a4-8ae2-fa31c8d68153', 'eab39fea-b874-43dd-87a6-eec94c34efd1',
                             '4a1036e7-58d0-4b81-b5fd-ab0de41dcee1', '3f774dde-e4f1-4086-85f9-c3942acc06ae',
                             '491d8acd-182a-4906-916d-433940a376e5', 'c7ac56ca-c0a4-4e76-82bb-6086eccdb4c9',
                             'ddb805c1-335a-409b-9ad7-93ba78bd9619', '57f7369f-3801-4f77-9091-d87fd7db0268',
                             '286adb02-4369-4a39-94a7-6e7735440a40', 'bbca7a81-f529-4be9-99d6-feed49228009')
                and public._condicion_solapa(c.id) is not null) then
    raise exception 'vuelta comisiones 1-nov: una condición reabierta solapa con otra';
  end if;
end $$;

-- (d) los tres CHECK, estrechos otra vez (definición viva del 13-oct); para si queda alguna fila con valores nuevos
do $$
declare v_a int; v_b int; v_c int;
begin
  select count(*) into v_a from public.condiciones_comision
   where base_calculo in ('precio_suelo_firmado', 'precio_obra_firmada', 'por_tramo');
  select count(*) into v_b from public.condicion_tramos
   where disparador_tipo in ('pct_cobrado_suelo_firmado', 'pct_cobrado_obra_firmada');
  select count(*) into v_c from public.condicion_tramos where base_calculo is not null;
  if v_a + v_b + v_c > 0 then
    raise exception 'vuelta comisiones 1-nov: quedan % condiciones con base nueva, % tramos con disparo nuevo y % tramos con base propia, creados después de la migración. Resolver a mano antes',
      v_a, v_b, v_c;
  end if;
end $$;

alter table public.condiciones_comision drop constraint condiciones_comision_base_calculo_check;
alter table public.condiciones_comision add constraint condiciones_comision_base_calculo_check check (
  base_calculo = any (array['precio_total', 'precio_suelo', 'precio_construccion', 'importe_fijo']));

alter table public.condicion_tramos drop constraint condicion_tramos_disparador_tipo_check;
alter table public.condicion_tramos add constraint condicion_tramos_disparador_tipo_check check (
  disparador_tipo = any (array['pct_cobrado_suelo', 'pct_cobrado_obra', 'pct_cobrado_total', 'obra_firmada',
                               'contrato_firmado']));

alter table public.condicion_tramos drop constraint condicion_tramos_umbral_coherente;
alter table public.condicion_tramos add constraint condicion_tramos_umbral_coherente check (
  (disparador_tipo = any (array['obra_firmada', 'contrato_firmado']) and umbral is null)
  or (disparador_tipo = any (array['pct_cobrado_suelo', 'pct_cobrado_obra', 'pct_cobrado_total'])
      and umbral is not null and umbral >= 0 and umbral <= 100));

-- (e) el trigger nuevo y la columna (su CHECK condicion_tramos_base_calculo_check y su comentario se van con ella;
--     sin cascade: si algo más dependiera de la columna, para)
drop trigger condiciones_comision_tramos_suma on public.condiciones_comision;
alter table public.condicion_tramos drop column base_calculo;

-- (f) las 5 funciones nuevas de la migración (lista exacta: las que crea y no estaban el 13-oct; sin cascade)
drop function public._comision_vista_completa(text, uuid, uuid);
drop function public._condicion_tramos_resumen(uuid);
drop function public._comisiones_bases_firmadas(uuid);
drop function public._comisiones_parte_obra(text, boolean);
drop function public._contrato_cobrado_interno(uuid, text);

-- (g) mi_condicion_comision: drop + create con su firma y cuerpo vivos; dueño y permisos de hoy
--     (postgres; EXECUTE de postgres, service_role y authenticated; nada para public ni anon)
drop function public.mi_condicion_comision();
CREATE OR REPLACE FUNCTION public.mi_condicion_comision()
 RETURNS TABLE(ambito text, equipo_nombre text, oculta boolean, proyecto_id uuid, nivel text, pct_comision numeric, base_calculo text, importe_fijo numeric, personal boolean, vigente_desde date, empresa text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_yo text := lower(coalesce(auth.email(), ''));
  v_hoy date := current_date;
  v_eq record;
  v_nivel text;
  v_p uuid;
  v_emp text;
  v_c public.condiciones_comision;
  v_vistas uuid[] := '{}';
  v_claves text[] := '{}';
  v_k text;
  v_hay boolean := false;
begin
  if auth.uid() is null or v_yo = '' then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  for v_eq in
    select em.equipo_id, em.rol, ev.nombre, ev.closers_ven_comision, ev.empresa
      from public.equipo_miembros em
      join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
     where lower(em.closer_email) = v_yo and em.desde <= v_hoy and (em.hasta is null or em.hasta >= v_hoy)
     order by em.created_at desc
  loop
    v_hay := true;
    if not coalesce(v_eq.closers_ven_comision, true) then
      v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, 'oculta'));
      if not (v_k = any (v_claves)) then
        v_claves := v_claves || v_k;
        return query select 'equipo'::text, v_eq.nombre::text, true, null::uuid, null::text, null::numeric, null::text,
                            null::numeric, null::boolean, null::date, v_eq.empresa::text;
      end if;
      continue;
    end if;
    v_nivel := case when v_eq.rol in ('closer', 'setter', 'team_lead') then v_eq.rol else 'closer' end;
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id and c.nivel = v_nivel and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.equipo_id = v_eq.equipo_id
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and lower(c.closer_email) = v_yo
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if not found then
        select * into v_c from public.condiciones_comision c
         where c.equipo_id = v_eq.equipo_id
           and (c.proyecto_id = v_p or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_k := md5(concat_ws('|', 'equipo', v_eq.nombre, v_c.proyecto_id, v_c.nivel, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'equipo'::text, v_eq.nombre::text, false, v_c.proyecto_id, v_c.nivel, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_eq.empresa::text;
        end if;
      end if;
    end loop;
  end loop;
  if v_hay then return; end if;

  for v_emp in select e.clave from public.empresas e where e.activa and (not public.alcance_restringido() or public.puede_empresa(e.clave)) order by e.orden loop
    for v_p in
      select null::uuid
      union
      select distinct c.proyecto_id from public.condiciones_comision c
       where c.empresa = v_emp and c.equipo_id is null and c.nivel = 'closer' and c.proyecto_id is not null
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
    loop
      select * into v_c from public.condiciones_comision c
       where c.empresa = v_emp
         and c.equipo_id is null
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_hoy and (c.vigente_hasta is null or c.vigente_hasta >= v_hoy)
         and (c.proyecto_id = v_p or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = v_yo)
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
      if found and not (v_c.id = any (v_vistas)) then
        v_vistas := v_vistas || v_c.id;
        v_k := md5(concat_ws('|', 'estandar', v_c.proyecto_id, v_c.pct_comision, v_c.base_calculo, v_c.importe_fijo,
                             v_c.closer_email is not null, v_c.vigente_desde));
        if not (v_k = any (v_claves)) then
          v_claves := v_claves || v_k;
          return query select 'estandar'::text, null::text, false, v_c.proyecto_id, 'estandar'::text, v_c.pct_comision,
                              v_c.base_calculo, v_c.importe_fijo, v_c.closer_email is not null, v_c.vigente_desde, v_emp::text;
        end if;
      end if;
    end loop;
  end loop;
end $function$
;
alter function public.mi_condicion_comision() owner to postgres;
revoke all on function public.mi_condicion_comision() from public, anon;
grant execute on function public.mi_condicion_comision() to authenticated, service_role;

-- (h) las 10 redefinidas, con su definición viva del 13-oct (create or replace conserva dueño y permisos). La última
--     deshace el parche de UNA línea del bloque 7 de la migración (base del tramo en «cambian las cifras»).
CREATE OR REPLACE FUNCTION public.contrato_cobrado(p_contrato_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_existe boolean;
begin
  select true into v_existe from public.contratos c where c.id = p_contrato_id;
  if not coalesce(v_existe, false) then return 0; end if;
  if (select auth.role()) <> 'service_role'
     and not (public.es_agente() or public.es_portal()) then
    return 0;
  end if;
  return coalesce((
      select sum(ra.importe_aplicado)
        from public.recibi_aplicaciones ra
        join public.facturas r on r.id = ra.recibi_id
        join public.facturas f on f.id = ra.factura_id
       where f.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
         and not coalesce(f.anulada, false)
    ), 0)
    + coalesce((
      select sum(
        r.total - coalesce((
          select sum(ra.importe_aplicado)
            from public.recibi_aplicaciones ra
            join public.facturas f2 on f2.id = ra.factura_id
           where ra.recibi_id = r.id
             and f2.contrato_id is not null
             and not coalesce(f2.anulada, false)
        ), 0))
        from public.facturas r
       where r.tipo = 'recibi'
         and r.contrato_id = p_contrato_id
         and not coalesce(r.anulada, false)
    ), 0);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.valida_suma_tramos_comision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_condicion_id uuid := coalesce(new.condicion_id, old.condicion_id);
  v_suma numeric;
begin
  -- La condición padre ya no existe (se borró ella misma, arrastrando estos
  -- tramos por el ON DELETE CASCADE): nada que validar, no queda condición
  -- viva con un % a medias.
  if not exists (select 1 from public.condiciones_comision c where c.id = v_condicion_id) then
    return coalesce(new, old);
  end if;

  select coalesce(sum(pct_tramo), 0) into v_suma
    from public.condicion_tramos
   where condicion_id = v_condicion_id;

  if abs(v_suma - 100) > 0.01 then
    raise exception 'los tramos de la condición % suman % (deben sumar exactamente 100)',
      v_condicion_id, v_suma using errcode = '23514';
  end if;

  return coalesce(new, old);
end;
$function$
;
CREATE OR REPLACE FUNCTION public._condicion_tramos_pone(p_condicion uuid, p_tramos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' or jsonb_array_length(p_tramos) = 0 then
    raise exception 'Hacen falta tramos de pago' using errcode = '23514';
  end if;
  delete from public.condicion_tramos where condicion_id = p_condicion;
  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
  select p_condicion, ord, t->>'disparador_tipo',
         case when (t->>'disparador_tipo') like 'pct_cobrado_%' then (t->>'umbral')::numeric end,
         (t->>'pct_tramo')::numeric
    from jsonb_array_elements(p_tramos) with ordinality as x(t, ord);
end $function$
;
CREATE OR REPLACE FUNCTION public.comisiones_evaluar_contrato(p_contrato_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_raiz_id              uuid;
  v_raiz_creada          date;
  v_fecha_equipo         date;
  v_moneda               text;
  v_proyecto_id          uuid;
  v_contrato_firmado     boolean := false;
  v_obra_firmada         boolean := false;
  v_precio_total         numeric := 0;
  v_precio_suelo         numeric := 0;
  v_precio_construccion  numeric := 0;
  v_cobrado_suelo        numeric := 0;
  v_cobrado_obra         numeric := 0;
  v_cobrado_total        numeric := 0;
  v_closer_email         text;
  v_fecha_venta          date;
  v_equipo_id            uuid;
  v_manager_email        text;
  v_propia               public.reclamaciones_venta_propia;
  v_niveles              text[];
  v_ultimo_recibi_id     uuid;
  v_ultimo_recibi_en     timestamptz;
  v_nivel                text;
  v_beneficiario         text;
  v_condicion            record;
  v_cond_fija            uuid;
  v_prev                 public.comisiones_devengadas;
  v_snap                 jsonb;
  v_tramo                record;
  v_base                 numeric;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_concepto             text;
  v_creados              integer := 0;
  v_eq_cong              uuid;
  v_man_cong             text;
  v_congelado            boolean := false;
  v_modo                 text;
  v_espera               timestamptz;
  v_propia_modo          boolean := false;
  v_pct_efectivo         numeric;
  v_plt_pct              numeric;
  v_plt_n                integer;
  v_prev_snap            jsonb;
  v_man_id               uuid;
  v_man_pct              numeric;
  v_man_base             text;
  v_empresa              text;
begin
  if p_contrato_id is null then
    return 0;
  end if;

  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0;
  end if;

  perform pg_advisory_xact_lock(hashtext('comisiones:' || v_raiz_id::text));

  select c.moneda, c.proyecto_id, c.bloqueado, (c.created_at at time zone 'Asia/Makassar')::date
    into v_moneda, v_proyecto_id, v_contrato_firmado, v_raiz_creada
    from public.contratos c
   where c.id = v_raiz_id;

  v_precio_total := public._comisiones_precio_total(v_raiz_id);
  v_empresa := public._empresa_de_proyecto_int(v_proyecto_id);

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado and exists (select 1 from public.contrato_tipo_etapa e where e.tipo = h.tipo and e.es_obra)
  );

  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_interno(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  select k.closer_email, k.fecha_venta into v_closer_email, v_fecha_venta
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0;
  end if;

  v_raiz_creada := coalesce(v_fecha_venta, v_raiz_creada);
  v_fecha_equipo := v_raiz_creada;

  select k.equipo_id, k.manager_email, (k.equipo_congelado_en is not null), k.modo, k.modo_espera_hasta
    into v_eq_cong, v_man_cong, v_congelado, v_modo, v_espera
    from public.contrato_closer k where k.contrato_id = v_raiz_id;
  if coalesce(v_congelado, false) then
    v_equipo_id := v_eq_cong;
  else
  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where lower(em.closer_email) = lower(v_closer_email)
     and ev.empresa = v_empresa
     and ev.activo
     and em.desde <= v_fecha_equipo
     and (em.hasta is null or em.hasta >= v_fecha_equipo)
   order by em.created_at desc
   limit 1;
  end if;

  if v_proyecto_id is null or v_moneda is null then
    return 0;
  end if;

  if v_modo is null then
    select * into v_propia
      from public.reclamaciones_venta_propia r
     where r.contrato_raiz_id = v_raiz_id and r.estado = 'aprobada' and r.tipo = 'reclamacion';
  end if;

  if v_modo = 'propia' and v_equipo_id is not null then
    if (v_espera is not null and v_espera > now())
       or exists (select 1 from public.reclamaciones_venta_propia r
                   where r.contrato_raiz_id = v_raiz_id and r.tipo = 'objecion' and r.estado = 'pendiente') then
      return 0;
    end if;
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_propia_modo := true;
    v_niveles := array['propia'];
  elsif v_modo = 'propia' then
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  elsif v_propia.id is not null then
    if lower(v_propia.solicitante_email) <> lower(v_closer_email) then
      return 0;
    end if;
    v_equipo_id := v_propia.equipo_id;
    v_niveles := array['propia'];
  elsif v_equipo_id is not null then
    if coalesce(v_congelado, false) then
      v_manager_email := v_man_cong;
    else
      select ev.manager_email into v_manager_email from public.equipos_venta ev where ev.id = v_equipo_id;
    end if;
    v_niveles := array['manager', 'closer', 'setter', 'team_lead'];
  else
    if not public.crm_usuario_activo(v_closer_email) then
      return 0;
    end if;
    v_niveles := array['estandar'];
  end if;

  select r.id, r.created_at
    into v_ultimo_recibi_id, v_ultimo_recibi_en
    from public.facturas r
   where r.tipo = 'recibi'
     and not coalesce(r.anulada, false)
     and (
       r.contrato_id = v_raiz_id
       or r.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id)
       or exists (
            select 1
              from public.recibi_aplicaciones ra
              join public.facturas f on f.id = ra.factura_id
             where ra.recibi_id = r.id
               and not coalesce(f.anulada, false)
               and (f.contrato_id = v_raiz_id
                    or f.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id))
          )
     )
   order by r.created_at desc
   limit 1;

  if v_ultimo_recibi_id is null then
    return 0;
  end if;

  foreach v_nivel in array v_niveles
  loop
    v_beneficiario := null;
    v_pct_efectivo := null;
    v_plt_pct := null;

    if v_nivel in ('closer', 'setter', 'team_lead') then
      if v_nivel = 'closer' then
        v_beneficiario := v_closer_email;
      else
        select re.email into v_beneficiario
          from public.contrato_roles_equipo re
         where re.contrato_raiz_id = v_raiz_id and re.rol = v_nivel and re.equipo_id = v_equipo_id;
      end if;
      if v_beneficiario is null then
        continue;
      end if;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = v_nivel
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and lower(c.closer_email) = lower(v_beneficiario)
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
           and c.nivel = v_nivel
           and (c.activo or c.vigente_hasta is not null)
           and c.vigente_desde <= v_raiz_creada
           and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
           and c.closer_email is null
         order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
         limit 1;
      end if;

    elsif v_nivel = 'estandar' or (v_nivel = 'propia' and v_propia_modo) then
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id is null
         and c.empresa = v_empresa
         and c.nivel = 'closer'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and (c.closer_email is null or lower(c.closer_email) = lower(v_closer_email))
       order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;

    else
      v_beneficiario := case when v_nivel = 'propia' then v_closer_email else v_manager_email end;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
         and c.nivel = 'manager'
         and (c.activo or c.vigente_hasta is not null)
         and c.vigente_desde <= v_raiz_creada
         and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
         and c.closer_email is null
       order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
       limit 1;
    end if;

    v_cond_fija := null;
    if v_beneficiario is not null then
      select d.condicion_id into v_cond_fija
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and lower(d.beneficiario_email) = lower(v_beneficiario)
         and d.nivel = v_nivel
       order by d.created_at, d.id
       limit 1;
      if v_cond_fija is not null then
        select * into v_condicion from public.condiciones_comision c where c.id = v_cond_fija;
      end if;
    end if;

    if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;

    if v_condicion.base_calculo <> 'importe_fijo' and v_condicion.pct_comision = 0 then
      continue;
    end if;

    -- F8: el devengo del closer de equipo sale de la plantilla del SM (% del bote del manager), no de una cifra suelta.
    -- Solo la condicion generica del equipo (closer_email null): una por closer (p. ej. 0 % propio) sigue mandando.
    if v_nivel = 'closer' and v_equipo_id is not null and v_condicion.equipo_id = v_equipo_id
       and v_condicion.closer_email is null and v_condicion.base_calculo <> 'importe_fijo' then
      select d.disparado_por_snapshot into v_prev_snap
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.nivel = 'closer'
         and lower(d.beneficiario_email) = lower(v_beneficiario)
       order by d.created_at, d.id
       limit 1;
      if found then
        -- ya hay primer devengo: se relee SU congelado (sin plantilla_pct = la plantilla no aplica en esta raiz)
        v_plt_pct := nullif(v_prev_snap->>'plantilla_pct', '')::numeric;
      else
        select count(*), max(p.pct) into v_plt_n, v_plt_pct
          from public.plantilla_reparto p
         where p.equipo_id = v_equipo_id and p.rol_tipo = 'closer';
        if v_plt_n <> 1 then
          if v_plt_n > 1 then
            raise warning 'comisiones_evaluar_contrato: el equipo % tiene % filas closer en su plantilla; se usa la condicion de closer (raiz %)', v_equipo_id, v_plt_n, v_raiz_id;
          end if;
          v_plt_pct := null;
        end if;
      end if;

      if v_plt_pct is not null then
        -- la condicion manager con la que la venta devengo (fija) o, si aun no hay, la vigente
        select d.condicion_id into v_man_id
          from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id and d.nivel = 'manager'
         order by d.created_at, d.id
         limit 1;
        if v_man_id is null then
          select c.id into v_man_id
            from public.condiciones_comision c
           where c.equipo_id = v_equipo_id
             and (c.proyecto_id = v_proyecto_id or c.proyecto_id is null)
             and c.nivel = 'manager'
             and (c.activo or c.vigente_hasta is not null)
             and c.vigente_desde <= v_raiz_creada
             and (c.vigente_hasta is null or c.vigente_hasta >= v_raiz_creada)
             and c.closer_email is null
           order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id
           limit 1;
        end if;
        select c.pct_comision, c.base_calculo into v_man_pct, v_man_base
          from public.condiciones_comision c where c.id = v_man_id;
        if v_man_pct is null or v_man_base is distinct from v_condicion.base_calculo then
          raise warning 'comisiones_evaluar_contrato: la condicion manager del equipo % no casa con la de closer (base o falta); se usa la condicion de closer (raiz %)', v_equipo_id, v_raiz_id;
          v_plt_pct := null;
        else
          v_pct_efectivo := least(v_plt_pct, 100) / 100 * v_man_pct;
        end if;
      end if;
    end if;

    v_base := case v_condicion.base_calculo
      when 'precio_total'        then v_precio_total
      when 'precio_suelo'        then v_precio_suelo
      when 'precio_construccion' then v_precio_construccion
      else null
    end;

    for v_tramo in
      select * from public.condicion_tramos
       where condicion_id = v_condicion.id
       order by orden
    loop
      v_prev := null;
      select * into v_prev
        from public.comisiones_devengadas d
       where d.contrato_raiz_id = v_raiz_id
         and d.tramo_id = v_tramo.id
         and d.beneficiario_email = v_beneficiario;
      if v_prev.id is not null and (v_prev.estado <> 'anulada' or not v_prev.anulado_por_modo) then
        continue;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') and exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.nivel in ('manager', 'estandar', 'propia')
           and d.estado <> 'anulada'
      ) then
        continue;
      end if;

      if not (case v_tramo.disparador_tipo
        when 'pct_cobrado_suelo' then
          v_precio_suelo > 0 and (v_cobrado_suelo / v_precio_suelo * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra' then
          v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral
        when 'pct_cobrado_total' then public._comisiones_precio_total_todos(v_raiz_id) > 0 and (v_cobrado_total / public._comisiones_precio_total_todos(v_raiz_id) * 100) >= v_tramo.umbral
        when 'obra_firmada' then v_obra_firmada
        when 'contrato_firmado' then v_contrato_firmado
        else false
      end) then
        continue;
      end if;

      if v_condicion.base_calculo = 'importe_fijo' then
        v_importe := round(v_condicion.importe_fijo * v_tramo.pct_tramo / 100, 2);
      else
        if v_base is null then
          continue;
        end if;
        v_importe := round((coalesce(v_pct_efectivo, v_condicion.pct_comision) / 100) * v_base * (v_tramo.pct_tramo / 100), 2);
      end if;

      if coalesce(v_importe, 0) <= 0 then
        continue;
      end if;

      v_snap := jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'base_calculo', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', coalesce(v_pct_efectivo, v_condicion.pct_comision),
          'plantilla_pct', case when v_pct_efectivo is not null then v_plt_pct end,
          'vigente_desde', v_condicion.vigente_desde,
          'precio_total', v_precio_total,
          'precio_suelo', v_precio_suelo,
          'precio_construccion', v_precio_construccion,
          'cobrado_suelo', v_cobrado_suelo,
          'cobrado_obra', v_cobrado_obra,
          'cobrado_total', v_cobrado_total,
          'obra_firmada', v_obra_firmada,
          'contrato_firmado', v_contrato_firmado,
          'fecha_venta', v_fecha_venta,
          'equipo_id', case when v_propia_modo then null else v_equipo_id end,
          'reclamacion_id', v_propia.id,
          'modo', v_modo,
          'condicion_fijada', v_cond_fija is not null
        );

      v_devengo_id := null;

      if v_prev.id is not null then
        v_creados := v_creados + 1;
        if public._comision_devengo_reponer(v_prev.id, v_importe, v_snap,
                                            'La venta vuelve a «' || coalesce(v_modo, 'equipo') || '»')
           or v_nivel not in ('manager', 'estandar', 'propia') then
          continue;
        end if;
        v_devengo_id := v_prev.id;
      else
        insert into public.comisiones_devengadas (
          contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
          importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
        ) values (
          v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
          v_importe, v_moneda, null, v_snap
        )
        on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
        returning id into v_devengo_id;

        if v_devengo_id is null then
          continue;
        end if;

        v_creados := v_creados + 1;
      end if;

      if v_nivel in ('manager', 'estandar', 'propia') then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) and u.activo limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) and u.activo limit 1),
          (select u.user_id from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1)
        );

        v_concepto := 'Comisión ' || case v_nivel when 'manager' then 'manager' when 'propia' then 'venta propia' else 'estándar' end
          || ' — tramo ' || v_tramo.orden || ' (' || v_tramo.disparador_tipo
          || case when v_tramo.umbral is not null then ' ' || v_tramo.umbral || '%' else '' end || ')'
          || case when v_condicion.base_calculo = 'importe_fijo'
               then ' — importe fijo ' || v_condicion.importe_fijo
               else ' — ' || v_condicion.pct_comision || '% s/ ' || replace(v_condicion.base_calculo, '_', ' ')
                    || ' a fecha de disparo: ' || round(v_base, 2) || ' ' || v_moneda
             end
          || ' × ' || v_tramo.pct_tramo || '% del tramo — importe BRUTO (retención al pagar)';

        if v_creado_por is null then
          raise warning 'comisiones_evaluar_contrato: sin creado_por resoluble para la solicitud de % (raiz %) -- devengo % sin solicitud',
            v_beneficiario, v_raiz_id, v_devengo_id;
        else
          v_sp_id := null;
          begin
            insert into public.solicitudes_pago (
              contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por
            ) values (
              v_raiz_id, v_concepto, v_importe, v_moneda, 'comision_automatica', v_beneficiario, v_creado_por
            )
            returning id into v_sp_id;

            update public.comisiones_devengadas
               set solicitud_id = v_sp_id
             where id = v_devengo_id;
          exception when others then
            raise warning 'comisiones_evaluar_contrato: fallo creando la solicitud de pago de % (raiz %, tramo %): % -- devengo % sin solicitud',
              v_beneficiario, v_raiz_id, v_tramo.id, sqlerrm, v_devengo_id;
          end;
        end if;
      end if;
    end loop;
  end loop;

  return v_creados;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.comisiones_reconciliar(p_raiz uuid, p_simular boolean DEFAULT true, p_origen jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(devengo_id uuid, venta text, beneficiario text, nivel text, estado_devengo text, base_antes numeric, base_despues numeric, vigente numeric, nuevo numeric, delta numeric, accion text, motivo text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record; v_sp public.solicitudes_pago;
  v_es_raiz boolean; v_moneda text; v_num text; v_base numeric;
  v_vig numeric; v_nuevo numeric; v_delta numeric; v_base_antes numeric;
  v_lawang boolean; v_manual boolean; v_accion text; v_motivo text;
  v_yo text := lower(coalesce(auth.email(), ''));
  v_dif public.comisiones_diferencias; v_dif_id uuid;
  v_hoy text := to_char(now() at time zone 'Asia/Makassar', 'DD-MM-YYYY');
  v_eq_id uuid; v_fecha_venta date; v_mismo_equipo boolean;   -- AXW-98 / B3c, por devengo
begin
  if p_raiz is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));

  select (c.contrato_padre_id is null and c.liberado_en is null), c.moneda, c.numero
    into v_es_raiz, v_moneda, v_num
    from public.contratos c where c.id = p_raiz;
  v_base := public._comisiones_precio_total(p_raiz);

  for r in
    select d.*, c.base_calculo, case when d.disparado_por_snapshot->>'plantilla_pct' is not null then nullif(d.disparado_por_snapshot->>'pct_comision', '')::numeric else c.pct_comision end as pct_comision, c.importe_fijo, t.pct_tramo
      from public.comisiones_devengadas d
      join public.condiciones_comision c on c.id = d.condicion_id
      join public.condicion_tramos t on t.id = d.tramo_id
     where d.contrato_raiz_id = p_raiz and d.estado <> 'anulada'
     order by d.created_at, d.id
  loop
    continue when r.base_calculo <> 'precio_total';

    v_lawang := r.nivel in ('manager', 'estandar', 'propia');
    v_sp := null;
    if r.solicitud_id is not null then
      select * into v_sp from public.solicitudes_pago sp where sp.id = r.solicitud_id;
    end if;
    select * into v_dif from public.comisiones_diferencias x where x.devengo_id = r.id and x.estado = 'revisar';

    v_base_antes := coalesce(
      (select x.base_despues from public.comisiones_diferencias x
        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')
        order by x.created_at desc limit 1),
      nullif(r.disparado_por_snapshot->>'base_valor', '')::numeric);
    v_vig := (case when v_lawang and v_sp.id is not null then v_sp.importe
                   else coalesce(r.importe_ajustado, r.importe) end)
           + coalesce((select sum(x.importe) from public.comisiones_diferencias x
                        where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')), 0);
    v_nuevo := round((r.pct_comision / 100) * v_base * (r.pct_tramo / 100), 2);
    v_delta := round(v_nuevo - v_vig, 2);
    v_manual := r.importe_ajustado is not null or (v_sp.id is not null and v_sp.importe_editado_por is not null);

    v_mismo_equipo := false;
    if v_delta > 0 and nullif(v_yo, '') is not null and r.nivel <> 'estandar' then
      v_eq_id := coalesce(nullif(r.disparado_por_snapshot->>'equipo_id', '')::uuid,
                          (select x.equipo_id from public._equipo_de_venta(p_raiz) x limit 1));
      if v_eq_id is not null then
        v_fecha_venta := coalesce((select x.fecha from public._equipo_de_venta(p_raiz) x limit 1), current_date);
        v_mismo_equipo :=
             exists (select 1 from public._equipo_de_venta(p_raiz) x
                      where x.equipo_id = v_eq_id and v_yo in (lower(x.manager_email), lower(x.closer_email)))
          or exists (select 1 from public.contrato_roles_equipo re
                      where re.contrato_raiz_id = p_raiz and re.equipo_id = v_eq_id and lower(re.email) = v_yo)
          or exists (select 1 from public.reclamaciones_venta_propia rp
                      where rp.contrato_raiz_id = p_raiz and rp.equipo_id = v_eq_id and rp.estado = 'aprobada'
                        and lower(rp.solicitante_email) = v_yo)
          or exists (select 1 from public.equipos_venta ev where ev.id = v_eq_id and lower(ev.manager_email) = v_yo)
          or exists (select 1 from public.equipo_miembros em
                      where em.equipo_id = v_eq_id and lower(em.closer_email) = v_yo
                        and ((em.desde <= v_fecha_venta and (em.hasta is null or em.hasta >= v_fecha_venta))
                          or (em.desde <= current_date and (em.hasta is null or em.hasta >= current_date))));
      end if;
    end if;

    v_accion := null; v_motivo := null;
    if not coalesce(v_es_raiz, false) then
      v_accion := 'revisar'; v_motivo := 'la venta ' || coalesce(v_num, '?') || ' ya no es una venta viva (traspasada a otro contrato o liberada)';
      v_delta := null;
    elsif v_moneda is distinct from r.moneda then
      v_accion := 'revisar'; v_motivo := 'la venta está ahora en ' || coalesce(v_moneda, '?') || ' y la comisión en ' || r.moneda;
      v_delta := null;
    elsif abs(v_delta) < 0.01 then
      v_accion := 'nada';
    elsif v_nuevo <= 0 then
      v_accion := 'revisar'; v_motivo := 'sin contratos firmados en la venta la comisión bajaría a 0';
    elsif v_manual then
      v_accion := 'revisar'; v_motivo := 'el importe se había ajustado a mano';
    elsif r.estado = 'en_disputa' then
      v_accion := 'revisar'; v_motivo := 'la comisión está en disputa';
    elsif v_lawang and (v_sp.id is null or v_sp.estado in ('rechazada', 'anulada')) then
      v_accion := 'revisar'; v_motivo := 'su solicitud de pago está ' || coalesce(v_sp.estado, 'sin crear');
    elsif v_delta > 0 and lower(r.beneficiario_email) = v_yo then
      v_accion := 'revisar'; v_motivo := 'la subida la provoca quien cobra la comisión';
    elsif v_delta > 0 and v_mismo_equipo then
      v_accion := 'revisar';
      v_motivo := 'subida_mismo_equipo: la subida beneficia a alguien del mismo equipo de la venta que quien provocó el cambio; la decide otra persona';
    elsif r.nivel in ('closer', 'setter', 'team_lead') then
      v_accion := 'actualizar';   -- F9M5-informativo: informativo (nunca un pago de la empresa): se actualiza en su sitio, sin diferencia
    elsif r.estado = 'pendiente' and (not v_lawang or v_sp.estado = 'pendiente')
          and not exists (select 1 from public.comisiones_diferencias x
                           where x.devengo_id = r.id and x.estado in ('pendiente', 'pagada', 'compensada')) then
      v_accion := 'actualizar';
    else
      v_accion := 'diferencia';
      v_motivo := 'la comisión ya estaba '
                  || case when r.estado = 'pagada' or v_sp.estado = 'pagada' then 'pagada' else 'aprobada' end
                  || case when v_delta > 0 then ': se paga la diferencia' else ': la diferencia se descuenta de un pago siguiente' end;
    end if;

    if v_accion = 'revisar' and exists (
         select 1 from public.comisiones_diferencias x
          where x.devengo_id = r.id and x.estado = 'anulada' and x.importe_nuevo is not distinct from v_nuevo
            and x.resuelto_por is not null and x.resuelto_por <> 'sistema') then
      v_accion := 'descartada';
    end if;

    if v_accion <> 'nada' or v_dif.id is not null then
      devengo_id := r.id; venta := v_num; beneficiario := r.beneficiario_email; nivel := r.nivel;
      estado_devengo := r.estado; base_antes := v_base_antes; base_despues := v_base;
      vigente := v_vig; nuevo := v_nuevo; delta := v_delta;
      accion := case when v_accion = 'nada' then 'cierra_revisar' else v_accion end;
      motivo := v_motivo;
      return next;
    end if;
    continue when p_simular;

    perform set_config('app.via_recalculo_comision', 'on', true);

    if v_accion = 'nada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'la comisión vuelve a cuadrar sola con la base de hoy'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'actualizar' then
      update public.comisiones_devengadas d
         set importe = v_nuevo,
             disparado_por_snapshot = d.disparado_por_snapshot
               || jsonb_build_object('base_valor', v_base, 'precio_total', v_base,
                                     'recalculado_en', now(), 'recalculo_origen', p_origen,
                                     'importe_motor_original', coalesce(d.disparado_por_snapshot->'importe_motor_original', to_jsonb(r.importe)),
                                     'base_original', coalesce(d.disparado_por_snapshot->'base_original', d.disparado_por_snapshot->'base_valor'))
       where d.id = r.id;
      if v_sp.id is not null then
        update public.solicitudes_pago sp
           set importe = v_nuevo,
               concepto = case
                 when sp.concepto ~ '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}'
                   then regexp_replace(sp.concepto, '(a fecha de disparo|recalculada el [0-9-]+): [0-9.]+ [A-Z]{3}',
                                       'recalculada el ' || v_hoy || ': ' || round(v_base, 2) || ' ' || sp.moneda)
                 else sp.concepto || ' — recalculada el ' || v_hoy || ' sobre ' || round(v_base, 2) || ' ' || sp.moneda
               end
         where sp.id = v_sp.id;
      end if;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_devengadas', r.id, 'recalculo_auto', v_vig, v_nuevo, r.estado, r.estado,
              'cambio en el contrato: base ' || coalesce(round(v_base_antes, 2)::text, '?') || ' → ' || round(v_base, 2) || ' ' || r.moneda,
              jsonb_build_object('origen', p_origen, 'solicitud_id', v_sp.id));

    elsif v_accion = 'descartada' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'un administrador ya descartó este mismo importe'
         where id = v_dif.id;
      end if;

    elsif v_accion = 'revisar' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set importe = v_delta, importe_vigente = v_vig, importe_nuevo = v_nuevo,
               base_despues = v_base, motivo = v_motivo, origen = p_origen
         where id = v_dif.id;
      else
        insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                   motivo, estado, origen, provocado_por)
        values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'revisar', p_origen, nullif(v_yo, ''))
        returning id into v_dif_id;
        insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
        values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'revisar', v_motivo, jsonb_build_object('origen', p_origen));
      end if;

    elsif v_accion = 'diferencia' then
      if v_dif.id is not null then
        update public.comisiones_diferencias
           set estado = 'anulada', resuelto_por = 'sistema', resuelto_en = now(),
               resolucion_motivo = 'sustituida por una diferencia automática'
         where id = v_dif.id;
      end if;
      insert into public.comisiones_diferencias (devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues,
                                                 motivo, estado, origen, provocado_por)
      values (r.id, v_delta, v_vig, v_nuevo, v_base_antes, v_base, v_motivo, 'pendiente', p_origen, nullif(v_yo, ''))
      returning id into v_dif_id;
      insert into public.comisiones_ajustes_log (tabla, fila_id, accion, importe_antes, importe_despues, estado_antes, estado_despues, motivo, copia)
      values ('comisiones_diferencias', v_dif_id, 'diferencia', v_vig, v_nuevo, null, 'pendiente', v_motivo, jsonb_build_object('origen', p_origen));
      perform public._comision_diferencia_solicitud(v_dif_id);
    end if;

    perform set_config('app.via_recalculo_comision', 'off', true);
  end loop;
end $function$
;
CREATE OR REPLACE FUNCTION public.condiciones_comision_datos()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_co jsonb; v_nco int; v_tr jsonb; v_ntr int;
begin
  if public.uid_sesion() is null then
    raise exception 'condiciones_comision_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'equipo_id', c.equipo_id, 'proyecto_id', c.proyecto_id,
                                               'nivel', c.nivel, 'closer_email', c.closer_email,
                                               'pct_comision', c.pct_comision, 'base_calculo', c.base_calculo,
                                               'importe_fijo', c.importe_fijo, 'activo', c.activo,
                                               'vigente_desde', c.vigente_desde, 'vigente_hasta', c.vigente_hasta,
                                               'created_at', c.created_at, 'sustituye_a', c.sustituye_a,
                                               'empresa', c.empresa)
                            order by c.rn) filter (where c.rn <= 2000), '[]'::jsonb), count(*)::int
    into v_co, v_nco
    from (select x.id, x.equipo_id, x.proyecto_id, x.nivel, x.closer_email, x.pct_comision, x.base_calculo,
                 x.importe_fijo, x.activo, x.vigente_desde, x.vigente_hasta, x.created_at, x.sustituye_a, x.empresa,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.condiciones_comision x order by x.created_at desc, x.id limit 2001) c;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'condicion_id', t.condicion_id, 'orden', t.orden,
                                               'disparador_tipo', t.disparador_tipo, 'umbral', t.umbral,
                                               'pct_tramo', t.pct_tramo)
                            order by t.rn) filter (where t.rn <= 10000), '[]'::jsonb), count(*)::int
    into v_tr, v_ntr
    from (select x.id, x.condicion_id, x.orden, x.disparador_tipo, x.umbral, x.pct_tramo,
                 row_number() over (order by x.orden, x.id) as rn
            from public.condicion_tramos x order by x.orden, x.id limit 10001) t;
  return jsonb_build_object('condiciones', v_co, 'tramos', v_tr,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'condiciones' k where v_nco > 2000
                                            union all select 'tramos' where v_ntr > 10000) r));
end $function$
;
CREATE OR REPLACE FUNCTION public.comision_de_solicitud_datos(p_solicitud uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lista jsonb; v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'comision_de_solicitud_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('estado', x.estado, 'pagado_en', x.pagado_en, 'importe', x.importe,
                                               'importe_ajustado', x.importe_ajustado, 'moneda', x.moneda)), '[]'::jsonb),
         count(*)::int
    into v_lista, v_n
    from (select d.estado, d.pagado_en, d.importe, d.importe_ajustado, d.moneda
            from public.comisiones_devengadas d
           where d.solicitud_id = p_solicitud and d.nivel in ('manager', 'estandar', 'propia')
           limit 2) x;
  return jsonb_build_object('comision', case when v_n = 1 then v_lista -> 0 end);
end $function$
;
CREATE OR REPLACE FUNCTION public.comision_trazabilidad(p_devengo uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), '')); v_completa boolean;
  v_base numeric; v_operacion numeric; v_hay_obra boolean; v_pc numeric;
  v_por_firmar jsonb; v_suma_pend numeric; v_sin_obra numeric; v_es_total boolean; v_falta numeric;
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_yo = '' then raise exception 'Tu sesión no trae correo: no se puede ver la trazabilidad' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- F4: el criterio de entrada es comision_visible, el mismo que la RLS de comisiones_devengadas
  if not found or not public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id) then
    raise exception 'No encuentro esa comisión entre las que puedes ver' using errcode = '42501';
  end if;
  v_completa := public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))
                or (d.nivel in ('closer', 'setter', 'team_lead') and (
                      public.es_manager_de_equipo((select c.equipo_id from public.condiciones_comision c where c.id = d.condicion_id))
                   or public.es_manager_de_equipo((select k.equipo_id from public.contrato_closer k where k.contrato_id = d.contrato_raiz_id))));

  -- falta por firmar (12-oct-2026): lo que entraría en la base y aún no está firmado. Solo tiene sentido si la
  -- comisión se calcula sobre el precio total: es la única base que sube al firmar (el reconciliador salta las
  -- demás). Con otra base, falta = 0.
  v_base := public._comisiones_precio_total(d.contrato_raiz_id);
  v_suma_pend := 0; v_por_firmar := '[]'::jsonb;
  select c.base_calculo = 'precio_total' into v_es_total
    from public.condiciones_comision c where c.id = d.condicion_id;
  if coalesce(v_es_total, false) then
    -- un borrador por tipo (el más reciente) y ninguno si ya hay firmado otro de ese tipo; misma moneda
    select coalesce(jsonb_agg(jsonb_build_object('numero', p.numero, 'tipo', p.tipo, 'precio_total', p.precio_total,
                                                 'moneda', p.moneda) order by p.created_at), '[]'::jsonb),
           coalesce(sum(p.precio_total), 0)
      into v_por_firmar, v_suma_pend
      from (select distinct on (c.tipo) c.numero, c.tipo, c.precio_total, c.moneda, c.created_at
              from public.contratos c
             where (c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id)
               and not coalesce(c.bloqueado, false) and c.liberado_en is null
               and c.moneda is not distinct from d.moneda
               and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%')
               and not exists (select 1 from public.contratos s
                                where (s.id = d.contrato_raiz_id or s.contrato_padre_id = d.contrato_raiz_id)
                                  and s.tipo = c.tipo and coalesce(s.bloqueado, false) and s.liberado_en is null)
             order by c.tipo, c.created_at desc) p;
    select coalesce(sum(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0)), 0),
           coalesce(sum(coalesce(u.precio_construccion, 0)), 0)
      into v_operacion, v_pc
      from public.unidades u where u.contrato_id = d.contrato_raiz_id;
    v_hay_obra := exists (select 1 from public.contratos h
                           where h.contrato_padre_id = d.contrato_raiz_id
                             and h.tipo like 'construccion%' and h.liberado_en is null);
    -- la obra sin contrato solo si ni lo firmado ni lo pendiente llegan al precio de la parcela (no contar dos veces)
    v_sin_obra := case when v_pc > 0 and not v_hay_obra and v_base + v_suma_pend < v_operacion then v_pc end;
  end if;
  v_falta := v_suma_pend + coalesce(v_sin_obra, 0);

  return jsonb_build_object(
    'venta', d.contrato_raiz_id,
    'completa', v_completa,
    'base_hoy', v_base,
    -- quien no ve la operación completa solo sabe SI falta algo (sin cifras: con un solo contrato pendiente, la
    -- suma sería su precio, que el recorte de 050714 le oculta)
    'falta_algo', v_falta > 0,
    'por_firmar', case when v_completa then v_por_firmar else '[]'::jsonb end,
    'sin_contrato_obra', case when v_completa then v_sin_obra end,
    'falta_por_firmar', case when v_completa then v_falta end,
    'operacion', case when not v_completa then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'numero', c.numero, 'tipo', c.tipo, 'precio_total', c.precio_total, 'moneda', c.moneda,
               'firmado', coalesce(c.bloqueado, false), 'fecha_firma', c.fecha_firma,
               'liberado', c.liberado_en is not null, 'es_raiz', c.id = d.contrato_raiz_id,
               'cuenta_en_base', coalesce(c.bloqueado, false) and c.liberado_en is null
                                 and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%'))
             order by (c.id = d.contrato_raiz_id) desc, c.created_at), '[]'::jsonb)
        from public.contratos c
       where c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id) end,
    'parcelas', case when not v_completa then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object('codigo', u.codigo, 'proyecto', u.proyecto) order by u.codigo_orden, u.codigo), '[]'::jsonb)
        from public.unidades u where u.contrato_id = d.contrato_raiz_id) end,
    'solicitud', (
      select jsonb_build_object('numero', sp.numero, 'estado', sp.estado, 'importe', sp.importe, 'moneda', sp.moneda)
        from public.solicitudes_pago sp where sp.id = d.solicitud_id),
    'diferencias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', x.id, 'numero', x.numero, 'importe', x.importe, 'estado', x.estado, 'motivo', x.motivo,
               'base_antes', x.base_antes, 'base_despues', x.base_despues, 'vigente', x.importe_vigente,
               'nuevo', x.importe_nuevo,
               'origen', case when v_completa then x.origen
                              else jsonb_build_object('en', x.origen->'en', 'cambio', coalesce((
                                     select jsonb_agg(k.campo order by k.campo)
                                       from (values ('precio_total'), ('firmado'), ('padre'), ('tipo'), ('liberado'), ('moneda')) k(campo)
                                      where x.origen->k.campo->'antes' is distinct from x.origen->k.campo->'despues'
                                        and x.origen ? k.campo), '[]'::jsonb)) end,
               'provocado_por', case when v_completa then x.provocado_por end,
               'resuelto_por', case when v_completa then x.resuelto_por end,
               'resuelto_en', x.resuelto_en, 'resolucion_motivo', x.resolucion_motivo,
               'solicitud', (select jsonb_build_object('numero', sp.numero, 'estado', sp.estado)
                               from public.solicitudes_pago sp where sp.id = x.solicitud_id),
               'creada', x.created_at) order by x.created_at), '[]'::jsonb)
        from public.comisiones_diferencias x where x.devengo_id = d.id),
    'historial', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'en', l.creado_en, 'tabla', l.tabla, 'accion', l.accion, 'antes', l.importe_antes, 'despues', l.importe_despues,
               'estado_antes', l.estado_antes, 'estado_despues', l.estado_despues, 'motivo', l.motivo,
               'quien', case when v_completa then l.actor_email end)
             order by l.creado_en), '[]'::jsonb)
        from public.comisiones_ajustes_log l
       where (l.tabla = 'comisiones_devengadas' and l.fila_id = d.id)
          or (l.tabla = 'solicitudes_pago' and l.fila_id = d.solicitud_id)
          or (l.tabla = 'comisiones_diferencias' and l.fila_id in (select x.id from public.comisiones_diferencias x where x.devengo_id = d.id)))
  );
end
$function$
;
CREATE OR REPLACE FUNCTION public.comisiones_reparto_datos()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_de jsonb; v_nde int; v_di jsonb; v_ndi int;
begin
  if public.uid_sesion() is null then
    raise exception 'comisiones_reparto_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'contrato_raiz_id', d.contrato_raiz_id,
                                               'beneficiario_email', d.beneficiario_email, 'nivel', d.nivel,
                                               'importe', d.importe, 'importe_ajustado', d.importe_ajustado,
                                               'ajuste_motivo', d.ajuste_motivo, 'anulado_motivo', d.anulado_motivo,
                                               'moneda', d.moneda, 'estado', d.estado, 'disparado_en', d.disparado_en,
                                               'pagado_por', d.pagado_por, 'pagado_en', d.pagado_en,
                                               'disparado_por_snapshot', d.disparado_por_snapshot)
                            order by d.rn) filter (where d.rn <= 20000), '[]'::jsonb), count(*)::int
    into v_de, v_nde
    from (select x.id, x.contrato_raiz_id, x.beneficiario_email, x.nivel, x.importe, x.importe_ajustado, x.ajuste_motivo,
                 x.anulado_motivo, x.moneda, x.estado, x.disparado_en, x.pagado_por, x.pagado_en,
                 x.disparado_por_snapshot,
                 row_number() over (order by x.disparado_en desc, x.id) as rn
            from public.comisiones_devengadas x
           where x.nivel in ('closer', 'setter', 'team_lead')
           order by x.disparado_en desc, x.id limit 20001) d;
  -- el devengo de cada diferencia se lee con la RLS de comisiones_devengadas (como el embebido de PostgREST):
  -- si el lector no lo ve, sale null.
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'numero', f.numero, 'devengo_id', f.devengo_id,
                                               'importe', f.importe, 'estado', f.estado, 'motivo', f.motivo,
                                               'created_at', f.created_at,
                                               'devengo', case when f.d_id is not null then
                                                 jsonb_build_object('nivel', f.d_nivel,
                                                                    'beneficiario_email', f.d_benef,
                                                                    'contrato_raiz_id', f.d_raiz,
                                                                    'moneda', f.d_moneda) end)
                            order by f.rn) filter (where f.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_di, v_ndi
    from (select x.id, x.numero, x.devengo_id, x.importe, x.estado, x.motivo, x.created_at,
                 d.id as d_id, d.nivel as d_nivel, d.beneficiario_email as d_benef, d.contrato_raiz_id as d_raiz,
                 d.moneda as d_moneda,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.comisiones_diferencias x
            left join public.comisiones_devengadas d on d.id = x.devengo_id
           order by x.created_at desc, x.id limit 5001) f;
  return jsonb_build_object('devengadas', v_de, 'diferencias', v_di,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'devengadas' k where v_nde > 20000
                                            union all select 'diferencias' where v_ndi > 5000) r));
end $function$
;
CREATE OR REPLACE FUNCTION public._condicion_comision_guarda_en(p_id uuid, p_cond jsonb, p_tramos jsonb, p_motivo text, p_empresa text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_old    public.condiciones_comision%rowtype;
  v_prev   public.condiciones_comision%rowtype;
  v_id     uuid;
  v_nivel  text;
  v_equipo uuid;
  v_proy   uuid;
  v_closer text := nullif(lower(btrim(coalesce(p_cond->>'closer_email', ''))), '');
  v_pct    numeric;
  v_base   text := p_cond->>'base_calculo';
  v_fijo   numeric;
  v_desde  date;
  v_admin  boolean;
  v_emp    text;   -- LAW-483: el privilegio de admin lo da la casilla
  v_n      int := 0;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_hoy    date := (now() at time zone 'Asia/Makassar')::date;
  v_ult    date;
  v_pred   uuid;
  v_sust   uuid;
  v_conf   int;
  v_ventas int;
  v_d1     date;
  v_d2     date;
  v_cerrada boolean;
  v_tr_act jsonb;
  v_tr_new jsonb;
  v_cifras boolean;
  v_closer_nuevo text;
  v_alcance boolean;
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  begin
    v_pct   := (p_cond->>'pct_comision')::numeric;
    v_fijo  := case when v_base = 'importe_fijo' then (p_cond->>'importe_fijo')::numeric end;
    v_desde := coalesce(nullif(p_cond->>'vigente_desde', '')::date, v_hoy);
    v_conf  := nullif(p_cond->>'confirmar_ventas', '')::int;
  exception when others then
    raise exception 'Revisa las cifras: el %%, el importe fijo o la fecha no son válidos' using errcode = '22023';
  end;
  if v_pct is null or v_pct < 0 or v_pct > 100 then raise exception 'El %% de comisión va entre 0 y 100' using errcode = '22023'; end if;

  if p_id is null then
    v_equipo := nullif(p_cond->>'equipo_id', '')::uuid;
    v_proy   := nullif(p_cond->>'proyecto_id', '')::uuid;
    v_nivel  := case when v_equipo is null then 'closer' else coalesce(p_cond->>'nivel', 'closer') end;
    v_emp := coalesce(public.empresa_de_equipo(v_equipo), public._empresa_de_proyecto_int(v_proy), p_empresa);
    if v_emp is null then
      raise exception 'Falta la empresa de la condición (o el proyecto no tiene empresa)' using errcode = '22023';
    end if;
    v_admin := public.puede_reparto_de(v_emp);
    if not public._condicion_es_mia(v_nivel, v_equipo, v_emp) then
      raise exception 'Solo puedes crear condiciones para los closers, setters o team leads de tu equipo' using errcode = '42501';
    end if;
    if not v_admin then
      if v_desde < v_hoy then raise exception 'La fecha no puede ser anterior a hoy.' using errcode = '22023'; end if;
      if v_closer is not null and not public._closer_del_equipo(v_equipo, v_closer) then
        raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
      end if;
    end if;
    if v_nivel not in ('closer', 'setter', 'team_lead') then v_closer := null; end if;
    -- LAW-483 (tras anular v_closer en niveles que no lo usan): nadie se pone ni toca una condición a su propio favor (salvo super admin); ver _condicion_a_su_favor
    if not public.es_super_admin_de(v_emp) and public._condicion_a_su_favor(array[v_closer], v_nivel, v_equipo) then
      raise exception 'Nadie se pone ni cambia una condición de comisión a su propio favor' using errcode = '42501';
    end if;

    -- 3b: con inicio hoy o en el pasado (hoy cuenta como pasado), cuántas ventas ya hechas (sin devengar o a medio
    -- devengar) pueden pasar a esta condición. El SM no las mueve (ni confirmando); administración confirma el número.
    if v_desde <= v_hoy then
      v_ventas := public._condicion_ventas_afectadas(v_equipo, v_proy, v_nivel, v_closer, v_desde, v_hoy, v_emp);
      if v_ventas > 0 and not v_admin then
        raise exception 'Con inicio hoy, % venta(s) ya hechas hoy y sin comisión completa pasarían a esta condición: empieza mañana o pide a administración',
          v_ventas using errcode = '42501';
      end if;
      if v_ventas > 0 and v_conf is distinct from v_ventas then
        raise exception 'Con inicio el %, hasta % venta(s) ya hechas y sin comisión completa pueden pasar a esta condición: confírmalo con ese número',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas
          using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
      end if;
    end if;

    -- una condición nueva CIERRA sola la anterior del mismo alcance (vigente_hasta = nueva.desde − 1) y
    -- queda apuntándola en sustituye_a; ANTES del insert, que el índice único solo mira las abiertas
    for v_prev in
      select * from public.condiciones_comision c
       where c.equipo_id is not distinct from v_equipo and c.proyecto_id is not distinct from v_proy and c.empresa = v_emp
         and c.nivel = v_nivel and lower(coalesce(c.closer_email, '')) = coalesce(v_closer, '')
         and c.activo and c.vigente_hasta is null
       for update
    loop
      if v_desde - 1 < v_prev.vigente_desde then
        raise exception 'Ya hay una condición para ese mismo alcance desde el %: la nueva tiene que empezar después (o edita la que hay)',
          to_char(v_prev.vigente_desde, 'DD-MM-YYYY') using errcode = '23P01';
      end if;
      v_ult := public._condicion_ultima_venta_devengada(v_prev.id);
      if v_ult is not null and v_ult > v_desde - 1 then
        raise exception 'La condición que sustituyes ya ha cobrado comisión en una venta del %: la nueva tiene que empezar después de esa fecha',
          to_char(v_ult, 'DD-MM-YYYY') using errcode = '22023';
      end if;
      update public.condiciones_comision set activo = false, vigente_hasta = v_desde - 1 where id = v_prev.id;
      insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
      values (v_prev.id, jsonb_build_object('activo', true, 'vigente_hasta', null),
              jsonb_build_object('activo', false, 'vigente_hasta', v_desde - 1), 'cerrada por una condición nueva');
      v_sust := v_prev.id;
    end loop;

    insert into public.condiciones_comision (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo,
                                             importe_fijo, vigente_desde, created_by, sustituye_a, empresa)
    values (v_equipo, v_proy, v_nivel, v_closer, v_pct, v_base, v_fijo, v_desde, (select auth.email()), v_sust, v_emp)
    returning id into v_id;
    if public._condicion_solapa(v_id) is not null then
      raise exception 'Se pisa con una condición ya cerrada del mismo alcance: empieza la nueva después de su fecha de cierre' using errcode = '23P01';
    end if;
    perform public._condicion_tramos_pone(v_id, p_tramos);
    insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
    select v_id, null, to_jsonb(c) || jsonb_build_object('ventas_max', v_ventas), v_motivo
      from public.condiciones_comision c where c.id = v_id;
    return v_id;
  end if;

  select * into v_old from public.condiciones_comision c where c.id = p_id for update;
  v_emp := v_old.empresa;
  v_admin := public.puede_reparto_de(v_emp);
  if not found or not public._condicion_es_mia(v_old.nivel, v_old.equipo_id, v_old.empresa) then
    raise exception 'No encuentro esa condición entre las tuyas' using errcode = '42501';
  end if;
  if v_old.vigente_hasta is not null and v_desde > v_old.vigente_hasta then
    raise exception 'Esta condición está cerrada el %: su inicio no puede ser posterior a su cierre', to_char(v_old.vigente_hasta, 'DD-MM-YYYY') using errcode = '22023';
  end if;

  select count(*) into v_n from public.comisiones_devengadas d where d.condicion_id = p_id;
  v_cerrada := public._condicion_cerrada(p_id);

  -- ALCANCE (a quién se aplica: «todo el equipo» o una persona) = identidad de la condición, como equipo,
  -- proyecto y nivel, que ya no se editan. Cambiarlo en una condición empezada o cerrada cambia qué ventas
  -- ya hechas cobran con ella sin recuento, y en una sustituta deja al resto del alcance sin condición.
  -- Solo se cambia en una condición FUTURA (hoy Bali < inicio viejo y nuevo), sin devengos, que no sustituye
  -- a otra ni la sustituye ninguna y sin cierre. Por eso los recuentos de abajo pueden usar v_old.closer_email.
  v_closer_nuevo := case when v_old.nivel in ('closer', 'setter', 'team_lead') then v_closer else v_old.closer_email end;
  v_alcance := lower(coalesce(v_closer_nuevo, '')) is distinct from lower(coalesce(v_old.closer_email, ''));
  if v_alcance and not (v_old.vigente_desde > v_hoy and v_desde > v_hoy and v_n = 0
                        and v_old.sustituye_a is null and v_old.vigente_hasta is null
                        and not exists (select 1 from public.condiciones_comision s where s.sustituye_a = p_id)) then
    raise exception 'Para cambiar a quién se aplica, crea una condición nueva desde hoy' using errcode = '22023';
  end if;
  -- LAW-483: nadie se pone ni toca una condición a su propio favor (salvo super admin); ver _condicion_a_su_favor
  if not public.es_super_admin_de(v_emp) and public._condicion_a_su_favor(array[v_closer_nuevo, v_old.closer_email], v_old.nivel, v_old.equipo_id) then
    raise exception 'Nadie se pone ni cambia una condición de comisión a su propio favor' using errcode = '42501';
  end if;

  -- ¿cambian las cifras? (%, base, importe fijo o tramos; los tramos solo cuentan donde de verdad se guardan:
  -- sin devengos y sin cerrar, o cerrada, que es donde 3a los prohíbe)
  select coalesce(jsonb_agg(jsonb_build_array(t.disparador_tipo, t.umbral, t.pct_tramo) order by t.orden), '[]'::jsonb)
    into v_tr_act from public.condicion_tramos t where t.condicion_id = p_id;
  if p_tramos is null or jsonb_typeof(p_tramos) <> 'array' then
    v_tr_new := v_tr_act;
  else
    begin
      select coalesce(jsonb_agg(jsonb_build_array(x->>'disparador_tipo',
               case when (x->>'disparador_tipo') like 'pct_cobrado_%' then (x->>'umbral')::numeric end,
               (x->>'pct_tramo')::numeric) order by o), '[]'::jsonb)
        into v_tr_new from jsonb_array_elements(p_tramos) with ordinality y(x, o);
    exception when others then
      raise exception 'Revisa los tramos: alguna cifra no es válida' using errcode = '22023';
    end;
  end if;
  v_cifras := v_pct is distinct from v_old.pct_comision or v_base is distinct from v_old.base_calculo
              or v_fijo is distinct from v_old.importe_fijo
              or ((v_cerrada or v_n = 0) and v_tr_new is distinct from v_tr_act);

  -- 3a: las cifras de una condición cerrada no se tocan (tampoco sus tramos): se crea una nueva
  if v_cerrada and v_cifras then
    raise exception 'Esta condición está cerrada desde el %: sus cifras no se cambian. Crea una nueva desde la fecha que toque.',
      to_char(v_old.vigente_hasta, 'DD-MM-YYYY') using errcode = '22023';
  end if;

  -- 1: las cifras de una condición en vigor desde antes de hoy ya pesan sobre ventas hechas: el SM no las cambia
  if v_cifras and v_old.vigente_desde < v_hoy and not v_admin then
    raise exception 'Esta condición está en vigor desde el %: sus cifras no se cambian, crea una condición nueva desde hoy',
      to_char(v_old.vigente_desde, 'DD-MM-YYYY') using errcode = '42501';
  end if;

  if v_n > 0 then
    if not v_admin then
      raise exception 'Esta condición ya ha generado comisiones: no se cambian sus cifras. Ciérrala y crea una nueva.' using errcode = '22023';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Esta condición ya ha generado comisiones: escribe por qué cambias sus cifras (queda registrado)' using errcode = '22023';
    end if;
    if v_desde > v_old.vigente_desde then
      raise exception 'Esta condición ya ha generado comisiones: su fecha de vigencia no se puede adelantar (dejaría sin cobrar los tramos pendientes de ventas ya empezadas)' using errcode = '22023';
    end if;
    if v_base is distinct from v_old.base_calculo then
      raise exception 'Esta condición ya ha generado comisiones: su base de cálculo no se cambia. Ciérrala y crea una nueva.' using errcode = '22023';
    end if;
  end if;
  if not v_admin then
    if v_desde is distinct from v_old.vigente_desde and v_desde < v_hoy then
      raise exception 'la fecha de vigencia no puede quedar en el pasado' using errcode = '22023';
    end if;
    if v_alcance and v_closer_nuevo is not null and not public._closer_del_equipo(v_old.equipo_id, v_closer_nuevo) then
      raise exception 'Esa persona no está hoy en tu equipo' using errcode = '42501';
    end if;
  end if;

  -- 1: cifras nuevas en una condición en vigor desde hoy o antes (hoy cuenta como pasado) → recuento de ventas
  -- afectadas desde el inicio más temprano (viejo o nuevo) hasta su cierre o hoy. Cubre también un cambio de fecha a
  -- la vez. Aquí solo llega el SM con inicio HOY (antes de hoy ya lo paró el bloqueo de arriba): con ventas, rechazo.
  if v_cifras and v_old.vigente_desde <= v_hoy then
    v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email,
                  least(v_desde, v_old.vigente_desde), coalesce(v_old.vigente_hasta, v_hoy), v_old.empresa);
    if v_ventas > 0 and not v_admin then
      raise exception 'Esta condición empezó hoy y % venta(s) de hoy sin comisión completa cobran con ella: sus cifras no se cambian, empieza una nueva mañana o pide a administración',
        v_ventas using errcode = '42501';
    end if;
    if v_ventas > 0 and v_conf is distinct from v_ventas then
      raise exception 'Cambiar las cifras de esta condición (en vigor desde el %) afecta hasta a % venta(s) ya hechas sin comisión completa: confírmalo con ese número',
        to_char(v_old.vigente_desde, 'DD-MM-YYYY'), v_ventas
        using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
    end if;
  end if;

  if v_desde is distinct from v_old.vigente_desde then
    -- 3b: la frontera se mueve entre la fecha vieja y la nueva; las ventas ya hechas de ese tramo cambian de condición
    v_d1 := least(v_desde, v_old.vigente_desde);
    v_d2 := greatest(v_desde, v_old.vigente_desde) - 1;
    if v_d1 <= v_hoy and not (v_cifras and v_old.vigente_desde <= v_hoy) then
      v_ventas := public._condicion_ventas_afectadas(v_old.equipo_id, v_old.proyecto_id, v_old.nivel, v_old.closer_email, v_d1, v_d2, v_old.empresa);
      if v_ventas > 0 and not v_admin then
        raise exception 'Mover el inicio al % cambia de condición % venta(s) ya hechas y sin comisión completa: pídeselo a administración',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas using errcode = '42501';
      end if;
      if v_ventas > 0 and v_conf is distinct from v_ventas then
        raise exception 'Mover el inicio al % cambia de condición hasta % venta(s) ya hechas y sin comisión completa: confírmalo con ese número',
          to_char(v_desde, 'DD-MM-YYYY'), v_ventas
          using errcode = '22023', hint = 'lw-confirmar-ventas:' || v_ventas;
      end if;
    end if;

    -- sustituta sin devengos que cambia de fecha (futura o ya empezada): la que ella cerró se cierra el día
    -- antes de la fecha nueva, para que no quede ni hueco ni solape
    v_pred := v_old.sustituye_a;
    if v_pred is not null and v_n = 0 then
      select * into v_prev from public.condiciones_comision c where c.id = v_pred for update;
      if v_desde - 1 < v_prev.vigente_desde then
        raise exception 'Esta condición sustituye a otra que vale desde el %: tiene que empezar después',
          to_char(v_prev.vigente_desde, 'DD-MM-YYYY') using errcode = '23P01';
      end if;
      v_ult := public._condicion_ultima_venta_devengada(v_pred);
      if v_ult is not null and v_ult > v_desde - 1 then
        raise exception 'La condición a la que sustituye ya ha cobrado comisión en una venta del %: esta tiene que empezar después',
          to_char(v_ult, 'DD-MM-YYYY') using errcode = '22023';
      end if;
      update public.condiciones_comision set vigente_hasta = v_desde - 1 where id = v_pred;
      insert into public.condiciones_comision_log (condicion_id, antes, despues, motivo)
      values (v_pred, jsonb_build_object('vigente_hasta', v_prev.vigente_hasta), jsonb_build_object('vigente_hasta', v_desde - 1),
              'ajustada: su sustituta cambió de fecha');
    end if;
  end if;

  update public.condiciones_comision c
     set pct_comision = v_pct, base_calculo = v_base, importe_fijo = v_fijo, vigente_desde = v_desde,
         closer_email = case when v_alcance then v_closer_nuevo else c.closer_email end
   where c.id = p_id;
  if public._condicion_solapa(p_id) is not null then
    raise exception 'Con esa fecha se pisa con otra condición del mismo alcance' using errcode = '23P01';
  end if;
  if v_n = 0 and not v_cerrada then
    perform public._condicion_tramos_pone(p_id, p_tramos);
  end if;
  insert into public.condiciones_comision_log (condicion_id, antes, despues, con_devengos, motivo)
  select p_id, to_jsonb(v_old),
         to_jsonb(c) || jsonb_build_object('ventas_con_devengos',
           (select count(distinct d.contrato_raiz_id) from public.comisiones_devengadas d where d.condicion_id = p_id),
           'ventas_max', v_ventas),
         v_n > 0, v_motivo
    from public.condiciones_comision c where c.id = p_id;
  return p_id;
end $function$
;

-- (i) comprobaciones finales: todo como el 13-oct (md5 = bloque 0 de la migración; dueños y permisos = medidos ese día)
do $$
declare v record;
begin
  for v in select * from (values
      ('public.comisiones_evaluar_contrato(uuid)', '3ae27316aba2045428d5a763981c3f01', 'postgres', '{postgres=X/postgres,service_role=X/postgres}'),
      ('public.comisiones_reconciliar(uuid,boolean,jsonb)', '4d2bff43e2f47834e9a6c30334e6f3c7', 'postgres', '{postgres=X/postgres,service_role=X/postgres}'),
      ('public._condicion_tramos_pone(uuid,jsonb)', '1e0dfd064a1dc32955ab69e056ec1ec5', 'postgres', '{postgres=X/postgres,service_role=X/postgres}'),
      ('public.valida_suma_tramos_comision()', '11a246607c2097424f10dc6a140bbed1', 'postgres', '{postgres=X/postgres,service_role=X/postgres}'),
      ('public.condiciones_comision_datos()', 'c74355e79665c6dbada4b327d0c6156a', 'lw_lector', '{authenticated=X/lw_lector,lw_lector=X/lw_lector}'),
      ('public.mi_condicion_comision()', '07575d8e7d35e0f1902ee22374978441', 'postgres', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
      ('public.comision_trazabilidad(uuid)', 'ff6399cf578171a83ca5ce5ee996843d', 'postgres', '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'),
      ('public.comision_de_solicitud_datos(uuid)', '2a36889bfefc2cd46f2cd68907d84a43', 'lw_lector', '{authenticated=X/lw_lector,lw_lector=X/lw_lector}'),
      ('public.contrato_cobrado(uuid)', '644391725cb6a32f4ca6450f09b8abd7', 'postgres', '{postgres=X/postgres,service_role=X/postgres}'),
      ('public.comisiones_reparto_datos()', 'd7eb53f49eeb6ecc3ce425c9f49c2a2a', 'lw_lector', '{authenticated=X/lw_lector,lw_lector=X/lw_lector}'),
      ('public._condicion_comision_guarda_en(uuid,jsonb,jsonb,text,text)', '283a288773288a67e26215a7a9c8dbb7', 'postgres', '{postgres=X/postgres,service_role=X/postgres}')
    ) x(f, h, dueno, acl)
  loop
    if md5(pg_get_functiondef(v.f::regprocedure)) <> v.h then
      raise exception 'vuelta comisiones 1-nov: % no ha quedado como el 13-oct (md5)', v.f;
    end if;
    if (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = v.f::regprocedure) <> v.dueno
       or (select array_agg(a order by a collate "C")::text from pg_proc p, unnest(p.proacl::text[]) a where p.oid = v.f::regprocedure) <> v.acl then
      raise exception 'vuelta comisiones 1-nov: % tiene otro dueño o permisos que el 13-oct', v.f;
    end if;
  end loop;

  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('_contrato_cobrado_interno', '_comisiones_parte_obra', '_comisiones_bases_firmadas',
                                '_condicion_tramos_resumen', '_comision_vista_completa'))
     or exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'condicion_tramos' and column_name = 'base_calculo')
     or exists (select 1 from pg_trigger where tgrelid = 'public.condiciones_comision'::regclass
                 and tgname = 'condiciones_comision_tramos_suma')
     or exists (select 1 from public.condiciones_comision where id::text like 'c0a11010-1101-4a10-8000-0000000000%') then
    raise exception 'vuelta comisiones 1-nov: queda algo de la migración (función, columna, trigger o sucesora)';
  end if;

  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'condiciones_comision_base_calculo_check'
        and conrelid = 'public.condiciones_comision'::regclass)
       <> 'CHECK ((base_calculo = ANY (ARRAY[''precio_total''::text, ''precio_suelo''::text, ''precio_construccion''::text, ''importe_fijo''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'condicion_tramos_disparador_tipo_check'
        and conrelid = 'public.condicion_tramos'::regclass)
       <> 'CHECK ((disparador_tipo = ANY (ARRAY[''pct_cobrado_suelo''::text, ''pct_cobrado_obra''::text, ''pct_cobrado_total''::text, ''obra_firmada''::text, ''contrato_firmado''::text])))'
     or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'condicion_tramos_umbral_coherente'
        and conrelid = 'public.condicion_tramos'::regclass)
       <> 'CHECK ((((disparador_tipo = ANY (ARRAY[''obra_firmada''::text, ''contrato_firmado''::text])) AND (umbral IS NULL)) OR ((disparador_tipo = ANY (ARRAY[''pct_cobrado_suelo''::text, ''pct_cobrado_obra''::text, ''pct_cobrado_total''::text])) AND (umbral IS NOT NULL) AND (umbral >= (0)::numeric) AND (umbral <= (100)::numeric))))' then
    raise exception 'vuelta comisiones 1-nov: algún CHECK no ha quedado como el 13-oct';
  end if;
end $$;

commit;
