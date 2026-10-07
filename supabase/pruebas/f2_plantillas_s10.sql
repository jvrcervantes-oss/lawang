-- Prueba de S10 cierre (8-oct-2026): despues de las migraciones 20261009030000 y 20261009030100. Un solo bloque que termina en raise (ensayo sin rastro). Debe decir FALLOS=0.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); el equipo y la cuenta de prueba se deshacen
do $t$
declare r text := ''; n int; e uuid; s text; c1 text; c2 text; em text; fallos int;
begin
  -- 1 · ninguna de las 3 funciones de trigger la ejecuta authenticated, anon ni service_role
  select count(*) into n from pg_proc p join pg_roles ro on ro.rolname in ('authenticated','anon','service_role')
   where p.pronamespace = 'public'::regnamespace and p.proname in ('un_solo_default_por_plantilla','_trg_equipos_venta_plantilla_defecto','_trg_plantilla_reparto_suma_100')
     and has_function_privilege(ro.oid, p.oid, 'execute');
  r := r || case when n = 0 then 'OK    ' else 'FALLO ' end || '1 las 3 funciones de trigger sin EXECUTE para el API (' || n || E')\n';
  -- 2 · los triggers siguen disparando: equipo nuevo nace con su reparto por defecto (2 filas) y la suma 100 frena
  select coalesce(min(empresa), 'lawang') into em from public.equipos_venta;
  insert into public.equipos_venta (nombre, manager_email, empresa) values ('zz prueba s10', 'zz_s10@example.test', em) returning id into e;
  select count(*) into n from public.plantilla_reparto where equipo_id = e;
  r := r || case when n = 2 then 'OK    ' else 'FALLO ' end || '2 trg_equipos_venta_plantilla_defecto dispara (' || n || E' filas)\n';
  set constraints all immediate;
  begin update public.plantilla_reparto set pct = 10 where equipo_id = e and rol_tipo = 'closer'; r := r || E'FALLO 3 la suma 100 no frena\n';
  exception when check_violation then r := r || E'OK    3 trg_plantilla_reparto_suma_100 frena\n'; end;
  -- 3 · un solo default por plantilla de cuentas
  select slug, clave into s, c1 from public.plantilla_cuentas where es_default limit 1;
  select clave into c2 from public.cuentas_bancarias where clave <> c1 limit 1;
  if s is not null and c2 is not null then
    insert into public.plantilla_cuentas (slug, clave, es_default) values (s, c2, true);
    select count(*) into n from public.plantilla_cuentas where slug = s and es_default;
    r := r || case when n = 1 then 'OK    ' else 'FALLO ' end || '4 trg_un_solo_default deja un solo default (' || n || E')\n';
  else r := r || E'FALLO 4 sin datos para probar trg_un_solo_default\n'; end if;
  -- 4 · promotora_razon para las dos empresas y nada activado ni cruzado
  select count(*) into n from public.plantilla_ficha where clave = 'promotora_razon' and valor = 'PT Tepi Sun Gai' and empresa in ('lawang','sandal_woods');
  r := r || case when n = 2 then 'OK    ' else 'FALLO ' end || '5 promotora_razon en las 2 empresas (' || n || E')\n';
  select count(*) into n from public.plantilla_contrato_versiones where estado = 'activa';
  r := r || case when n = 0 then 'OK    ' else 'FALLO ' end || '6 0 versiones activas (' || n || E')\n';
  select count(*) into n from public.plantilla_sociedad_cruce;
  r := r || case when n = 0 then 'OK    ' else 'FALLO ' end || '7 0 cruces empresa-sociedad (' || n || E')\n';
  fallos := (select count(*) from regexp_matches(r, 'FALLO', 'g'));
  raise exception E'INFORME S10\n%FALLOS=%', r, fallos;
end $t$;
