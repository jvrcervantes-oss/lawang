-- Prueba de la migracion 20261009040000 (5 borradores v2 de Sandal Woods, 8-oct-2026). Se pega DESPUES de la migracion. Un solo bloque en transaccion que acaba en raise (rollback): FALLOS=0.
-- No activa nada de verdad: las activaciones de prueba se deshacen con el rollback.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback)
do $t$
declare
  r text := ''; n bigint; v text; ok boolean; id1 uuid; u text;
  uL uuid; eL text; uS uuid; eS text; uJ uuid; eJ text;
  s5 text[] := array['carta_reserva','ppjb_reserva','ppjb_parcela','ppjb_construccion','poa_notario'];
  s text;
begin
  -- 1 · Lawang intacto: 20 semillas, ninguna version de empresa, ninguna activa; sus dos REV04 siguen en nunca_activable
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang';
  r := r || case when n = 20 then 'OK    ' else 'FALLO ' end || '1a Lawang conserva sus 20 versiones (' || n || E')\n';
  select count(*) into n from public.plantilla_contrato_versiones where empresa = 'lawang' and (origen <> 'semilla' or estado <> 'borrador');
  r := r || case when n = 0 then 'OK    ' else 'FALLO ' end || '1b ninguna version de Lawang es de empresa ni activa (' || n || E')\n';
  select count(*) into n from public.plantilla_nunca_activable where empresa = 'lawang' and slug in ('ppjb_parcela','ppjb_construccion');
  r := r || case when n = 2 then 'OK    ' else 'FALLO ' end || '1c los candados REV04 de Lawang siguen (' || n || E')\n';
  -- 2 · solo_global se mantiene
  select count(*) into n from public.plantilla_solo_global where slug in ('ppjb_parcela','ppjb_construccion','poa_notario');
  r := r || case when n = 3 then 'OK    ' else 'FALLO ' end || '2 plantilla_solo_global sigue con las 3 (' || n || E')\n';
  -- 3 · los 5 borradores de Sandal Woods
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = 'sandal_woods' and v.slug = any (s5) and v.origen = 'empresa' and v.estado = 'borrador' and v.activable and v.bloqueo_motivo is null
     and v.hash = public._plantilla_hash(c.cuerpo_html) and v.bytes = octet_length(c.cuerpo_html);
  r := r || case when n = 5 then 'OK    ' else 'FALLO ' end || '3 los 5 borradores de Sandal Woods: activables, hash y bytes del servidor (' || n || E')\n';
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = 'sandal_woods' and v.origen = 'empresa' and public._plantilla_norm(c.cuerpo_html) ~ '(tepisungai|lawang)';
  r := r || case when n = 0 then 'OK    ' else 'FALLO ' end || '4 ni rastro de Tepi Sun Gai / Lawang en el texto visible (' || n || E')\n';
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
   where v.empresa = 'sandal_woods' and v.origen = 'empresa' and c.cuerpo_html ~ '<title>[^<]*\{\{prom_marca\}\}</title>';
  r := r || case when n = 5 then 'OK    ' else 'FALLO ' end || '5 el titulo lleva {{prom_marca}} (' || n || E')\n';
  -- 6 · el texto contractual es identico a la semilla (solo cambia el titulo)
  select count(*) into n from public.plantilla_contrato_versiones v join public.plantilla_contrato_cuerpos c on c.version_id = v.id
    join public.plantilla_contrato_versiones sv on sv.id = v.hereda_de join public.plantilla_contrato_cuerpos sc on sc.version_id = sv.id
   where v.empresa = 'sandal_woods' and v.origen = 'empresa'
     and public._plantilla_ws(replace(c.cuerpo_html, ' — {{prom_marca}}</title>', ' — LAWANG</title>')) = public._plantilla_ws(public._plantilla_sin_notas(sc.cuerpo_html));
  r := r || case when n = 5 then 'OK    ' else 'FALLO ' end || '6 salvo el titulo, igual a la semilla de la que heredan (' || n || E')\n';
  -- 7 · activacion de prueba (se deshace): el super de Sandal Woods puede, el admin de Lawang no
  select user_id, email into uL, eL from public.usuarios where activo and ambito = 'global' and rol = 'agente' order by email limit 1;
  select user_id, email into uS, eS from public.usuarios where activo and ambito = 'global' and rol = 'agente' and user_id <> uL order by email limit 1;
  select user_id, email into uJ, eJ from public.usuarios where email = 'jvr.cervantes@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub', uJ, 'role', 'authenticated', 'email', eJ)::text, true);
  update public.usuarios set rol = 'admin_empresa', ambito = 'empresa', empresas = '{lawang}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = uL;
  update public.usuarios set rol = 'super_admin_empresa', ambito = 'empresa', empresas = '{sandal_woods}', proyectos = '{}', proyectos_supervisados = '{}', herramientas = '{contratos}', tipos_contrato = '{}' where user_id = uS;
  select id into id1 from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = 'carta_reserva' and origen = 'empresa';
  perform set_config('request.jwt.claims', json_build_object('sub', uL, 'role', 'authenticated', 'email', eL)::text, true);
  set local role authenticated;
  begin perform public.plantilla_contrato_activa(id1, 'Persona de Prueba', true); v := 'ACTIVO'; exception when others then v := 'ERR' || sqlstate; end;
  reset role;
  r := r || case when v = 'ERR42501' then 'OK    ' else 'FALLO ' end || '7a el admin de Lawang NO activa un texto de Sandal Woods (' || v || E')\n';
  perform set_config('request.jwt.claims', json_build_object('sub', uS, 'role', 'authenticated', 'email', eS)::text, true);
  foreach s in array s5 loop
    select id into id1 from public.plantilla_contrato_versiones where empresa = 'sandal_woods' and slug = s and origen = 'empresa';
    set local role authenticated;
    begin perform public.plantilla_contrato_activa(id1, 'Persona de Prueba', true); v := 'ACTIVO'; exception when others then v := 'ERR' || sqlstate || left(sqlerrm, 80); end;
    reset role;
    r := r || case when v = 'ACTIVO' then 'OK    ' else 'FALLO ' end || '7b el super de Sandal Woods activa ' || s || ' (' || v || E')\n';
  end loop;
  raise exception 'INFORME' using errcode = 'LWS06', detail = r;
exception when sqlstate 'LWS06' then
  get stacked diagnostics u = pg_exception_detail;
  raise exception E'\n%FALLOS=%', u, (length(u) - length(replace(u, 'FALLO', ''))) / 5;
end $t$;
