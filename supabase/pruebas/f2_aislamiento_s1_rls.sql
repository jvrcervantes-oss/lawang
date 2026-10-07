-- PRUEBA FINAL DE AISLAMIENTO · SECCION 1 (7-oct-2026): RLS generico en TODAS las tablas y vistas de public.
-- Pregunta: ¿puede un admin_empresa / super_admin_empresa VER filas de la OTRA empresa? ¿Que ve de lo que no tiene empresa?
-- Personas (SIN crear usuarios; fichas de agente convertidas dentro de la transaccion, todo en rollback):
--   ae_L=admin_empresa{lawang}  se_L=super_admin_empresa{lawang}  ae_S=admin_empresa{sandal_woods}  se_S=super_admin_empresa{sandal_woods}  ctl=agente global sin empresas
-- Atribucion de cada fila (calculada como postgres, sin sesion): columna empresa | empresa_de_contrato | empresa_de_proyecto | empresa_de_unidad | empresa_de_factura
--   | sociedad->empresas.clave | proyecto(texto)->proyectos.empresa | client_id->comprador (ambas si tiene contratos en las dos).
-- Salida: por persona, tablas donde ve filas con atribucion = la otra empresa (CRITICO) y lista de tablas sin atribucion con cuantas filas ve.
-- destructivo-ok: solo lectura + fichas de prueba; termina en raise (rollback)
do $t$
declare
  jv uuid; je text; ids uuid[]; ems text[]; per text[] := array['ae_L','se_L','ae_S','se_S','ctl']; pe text[] := array['lawang','lawang','sandal_woods','sandal_woods',null];
  r record; cols text[]; ex text[]; expr text; i int; n bigint; otra text; cruz text := ''; sinatr text := ''; res text := ''; ntab int := 0; ncruz int := 0;
  a_total bigint; m bigint;
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select array_agg(user_id order by o), array_agg(email order by o) into ids, ems from (
    select user_id, email, case email when 'yanayjefferson@gmail.com' then 1 when 'adenovit.b@gmail.com' then 2 when 'cris.blueiestates@gmail.com' then 4 when 'david@newconcisa.com' then 3 when 'dortegag@gmail.com' then 5 end o
      from public.usuarios where email in ('yanayjefferson@gmail.com','adenovit.b@gmail.com','cris.blueiestates@gmail.com','david@newconcisa.com','dortegag@gmail.com')) q;
  -- ids ordenados: 1 yanay(ae_L) 2 adenovit(se_L) 3 david(ae_S) 4 cris(se_S) 5 dortega(ctl)
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[1];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[2];
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[3];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[4];
  perform set_config('request.jwt.claims', '', true); reset role;

  -- atribucion por fila (como postgres, sin sesion: auth.uid() null)
  create temp table cli_emp as
    select cc.client_id::text id, case when count(distinct p.empresa) filter (where p.empresa is not null) = 1 then min(p.empresa) when count(distinct p.empresa) > 1 then 'ambas' end emp
      from public.contrato_compradores cc join public.contratos c on c.id = cc.contrato_id join public.proyectos p on p.id = c.proyecto_id group by cc.client_id;
  create temp table att (rel text, rk text, emp text);
  create index on att (rel, rk);
  grant select on cli_emp, att to authenticated;
  for r in select c.oid, c.relname, c.relkind from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','p') and c.relname !~ '^_' and has_table_privilege('authenticated', c.oid, 'select') order by 2 loop
    select array_agg(attname::text) into cols from pg_attribute where attrelid = r.oid and attnum > 0 and not attisdropped;
    ex := array[]::text[];
    if r.relname = 'clients' then ex := array['(select ce.emp from pg_temp.cli_emp ce where ce.id = x.id::text)'];
    elsif r.relname = 'solicitudes_pago' then ex := array['public.empresa_de_solicitud_pago(x.id)'];
    elsif r.relname = 'empresas' then ex := array['x.clave'];
    else
      if 'empresa' = any (cols) then ex := array_append(ex, 'x.empresa::text'); end if;
      if 'contrato_id' = any (cols) then ex := array_append(ex, 'public.empresa_de_contrato(x.contrato_id)'); end if;
      if 'proyecto_id' = any (cols) then ex := array_append(ex, 'public.empresa_de_proyecto(x.proyecto_id)'); end if;
      if 'unidad_id' = any (cols) then ex := array_append(ex, 'public.empresa_de_unidad(x.unidad_id)'); end if;
      if 'factura_id' = any (cols) then ex := array_append(ex, 'public.empresa_de_factura(x.factura_id)'); end if;
      if 'sociedad' = any (cols) then ex := array_append(ex, '(select e.clave from public.empresas e where e.sociedad_clave = x.sociedad::text)'); end if;
      if 'proyecto' = any (cols) then ex := array_append(ex, '(select pr.empresa from public.proyectos pr where pr.nombre = x.proyecto::text limit 1)'); end if;
      if 'client_id' = any (cols) then ex := array_append(ex, '(select ce.emp from pg_temp.cli_emp ce where ce.id = x.client_id::text)'); end if;
    end if;
    expr := case when cardinality(ex) = 0 then 'null::text' else 'coalesce(' || array_to_string(ex, ', ') || ')' end;
    execute format('insert into pg_temp.att select %L, %s, %s from public.%I x', r.relname, case when r.relkind = 'v' then 'md5(x::text)' else 'x.ctid::text' end, expr, r.relname);
    ntab := ntab + 1;
  end loop;

  -- visibilidad por persona
  for i in 1..5 loop
    perform set_config('request.jwt.claims', json_build_object('sub', ids[i], 'role', 'authenticated', 'email', ems[i])::text, true);
    set local role authenticated;
    otra := case pe[i] when 'lawang' then 'sandal_woods' when 'sandal_woods' then 'lawang' end;
    cruz := ''; sinatr := '';
    for r in select distinct rel from pg_temp.att order by 1 loop
      begin
        execute format('select count(*), count(*) filter (where a.emp = %L), count(*) filter (where a.emp is null) from public.%I x left join pg_temp.att a on a.rel = %L and a.rk = %s',
                       coalesce(otra, '-'), r.rel, r.rel, case when r.rel in (select relname from pg_class where relnamespace = 'public'::regnamespace and relkind = 'v') then 'md5(x::text)' else 'x.ctid::text' end) into n, a_total, m;
        if n > 0 then
          if a_total > 0 then cruz := cruz || format('%s=%s/%s ', r.rel, a_total, n); ncruz := ncruz + 1; end if;
          if m > 0 then sinatr := sinatr || format('%s=%s ', r.rel, m); end if;
        end if;
      exception when others then sinatr := sinatr || format('[%s:E%s] ', r.rel, sqlstate);
      end;
    end loop;
    reset role;
    res := res || format(E'%s (%s) CRUZADO[%s]\n   SIN_ATRIBUCION_VISIBLE[%s]\n', per[i], coalesce(pe[i],'-'), cruz, sinatr);
  end loop;
  raise exception E'S1 RLS: % relaciones\n%', ntab, res;
end $t$;
