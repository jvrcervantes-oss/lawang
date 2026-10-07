-- Prueba del BLOQUE 9 (equipo_venta_guarda con p_empresa opcional), 7-oct-2026.
-- Se ejecuta DESPUES de la migracion 20261008700000 (o pegada tras ella en la misma peticion para ensayarla sin rastro). Todo en una transaccion que acaba en raise (rollback).
-- Sin crear usuarios: convierte fichas existentes como f2_b4_empresas.sql: ya = admin_empresa/lawang · cr = super_admin_empresa/sandal_woods · ad4 = admin_empresa con las dos · pe = super global · ctl = agente de control.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop
create or replace function pg_temp.crea(p_uid uuid, p_email text, p_sql text) returns text language plpgsql as $f$
declare v text; v_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'email', p_email)::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql into v_id;
    select e.empresa into v from public.equipos_venta e where e.id = v_id;
    raise exception 'deshacer' using errcode = 'LWS03';
  exception when sqlstate 'LWS03' then null;
            when others then v := sqlstate;
  end;
  execute 'reset role';
  return v;
end $f$;

do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; pe uuid; e_ya text; e_cr text; e_ad4 text; e_ctl text; e_pe text;
  st uuid; r text := ''; fallos int := 0; v text; n int;
begin
  select user_id into jv from public.usuarios where email = 'jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email = 'yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email = 'cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email = 'adenovit.b@gmail.com';
  select user_id, email into pe, e_pe from public.usuarios where email = 'pepito@lawangproperties.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito = 'global' and cardinality(coalesce(empresas, '{}')) = 0 and rol = 'agente' and user_id not in (ya, cr, ad4) order by email limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', jv, 'role', 'authenticated', 'email', 'jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ya;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = cr;
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang,sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{}', tipos_contrato = '{}' where user_id = ad4;
  select id into st from public.equipos_venta where empresa = 'sandal_woods' limit 1;

  select count(*) into n from pg_proc where proname = 'equipo_venta_guarda' and pronamespace = 'public'::regnamespace;
  r := r || case when n = 1 then 'OK   ' else 'FALLO' end || format(' una sola equipo_venta_guarda (%s) — sin ambiguedad PGRST203', n) || E'\n'; if n <> 1 then fallos := fallos + 1; end if;
  r := r || case when has_function_privilege('authenticated', 'public.equipo_venta_guarda(uuid,text,text,text)', 'execute') and not has_function_privilege('anon', 'public.equipo_venta_guarda(uuid,text,text,text)', 'execute') then 'OK   ' else 'FALLO' end || ' EXECUTE: authenticated si, anon no' || E'\n';
  if not (has_function_privilege('authenticated', 'public.equipo_venta_guarda(uuid,text,text,text)', 'execute') and not has_function_privilege('anon', 'public.equipo_venta_guarda(uuid,text,text,text)', 'execute')) then fallos := fallos + 1; end if;

  -- (clave, esperado, descripcion, sql, uid, email)
  declare c record;
  begin
    for c in select * from (values
      (ya, e_ya, 'lawang',       'ae (una empresa), 3 argumentos: nace en lawang',            format('select public.equipo_venta_guarda(null, ''T1'', %L)', e_ctl)),
      (cr, e_cr, 'sandal_woods', 'se (una empresa), 3 argumentos: nace en sandal_woods',      format('select public.equipo_venta_guarda(null, ''T2'', %L)', e_ctl)),
      (pe, e_pe, 'lawang',       'global sin parametro: lawang como hoy',                     format('select public.equipo_venta_guarda(null, ''T3'', %L)', e_ctl)),
      (pe, e_pe, 'sandal_woods', 'global con p_empresa=sandal_woods: nace ahi',               format('select public.equipo_venta_guarda(null, ''T4'', %L, ''sandal_woods'')', e_ctl)),
      (pe, e_pe, 'lawang',       'global con p_empresa=lawang',                               format('select public.equipo_venta_guarda(null, ''T5'', %L, ''lawang'')', e_ctl)),
      (pe, e_pe, '22023',        'empresa inexistente: 22023',                                format('select public.equipo_venta_guarda(null, ''T6'', %L, ''no_existe'')', e_ctl)),
      (pe, e_pe, '22023',        'manager que solo vende en lawang no dirige un equipo de sandal_woods', format('select public.equipo_venta_guarda(null, ''T7'', %L, ''sandal_woods'')', e_ya)),
      (ad4, e_ad4, '22023',      'dos empresas sin indicar cual: 22023',                      format('select public.equipo_venta_guarda(null, ''T8'', %L)', e_ctl)),
      (ad4, e_ad4, 'sandal_woods','dos empresas, elige sandal_woods',                         format('select public.equipo_venta_guarda(null, ''T9'', %L, ''sandal_woods'')', e_ctl)),
      (ad4, e_ad4, 'lawang',     'dos empresas, elige lawang',                                format('select public.equipo_venta_guarda(null, ''T10'', %L, ''lawang'')', e_ctl)),
      (ya, e_ya, '42501',        'ae NO crea en sandal_woods (no la gobierna)',               format('select public.equipo_venta_guarda(null, ''T11'', %L, ''sandal_woods'')', e_ctl)),
      (cr, e_cr, '42501',        'se NO crea en lawang',                                      format('select public.equipo_venta_guarda(null, ''T12'', %L, ''lawang'')', e_ctl)),
      (ctl, e_ctl, '42501',      'agente de control sigue rechazado (sin y con empresa)',     format('select public.equipo_venta_guarda(null, ''T13'', %L, ''lawang'')', e_ctl)),
      (ctl, e_ctl, '42501',      'agente de control sigue rechazado (3 argumentos)',          format('select public.equipo_venta_guarda(null, ''T14'', %L)', e_ctl)),
      (ad4, e_ad4, '22023',      'editar un equipo con otra empresa distinta de la suya: 22023', format('select public.equipo_venta_guarda(%L, ''T15'', %L, ''lawang'')', st, e_ctl)),
      (ad4, e_ad4, 'sandal_woods','editar un equipo de sandal_woods nombrando su empresa: ok, sigue en sandal_woods', format('select public.equipo_venta_guarda(%L, ''T16'', %L, ''sandal_woods'')', st, e_ctl))
    ) as t(uid, email, esperado, que, q) loop
      v := pg_temp.crea(c.uid, c.email, c.q);
      r := r || case when v = c.esperado then 'OK   ' else 'FALLO' end || format(' %s (%s)', c.que, v) || E'\n';
      if v is distinct from c.esperado then fallos := fallos + 1; end if;
    end loop;
  end;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
