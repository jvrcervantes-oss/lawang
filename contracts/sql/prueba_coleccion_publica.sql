-- destructivo-ok: modifica filas y añade una columna de prueba (alter table … add column) en fichas_publicas y escribe en config_instancia dentro de una transacción que SIEMPRE acaba en rollback por `raise exception`; no queda nada.
-- PRUEBA — coleccion_publica() (The Collection v2 · F5b, 2-oct-2026). Cubre 20261002150000_thecollection_coleccion_publica.sql.
-- Se ejecuta DESPUÉS de aplicar la migración, con execute_sql (MCP) o psql como postgres, UN BLOQUE: acaba en
-- `raise exception 'RES: …'`, que revierte la transacción entera y enseña el resultado: NO ESCRIBE NADA.
-- Cada punto debe decir «ok»; «FALLO» es un agujero o una regresión; «omitido» = el caso no se pudo montar (se explica), no es un ok.
-- Estilo de prueba_ficha_publica.sql. Cada execute_sql es su propia sesión: todo va en este bloque.
-- Los casos de dinero comparan con el cálculo INDEPENDIENTE escrito aquí otra vez a propósito (si la RPC y la prueba coinciden por
-- construcción no prueban nada); el de las claves usa una COPIA de la lista blanca de coleccion/contrato_publico.json → ficha: si
-- esa lista cambia hay que actualizar esta copia (coleccion/tests/coleccion_test.php vigila el contrato; esto vigila la base).
do $t$
declare
  r text := '';
  res jsonb; res2 jsonb;
  n int; n2 int; v text; v2 numeric;
  blanca text[] := array['id','line','region','regionKey','featured','status','tenure','leaseYears','handover','visible','inCollection',
    'homeFeatured','showExtras','showHomeModels','showLandOptions','title','sub','desc','metaText','splitTitle','splitSub','highlights',
    'tabs','techSpecs','beds','baths','built','land','pool','poolType','garage','garageDesc','furnished','style','view','priceEUR',
    'priceMode','nightlyRate','paymentPlan','unitsAvailable','unitsTotal','images','videos','aerial','logo','isotype','landColor',
    'splitImage','bleedImage','plan3dImage','mapImage','masterplanImage','masterplanPlots','masterplanProject','downloads',
    'landOptions','homeModels','extras','parcelas'];
begin
  -- (a) permisos: anon sí; nadie más; el auxiliar, para nadie; ninguna tabla de la ficha legible por anon/authenticated
  r := r || case when has_function_privilege('anon', 'public.coleccion_publica()', 'execute') then 'a1 ok; ' else 'a1 FALLO anon no puede; ' end;
  r := r || case when not has_function_privilege('authenticated', 'public.coleccion_publica()', 'execute')
                  and not has_function_privilege('service_role', 'public.coleccion_publica()', 'execute') then 'a2 ok; ' else 'a2 FALLO execute de más; ' end;
  r := r || case when not has_function_privilege('anon', 'public._coleccion_a_eur(numeric,text)', 'execute')
                  and not has_function_privilege('authenticated', 'public._coleccion_a_eur(numeric,text)', 'execute')
                  and not has_function_privilege('service_role', 'public._coleccion_a_eur(numeric,text)', 'execute') then 'a3 ok; ' else 'a3 FALLO el auxiliar es ejecutable; ' end;
  r := r || case when not has_table_privilege('anon', 'public.fichas_publicas', 'select') and not has_table_privilege('authenticated', 'public.fichas_publicas', 'select')
                  and not has_table_privilege('anon', 'public.fichas_publicas_log', 'select') then 'a4 ok; ' else 'a4 FALLO tabla legible; ' end;
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'coleccion_publica' and p.prosecdef and p.provolatile = 's' and p.pronargs = 0
     and coalesce(p.proconfig::text, '') like '%search_path%';
  r := r || case when n = 1 then 'a5 ok (definer, stable, sin parámetros, search_path fijo); ' else 'a5 FALLO ficha de la función; ' end;

  -- (b) forma, llamada COMO anon
  set local role anon;
  res := public.coleccion_publica();
  reset role;
  r := r || case when jsonb_typeof(res->'properties') = 'array' and res ? 'generated_at'
                  and (select count(*) from jsonb_object_keys(res)) = 2 then 'b1 ok; ' else 'b1 FALLO forma {properties, generated_at}; ' end;

  -- (c) claves: solo la lista blanca en cada ficha, y ninguna prohibida a NINGUNA profundidad
  select count(*) into n from jsonb_array_elements(res->'properties') p, jsonb_object_keys(p) k where k <> all (blanca);
  r := r || case when n = 0 then 'c1 ok; ' else 'c1 FALLO ' || n || ' claves fuera de la lista blanca; ' end;
  select count(*) into n from jsonb_path_query(res, 'strict $.** ? (@.type() == "object")') o, jsonb_object_keys(o) k
   where lower(k) in ('notas', 'contrato_id', 'iban', 'email', 'comprador', 'agente', 'precio_suelo', 'precio_construccion')
      or lower(k) like 'cuota%' or lower(k) like 'comision%';
  r := r || case when n = 0 then 'c2 ok; ' else 'c2 FALLO ' || n || ' claves prohibidas; ' end;

  -- (d) solo fichas publicadas con proyecto: todas las filas que cumplen, y ninguna más
  select count(*) into n from public.fichas_publicas f join public.proyectos p on p.id = f.proyecto_id where f.publicada_web and coalesce(p.activo, true);
  r := r || case when jsonb_array_length(res->'properties') = n and n > 0 then 'd1 ok (' || n || ' fichas); ' else 'd1 FALLO esperaba ' || n || ' y salen ' || jsonb_array_length(res->'properties') || '; ' end;
  select count(*) into n from jsonb_array_elements(res->'properties') p join public.fichas_publicas f on f.slug = p->>'id' where not f.publicada_web;
  r := r || case when n = 0 then 'd2 ok; ' else 'd2 FALLO sirve ' || n || ' no publicadas; ' end;

  -- (e) LAW-489: una ficha publicada que pierde su proyecto deja de servirse
  select count(*) into n from jsonb_array_elements(res->'properties') p where p->>'id' = 'cube';
  update public.fichas_publicas set proyecto_id = null where slug = 'cube';
  set local role anon; res2 := public.coleccion_publica(); reset role;
  select count(*) into n2 from jsonb_array_elements(res2->'properties') p where p->>'id' = 'cube';
  r := r || case when n = 1 and n2 = 0 then 'e1 ok (cube desaparece sin proyecto); ' else 'e1 FALLO (antes ' || n || ', después ' || n2 || '); ' end;
  update public.fichas_publicas set proyecto_id = (select id from public.proyectos where slug = 'cube') where slug = 'cube';

  -- (f) una columna nueva en fichas_publicas, o un dato interno de unidades/contratos, NO aparece
  alter table public.fichas_publicas add column zz_secreto text;
  update public.fichas_publicas set zz_secreto = 'SECRETO_ZZ_F5B_COLUMNA' where slug in ('cube', 'palm-field-bali');
  set local role anon; res2 := public.coleccion_publica(); reset role;
  r := r || case when res2::text not like '%SECRETO_ZZ_F5B_COLUMNA%' and res2::text not like '%zz_secreto%' then 'f1 ok; ' else 'f1 FALLO la columna nueva sale; ' end;
  select count(*) into n from public.unidades u
   where u.contrato_id is not null and res::text like '%' || u.contrato_id::text || '%';
  select count(*) into n2 from public.unidades u join public.proyectos p on p.id = u.proyecto_id
   where char_length(coalesce(u.notas, '')) >= 12 and res::text like '%' || replace(u.notas, '"', '') || '%';
  r := r || case when n = 0 and n2 = 0 then 'f2 ok (ni contrato_id ni notas de unidades); ' else 'f2 FALLO contrato_id ' || n || ', notas ' || n2 || '; ' end;

  -- (g) estado de parcela: mapeo del owner, comparado con unidades
  select count(*) into n from jsonb_array_elements(res->'properties') p
    join public.fichas_publicas f on f.slug = p->>'id'
    cross join lateral jsonb_array_elements(p->'parcelas') q
    join public.unidades u on u.proyecto_id = f.proyecto_id and u.codigo = q->>'codigo' and (f.unidad_id is null or u.id = f.unidad_id)
   where q->>'estado' is distinct from case u.estado when 'disponible' then 'disponible' when 'reservada' then 'reservada'
                                                  when 'vendida' then 'vendida' when 'cobrada' then 'vendida'
                                                  when 'bloqueada' then 'vendida' when 'no_disponible' then 'vendida' end;
  select count(*) into n2 from jsonb_array_elements(res->'properties') p, jsonb_array_elements(p->'parcelas') q
   where q->>'estado' not in ('disponible', 'reservada', 'vendida');
  r := r || case when n = 0 and n2 = 0 then 'g1 ok; ' else 'g1 FALLO mapeo (' || n || ' distintas, ' || n2 || ' valores fuera de los 3); ' end;
  select count(*) into n from jsonb_array_elements(res->'properties') p, jsonb_array_elements(p->'parcelas') q, jsonb_object_keys(q) k
   where k not in ('codigo', 'superficie_m2', 'estado');
  r := r || case when n = 0 then 'g2 ok (solo codigo, superficie_m2, estado); ' else 'g2 FALLO parcela con claves de más; ' end;
  -- mutación por estado (si un trigger de unidades lo impide, se anota «omitido»: no vale como ok)
  declare v_est text; v_cod text; v_proy uuid; v_ant text; v_res text;
  begin
    select u.id::text, u.codigo, u.proyecto_id, u.estado into v, v_cod, v_proy, v_ant
      from public.unidades u where u.proyecto_id = (select proyecto_id from public.fichas_publicas where slug = 'palm-field-bali') and u.estado = 'disponible' limit 1;
    foreach v_est in array array['no_disponible', 'bloqueada', 'cobrada', 'reservada'] loop
      begin
        update public.unidades set estado = v_est where id = v::uuid;
        set local role anon; res2 := public.coleccion_publica(); reset role;
        select q->>'estado' into v_res from jsonb_array_elements(res2->'properties') p, jsonb_array_elements(p->'parcelas') q
         where p->>'id' = 'palm-field-bali' and q->>'codigo' = v_cod;
        r := r || case when (v_est = 'reservada' and v_res = 'reservada') or (v_est <> 'reservada' and v_res = 'vendida') then 'g3-' || v_est || ' ok; '
                       else 'g3-' || v_est || ' FALLO sale ' || coalesce(v_res, 'nada') || '; ' end;
      exception when others then r := r || 'g3-' || v_est || ' omitido (' || sqlstate || ' ' || left(sqlerrm, 60) || '); '; reset role;
      end;
    end loop;
  exception when others then r := r || 'g3 omitido (' || sqlstate || ' ' || left(sqlerrm, 60) || '); '; reset role;
  end;

  -- (h) dinero. Cálculo independiente de lo que debe salir.
  select count(*) into n from public.fichas_publicas f
   where f.publicada_web and f.proyecto_id is not null and f.precio_modo = 'fijo'
     and not exists (select 1 from jsonb_array_elements(res->'properties') p
                      where p->>'id' = f.slug and p->>'priceMode' = 'fixed' and (p->>'priceEUR')::numeric = f.precio_eur);
  r := r || case when n = 0 then 'h1 ok (fijo = precio_eur); ' else 'h1 FALLO ' || n || ' fichas fijas con otro precio; ' end;
  select f.precio_modo into v from public.fichas_publicas f where f.slug = 'palm-field-bali';
  if v = 'desde' then
    select coalesce((select min(u.precio) from public.unidades u where u.proyecto_id = f.proyecto_id and u.estado = 'disponible' and u.precio > 0
                       and u.moneda = 'EUR' and coalesce(u.precio_construccion, 0) = 0), 0)
         + coalesce((select min(case when public.catalogo_tramo_activo() = '2026' then m.precio_construccion
                                     else coalesce(m.precio_construccion_2027, m.precio_construccion) end)
                       from public.modelos_villa mv join public.modelos m on m.id = mv.modelo_id and m.publicado and m.activo
                      where mv.proyecto_id = f.proyecto_id and m.moneda = 'EUR'), 0)
      into v2 from public.fichas_publicas f where f.slug = 'palm-field-bali';
    r := r || case when exists (select 1 from jsonb_array_elements(res->'properties') p
                                where p->>'id' = 'palm-field-bali' and p->>'priceMode' = 'from' and (p->>'priceEUR')::numeric = v2)
                   then 'h2 ok (desde = parcela más barata + modelo más barato = ' || v2 || '); '
                   else 'h2 FALLO esperaba from ' || v2 || '; ' end;
  else
    r := r || 'h2 omitido (palm-field-bali ya no es «desde»); ';
  end if;
  -- consultar
  update public.fichas_publicas set precio_modo = 'consultar' where slug = 'cube';
  set local role anon; res2 := public.coleccion_publica(); reset role;
  r := r || case when exists (select 1 from jsonb_array_elements(res2->'properties') p
                              where p->>'id' = 'cube' and p->>'priceMode' = 'consultar' and (p->>'priceEUR')::numeric = 0)
                 then 'h3 ok (consultar → priceEUR 0); ' else 'h3 FALLO consultar; ' end;
  -- conversión de moneda: riverfront-i (unidades en IDR) pasa a «desde»
  update public.fichas_publicas set precio_modo = 'desde' where slug = 'riverfront-i';
  select count(*) into n from public.config_instancia where clave = 'tc_idr_por_eur';
  if n = 0 then
    set local role anon; res2 := public.coleccion_publica(); reset role;
    r := r || case when exists (select 1 from jsonb_array_elements(res2->'properties') p
                                where p->>'id' = 'riverfront-i' and p->>'priceMode' = 'consultar' and (p->>'priceEUR')::numeric = 0)
                   then 'h4 ok (IDR sin tipo de cambio → consultar, no inventa); ' else 'h4 FALLO IDR sin tipo no es consultar; ' end;
  else
    r := r || 'h4 omitido (ya existe tc_idr_por_eur: no se toca); ';
  end if;
  begin
    select min(u.precio) into v2 from public.unidades u join public.proyectos p on p.id = u.proyecto_id
     where p.slug = 'riverfront-i' and u.estado = 'disponible' and u.precio > 0 and u.moneda = 'IDR';
    if n = 0 and v2 is not null then
      insert into public.config_instancia (clave, valor, descripcion, actualizado_en) values ('tc_idr_por_eur', to_jsonb(20000), 'prueba', now());
      set local role anon; res2 := public.coleccion_publica(); reset role;
      r := r || case when exists (select 1 from jsonb_array_elements(res2->'properties') p
                                  where p->>'id' = 'riverfront-i' and p->>'priceMode' = 'from' and (p->>'priceEUR')::numeric = floor(v2 / 20000))
                     then 'h5 ok (IDR con tipo 20000 → ' || floor(v2 / 20000) || ' EUR, hacia abajo); ' else 'h5 FALLO conversión; ' end;
      update public.config_instancia set valor = to_jsonb('20000'::text) where clave = 'tc_idr_por_eur';
      set local role anon; res2 := public.coleccion_publica(); reset role;
      r := r || case when exists (select 1 from jsonb_array_elements(res2->'properties') p
                                  where p->>'id' = 'riverfront-i' and p->>'priceMode' = 'from') then 'h6 ok (valor como texto también); ' else 'h6 FALLO valor texto; ' end;
      update public.config_instancia set valor = to_jsonb(20) where clave = 'tc_idr_por_eur';
      set local role anon; res2 := public.coleccion_publica(); reset role;
      r := r || case when exists (select 1 from jsonb_array_elements(res2->'properties') p
                                  where p->>'id' = 'riverfront-i' and p->>'priceMode' = 'consultar') then 'h7 ok (tipo implausible → consultar); ' else 'h7 FALLO tipo implausible aceptado; ' end;
      update public.config_instancia set valor = to_jsonb(20000), actualizado_en = now() - interval '61 days' where clave = 'tc_idr_por_eur';
      set local role anon; res2 := public.coleccion_publica(); reset role;
      r := r || case when exists (select 1 from jsonb_array_elements(res2->'properties') p
                                  where p->>'id' = 'riverfront-i' and p->>'priceMode' = 'consultar') then 'h8 ok (tipo de hace 61 días → consultar); ' else 'h8 FALLO tipo caducado aceptado; ' end;
    else
      r := r || 'h5-h8 omitido (no se pudo montar el tipo de cambio de prueba); ';
    end if;
  exception when others then r := r || 'h5-h8 omitido (' || sqlstate || ' ' || left(sqlerrm, 70) || '); '; reset role;
  end;

  raise exception 'RES: %', r;
end $t$;
