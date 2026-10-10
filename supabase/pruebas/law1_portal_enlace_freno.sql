-- LAW-1: prueba del freno del enlace del portal (portal_enlace_freno(text,text,text,boolean), migración 20261010194801 que
-- sustituye a la de 20261010182058). TODO se deshace: el bloque acaba con RAISE, que revierte la transacción entera; el
-- resultado viaja en el mensaje del error. No deja filas ni marcas en la base (ni la purga que prueba el caso 6).
-- Correr con execute_sql (MCP supabase-lawang) o psql. Resultado esperado: «PRUEBA_FRENO_OK n=<casos>».
-- Medido el 11-oct-2026 tras aplicar 20261010194801: PRUEBA_FRENO_OK n=29, y después la base con 1 fila (la global), 0 marcas y 0 filas de IP.
-- Simultaneidad: la función toma pg_advisory_xact_lock(7316402251001) al empezar, así que dos llamadas a la vez se ponen en
-- fila y la segunda ve la marca de la primera (caso 1b: frenada). Dos execute_sql «en paralelo» por el MCP NO sirven para
-- medir la espera: el MCP las ejecuta una detrás de otra.
do $$
declare
  e1 constant text := 'prueba-law1-freno-a@axisworks.invalid';
  e2 constant text := 'prueba-law1-freno-b@axisworks.invalid';
  e3 constant text := 'prueba-law1-freno-c@axisworks.invalid';
  viejo constant text := 'prueba-law1-freno-viejo@axisworks.invalid';
  ipa constant text := repeat('a', 64);
  ipb constant text := repeat('b', 64);
  ipv constant text := repeat('c', 64);
  n int := 0; fallos text := '';
  ahora timestamptz := clock_timestamp();
  r text;
begin
  -- 0. permisos: anon y authenticated no pueden ejecutarla ni leer las tablas; service_role sí ejecuta
  begin
    set local role anon;
    perform public.portal_enlace_freno(e1, 'autoservicio');
    fallos := fallos || ' anon_ejecuta';
  exception when insufficient_privilege then n := n + 1;
  end;
  reset role;
  begin
    set local role authenticated;
    perform public.portal_enlace_freno(e1, 'autoservicio');
    fallos := fallos || ' authenticated_ejecuta';
  exception when insufficient_privilege then n := n + 1;
  end;
  reset role;
  begin
    set local role anon;
    perform 1 from public.portal_enlaces_envios limit 1;
    fallos := fallos || ' anon_lee_envios';
  exception when insufficient_privilege then n := n + 1;
  end;
  reset role;
  begin
    set local role service_role;
    perform 1 from public.portal_enlaces_ip limit 1;
    fallos := fallos || ' service_lee_ip';
  exception when insufficient_privilege then n := n + 1;
  end;
  reset role;
  set local role service_role;

  -- 1. dos llamadas seguidas al mismo correo: la primera pasa, la segunda (a menos de 60 s) frenada por correo
  if public.portal_enlace_freno(e1, 'autoservicio') = 'pasa' then n := n + 1; else fallos := fallos || ' 1a'; end if;
  if public.portal_enlace_freno(e1, 'autoservicio') = 'correo' then n := n + 1; else fallos := fallos || ' 1b_60s'; end if;
  -- mayúsculas y espacios = mismo correo
  if public.portal_enlace_freno('  ' || upper(e1) || ' ', 'autoservicio') = 'correo' then n := n + 1; else fallos := fallos || ' 1c_normaliza'; end if;
  -- 2. libera: tras un envío fallido, el siguiente intento inmediato pasa
  if public.portal_enlace_freno(e1, 'autoservicio', null, true) = 'liberado' then n := n + 1; else fallos := fallos || ' 2a_liberado'; end if;
  if public.portal_enlace_freno(e1, 'autoservicio') = 'pasa' then n := n + 1; else fallos := fallos || ' 2b_libera'; end if;
  reset role;

  -- 3. 5 por hora por correo: con 5 marcas en la última hora (la última hace 10 min) la 6.ª frena; con 4 pasa
  update public.portal_enlaces_envios
     set envios = array[ahora - interval '50 min', ahora - interval '40 min', ahora - interval '30 min', ahora - interval '20 min', ahora - interval '10 min']
   where clave = e1;
  set local role service_role;
  if public.portal_enlace_freno(e1, 'invitar') = 'correo' then n := n + 1; else fallos := fallos || ' 3a_6_en_hora'; end if;
  reset role;
  update public.portal_enlaces_envios
     set envios = array[ahora - interval '70 min', ahora - interval '40 min', ahora - interval '30 min', ahora - interval '20 min', ahora - interval '10 min']
   where clave = e1;
  set local role service_role;
  if public.portal_enlace_freno(e1, 'invitar') = 'pasa' then n := n + 1; else fallos := fallos || ' 3b_marca_vieja_no_cuenta'; end if;
  reset role;
  if (select cardinality(envios) from public.portal_enlaces_envios where clave = e1) = 5 then n := n + 1; else fallos := fallos || ' 3c_poda'; end if;

  -- 4. por IP: con 5 marcas de la IP A en la hora, un correo NUEVO desde A frena ('ip'); desde B pasa; un admin no cuenta IP
  insert into public.portal_enlaces_ip (ip_hash, envios, actualizado_at)
  values (ipa, array[ahora - interval '50 min', ahora - interval '40 min', ahora - interval '30 min', ahora - interval '20 min', ahora - interval '10 min'], ahora)
  on conflict (ip_hash) do update set envios = excluded.envios, actualizado_at = excluded.actualizado_at;
  set local role service_role;
  if public.portal_enlace_freno(e2, 'autoservicio', ipa) = 'ip' then n := n + 1; else fallos := fallos || ' 4a_ip'; end if;
  if public.portal_enlace_freno(e2, 'autoservicio', ipb) = 'pasa' then n := n + 1; else fallos := fallos || ' 4b_otra_ip'; end if;
  reset role;
  if (select cardinality(envios) from public.portal_enlaces_ip where ip_hash = ipb) = 1 then n := n + 1; else fallos := fallos || ' 4c_anota_ip'; end if;
  -- libera también devuelve la marca de la IP
  set local role service_role;
  perform public.portal_enlace_freno(e2, 'autoservicio', ipb, true);
  reset role;
  if (select cardinality(envios) from public.portal_enlaces_ip where ip_hash = ipb) = 0 then n := n + 1; else fallos := fallos || ' 4d_libera_ip'; end if;
  set local role service_role;
  if public.portal_enlace_freno(e3, 'invitar', ipa) = 'pasa' then n := n + 1; else fallos := fallos || ' 4e_invitar_sin_ip'; end if;
  reset role;

  -- 5. tope global: con 30 marcas del formulario en la hora, un correo nuevo desde una IP limpia frena ('global'); un admin pasa
  update public.portal_enlaces_envios
     set envios = array(select ahora - make_interval(mins => g) from generate_series(1, 30) g)
   where clave = '*';
  set local role service_role;
  r := public.portal_enlace_freno('prueba-law1-freno-g@axisworks.invalid', 'autoservicio', repeat('d', 64));
  if r = 'global' then n := n + 1; else fallos := fallos || ' 5a_global:' || coalesce(r, 'null'); end if;
  if public.portal_enlace_freno('prueba-law1-freno-g@axisworks.invalid', 'invitar') = 'pasa' then n := n + 1; else fallos := fallos || ' 5b_invitar_no_global'; end if;
  reset role;

  -- 6. purga: una fila de OTRO correo y una de OTRA IP sin actividad en más de 1 h desaparecen; la del correo y la IP de la
  --    llamada en curso no (aunque también lleven más de 1 h), ni la global
  insert into public.portal_enlaces_envios (clave, envios, actualizado_at) values (viejo, array[ahora - interval '3 hours'], ahora - interval '3 hours');
  update public.portal_enlaces_envios set actualizado_at = ahora - interval '2 hours', envios = '{}' where clave = e3;
  insert into public.portal_enlaces_ip (ip_hash, envios, actualizado_at) values (ipv, array[ahora - interval '3 hours'], ahora - interval '3 hours');
  update public.portal_enlaces_ip set actualizado_at = ahora - interval '2 hours', envios = '{}' where ip_hash = ipb;
  update public.portal_enlaces_envios set envios = '{}' where clave = '*';
  set local role service_role;
  r := public.portal_enlace_freno(e3, 'autoservicio', ipb);
  reset role;
  if r = 'pasa' then n := n + 1; else fallos := fallos || ' 6a_pasa:' || coalesce(r, 'null'); end if;
  if not exists (select 1 from public.portal_enlaces_envios where clave = viejo) then n := n + 1; else fallos := fallos || ' 6b_purga_correo'; end if;
  if not exists (select 1 from public.portal_enlaces_ip where ip_hash = ipv) then n := n + 1; else fallos := fallos || ' 6c_purga_ip'; end if;
  if exists (select 1 from public.portal_enlaces_envios where clave = e3) then n := n + 1; else fallos := fallos || ' 6d_correo_actual_queda'; end if;
  if exists (select 1 from public.portal_enlaces_ip where ip_hash = ipb) then n := n + 1; else fallos := fallos || ' 6e_ip_actual_queda'; end if;
  if exists (select 1 from public.portal_enlaces_envios where clave = '*') then n := n + 1; else fallos := fallos || ' 6f_global_queda'; end if;

  -- 7. origen no válido = error; ip_hash sin forma = error; correo no válido = 'invalido' sin anotar
  set local role service_role;
  begin
    perform public.portal_enlace_freno(e2, 'otro');
    fallos := fallos || ' 7a_origen';
  exception when invalid_parameter_value then n := n + 1;
  end;
  begin
    perform public.portal_enlace_freno(e2, 'autoservicio', '10.0.0.1');
    fallos := fallos || ' 7b_ip_en_claro';
  exception when invalid_parameter_value then n := n + 1;
  end;
  if public.portal_enlace_freno('no-es-correo', 'autoservicio', ipb) = 'invalido' then n := n + 1; else fallos := fallos || ' 7c_formato'; end if;
  reset role;
  if not exists (select 1 from public.portal_enlaces_envios where clave = 'no-es-correo') then n := n + 1; else fallos := fallos || ' 7d_anota'; end if;

  if fallos = '' then
    raise exception 'PRUEBA_FRENO_OK n=%', n;
  else
    raise exception 'PRUEBA_FRENO_FALLA n=% fallos=%', n, fallos;
  end if;
end $$;
