-- PRUEBA FINAL DE AISLAMIENTO · SECCION 3 (7-oct-2026): storage por bucket. ¿Que objetos (solo se CUENTAN, no se descargan) ve un rol de empresa que sean de la otra empresa?
-- Atribucion por ruta (como postgres): contratos-firmados = numero de contrato antes del «_»; kyc = id de comprador (solo compradores de UNA empresa); justificantes = documents.path;
-- documentacion = proyectos/<id> (o documentos_proyecto.path); contratos-anexos y creatividades = primer segmento (contrato / creatividad).
-- destructivo-ok: solo lectura; termina en raise
do $t$
declare
  jv uuid; je text; ids uuid[]; ems text[]; per text[] := array['ae_L','se_L','ae_S','se_S','ctl']; pe text[] := array['lawang','lawang','sandal_woods','sandal_woods',null]; i int; r record; res text := ''; otra text; ct bigint; co bigint; cn bigint;
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select array_agg(user_id order by o), array_agg(email order by o) into ids, ems from (
    select user_id, email, case email when 'yanayjefferson@gmail.com' then 1 when 'adenovit.b@gmail.com' then 2 when 'david@newconcisa.com' then 3 when 'cris.blueiestates@gmail.com' then 4 when 'dortegag@gmail.com' then 5 end o
      from public.usuarios where email in ('yanayjefferson@gmail.com','adenovit.b@gmail.com','david@newconcisa.com','cris.blueiestates@gmail.com','dortegag@gmail.com')) q;
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[1];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[2];
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[3];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[4];
  perform set_config('request.jwt.claims', '', true); reset role;
  create temp table cli_emp as
    select cc.client_id::text id, case when count(distinct p.empresa) filter (where p.empresa is not null) = 1 then min(p.empresa) when count(distinct p.empresa) > 1 then 'ambas' end emp
      from public.contrato_compradores cc join public.contratos c on c.id = cc.contrato_id join public.proyectos p on p.id = c.proyecto_id group by cc.client_id;
  create temp table att (bucket text, nombre text, emp text);
  insert into att
  select o.bucket_id, o.name, case o.bucket_id
    when 'contratos-firmados' then (select p.empresa from public.contratos c join public.proyectos p on p.id = c.proyecto_id where c.numero = split_part(o.name, '_', 1) limit 1)
    when 'kyc' then (select ce.emp from cli_emp ce where ce.id = split_part(o.name, '/', 1))
    when 'justificantes' then (select coalesce(public.empresa_de_contrato(d.contrato_id), (select ce.emp from cli_emp ce where ce.id = d.client_id::text)) from public.documents d where d.storage_path = o.name limit 1)
    when 'documentacion' then coalesce((select p.empresa from public.proyectos p where p.id::text = split_part(o.name, '/', 2) and split_part(o.name, '/', 1) = 'proyectos'),
                                       (select p.empresa from public.documentos_proyecto dp join public.proyectos p on p.id = dp.proyecto_id where dp.path = o.name limit 1))
    when 'contratos-anexos' then public.empresa_de_contrato(nullif(split_part(o.name, '/', 1), '')::uuid)
    when 'creatividades' then (select public.empresa_de_proyecto(c.proyecto_id) from public.creatividades c where c.id::text = split_part(o.name, '/', 1))
    end
  from storage.objects o where o.bucket_id in ('contratos-firmados','kyc','justificantes','documentacion','contratos-anexos','creatividades','modelos','obra','gastos');
  create index on att (bucket, nombre);
  grant select on att to authenticated;
  res := (select string_agg(bucket || ': total=' || n || ' lawang=' || l || ' sandal=' || s || ' ambas=' || a || ' sin_atribucion=' || z, E'\n' order by bucket)
            from (select bucket, count(*) n, count(*) filter (where emp = 'lawang') l, count(*) filter (where emp = 'sandal_woods') s, count(*) filter (where emp = 'ambas') a, count(*) filter (where emp is null) z from att group by bucket) q) || E'\n';
  for i in 1..5 loop
    perform set_config('request.jwt.claims', json_build_object('sub', ids[i], 'role', 'authenticated', 'email', ems[i])::text, true);
    set local role authenticated;
    otra := case pe[i] when 'lawang' then 'sandal_woods' when 'sandal_woods' then 'lawang' end;
    res := res || per[i] || ' ve:';
    for r in select o.bucket_id, count(*) n, count(*) filter (where a.emp = otra) ajeno, count(*) filter (where a.emp is null) sin from storage.objects o left join att a on a.bucket = o.bucket_id and a.nombre = o.name
              where o.bucket_id in ('contratos-firmados','kyc','justificantes','documentacion','contratos-anexos','creatividades','modelos','obra','gastos','deck-privado','sociedades','correos-enviados') group by o.bucket_id order by 1 loop
      res := res || format(' [%s n=%s AJENO=%s sin=%s]', r.bucket_id, r.n, r.ajeno, r.sin);
    end loop;
    reset role;
    res := res || E'\n';
  end loop;
  raise exception E'S3 storage\n%', res;
end $t$;
