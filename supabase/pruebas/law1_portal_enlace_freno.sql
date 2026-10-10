-- LAW-1 S1: prueba del freno del enlace del portal (portal_enlace_freno). TODO se deshace: el bloque acaba con RAISE, que
-- revierte la transacción entera; el resultado viaja en el mensaje del error. No deja filas ni marcas en la base.
-- Correr con execute_sql (MCP supabase-lawang) o psql. Resultado esperado: «PRUEBA_FRENO_OK n=<casos>».
-- Medido el 11-oct-2026 tras aplicar 20261010182058: PRUEBA_FRENO_OK n=15.
-- Simultaneidad: la función toma pg_advisory_xact_lock(7316402251001) al empezar, así que dos llamadas a la vez se ponen en
-- fila y la segunda ve la marca de la primera (caso 1b: frenada). Medido el mismo día: tras volver la función, la sesión
-- sigue teniendo ese candado (ExclusiveLock, granted) hasta el final de la transacción. Dos execute_sql «en paralelo» por
-- el MCP NO sirvieron para medir la espera: el MCP las ejecutó una detrás de otra (espera medida 0,004 s).
do $$
declare
  e1 constant text := 'prueba-law1-freno-a@axisworks.invalid';
  e2 constant text := 'prueba-law1-freno-b@axisworks.invalid';
  n int := 0; fallos text := '';
  ahora timestamptz := clock_timestamp();
begin
  -- 0. permisos: anon y authenticated no pueden ejecutarla; service_role sí
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
    fallos := fallos || ' anon_lee_tabla';
  exception when insufficient_privilege then n := n + 1;
  end;
  reset role;
  set local role service_role;

  -- 1. dos llamadas seguidas al mismo correo: la primera pasa, la segunda (a menos de 60 s) frenada
  if public.portal_enlace_freno(e1, 'autoservicio') then n := n + 1; else fallos := fallos || ' 1a'; end if;
  if not public.portal_enlace_freno(e1, 'autoservicio') then n := n + 1; else fallos := fallos || ' 1b_60s'; end if;
  -- mayúsculas y espacios = mismo correo
  if not public.portal_enlace_freno('  ' || upper(e1) || ' ', 'autoservicio') then n := n + 1; else fallos := fallos || ' 1c_normaliza'; end if;
  -- 2. libera: tras un envío fallido, el siguiente intento inmediato pasa
  perform public.portal_enlace_freno(e1, 'autoservicio', true);
  if public.portal_enlace_freno(e1, 'autoservicio') then n := n + 1; else fallos := fallos || ' 2_libera'; end if;
  reset role;

  -- 3. 5 por hora: con 5 marcas en la última hora (la última hace 10 min) la 6.ª frena; con 4 pasa
  update public.portal_enlaces_envios
     set envios = array[ahora - interval '50 min', ahora - interval '40 min', ahora - interval '30 min', ahora - interval '20 min', ahora - interval '10 min']
   where clave = e1;
  set local role service_role;
  if not public.portal_enlace_freno(e1, 'invitar') then n := n + 1; else fallos := fallos || ' 3a_6_en_hora'; end if;
  reset role;
  update public.portal_enlaces_envios
     set envios = array[ahora - interval '70 min', ahora - interval '40 min', ahora - interval '30 min', ahora - interval '20 min', ahora - interval '10 min']
   where clave = e1;
  set local role service_role;
  if public.portal_enlace_freno(e1, 'invitar') then n := n + 1; else fallos := fallos || ' 3b_marca_vieja_no_cuenta'; end if;
  reset role;
  if (select cardinality(envios) from public.portal_enlaces_envios where clave = e1) = 5 then n := n + 1; else fallos := fallos || ' 3c_poda'; end if;

  -- 4. tope global: con 30 marcas del formulario en la hora, un correo nuevo del formulario frena; uno de un admin pasa
  update public.portal_enlaces_envios
     set envios = array(select ahora - make_interval(mins => g) from generate_series(1, 30) g)
   where clave = '*';
  set local role service_role;
  if not public.portal_enlace_freno(e2, 'autoservicio') then n := n + 1; else fallos := fallos || ' 4a_global'; end if;
  if public.portal_enlace_freno(e2, 'invitar') then n := n + 1; else fallos := fallos || ' 4b_invitar_no_global'; end if;
  -- 5. origen no válido = error; correo no válido = false sin anotar
  begin
    perform public.portal_enlace_freno(e2, 'otro');
    fallos := fallos || ' 5a_origen';
  exception when invalid_parameter_value then n := n + 1;
  end;
  if not public.portal_enlace_freno('no-es-correo', 'autoservicio') then n := n + 1; else fallos := fallos || ' 5b_formato'; end if;
  reset role;
  if not exists (select 1 from public.portal_enlaces_envios where clave = 'no-es-correo') then n := n + 1; else fallos := fallos || ' 5c_anota'; end if;

  if fallos = '' then
    raise exception 'PRUEBA_FRENO_OK n=%', n;
  else
    raise exception 'PRUEBA_FRENO_FALLA n=% fallos=%', n, fallos;
  end if;
end $$;
