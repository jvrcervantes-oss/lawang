-- Prueba del paso 2B (Fase 2, 7-oct-2026): cuentas de cobro, sociedades, directorio de compradores y usuario_guarda_permisos por empresa.
-- Se ejecuta DESPUES de las migraciones 20261007001600..001900 (o pegada tras ellas en la misma peticion para ensayarlas sin rastro). Todo dentro de una transaccion que acaba en raise (rollback).
-- No crea usuarios: convierte fichas de agente existentes, como la prueba 2A:
--   ae = admin_empresa/lawang · se = super_admin_empresa/sandal_woods · a2 = admin_empresa con las dos · ctl = agente de control NO tocado (empresas vacias)
-- Cada linea OK/FALLO. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; e_ya text; e_cr text; e_ad4 text; e_ctl text;
  ids uuid[]; ems text[]; emp text[] := array['lawang','sandal_woods','lawang,sandal_woods'];
  r text := ''; fallos int := 0; i int; n bigint; x bigint; cmp uuid; v boolean;
  kar uuid; pl uuid; adm uuid; ok boolean;
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin')
     and user_id not in (ya, cr, ad4) order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{comisiones}', tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{comisiones}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{comisiones}', tipos_contrato='{}' where user_id=ad4;
  ids := array[ya, cr, ad4]; ems := array[e_ya, e_cr, e_ad4];
  select cc.client_id into cmp from public.contrato_compradores cc join public.contratos c on c.id=cc.contrato_id join public.proyectos p on p.id=c.proyecto_id
   group by cc.client_id having count(distinct p.empresa) filter (where p.empresa in ('lawang','sandal_woods')) = 2 limit 1;

  for i in 1..3 loop
    perform set_config('request.jwt.claims', json_build_object('sub',ids[i],'role','authenticated','email',ems[i])::text, true);
    set local role authenticated;
    -- cuentas de cobro: funcion y tabla directa = cuentas sin empresa + las de sus empresas
    select count(*) into x from public.cuentas_bancarias c where c.activa and (c.empresa is null or c.empresa = any (string_to_array(emp[i], ',')));
    select count(*) into n from public.cuentas_cobro_visibles();
    r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s cuentas_cobro_visibles %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    select count(*) into n from public.cuentas_bancarias where activa;
    r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s cuentas_bancarias directa %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    select count(*) into n from public.cuentas_bancarias where empresa is not null and not (empresa = any (string_to_array(emp[i], ',')));
    r := r || case when n=0 then 'OK   ' else 'FALLO' end || format(' %s cuentas de la otra empresa visibles=%s', i, n) || E'\n'; if n<>0 then fallos:=fallos+1; end if;
    -- sociedades: sin empresa o de las suyas
    select count(*) into x from public.sociedades s where s.activa and not exists (select 1 from public.empresas e where e.sociedad_clave=s.clave and not (e.clave = any (string_to_array(emp[i], ','))));
    select count(*) into n from public.sociedades_visibles();
    r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s sociedades_visibles %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    select count(*) into n from public.sociedades where activa;
    r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s sociedades directa %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    -- directorio de compradores = lo que ve de clients por RLS
    select count(*) into x from public.clients;
    select count(*) into n from public.compradores_lista();
    r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s compradores_lista %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    select count(*) into n from public.compradores_numeros();
    r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s compradores_numeros %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    -- resumen de contratos de un cliente compartido: solo filas visibles
    if cmp is not null then
      select count(*) into n from public.comprador_contratos_resumen(cmp) where not visible;
      r := r || case when n=0 then 'OK   ' else 'FALLO' end || format(' %s resumen cliente compartido filas ajenas=%s', i, n) || E'\n'; if n<>0 then fallos:=fallos+1; end if;
    end if;
    reset role;
  end loop;

  -- control: agente sin empresas = como antes (ve todo)
  perform set_config('request.jwt.claims', json_build_object('sub',ctl,'role','authenticated','email',e_ctl)::text, true);
  set local role authenticated;
  select count(*) into n from public.compradores_lista();
  select count(*) into x from public.clients c where false;  -- placeholder, se recalcula abajo como postgres
  reset role;
  select count(*) into x from public.clients;
  r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' ctl compradores_lista %s/%s (todos, sin cambio)', n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
  set local role authenticated;
  select count(*) into n from public.cuentas_cobro_visibles();
  reset role;
  select count(*) into x from public.cuentas_bancarias where activa;
  r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' ctl cuentas_cobro_visibles %s/%s (todas)', n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
  set local role authenticated;
  select count(*) into n from public.sociedades_visibles();
  reset role;
  select count(*) into x from public.sociedades where activa;
  r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' ctl sociedades_visibles %s/%s (todas)', n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;

  -- usuario_guarda_permisos: (a) un admin global NO super no toca a un admin de empresa
  select user_id into adm from public.usuarios where activo and rol='admin' and ambito='global' limit 1;
  if adm is not null then
    perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
    update public.usuarios set herramientas = array(select distinct unnest(coalesce(herramientas,'{}') || '{usuarios}')) where user_id=adm;
    perform set_config('request.jwt.claims', json_build_object('sub',adm,'role','authenticated','email',(select email from public.usuarios where user_id=adm))::text, true);
    set local role authenticated;
    ok := false;
    begin perform public.usuario_guarda_permisos(ya, '{"activo": false}'::jsonb); exception when sqlstate '42501' then ok := true; end;
    reset role;
    r := r || case when ok then 'OK   ' else 'FALLO' end || ' admin global no-super no gestiona a un admin_empresa' || E'\n'; if not ok then fallos:=fallos+1; end if;
  end if;
  -- (b) proyectos dentro de las empresas: el propietario no puede dar un proyecto sin empresa ni de la otra a quien tiene empresas marcadas
  select id into kar from public.proyectos where empresa is null limit 1;
  select id into pl from public.proyectos where empresa = 'sandal_woods' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  set local role authenticated;
  if kar is not null then
    ok := false;
    begin perform public.usuario_guarda_permisos(ya, jsonb_build_object('proyectos', jsonb_build_array(kar))); exception when sqlstate '42501' then ok := true; end;
    r := r || case when ok then 'OK   ' else 'FALLO' end || ' proyecto sin empresa rechazado a quien tiene empresas' || E'\n'; if not ok then fallos:=fallos+1; end if;
  end if;
  if pl is not null then
    ok := false;
    begin perform public.usuario_guarda_permisos(ya, jsonb_build_object('proyectos', jsonb_build_array(pl))); exception when sqlstate '42501' then ok := true; end;
    r := r || case when ok then 'OK   ' else 'FALLO' end || ' proyecto de la otra empresa rechazado' || E'\n'; if not ok then fallos:=fallos+1; end if;
    ok := true;
    begin perform public.usuario_guarda_permisos(cr, jsonb_build_object('proyectos', jsonb_build_array(pl))); exception when others then ok := false; end;
    r := r || case when ok then 'OK   ' else 'FALLO' end || ' proyecto de su empresa aceptado' || E'\n'; if not ok then fallos:=fallos+1; end if;
  end if;
  reset role;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
