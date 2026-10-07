-- PRUEBA FINAL DE AISLAMIENTO · caso reproducible de los hallazgos arreglados por el BLOQUE 10 (migraciones 20261008900000 y 20261008900100) — 7-oct-2026.
-- Se ejecuta DESPUES de las migraciones (o pegada tras ellas en la misma peticion para ensayarlas sin rastro). Todo en UNA transaccion que acaba en raise (rollback).
-- Personas SIN crear usuarios (fichas de agente convertidas dentro de la transaccion): ae_L=admin_empresa{lawang} se_L=super_admin_empresa{lawang} ae_S=admin_empresa{sandal_woods} se_S=super_admin_empresa{sandal_woods}.
-- Secciones: 1) un rol de empresa NO ve filas de la otra empresa en las 8 tablas arregladas (y SI ve las suyas); 2) los 34 usuarios reales ven exactamente lo mismo que antes (A/B contra la expresion antigua);
--            3) documentos generales: de Lawang para Lawang, ninguno para Sandal Woods; 4) el admin global lo ve todo. Cada linea OK/FALLO; debe terminar con «FALLOS=0».
-- Los otros hallazgos de la prueba (cuentas de cobro sin empresa, usuarios globales visibles, lineas de comision de administracion por sociedad, documentos con empresa dudosa) no se arreglan aqui: ver encargos/20261007_lawang_empresas_aislamiento_resultado.md.
-- destructivo-ok: solo lectura + fichas de prueba; termina en raise (rollback)
do $t$
declare
  jv uuid; je text; ids uuid[]; ems text[]; per text[] := array['ae_L','se_L','ae_S','se_S']; pe text[] := array['lawang','lawang','sandal_woods','sandal_woods']; i int; otra text; r text := ''; fallos int := 0; n bigint; m bigint; esp bigint;
  u record; adm uuid; adme text; t text; ts text[] := array['contrato_compradores','hilo_soporte','mensajes_comprador','proyecto_cuentas','proyecto_eventos','proyecto_plazo_pago','deck_publicaciones','documentos_proyecto'];
  antes text[] := array['public.es_agente()', 'public.es_agente()', 'public.es_agente()', 'public.es_agente()', 'public.es_agente()', 'public.es_agente()', 'public.es_agente()', 'public.es_agente() and (general or public.puede_proyecto(proyecto, proyecto_id))'];
  n_ab int := 0; n_dif int := 0;
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select array_agg(user_id order by o), array_agg(email order by o) into ids, ems from (
    select user_id, email, case email when 'yanayjefferson@gmail.com' then 1 when 'adenovit.b@gmail.com' then 2 when 'david@newconcisa.com' then 3 when 'cris.blueiestates@gmail.com' then 4 end o
      from public.usuarios where email in ('yanayjefferson@gmail.com','adenovit.b@gmail.com','david@newconcisa.com','cris.blueiestates@gmail.com')) q;
  select user_id, email into adm, adme from public.usuarios where email = 'andreabenimeli@gmail.com';
  -- 2) A/B de los 34 ANTES de convertir a nadie: lo visible ahora (policy nueva, como authenticated) == lo que daba la condicion antigua (evaluada como postgres con los mismos claims)
  for u in select user_id, email from public.usuarios where not (ambito = 'empresa' or cardinality(empresas) > 0) order by email loop
    foreach t in array ts loop
      perform set_config('request.jwt.claims', json_build_object('sub', u.user_id, 'role', 'authenticated', 'email', u.email)::text, true);
      execute format('select count(*) from public.%I where %s', t, antes[array_position(ts, t)]) into esp;
      set local role authenticated;
      execute format('select count(*) from public.%I', t) into n;
      reset role;
      n_ab := n_ab + 1;
      if n is distinct from esp then n_dif := n_dif + 1; if n_dif <= 6 then r := r || format(E'  DIF 34: %s %s ve=%s antes=%s\n', u.email, t, n, esp); end if; end if;
    end loop;
  end loop;
  r := r || case when n_dif = 0 then 'OK   ' else 'FALLO' end || format(' S2 los 34 usuarios: %s combinaciones usuario x tabla, distintas de antes=%s', n_ab, n_dif) || E'\n'; if n_dif > 0 then fallos := fallos + 1; end if;
  -- personas de empresa
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[1];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[2];
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[3];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[4];
  perform set_config('request.jwt.claims', '', true); reset role;
  for i in 1..4 loop
    otra := case pe[i] when 'lawang' then 'sandal_woods' else 'lawang' end;
    perform set_config('request.jwt.claims', json_build_object('sub', ids[i], 'role', 'authenticated', 'email', ems[i])::text, true);
    set local role authenticated;
    -- 1) ajenas = 0
    select count(*) into n from public.contrato_compradores cc where public.empresa_de_contrato(cc.contrato_id) = otra;
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s contrato_compradores de contratos de %s=%s', per[i], otra, n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    select count(*) into n from public.contrato_compradores cc where public.empresa_de_contrato(cc.contrato_id) = pe[i];
    reset role;
    select count(*) into m from public.contrato_compradores cc where public.empresa_de_contrato(cc.contrato_id) = pe[i];
    r := r || case when n = m and m > 0 then 'OK   ' else 'FALLO' end || format(' S1 %s ve TODOS los suyos de contrato_compradores: %s/%s', per[i], n, m) || E'\n'; if not (n = m and m > 0) then fallos := fallos + 1; end if;
    set local role authenticated;
    select count(*) into n from public.hilo_soporte h where not exists (select 1 from public.clients k where k.id = h.client_id);
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s hilo_soporte de compradores que no ve=%s', per[i], n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    select count(*) into n from public.mensajes_comprador h where not exists (select 1 from public.clients k where k.id = h.client_id);
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s mensajes_comprador de compradores que no ve=%s', per[i], n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    select count(*) into n from public.proyecto_cuentas x where public.empresa_de_proyecto(x.proyecto_id) is distinct from pe[i];
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s proyecto_cuentas de otra empresa o sin ella=%s', per[i], n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    select count(*) into n from public.proyecto_eventos x where public.empresa_de_proyecto(x.proyecto_id) is distinct from pe[i];
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s proyecto_eventos de otra empresa o sin ella=%s', per[i], n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    select count(*) into n from public.proyecto_plazo_pago x where public.empresa_de_proyecto(x.proyecto_id) is distinct from pe[i];
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s proyecto_plazo_pago de otra empresa o sin ella=%s', per[i], n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    select count(*) into n from public.deck_publicaciones x where public.empresa_de_proyecto(nullif(coalesce(x.despues ->> 'proyecto_id', x.antes ->> 'proyecto_id'), '')::uuid) is distinct from pe[i];
    r := r || case when n = 0 then 'OK   ' else 'FALLO' end || format(' S1 %s deck_publicaciones de otra empresa o sin proyecto=%s', per[i], n) || E'\n'; if n <> 0 then fallos := fallos + 1; end if;
    -- 3) documentos generales
    select count(*) into n from public.documentos_proyecto d where d.general;
    esp := case pe[i] when 'lawang' then (select count(*) from public.documentos_proyecto d where d.general and d.empresa = 'lawang') else 0 end;
    r := r || case when n = esp then 'OK   ' else 'FALLO' end || format(' S3 %s ve %s documentos generales (esperado %s)', per[i], n, esp) || E'\n'; if n <> esp then fallos := fallos + 1; end if;
    reset role;
  end loop;
  -- 4) admin global
  perform set_config('request.jwt.claims', json_build_object('sub', adm, 'role', 'authenticated', 'email', adme)::text, true);
  set local role authenticated;
  select count(*) into n from public.documentos_proyecto d where d.general;
  select count(*) into m from public.contrato_compradores;
  reset role;
  r := r || case when n = (select count(*) from public.documentos_proyecto d where d.general) and m = (select count(*) from public.contrato_compradores) then 'OK   ' else 'FALLO' end || format(' S4 admin global ve todo: generales=%s contrato_compradores=%s', n, m) || E'\n';
  if not (n = (select count(*) from public.documentos_proyecto d where d.general) and m = (select count(*) from public.contrato_compradores)) then fallos := fallos + 1; end if;
  raise exception E'F2 AISLAMIENTO B10 · FALLOS=%\n%', fallos, r;
end $t$;
