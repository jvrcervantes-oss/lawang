-- PRUEBA FINAL DE AISLAMIENTO · SECCION 2 (7-oct-2026): las funciones DEFINER ejecutables por `authenticated`, llamadas con objetos de la OTRA empresa.
-- Personas como en la seccion 1 (fichas de agente convertidas dentro de la transaccion). Parametros al principio: v_pi (1 ae_L, 2 se_L, 3 ae_S, 4 se_S) y v_re (regex de nombres de funcion).
-- Para cada funcion se resuelven los argumentos por TIPO y NOMBRE con objetos de la otra empresa (contrato, proyecto, unidad, factura, comprador, solicitud de pago, gasto, equipo, linea de comision...)
-- y, si el argumento es un `p_id` generico, se prueba con TODOS los tipos de objeto. Cada llamada va en una subtransaccion que SIEMPRE se deshace (set local role authenticated; statement_timeout 5s).
-- Veredicto por llamada: AUTH (42501 / mensaje de permiso), OK (se ejecuto), ERR (otro error: ambiguo; se revisa leyendo la funcion). Ademas se busca en la salida cualquier id/numero de objeto de la otra empresa
-- (fuga por lectura): `HITS`. Linea de base: el mismo objeto con un uuid inexistente (kind=rand).
-- destructivo-ok: cada llamada se deshace; termina en raise (rollback)
do $t$
declare
  v_pi int := 1; v_re text := '.';
  jv uuid; je text; ids uuid[]; ems text[]; pe text[] := array['lawang','lawang','sandal_woods','sandal_woods']; otra text; propia text;
  f record; a record; kinds text[] := array['contrato','proyecto','unidad','factura','client','sp','gasto','equipo','linea','cond','faq','foto','comunicado','creatividad','proveedor','devengo','cobro','tarifa','fee','miembro'];
  k text; ks text[]; vals text[]; kk text; v text; sqltxt text; argtoks text[]; st text; msg text; outt text; hits int; sample text; i int; n int := 0; res text := '';
  nombre_o text; soc_o text; email_o text; user_o uuid; kd_id uuid; gen_pos int; isgen boolean; cls text; cnt int := 0; sc text; lab text;
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select array_agg(user_id order by o), array_agg(email order by o) into ids, ems from (
    select user_id, email, case email when 'yanayjefferson@gmail.com' then 1 when 'adenovit.b@gmail.com' then 2 when 'david@newconcisa.com' then 3 when 'cris.blueiestates@gmail.com' then 4 end o
      from public.usuarios where email in ('yanayjefferson@gmail.com','adenovit.b@gmail.com','david@newconcisa.com','cris.blueiestates@gmail.com')) q;
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[1];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[2];
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[3];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[4];
  perform set_config('request.jwt.claims', '', true); reset role;
  otra := case pe[v_pi] when 'lawang' then 'sandal_woods' else 'lawang' end; propia := pe[v_pi];

  -- marcadores: ids y numeros de objetos de cada empresa
  create temp table mk (tok text, emp text); create index on mk (tok);
  insert into mk select id::text, empresa from public.proyectos where empresa is not null;
  insert into mk select c.id::text, p.empresa from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa is not null;
  insert into mk select c.numero, p.empresa from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa is not null and c.numero is not null;
  insert into mk select u.id::text, p.empresa from public.unidades u join public.proyectos p on p.id = u.proyecto_id where p.empresa is not null;
  insert into mk select fa.id::text, public.empresa_de_factura(fa.id) from public.facturas fa where public.empresa_de_factura(fa.id) is not null;
  insert into mk select fa.numero, public.empresa_de_factura(fa.id) from public.facturas fa where public.empresa_de_factura(fa.id) is not null and fa.numero is not null;
  insert into mk select s.id::text, public.empresa_de_solicitud_pago(s.id) from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id) is not null;
  create temp table cli_emp as
    select cc.client_id::text id, case when count(distinct p.empresa) filter (where p.empresa is not null) = 1 then min(p.empresa) end emp
      from public.contrato_compradores cc join public.contratos c on c.id = cc.contrato_id join public.proyectos p on p.id = c.proyecto_id group by cc.client_id;
  insert into mk select id, emp from cli_emp where emp is not null;
  create temp table kd (emp text, kind text, id uuid);
  create temp table rz (fn text, kind text, st text, msg text, hits int, sample text);
  grant select on mk, kd to authenticated;

  -- objetos de la otra empresa y de la propia (uno por tipo)
  for k in select unnest(array[otra, propia]) loop
    begin insert into kd select k, 'contrato', c.id from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = k and c.unidad_id is not null order by (select count(*) from public.facturas fa where fa.contrato_id = c.id) desc, c.id limit 1; exception when others then null; end;
    begin insert into kd select k, 'proyecto', p.id from public.contratos c join public.proyectos p on p.id = c.proyecto_id where p.empresa = k and c.id = (select id from kd where emp = k and kind = 'contrato'); exception when others then null; end;
    begin insert into kd select k, 'unidad', c.unidad_id from public.contratos c where c.id = (select id from kd where emp = k and kind = 'contrato'); exception when others then null; end;
    begin insert into kd select k, 'factura', fa.id from public.facturas fa where public.empresa_de_factura(fa.id) = k order by (fa.contrato_id = (select id from kd where emp = k and kind = 'contrato')) desc nulls last, fa.id limit 1; exception when others then null; end;
    begin insert into kd select k, 'client', cc.client_id from public.contrato_compradores cc join cli_emp ce on ce.id = cc.client_id::text where ce.emp = k order by (cc.contrato_id = (select id from kd where emp = k and kind = 'contrato')) desc, cc.client_id limit 1; exception when others then null; end;
    begin insert into kd select k, 'sp', s.id from public.solicitudes_pago s where public.empresa_de_solicitud_pago(s.id) = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'gasto', g.id from public.gastos g where public.empresa_de_proyecto(g.proyecto_id) = k or g.sociedad = (select e.sociedad_clave from public.empresas e where e.clave = k) limit 1; exception when others then null; end;
    begin insert into kd select k, 'equipo', e.id from public.equipos_venta e where e.empresa = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'linea', l.id from public.comision_admin_lineas l where coalesce(public.empresa_de_contrato(l.contrato_id), public.empresa_de_proyecto(l.proyecto_id)) = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'cond', c.id from public.condiciones_comision c where c.empresa = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'faq', q.id from public.deck_faq q where public.empresa_de_proyecto(q.proyecto_id) = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'foto', q.id from public.deck_fotos q where public.empresa_de_proyecto(q.proyecto_id) = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'comunicado', q.id from public.comunicados q where q.empresa = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'creatividad', q.id from public.creatividades q where public.empresa_de_proyecto(q.proyecto_id) = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'proveedor', q.id from public.proveedores q where q.empresa = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'devengo', q.id from public.comisiones_devengadas q where public.empresa_de_contrato(q.contrato_raiz_id) = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'cobro', q.id from public.comision_admin_cobros q where q.sociedad = (select e.sociedad_clave from public.empresas e where e.clave = k) limit 1; exception when others then null; end;
    begin insert into kd select k, 'tarifa', q.id from public.comision_admin_tarifas q where q.empresa = k limit 1; exception when others then null; end;
    begin insert into kd select k, 'fee', q.id from public.comision_admin_fees q where q.sociedad = (select e.sociedad_clave from public.empresas e where e.clave = k) limit 1; exception when others then null; end;
    begin insert into kd select k, 'miembro', q.id from public.equipo_miembros q where q.empresa = k limit 1; exception when others then null; end;
  end loop;
  insert into kd values (otra, 'user', ids[case when otra = 'lawang' then 1 else 3 end]), (propia, 'user', ids[v_pi]);
  select nombre into nombre_o from public.proyectos where id = (select id from kd where emp = otra and kind = 'proyecto');
  select sociedad_clave into soc_o from public.empresas where clave = otra;
  select email into email_o from public.usuarios where user_id = (select id from kd where emp = otra and kind = 'user');

  -- el bucle
  for f in select p.oid, p.proname, p.pronargs, p.provolatile, coalesce(p.proargnames[1:p.pronargs], array[]::text[]) nm, string_to_array(p.proargtypes::text, ' ')::oid[] tp
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prorettype <> 'trigger'::regtype
              and has_function_privilege('authenticated', p.oid, 'execute') and p.proname ~ v_re
              and p.proname !~ '^(es_|puede|empresa_|mis_|alcance_|_|agente_ve_|portal_|sociedad_en_alcance|proyecto_en_alcance|proyecto_visible|unidad_visible|cliente_visible|documento_visible|gasto_visible|gasto_ruta|comision_visible|usuario_puede_poner_clave|instancia_marca|modo_obligatorio|intranet_estado|asistente_contar)'
              and p.proname <> all (array['obra_puede','contrato_anexo_puede','documento_proyecto_puede','creatividad_puede_ver','creatividad_puede_hacer'])
            order by p.proname, p.oid loop
    -- tipos de argumento
    isgen := false; gen_pos := null;
    for i in 1..f.pronargs loop
      if f.tp[i] = 'uuid'::regtype and (f.nm[i] is null or f.nm[i] !~ 'contrato|raiz|proyecto|unidad|factura|recibi|client|comprador|solicitud|equipo|user|usuario|modelo|lead') and gen_pos is null then gen_pos := i; end if;
    end loop;
    ks := case when gen_pos is null then array['x'] else kinds end;
    foreach sc in array array[otra, propia] loop
    foreach kk in array array_cat(ks, array['rand']) loop
      if sc = propia and (kk = 'rand' or not exists (select 1 from unnest(f.tp) t where t in ('uuid'::regtype, 'uuid[]'::regtype))) then continue; end if;
      lab := case when sc = propia then 'own:' else '' end || kk;
      if kk <> 'rand' and gen_pos is not null and not exists (select 1 from kd where emp = sc and kind = kk) then continue; end if;
      if kk = 'rand' and gen_pos is null and not exists (select 1 from unnest(f.tp) t where t = 'uuid'::regtype) then continue; end if;
      vals := array[]::text[]; argtoks := array[]::text[];
      for i in 1..f.pronargs loop
        v := null;
        if f.tp[i] = 'uuid'::regtype then
          select id::text into v from kd where emp = sc and kind =
            case when i = gen_pos then kk
                 when f.nm[i] ~ 'contrato|raiz' then 'contrato' when f.nm[i] ~ 'proyecto' then 'proyecto' when f.nm[i] ~ 'unidad' then 'unidad'
                 when f.nm[i] ~ 'factura|recibi' then 'factura' when f.nm[i] ~ 'client|comprador' then 'client' when f.nm[i] ~ 'solicitud' then 'sp'
                 when f.nm[i] ~ 'equipo' then 'equipo' when f.nm[i] ~ 'user|usuario' then 'user' end;
          if kk = 'rand' or v is null then v := gen_random_uuid()::text; else argtoks := array_append(argtoks, v); end if;
          vals := array_append(vals, format('%L::uuid', v));
        elsif f.tp[i] = 'uuid[]'::regtype then vals := array_append(vals, format('array[%L]::uuid[]', coalesce((select id::text from kd where emp = sc and kind = 'contrato'), gen_random_uuid()::text)));
        elsif f.tp[i] = 'text'::regtype then
          v := case when f.nm[i] ~ 'empresa' then otra when f.nm[i] ~ 'proyecto|nombre|antiguo|nuevo' and f.nm[i] !~ 'nuevo_propietario' then nombre_o when f.nm[i] ~ 'sociedad|cuenta|clave' then soc_o
                    when f.nm[i] ~ 'email|propietario|beneficiario' then email_o when f.nm[i] ~ 'tabla' then 'contratos' else 'x' end;
          vals := array_append(vals, format('%L', v));
        elsif f.tp[i] = 'text[]'::regtype then vals := array_append(vals, '''{}''::text[]');
        elsif f.tp[i] = 'jsonb'::regtype then vals := array_append(vals, '''{}''::jsonb');
        elsif f.tp[i] in ('int4'::regtype, 'int8'::regtype, 'numeric'::regtype) then vals := array_append(vals, '1');
        elsif f.tp[i] = 'bool'::regtype then vals := array_append(vals, 'false');
        elsif f.tp[i] = 'date'::regtype then vals := array_append(vals, 'current_date');
        elsif f.tp[i] = 'timestamptz'::regtype then vals := array_append(vals, 'now()');
        else vals := array_append(vals, 'null'); end if;
      end loop;
      sqltxt := format('select string_agg(x::text, '','') from public.%I(%s) x', f.proname, array_to_string(vals, ', '));
      st := null; msg := null; outt := '';
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', ids[v_pi], 'role', 'authenticated', 'email', ems[v_pi])::text, true);
        set local statement_timeout = '5s';
        set local role authenticated;
        execute sqltxt into outt;
        raise exception 'RB' using errcode = 'ZZ001', detail = left(coalesce(outt, ''), 60000);
      exception
        when sqlstate 'ZZ001' then get stacked diagnostics outt = pg_exception_detail; st := 'OK'; msg := 'len=' || length(outt);
        when others then st := case when sqlstate = '42501' or sqlerrm ~* 'autori|permiso|permission|denegad|no tienes|no puedes|solo (el )?(admin|super|propiet)|insufficient|acceso|forbidden|no est[aá] en tu|no es tuy|sin permiso|reservad' then 'AUTH' else 'ERR' end;
                         msg := regexp_replace(left(sqlerrm, 70), '[0-9a-f]{8}-[0-9a-f-]{27}', '<id>', 'g'); outt := '';
      end;
      perform set_config('request.jwt.claims', '', true); reset role;
      hits := 0; sample := null;
      if outt <> '' and kk <> 'rand' and sc = otra then
        select count(distinct m.tok), min(m.tok) into hits, sample from (select (regexp_matches(outt, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Z]{2,4}[0-9]{4,6}', 'g'))[1] tok) t
          join mk m on m.tok = t.tok and m.emp = otra where t.tok <> all (argtoks);
      end if;
      insert into rz values (f.proname || case when f.provolatile = 'v' then ' [V]' else '' end, lab, st, msg, hits, sample);
      cnt := cnt + 1;
    end loop;
    end loop;
  end loop;

  -- informe: solo lo que no es AUTH puro
  res := res || E'--- A) SOSPECHOSAS: objeto de la otra empresa da el MISMO resultado no-AUTH que el objeto propio (y distinto de uuid inexistente):\n';
  for f in select o.fn, string_agg(o.kind || '=' || o.st || ':' || coalesce(o.msg, '') || case when o.hits > 0 then ' HITS' || o.hits else '' end, ' | ') r
             from rz o join rz w on w.fn = o.fn and w.kind = 'own:' || o.kind and w.st = o.st and coalesce(w.msg, '') = coalesce(o.msg, '')
             left join rz ra on ra.fn = o.fn and ra.kind = 'rand'
            where o.kind not like 'own:%' and o.kind <> 'rand' and o.st <> 'AUTH' and (ra.st is null or ra.st || coalesce(ra.msg, '') <> o.st || coalesce(o.msg, ''))
            group by o.fn order by o.fn loop
    res := res || f.fn || ' -> ' || left(f.r, 500) || E'\n';
  end loop;
  res := res || E'--- B) con fuga (HITS) o sin argumento de objeto y no-AUTH:\n';
  for f in select g.fn, string_agg(g.o, ' | ' order by g.o) r from (
             select rz.fn, rz.st || ':' || coalesce(rz.msg, '') || ' [' || case when count(*) > 3 then count(*)::text || ' tipos' else string_agg(rz.kind, ',') end || ']'
                    || case when sum(rz.hits) > 0 then ' HITS' || sum(rz.hits) || '(' || min(rz.sample) || ')' else '' end o
               from rz group by rz.fn, rz.st, rz.msg) g
            where g.fn in (select r2.fn from rz r2 group by r2.fn having sum(r2.hits) > 0 or (bool_and(r2.kind = 'x') and bool_or(r2.st <> 'AUTH')))
            group by g.fn order by g.fn loop
    res := res || f.fn || ' -> ' || left(f.r, 300) || E'\n';
  end loop;
  res := res || E'--- C) INCONCLUSAS (todo da el mismo error no-AUTH):\n';
  for f in select r2.fn, min(r2.st || ':' || coalesce(r2.msg, '')) r from rz r2 group by r2.fn
            having count(distinct r2.st || coalesce(r2.msg, '')) = 1 and bool_and(r2.st = 'ERR') order by r2.fn loop
    res := res || f.fn || '=' || left(f.r, 40) || E'\n';
  end loop;
  raise exception E'S2 persona=% otra=% llamadas=%\n%', v_pi, otra, cnt, res;
end $t$;
