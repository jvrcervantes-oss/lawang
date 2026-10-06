-- Prueba ADVERSARIA de la Fase 2 (7-oct-2026): ¿que responde cada funcion DEFINER ejecutable por `authenticated` a un admin_empresa y a un super_admin_empresa?
-- Todo dentro de una transaccion que acaba en raise (rollback, sin rastro). No crea filas nuevas (no gasta secuencias): reutiliza 3 fichas de agente existentes,
-- las convierte (con los claims del propietario, como haria la pantalla) en admin_empresa/lawang, super_admin_empresa/sandal_woods y un agente de control, los tres SIN proyectos ni herramientas.
-- Ejecuta con argumentos de relleno SOLO las funciones STABLE/IMMUTABLE y las VOLATILE cuyo cuerpo no inserta ni usa secuencias/net/notify (evita huecos en la numeracion de documentos).
-- Las otras (volatiles que insertan) se clasifican a mano por su cuerpo: «sin puerta de rol» / «solo es_agente» / «con puerta».
-- Codigos: E<sqlstate> = rechazada | N = vacia | D = devuelve datos | X = void ejecutada | Bt/Bf = booleano.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); el unico «drop» es el de la tabla temporal
-- Parametros: pg = pagina (0..) del listado de anomalias (70 por pagina).
do $t$
declare pg int := 0;
  jv uuid; ya uuid; cr uuid; bl uuid; pr uuid; un uuid; co uuid; cl uuid; u_ag uuid;
  f record; persona text; code text; res text; args text; a record; n bigint; v jsonb; vacio boolean;
  nom text[] := array['ae','se','ag']; ids uuid[]; i int; r text := ''; tot text := ''; k int := 0;
  cnt jsonb := '{}'::jsonb; lista text := ''; est text := '';
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id into ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id into cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id into bl from public.usuarios where email='blueicrm@gmail.com';
  select id into pr from public.proyectos where nombre='Bonian Village';
  select id into un from public.unidades order by id limit 1;
  select id into co from public.contratos order by id limit 1;
  select id into cl from public.clients order by id limit 1;
  select user_id into u_ag from public.usuarios where email='adenovit.b@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set proyectos='{}', proyectos_supervisados='{}', herramientas='{}', tipos_contrato='{}' where user_id=bl;
  ids := array[ya, cr, bl];
  create temp table res_adv(fn text, ae text, se text, ag text, modo text) on commit drop;
  for f in select p.oid, p.proname, p.provolatile, pg_get_function_identity_arguments(p.oid) ia, p.pronargs, p.proargnames, p.proargtypes, p.prorettype,
                  (p.prorettype = 'void'::regtype) es_void, pg_get_functiondef(p.oid) def
             from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f' and p.prosecdef
              and has_function_privilege('authenticated', p.oid, 'execute') and p.prorettype <> 'trigger'::regtype
              and p.proname not in ('es_propietario','es_admin_de','es_super_admin_de','puede_empresa','mi_alcance') order by p.proname, p.oid loop
    if f.provolatile = 'v' and f.def ~* 'insert\s+into|nextval|net\.http|pg_notify|pg_net|http_post|setval' then
      est := case when f.def !~* 'es_admin\(|es_super_admin\(|es_propietario|es_gestor|es_manager_de|puede_proyecto|proyecto_visible|puede_ver_contrato|puede\(|_puede_|\.rol|es_portal|auth\.uid|es_suyo' then 'SIN_PUERTA'
                  when f.def !~* 'es_admin\(|es_super_admin\(|es_propietario|es_gestor|es_manager_de|puede_proyecto|proyecto_visible|puede_ver_contrato|puede\(|_puede_|\.rol' then 'SOLO_UID_O_PORTAL'
                  when f.def ~* 'es_admin\(|es_super_admin\(' then 'PUERTA_ADMIN' else 'PUERTA_OTRA' end;
      insert into res_adv values (f.proname||'('||f.ia||')', '-','-','-','estatica:'||est);
      continue;
    end if;
    -- argumentos de relleno
    args := '';
    for i in 1..f.pronargs loop
      select format_type(t.oid, null) as tn, t.typcategory tc, t.typelem el into a from pg_type t where t.oid = f.proargtypes[i-1];
      declare nm text := lower(coalesce(f.proargnames[i], '')); tn text := a.tn; lit text;
      begin
        lit := case
          when tn = 'uuid' then format('%L', case when nm ~ 'proyecto' then pr when nm ~ 'unidad' then un when nm ~ 'cliente|client|comprador' then cl when nm ~ 'user|usuario' then u_ag else co end)
          when tn = 'text' or tn = 'character varying' then format('%L', case when nm ~ 'empresa' then 'lawang' when nm ~ 'email|correo' then 'x@x.test' when nm ~ 'sociedad' then 'tepi_sungai' else 'x' end)
          when tn in ('integer','bigint','smallint','numeric','double precision','real') then '1'
          when tn = 'boolean' then 'false'
          when tn = 'date' then 'current_date'
          when tn like 'timestamp%' then 'now()'
          when tn in ('jsonb','json') then '''{}'''
          when tn like '%[]' then '''{}'''
          else 'null' end;
        args := args || case when i > 1 then ',' else '' end || lit || '::' || tn;
      end;
    end loop;
    k := k + 1;
    perform set_config('statement_timeout','4000',true);
    for i in 1..3 loop
      perform set_config('request.jwt.claims', json_build_object('sub',ids[i],'role','authenticated','email',(select email from public.usuarios where user_id=ids[i]))::text, true);
      set local role authenticated;
      begin
        if f.es_void then
          execute format('select public.%I(%s)', f.proname, args);
          code := 'X';
        else
          execute format('select count(*), (array_agg(to_jsonb(t)))[1] from (select * from public.%I(%s) limit 5) t', f.proname, args) into n, v;
          if n = 0 then code := 'N';
          else
            select coalesce(bool_and(e.value is null or e.value::text in ('null','""','false','0','[]','{}','"0"','0.0')), true) into vacio from jsonb_each(coalesce(v,'{}'::jsonb)) e;
            code := case when vacio then (case when f.prorettype='boolean'::regtype then 'Bf' else 'N' end) else (case when f.prorettype='boolean'::regtype then 'Bt' else 'D' end) end;
          end if;
        end if;
      exception when others then code := 'E' || sqlstate;
      end;
      reset role;
      res := coalesce(res,'') ;
      if i = 1 then insert into res_adv values (f.proname||'('||f.ia||')', code, null, null, case when f.provolatile='v' then 'volatil-ejecutada' else 'lectura' end);
      elsif i = 2 then update res_adv set se = code where fn = f.proname||'('||f.ia||')';
      else update res_adv set ag = code where fn = f.proname||'('||f.ia||')'; end if;
    end loop;
    perform set_config('statement_timeout','0',true);
  end loop;
  perform set_config('request.jwt.claims','',true);
  select jsonb_object_agg(modo||'/ae='||ae, c) into cnt from (select modo, ae, count(*) c from res_adv group by 1,2) x;
  tot := 'EJECUTADAS=' || k || ' | ' || (select string_agg(m||' '||c, '; ' order by m) from (select 'ae='||ae||'/'||modo m, count(*) c from res_adv where modo<>'' and modo not like 'estatica%' group by 1) y)
      || E'\n' || 'SE: ' || (select string_agg(se||'='||c, ' ' order by se) from (select se, count(*) c from res_adv where modo not like 'estatica%' group by 1) z)
      || E'\n' || 'AG(control): ' || (select string_agg(ag||'='||c, ' ' order by ag) from (select ag, count(*) c from res_adv where modo not like 'estatica%' group by 1) z2)
      || E'\n' || 'ESTATICAS: ' || (select string_agg(modo||'='||c, ' ') from (select modo, count(*) c from res_adv where modo like 'estatica%' group by 1) z3);
  select string_agg(rn||' '||fn||' '||ae||'/'||se||'/'||ag||' '||left(modo,4), E'\n' order by rn) into lista
    from (select row_number() over (order by fn) rn, fn, ae, se, ag, modo from res_adv
           where modo not like 'estatica%' and (ae in ('D','X','Bt') or se in ('D','X','Bt'))) q where rn > pg*70 and rn <= (pg+1)*70;
  raise exception E'ADVERSARIA\n%\n--- anomalias pag %\n%', tot, pg, lista;
end $t$;
