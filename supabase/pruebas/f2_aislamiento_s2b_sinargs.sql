-- PRUEBA FINAL DE AISLAMIENTO · SECCION 2b (7-oct-2026): funciones DEFINER de LECTURA sin argumentos. Un lector de empresa debe ver menos (o distinto) que un admin global.
-- Para cada funcion `stable` sin argumentos se saca md5+longitud de lo que devuelve a: ae_L, se_L, ae_S, se_S (roles de empresa de prueba), adm (admin global), sup (super admin global) y ctl (agente global sin empresas).
-- SOSPECHA = el rol de empresa recibe EXACTAMENTE lo mismo que el admin global y no es vacio (la funcion no filtra por empresa). Todo en subtransacciones que se deshacen.
-- destructivo-ok: solo lectura; termina en raise (rollback)
do $t$
declare
  jv uuid; je text; ids uuid[]; ems text[]; adm uuid; adme text; sup uuid; supe text; ctl uuid; ctle text; f record; i int; outt text; hh text[]; ln int[]; st text[]; res text := ''; n int := 0;
  u uuid[]; e text[]; lab text[] := array['ae_L','se_L','ae_S','se_S','adm','sup','ctl'];
begin
  select user_id, email into jv, je from public.usuarios where es_propietario;
  select array_agg(user_id order by o), array_agg(email order by o) into ids, ems from (
    select user_id, email, case email when 'yanayjefferson@gmail.com' then 1 when 'adenovit.b@gmail.com' then 2 when 'david@newconcisa.com' then 3 when 'cris.blueiestates@gmail.com' then 4 end o
      from public.usuarios where email in ('yanayjefferson@gmail.com','adenovit.b@gmail.com','david@newconcisa.com','cris.blueiestates@gmail.com')) q;
  select user_id, email into adm, adme from public.usuarios where email = 'andreabenimeli@gmail.com';
  select user_id, email into sup, supe from public.usuarios where email = 'pepito@lawangproperties.com';
  select user_id, email into ctl, ctle from public.usuarios where email = 'dortegag@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', je)::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[1];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[2];
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[3];
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=(select array_agg(distinct h) from public.usuarios, unnest(herramientas) h), tipos_contrato=(select array_agg(distinct h) from public.usuarios, unnest(tipos_contrato) h) where user_id=ids[4];
  perform set_config('request.jwt.claims', '', true); reset role;
  u := ids || array[adm, sup, ctl]; e := ems || array[adme, supe, ctle];
  for f in select p.proname, p.provolatile from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.pronargs = 0 and p.prorettype <> 'trigger'::regtype
            and has_function_privilege('authenticated', p.oid, 'execute') and p.provolatile in ('s', 'i')
            and p.proname !~ '^(es_|puede|alcance_|_|mis_|empresa_|modo_obligatorio|intranet_estado|instancia_marca|gastos_acceso|uid_sesion|crm_mi_alcance|mi_alcance|portal_)'
            order by p.proname loop
    hh := array[]::text[]; ln := array[]::int[]; st := array[]::text[];
    for i in 1..7 loop
      outt := '';
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', u[i], 'role', 'authenticated', 'email', e[i])::text, true);
        set local statement_timeout = '8s';
        set local role authenticated;
        execute format('select string_agg(x::text, '','' order by x::text) from public.%I() x', f.proname) into outt;
        raise exception 'RB' using errcode = 'ZZ001', detail = left(coalesce(outt, ''), 400000);
      exception
        when sqlstate 'ZZ001' then get stacked diagnostics outt = pg_exception_detail; st := array_append(st, 'ok');
        when others then outt := 'E' || sqlstate; st := array_append(st, 'E');
      end;
      perform set_config('request.jwt.claims', '', true); reset role;
      hh := array_append(hh, left(md5(outt), 6)); ln := array_append(ln, length(outt));
    end loop;
    n := n + 1;
    if st[5] = 'ok' and ln[5] > 2 then
      res := res || format(E'%-34s len ae_L=%s se_L=%s ae_S=%s se_S=%s | adm=%s sup=%s ctl=%s | igual a adm: %s\n', f.proname, ln[1], ln[2], ln[3], ln[4], ln[5], ln[6], ln[7],
               concat_ws(',', case when hh[1] = hh[5] then 'ae_L' end, case when hh[2] = hh[5] then 'se_L' end, case when hh[3] = hh[5] then 'ae_S' end, case when hh[4] = hh[5] then 'se_S' end));
    end if;
  end loop;
  raise exception E'S2b % funciones sin argumentos\n%', n, res;
end $t$;
