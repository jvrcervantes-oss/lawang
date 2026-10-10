-- Prueba LAW-482 / LAW-483 (deja todo como estaba: TODO va en una transacción que termina en ROLLBACK). Correr con la migración
-- 20261001090500/090600 ya aplicada, pegándola entera en el MCP de Supabase de Lawang o en el SQL Editor.
-- Devuelve una fila por caso (caso, ok, detalle); cualquier ok = false es una regresión. Sin PII: las identidades se resuelven desde la base
-- y solo viajan por GUCs de la sesión (el repo de Lawang es público).
--
-- 10-oct-2026 (cierre del encargo de equipos de venta): reescrita. La de 1-oct buscaba la guarda dentro de condicion_comision_guarda, pero
-- el reparto en dos empresas la convirtió en un envoltorio que delega en _condicion_comision_guarda_en (con la guarda dentro) y ató el
-- privilegio de admin a puede_reparto_de(empresa): la estructura vieja daba un rojo falso. Y la sección 3 («pendiente de correr con datos
-- reales») ya se ejecuta: el caso LAW-483 con el ROL REAL de un admin con la casilla `comisiones_reparto`, y el caso LAW-482 sobre un
-- devengo informativo pagado, ambos dentro de esta transacción.
begin;
-- destructivo-ok: prueba con ROLLBACK; el único update toca una fila por id dentro de la transacción y se revierte
create temporary table _prueba(caso text, ok boolean, detalle text) on commit drop;
grant all on _prueba to authenticated;

-- 1. Estructura
do $t$
declare f text; v_def text; v_env text;
begin
  foreach f in array array['public.condicion_comision_activa(uuid,boolean)','public.condicion_comision_borra(uuid)'] loop
    insert into _prueba values ('1 guarda en ' || f, position('_condicion_a_su_favor' in pg_get_functiondef(f::regprocedure)) > 0, '');
  end loop;
  v_def := pg_get_functiondef('public._condicion_comision_guarda_en(uuid,jsonb,jsonb,text,text)'::regprocedure);
  v_env := pg_get_functiondef('public.condicion_comision_guarda(uuid,jsonb,jsonb,text)'::regprocedure);
  insert into _prueba values ('1 guarda_en: guarda al crear y al editar',
    (length(v_def) - length(replace(v_def, 'public._condicion_a_su_favor(', ''))) / length('public._condicion_a_su_favor(') = 2, '');
  insert into _prueba values ('1 guarda_en: la edición comprueba el closer NUEVO y el viejo', position('array[v_closer_nuevo, v_old.closer_email]' in v_def) > 0, '');
  insert into _prueba values ('1 guarda_en: v_admin = puede_reparto_de (la casilla)', position('v_admin := public.puede_reparto_de(v_emp)' in v_def) > 0, '');
  insert into _prueba values ('1 puede_reparto_de exige la casilla comisiones_reparto',
    position('comisiones_reparto' in pg_get_functiondef('public.puede_reparto_de(text)'::regprocedure)) > 0, '');
  insert into _prueba values ('1 _condicion_es_mia pasa por puede_reparto_de',
    position('puede_reparto_de' in pg_get_functiondef('public._condicion_es_mia(text,uuid,text)'::regprocedure)) > 0, '');
  -- el envoltorio no escribe por su cuenta: todo camino va a guarda_en
  insert into _prueba values ('1 condicion_comision_guarda solo delega (3 llamadas, sin insert/update propios)',
    (length(v_env) - length(replace(v_env, 'public._condicion_comision_guarda_en(', ''))) / length('public._condicion_comision_guarda_en(') = 3
    and v_env !~* '\m(insert|update)\M', '');
  insert into _prueba values ('1 reconciliador con la rama del informativo (F9M5-informativo)',
    position('F9M5-informativo' in pg_get_functiondef('public.comisiones_reconciliar(uuid,boolean,jsonb)'::regprocedure)) > 0, '');
  insert into _prueba values ('1 helpers no llamables desde fuera',
    not has_function_privilege('authenticated', 'public._condicion_a_su_favor(text[],text,uuid)', 'execute')
    and not has_function_privilege('anon', 'public._condicion_a_su_favor(text[],text,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public._condicion_comision_guarda_en(uuid,jsonb,jsonb,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.condicion_comision_guarda(uuid,jsonb,jsonb,text)', 'execute'), '');
end $t$;

-- 2. Comportamiento del helper con un email simulado en el JWT.
select set_config('request.jwt.claims', '{"email":"yo@prueba.test","role":"authenticated"}', true);
do $t$
begin
  insert into _prueba values ('2 su email cuenta como a su favor', public._condicion_a_su_favor(array['yo@prueba.test'], 'closer', null), '');
  insert into _prueba values ('2 el de otro no', not public._condicion_a_su_favor(array['otro@prueba.test'], 'closer', null), '');
  insert into _prueba values ('2 estandar sin equipo no', not public._condicion_a_su_favor(array[null::text], 'estandar', null), '');
  insert into _prueba values ('2 reasignarse una ajena cuenta', public._condicion_a_su_favor(array['yo@prueba.test', 'otro@prueba.test'], 'closer', null), '');
end $t$;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $t$
begin
  insert into _prueba values ('2 sin email nunca es a su favor', not public._condicion_a_su_favor(array['yo@prueba.test'], 'closer', null), '');
end $t$;

-- 3. Con datos reales y el rol real (todo se revierte al final).
-- Identidades, resueltas como postgres: un admin GLOBAL (no super admin) con la casilla, y otro usuario activo cualquiera.
select set_config('prueba.admin_sub', u.user_id::text, true), set_config('prueba.admin_email', lower(u.email), true)
  from public.usuarios u where u.activo and u.rol = 'admin' and 'comisiones_reparto' = any(u.herramientas) order by u.creado_en limit 1;
select set_config('prueba.otro_email', lower(u.email), true)
  from public.usuarios u where u.activo and u.rol = 'agente' and lower(u.email) <> current_setting('prueba.admin_email', true) order by u.creado_en limit 1;
select set_config('prueba.proyecto', (select p.id::text from public.proyectos p where public._empresa_de_proyecto_int(p.id) is not null order by p.id limit 1), true);
-- la empresa del proyecto se resuelve aquí, como postgres: _empresa_de_proyecto_int está cerrada a authenticated
select set_config('prueba.empresa', public._empresa_de_proyecto_int(current_setting('prueba.proyecto', true)::uuid), true);
select set_config('request.jwt.claim.sub', current_setting('prueba.admin_sub', true), true),
       set_config('request.jwt.claim.email', current_setting('prueba.admin_email', true), true),
       set_config('request.jwt.claims', json_build_object('sub', current_setting('prueba.admin_sub', true),
                  'email', current_setting('prueba.admin_email', true), 'role', 'authenticated')::text, true);

-- 3b. LAW-482 (como postgres, con las claims del admin para los triggers): un devengo informativo PAGADO cuyo importe
-- queda por encima de lo que toca (bajada) no abre «se paga la diferencia»: se actualiza en su sitio.
do $t$
declare d record; v_acc text; v_base_acc text; v_dif0 int; v_dif1 int; v_log0 int; v_log1 int; v_imp numeric;
begin
  select dv.id, dv.contrato_raiz_id, dv.importe into d from public.comisiones_devengadas dv
   where dv.nivel in ('closer', 'setter', 'team_lead') and dv.estado = 'pagada' and dv.importe_ajustado is null
   order by dv.created_at limit 1;
  if d.id is null then
    insert into _prueba values ('3b LAW-482 informativo pagado', true, 'SIN DATOS: no hay devengo informativo pagado sin ajuste (no se pudo ejercitar)');
    return;
  end if;
  select string_agg(r.accion, ',') into v_base_acc from public.comisiones_reconciliar(d.contrato_raiz_id, true) r where r.devengo_id = d.id;
  update public.comisiones_devengadas set importe = importe + 1 where id = d.id;
  select string_agg(r.accion, ',') into v_acc from public.comisiones_reconciliar(d.contrato_raiz_id, true) r where r.devengo_id = d.id;
  insert into _prueba values ('3b LAW-482 simulado: el informativo pagado se actualiza, sin diferencia', v_acc = 'actualizar',
    'antes=' || coalesce(v_base_acc, 'null') || ' tras subir 1=' || coalesce(v_acc, 'null'));
  select count(*) into v_dif0 from public.comisiones_diferencias;
  select count(*) into v_log0 from public.comisiones_ajustes_log;
  perform 1 from public.comisiones_reconciliar(d.contrato_raiz_id, false);
  select count(*) into v_dif1 from public.comisiones_diferencias;
  select count(*) into v_log1 from public.comisiones_ajustes_log;
  select importe into v_imp from public.comisiones_devengadas where id = d.id;
  insert into _prueba values ('3b LAW-482 aplicado: 0 diferencias nuevas, importe repuesto y apunte en el log',
    v_dif1 = v_dif0 and v_imp = d.importe and v_log1 > v_log0,
    'dif ' || v_dif0 || '->' || v_dif1 || ' log ' || v_log0 || '->' || v_log1 || ' importe vuelve=' || (v_imp = d.importe)::text);
exception when others then
  insert into _prueba values ('3b LAW-482', false, sqlstate || ' ' || left(sqlerrm, 160));
end $t$;

-- 3a. LAW-483 con el ROL REAL: el admin con la casilla no se crea una condición a su favor; para otro, la guarda no salta.
-- es_super_admin_de / puede_reparto_de están cerradas a authenticated: el canario de identidad se calcula aquí, como postgres
-- pero con las claims del admin (las dos leen auth.uid()).
select set_config('prueba.canario', (not public.es_super_admin_de(current_setting('prueba.empresa', true))
                  and public.puede_reparto_de(current_setting('prueba.empresa', true)))::text, true);
set local role authenticated;
do $t$
declare v_emp text := current_setting('prueba.empresa', true);
begin
  insert into _prueba values ('3a canario: rol authenticated, sesión del admin, no super admin, con reparto',
    current_user = 'authenticated' and auth.uid() is not null and current_setting('prueba.canario', true) = 'true', 'empresa ' || coalesce(v_emp, 'null'));
  begin
    perform public.condicion_comision_guarda(null, jsonb_build_object('closer_email', current_setting('prueba.admin_email', true),
      'pct_comision', 5, 'base_calculo', 'precio_total', 'proyecto_id', current_setting('prueba.proyecto', true)), '[]'::jsonb, 'prueba LAW-483');
    insert into _prueba values ('3a LAW-483: a su favor se rechaza', false, 'PASÓ: se creó una condición a su propio favor');
  exception when others then
    insert into _prueba values ('3a LAW-483: a su favor se rechaza', sqlstate = '42501' and sqlerrm like '%a su propio favor%', sqlstate || ' ' || left(sqlerrm, 120));
  end;
  begin
    perform public.condicion_comision_guarda(null, jsonb_build_object('closer_email', current_setting('prueba.otro_email', true),
      'pct_comision', 5, 'base_calculo', 'precio_total', 'proyecto_id', current_setting('prueba.proyecto', true)), '[]'::jsonb, 'prueba LAW-483');
    insert into _prueba values ('3a control: para otra persona la guarda no salta', true, 'creada (se revierte)');
  exception when others then
    insert into _prueba values ('3a control: para otra persona la guarda no salta', sqlerrm not like '%a su propio favor%', sqlstate || ' ' || left(sqlerrm, 120));
  end;
end $t$;
reset role;

select caso, ok, detalle from _prueba order by caso;
rollback;
