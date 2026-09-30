-- PRUEBA — F2 del encargo equipos de venta (LAW-447 + modelo), 30-sep-2026.
-- Se ejecuta entera como postgres (MCP execute_sql o `supabase db query --linked -f`). NO ESCRIBE NADA: cada caso va
-- en un sub-bloque que acaba en excepcion (Postgres lo deshace) y el bloque entero termina en `raise exception 'RES: …'`.
--
-- LAW-447: dar de alta un miembro con `desde` en el pasado re-atribuia ventas viejas porque el equipo se buscaba a
-- `coalesce(fecha_venta, current_date)` (solo 13 de 188 ventas tienen fecha_venta). Tras el arreglo se busca a
-- `coalesce(fecha_venta, <contrato raiz>.created_at::date)`, la misma fecha que ya usaba el motor para la condicion.
--
-- Casos (cada uno cuenta cuantas ventas cambian de equipo_id/manager_email; huella sobre esas columnas SOLO):
--   a · alta con desde = ayer                       -> tras el arreglo: 0 (antes: todas las del closer sin devengo)
--   h · alta con desde = hoy (la regla del SM, D6)  -> tras el arreglo: 0 salvo ventas creadas hoy
--   b · alta con desde ANTERIOR a su venta mas vieja -> SIGUE atribuyendo las ventas sin devengo creadas despues de
--       `desde`: es el diseño de `_equipo_recongela_sin_equipo` (alta retroactiva de admin). Choca con D7 si se lee
--       «ninguna venta pasada»: decision del owner, ver el informe de F2. La prueba lo MIDE, no lo da por bueno.
--   i · el indice unico de miembro activo rechaza una segunda fila activa de la misma persona (tras F2).
--   s · plantilla_reparto: suma distinta de 100 falla al cerrar; suma 100 pasa (tras F2).
--   m · el motor elige la misma condicion que antes para todas las ventas (sin condiciones con vigente_hasta).
do $$
declare
  r text := ''; v_email text; v_eq uuid; v_antes jsonb; v_huella text; v_min date; v_n int; v_hoy int; v_t text;
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
  select min(rz.created_at::date) into v_min
    from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
   where lower(k.closer_email) = v_email;
  select count(*) into v_hoy
    from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
   where lower(k.closer_email) = v_email and rz.created_at::date >= current_date;

  select jsonb_object_agg(k.contrato_id::text, coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, '')),
         md5(string_agg(k.contrato_id::text || '|' || coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, ''), ';' order by k.contrato_id))
    into v_antes, v_huella
    from public.contrato_closer k;
  r := r || 'closer=' || split_part(v_email, '@', 1) || ' min=' || v_min || ' ventas_hoy=' || v_hoy || '; ';

  -- a · desde = ayer
  begin
    insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, current_date - 1, 'prueba_f2');
    select count(*) into v_n from public.contrato_closer k
     where v_antes ->> k.contrato_id::text is distinct from coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, '');
    raise exception '%', v_n;
  exception when others then r := r || 'a ayer cambia=' || sqlerrm || case when sqlerrm = '0' then ' ok; ' else ' FALLO; ' end; end;

  -- h · desde = hoy
  begin
    insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, current_date, 'prueba_f2');
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
      insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, v_email, current_date, 'prueba_f2');
      insert into public.equipo_miembros (equipo_id, closer_email, desde, added_by) values (v_eq, upper(v_email), current_date, 'prueba_f2');
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

  -- m · paridad del motor: para cada venta raiz y cada nivel que el motor prueba, la condicion que elige el filtro
  --     NUEVO (vigencia + orden por vigente_desde) es la misma que elegia el VIEJO (activo, sin orden). Sin efectos.
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'condiciones_comision' and column_name = 'vigente_hasta') then
    with v as (
      select k.contrato_id as raiz, lower(k.closer_email) as closer, c.proyecto_id as pr,
             coalesce(k.fecha_venta, c.created_at::date) as f,
             case when k.equipo_congelado_en is not null then k.equipo_id
                  else (select em.equipo_id from public.equipo_miembros em join public.equipos_venta ev on ev.id = em.equipo_id
                         where lower(em.closer_email) = lower(k.closer_email) and ev.activo
                           and em.desde <= coalesce(k.fecha_venta, current_date)
                           and (em.hasta is null or em.hasta >= coalesce(k.fecha_venta, current_date))
                         order by em.created_at desc limit 1) end as eq
        from public.contrato_closer k join public.contratos c on c.id = k.contrato_id
       where c.contrato_padre_id is null
    ), picks as (
      -- estandar (sin equipo)
      select v.raiz, 'estandar' as nivel,
        (select c.id from public.condiciones_comision c where c.equipo_id is null and c.nivel = 'closer' and c.activo and c.vigente_desde <= v.f
            and (c.proyecto_id = v.pr or c.proyecto_id is null) and (c.closer_email is null or lower(c.closer_email) = v.closer)
          order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc limit 1) as viejo,
        (select c.id from public.condiciones_comision c where c.equipo_id is null and c.nivel = 'closer' and (c.activo or c.vigente_hasta is not null)
            and c.vigente_desde <= v.f and (c.vigente_hasta is null or c.vigente_hasta >= v.f)
            and (c.proyecto_id = v.pr or c.proyecto_id is null) and (c.closer_email is null or lower(c.closer_email) = v.closer)
          order by (c.closer_email is not null) desc, (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id limit 1) as nuevo
        from v where v.eq is null
      union all
      -- manager
      select v.raiz, 'manager',
        (select c.id from public.condiciones_comision c where c.equipo_id = v.eq and (c.proyecto_id = v.pr or c.proyecto_id is null) and c.nivel = 'manager'
            and c.activo and c.vigente_desde <= v.f and c.closer_email is null order by (c.proyecto_id is not null) desc limit 1),
        (select c.id from public.condiciones_comision c where c.equipo_id = v.eq and (c.proyecto_id = v.pr or c.proyecto_id is null) and c.nivel = 'manager'
            and (c.activo or c.vigente_hasta is not null) and c.vigente_desde <= v.f and (c.vigente_hasta is null or c.vigente_hasta >= v.f)
            and c.closer_email is null order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id limit 1)
        from v where v.eq is not null
      union all
      -- closer (primero la del closer concreto, si no la generica)
      select v.raiz, 'closer',
        coalesce(
          (select c.id from public.condiciones_comision c where c.equipo_id = v.eq and (c.proyecto_id = v.pr or c.proyecto_id is null) and c.nivel = 'closer'
              and c.activo and c.vigente_desde <= v.f and lower(c.closer_email) = v.closer order by (c.proyecto_id is not null) desc limit 1),
          (select c.id from public.condiciones_comision c where c.equipo_id = v.eq and (c.proyecto_id = v.pr or c.proyecto_id is null) and c.nivel = 'closer'
              and c.activo and c.vigente_desde <= v.f and c.closer_email is null order by (c.proyecto_id is not null) desc limit 1)),
        coalesce(
          (select c.id from public.condiciones_comision c where c.equipo_id = v.eq and (c.proyecto_id = v.pr or c.proyecto_id is null) and c.nivel = 'closer'
              and (c.activo or c.vigente_hasta is not null) and c.vigente_desde <= v.f and (c.vigente_hasta is null or c.vigente_hasta >= v.f)
              and lower(c.closer_email) = v.closer order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id limit 1),
          (select c.id from public.condiciones_comision c where c.equipo_id = v.eq and (c.proyecto_id = v.pr or c.proyecto_id is null) and c.nivel = 'closer'
              and (c.activo or c.vigente_hasta is not null) and c.vigente_desde <= v.f and (c.vigente_hasta is null or c.vigente_hasta >= v.f)
              and c.closer_email is null order by (c.proyecto_id is not null) desc, c.vigente_desde desc, c.created_at desc, c.id limit 1))
        from v where v.eq is not null
    )
    select count(*) filter (where viejo is distinct from nuevo), count(*) into v_n, v_hoy from picks;
    r := r || 'm motor distintas=' || v_n || ' de ' || v_hoy || case when v_n = 0 then ' ok; ' else ' FALLO; ' end;
  end if;

  -- la huella no se ha movido (los sub-bloques se deshicieron)
  select md5(string_agg(k.contrato_id::text || '|' || coalesce(k.equipo_id::text, '') || '|' || coalesce(k.manager_email, ''), ';' order by k.contrato_id))
    into v_t from public.contrato_closer k;
  r := r || 'huella intacta=' || (v_t = v_huella);
  raise exception 'RES: %', r;
end $$;
