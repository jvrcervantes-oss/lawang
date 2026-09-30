-- PRUEBA — F2 del encargo equipos de venta (LAW-447 + modelo), 30-sep-2026.
-- Se ejecuta entera como postgres (MCP execute_sql o `supabase db query --linked -f`). NO ESCRIBE NADA: cada caso va
-- en un sub-bloque que acaba en excepcion (Postgres lo deshace) y el bloque entero termina en `raise exception 'RES: …'`.
--
-- LAW-447: dar de alta un miembro con `desde` en el pasado re-atribuia ventas viejas porque el equipo se buscaba a
-- `coalesce(fecha_venta, current_date)` (solo 13 de 188 ventas tienen fecha_venta). Tras el arreglo se busca a
-- `coalesce(fecha_venta, <contrato raiz>.created_at::date)`, la misma fecha que ya usaba el motor para la condicion
-- (desde 20260930034917, en hora de Bali y tambien para el equipo de las ventas no congeladas).
--
-- Casos (cada uno cuenta cuantas ventas cambian de equipo_id/manager_email; huella sobre esas columnas SOLO):
--   a · alta con desde = ayer                       -> tras el arreglo: 0 (antes: todas las del closer sin devengo)
--   h · alta con desde = hoy (la regla del SM, D6)  -> tras el arreglo: 0 salvo ventas creadas hoy
--   b · alta con desde ANTERIOR a su venta mas vieja -> SIGUE atribuyendo las ventas sin devengo creadas despues de
--       `desde`: es el diseño de `_equipo_recongela_sin_equipo` (alta retroactiva de admin). Choca con D7 si se lee
--       «ninguna venta pasada»: decision del owner, ver el informe de F2. La prueba lo MIDE, no lo da por bueno.
--   i · el indice unico de miembro activo rechaza una segunda fila activa de la misma persona (tras F2).
--   s · plantilla_reparto: suma distinta de 100 falla al cerrar; suma 100 pasa (tras F2).
--   m · (tras 20260930034917) para cada venta raiz SIN equipo, la condicion estandar a su fecha es: el override del
--       closer si lo tiene; si no, la 2,5 % si la venta es de hasta el 29-sep y la 10 % si es del 30-sep o posterior.
--   n · condicion estandar de una venta sin equipo del 30-sep -> 10 %; del 29-sep -> 2,5 %; el override (0 %) manda.
--   d · equipo_miembro_guarda: la misma persona dos veces en el MISMO equipo con fechas solapadas -> 23P01 «este equipo»
--       (antes pasaba el filtro y solo la paraba el indice unico con 23505); en otro equipo -> 23P01 «otro equipo».
-- Fechas: «hoy» es el dia de Bali (Asia/Makassar), como el ancla del motor desde 20260930034917; nunca current_date (UTC).
do $$
declare
  r text := ''; v_email text; v_eq uuid; v_antes jsonb; v_huella text; v_min date; v_n int; v_hoy int; v_t text;
  v_dia date := (now() at time zone 'Asia/Makassar')::date; v_uid uuid; v_adm text; v_carmen uuid; v_otro uuid;
  v_ovr text; v_pct numeric;
begin
  -- closer sin equipo activo con mas ventas sin devengo; equipo activo en el que no esta
  select lower(k.closer_email) into v_email
    from public.contrato_closer k
   where not exists (select 1 from public.comisiones_devengadas d where d.contrato_raiz_id = k.contrato_id)
     and not exists (select 1 from public.equipo_miembros em where lower(em.closer_email) = lower(k.closer_email) and em.hasta is null)
     and exists (select 1 from public.usuarios u where lower(u.email) = lower(k.closer_email))
   group by 1 order by count(*) desc, 1 limit 1;
  if v_email is null then raise exception 'RES: sin closer candidato (sin equipo activo y con ventas sin devengo)'; end if;
  select ev.id into v_eq from public.equipos_venta ev
   where ev.activo and not exists (select 1 from public.equipo_miembros em where em.equipo_id = ev.id and lower(em.closer_email) = v_email)
   order by ev.created_at limit 1;
  select min(coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date)) into v_min
    from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
   where lower(k.closer_email) = v_email;
  select count(*) into v_hoy
    from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
   where lower(k.closer_email) = v_email and coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date) >= v_dia;

  select jsonb_object_agg(k.contrato_id::text, coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, '')),
         md5(string_agg(k.contrato_id::text || '|' || coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, ''), ';' order by k.contrato_id))
    into v_antes, v_huella
    from public.contrato_closer k;
  r := r || 'closer=' || split_part(v_email, '@', 1) || ' min=' || v_min || ' ventas_hoy=' || v_hoy || '; ';

  -- a · desde = ayer
  begin
    insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, v_dia - 1, 'prueba_f2');
    select count(*) into v_n from public.contrato_closer k
     where v_antes ->> k.contrato_id::text is distinct from coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, '');
    raise exception '%', v_n;
  exception when others then r := r || 'a ayer cambia=' || sqlerrm || case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end; end;

  -- h · desde = hoy
  begin
    insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, v_dia, 'prueba_f2');
    select count(*) into v_n from public.contrato_closer k
     where v_antes ->> k.contrato_id::text is distinct from coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, '');
    raise exception '%', v_n;
  exception when others then r := r || 'h hoy cambia=' || sqlerrm || case when sqlerrm = v_hoy::text then ' ok; ' else ' FALLO; ' end; end;

  -- b · desde anterior a la venta mas vieja (mide, no aprueba)
  begin
    insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, v_min - 1, 'prueba_f2');
    select count(*) into v_n from public.contrato_closer k
     where v_antes ->> k.contrato_id::text is distinct from coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, '');
    raise exception '%', v_n;
  exception when others then r := r || 'b retroactiva cambia=' || sqlerrm || ' (medida); '; end;

  -- i · indice unico de miembro activo
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'equipo_miembros_un_equipo_activo') then
    begin
      insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, v_dia, 'prueba_f2');
      insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, upper(v_email), v_dia, 'prueba_f2');
      raise exception 'entro';
    exception when unique_violation then r := r || 'i unico ok; ';
              when others then r := r || 'i unico FALLO ' || sqlerrm || '; '; end;
  end if;

  -- s · plantilla_reparto suma 100
  if to_regclass('public.plantilla_reparto') is not null then
    begin
      insert into public.plantilla_reparto (equipo_id, rol_tipo, rol_nombre, pct) values (v_eq, 'closer', 'Closer', 60);
      execute 'set constraints all immediate';
      raise exception 'entro';
    exception when others then r := r || 's suma60 ' || case when sqlerrm like '%100%' then 'rechaza ok; ' else 'FALLO ' || sqlerrm || '; ' end; end;
    begin
      insert into public.plantilla_reparto (equipo_id, rol_tipo, rol_nombre, pct) values (v_eq, 'closer', 'Closer', 60), (v_eq, 'setter', 'Setter', 40);
      execute 'set constraints all immediate';
      raise exception 'paso';
    exception when others then r := r || 's suma100 ' || case when sqlerrm = 'paso' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end; end;
  end if;

  -- m · condicion estandar por fecha para las ventas raiz sin equipo (misma consulta que el motor, nivel 'estandar')
  with v as (
    select k.contrato_id as raiz, lower(k.closer_email) as closer, c.proyecto_id as pr,
           coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date) as f,
           case when k.equipo_congelado_en is not null then k.equipo_id
                else (select em.equipo_id from public.equipo_miembros em join public.equipos_venta ev on ev.id = em.equipo_id
                       where lower(em.closer_email) = lower(k.closer_email) and ev.activo
                         and em.desde <= coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date)
                         and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, (c.created_at at time zone 'Asia/Makassar')::date))
                       order by em.created_at desc limit 1) end as eq
      from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
     where c.contrato_padre_id is null
  ), picks as (
    select v.raiz, v.f, v.closer,
      (select c.id from public.condiciones_comision c where c.equipo_id is null and c.nivel = 'closer' and (c.activo or c.vigente_hasta is not null)
          and c.vigente_desde <= v.f and (c.vigente_hasta is null or c.vigente_hasta >= v.f)
          and (c.proyecto_id = v.pr or c.proyecto_id is null) and (c.closer_email is null or lower(c.closer_email) = v.closer)
        order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id limit 1) as elegida
      from v where v.eq is null
  )
  select count(*) filter (where
           p.elegida is distinct from coalesce(
             (select o.id from public.condiciones_comision o where o.equipo_id is null and o.nivel = 'closer' and o.activo
                 and lower(o.closer_email) = p.closer and o.vigente_desde <= p.f and (o.vigente_hasta is null or o.vigente_hasta >= p.f) limit 1),
             (select e.id from public.condiciones_comision e where e.equipo_id is null and e.nivel = 'closer' and e.closer_email is null
                 and e.proyecto_id is null and e.pct_comision = case when p.f >= date '2026-09-30' then 10 else 2.5 end
                 and e.vigente_desde <= p.f and (e.vigente_hasta is null or e.vigente_hasta >= p.f) limit 1))),
         count(*)
    into v_n, v_hoy from picks p;
  r := r || 'm estandar por fecha distintas=' || v_n || ' de ' || v_hoy || case when v_n = 0 then ' ok; ' else ' FALLO; ' end;

  -- n · estandar de una venta sin equipo segun su fecha (sin override) y override que manda
  select c.pct_comision into v_pct from public.condiciones_comision c
   where c.equipo_id is null and c.nivel = 'closer' and (c.activo or c.vigente_hasta is not null)
     and c.vigente_desde <= date '2026-09-30' and (c.vigente_hasta is null or c.vigente_hasta >= date '2026-09-30')
     and c.proyecto_id is null and c.closer_email is null
   order by c.vigente_desde desc, c.created_at desc, c.id limit 1;
  r := r || 'n 30-sep=' || coalesce(v_pct::text, 'ninguna') || case when v_pct = 10 then ' ok; ' else ' FALLO; ' end;
  select c.pct_comision into v_pct from public.condiciones_comision c
   where c.equipo_id is null and c.nivel = 'closer' and (c.activo or c.vigente_hasta is not null)
     and c.vigente_desde <= date '2026-09-29' and (c.vigente_hasta is null or c.vigente_hasta >= date '2026-09-29')
     and c.proyecto_id is null and c.closer_email is null
   order by c.vigente_desde desc, c.created_at desc, c.id limit 1;
  r := r || 'n 29-sep=' || coalesce(v_pct::text, 'ninguna') || case when v_pct = 2.5 then ' ok; ' else ' FALLO; ' end;
  select lower(o.closer_email) into v_ovr from public.condiciones_comision o
   where o.equipo_id is null and o.nivel = 'closer' and o.closer_email is not null and o.activo and o.vigente_hasta is null
   order by o.created_at limit 1;
  if v_ovr is not null then
    select c.pct_comision into v_pct from public.condiciones_comision c
     where c.equipo_id is null and c.nivel = 'closer' and (c.activo or c.vigente_hasta is not null)
       and c.vigente_desde <= date '2026-09-30' and (c.vigente_hasta is null or c.vigente_hasta >= date '2026-09-30')
       and c.proyecto_id is null and (c.closer_email is null or lower(c.closer_email) = v_ovr)
     order by (c.closer_email is not null) desc, c.vigente_desde desc, c.created_at desc, c.id limit 1;
    r := r || 'n override ' || split_part(v_ovr, '@', 1) || '=' || v_pct
      || case when v_pct = (select o.pct_comision from public.condiciones_comision o
                             where lower(o.closer_email) = v_ovr and o.equipo_id is null and o.activo limit 1) then ' ok; ' else ' FALLO; ' end;
  end if;

  -- d · solape en el mismo equipo y en otro, como un admin (auth.uid() de un super_admin que no es el miembro)
  select u.user_id, lower(u.email) into v_uid, v_adm from public.usuarios u where u.rol = 'super_admin' and u.activo order by u.email limit 1;
  select em.equipo_id, lower(em.closer_email) into v_carmen, v_t
    from public.equipo_miembros em join public.equipos_venta ev on ev.id = em.equipo_id
   where em.hasta is null and ev.activo and lower(em.closer_email) <> v_adm and public._usuario_activo(lower(em.closer_email))
   order by em.created_at limit 1;
  select ev.id into v_otro from public.equipos_venta ev where ev.activo and ev.id <> v_carmen order by ev.created_at limit 1;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'email', v_adm, 'role', 'authenticated')::text, true);
    perform public.equipo_miembro_guarda(null, v_carmen, v_t, v_dia, null);
    raise exception 'entro';
  exception when others then
    r := r || 'd mismo equipo ' || case when sqlstate = '23P01' and sqlerrm like '%este equipo%' then 'ok; ' else 'FALLO ' || sqlstate || ' ' || sqlerrm || '; ' end;
  end;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'email', v_adm, 'role', 'authenticated')::text, true);
    perform public.equipo_miembro_guarda(null, v_otro, v_t, v_dia, null);
    raise exception 'entro';
  exception when others then
    r := r || 'd otro equipo ' || case when sqlstate = '23P01' and sqlerrm like '%otro equipo%' then 'ok; ' else 'FALLO ' || sqlstate || ' ' || sqlerrm || '; ' end;
  end;

  -- la huella no se ha movido (los sub-bloques se deshicieron)
  select md5(string_agg(k.contrato_id::text || '|' || coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, ''), ';' order by k.contrato_id))
    into v_t from public.contrato_closer k;
  r := r || 'huella intacta=' || (v_t = v_huella);
  raise exception 'RES: %', r;
end $$;
