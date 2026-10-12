-- Prueba por PERFILES del asistente IA del editor de textos (migración 20261013000000_editor_ia_apagado.sql, 13-oct-2026).
-- Se ejecuta DESPUÉS de aplicar la migración (o, antes de aplicarla, en el MISMO envío que ella: migración + este bloque).
-- Todo en una transacción que acaba en `raise exception` (rollback, sin rastro): el veredicto sale en el mensaje
-- «FALLOS=0 de N casos | …». Solo cuenta y códigos: ningún dato personal, ningún texto de contrato.
-- destructivo-ok: prueba en transacción que termina en raise (rollback); no se borra nada.
-- Perfiles: super admin global, admin de una empresa (alcance a UNA empresa), agente raso, anon y la edge (service_role).
-- Usa usuarios EXISTENTES; en una base de ensayo sin ellos, el ensayo los siembra antes (ver tools del estudio).
-- Lo que NO puede probar un bloque: dos peticiones simultáneas (una sola sesión). El contador es seguro por construcción
-- (un update condicional por fila); aquí se prueba en secuencia que nunca pasa del tope ni baja de cero.
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_sup uuid; v_sup_em text; v_ae uuid; v_ae_em text; v_ea text; v_eb text; v_ag uuid; v_ag_em text;
  v_slug text; v_ver uuid; r text; j jsonb; v_uso uuid; v_uso2 uuid; n int; i int; b boolean;
  h1 text := repeat('a', 64); h2 text := repeat('b', 64);
begin
  execute $f$
    create function pg_temp.intenta(p_rol text, p_sub uuid, p_email text, p_sql text) returns text
    language plpgsql as $g$
    declare n bigint; v_h text;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_rol, 'email', p_email)::text, true);
      execute format('set local role %I', p_rol);
      begin
        -- se EJECUTA la sentencia tal cual: un count(*) sobre una subconsulta deja sin evaluar una función stable y daría verde sin llamarla
        execute p_sql;
        get diagnostics n = row_count;
        reset role;
        return 'OK:' || n;
      exception when others then
        get stacked diagnostics v_h = pg_exception_hint;
        reset role;
        return 'E' || sqlstate || '/' || coalesce(v_h, '');
      end;
    end $g$;
  $f$;
  -- como intenta, pero devuelve el jsonb que contesta la función (o null si falla)
  execute $f$
    create function pg_temp.pide(p_rol text, p_sub uuid, p_email text, p_sql text) returns jsonb
    language plpgsql as $g$
    declare v jsonb;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_rol, 'email', p_email)::text, true);
      execute format('set local role %I', p_rol);
      begin
        execute p_sql into v;
        reset role;
        return v;
      exception when others then
        reset role;
        return null;
      end;
    end $g$;
  $f$;

  -- ── perfiles reales (sin literales) ──
  select user_id, email into v_sup, v_sup_em from public.usuarios where rol = 'super_admin' and activo order by user_id limit 1;
  select user_id, email, empresas[1] into v_ae, v_ae_em, v_ea from public.usuarios
   where rol in ('admin_empresa', 'super_admin_empresa') and ambito = 'empresa' and activo and cardinality(empresas) = 1 order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and activo order by user_id limit 1;
  select e.clave into v_eb from public.empresas e where e.clave <> v_ea and e.activa order by e.clave limit 1;
  select v.slug, v.id into v_slug, v_ver from public.plantilla_contrato_versiones v where v.empresa = v_ea order by v.slug, v.version limit 1;
  if v_sup is null or v_ae is null or v_ag is null or v_eb is null or v_slug is null then
    raise exception 'FALLOS=1 | sin perfiles de prueba (super %, admin de empresa %, agente %, otra empresa %, plantilla %)',
      v_sup is not null, v_ae is not null, v_ag is not null, v_eb is not null, v_slug is not null;
  end if;

  -- ═════════ A. NACE APAGADO ═════════
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or (j ->> 'encendido')::boolean is not false or coalesce(j ->> 'motivo', '') = '' then fallos := fallos + 1; resumen := resumen || ' [A1 estado inicial: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'E55000/apagado' then fallos := fallos + 1; resumen := resumen || ' [A2 reserva apagada: ' || r || ']'; end if;
  select count(*) into n from public.editor_ia_uso; total := total + 1; if n <> 0 then fallos := fallos + 1; resumen := resumen || ' [A3 apunte con el asistente apagado]'; end if;
  -- encender sin precios: se rechaza y no se guarda
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(%L, %L::jsonb, %L)', v_ea, '{"encendido": true}', 'prueba'));
  total := total + 1; if r <> 'E22023/faltan_datos' then fallos := fallos + 1; resumen := resumen || ' [A4 encender sin precio: ' || r || ']'; end if;
  select count(*) into n from public.editor_ia_empresa where encendido; total := total + 1; if n <> 0 then fallos := fallos + 1; resumen := resumen || ' [A5 quedó encendida]'; end if;

  -- ═════════ B. QUIÉN PUEDE QUÉ ═════════
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, 'select public.editor_ia_ajustes_datos()');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B1 admin de empresa lee precios: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"precio_credito": 0}', 'prueba'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B2 admin de empresa pone precio: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_ajustes_guarda(%L, %L::jsonb, %L)', v_ea, '{"encendido": true}', 'prueba'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B3 admin de empresa se enciende: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_eb));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B4 admin mira otra empresa: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ag, v_ag_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B5 agente mira el estado: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ag, v_ag_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, null, 1)', v_ea, 'propone', v_slug, 'estandar'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B6 agente reserva: ' || r || ']'; end if;
  r := pg_temp.intenta('anon', null, null, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B7 anon: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_cierra(%L, true, %L, 1, 1, 0, null, %L::jsonb)', gen_random_uuid(), 'x', '[]'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B8 un navegador cierra un uso: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, 'select * from public.editor_ia_uso');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B9 tabla de usos legible: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('update public.editor_ia_saldo set usados = 0 where empresa = %L returning 1', v_ea));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B10 saldo escribible: ' || r || ']'; end if;
  -- formas de dato: un texto donde va un número, un rango fuera
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"creditos_propuesta": "2"}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B11 texto por número: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"creditos_propuesta": 0}', 'prueba'));
  total := total + 1; if r not like 'E23514%' then fallos := fallos + 1; resumen := resumen || ' [B12 fuera de rango: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"modelo": "x"}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B13 clave desconocida: ' || r || ']'; end if;

  -- ═════════ C. EL OWNER RELLENA Y ENCIENDE ═════════
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)',
        '{"precio_credito": 1.5, "moneda": "EUR", "creditos_propuesta": 2, "creditos_traduccion_ia": 1, "creditos_traduccion_deepl": 1, "tope_global_mensual": 100, "factura_a": "instancia", "caducan": true, "prueba_creditos": 2}', 'prueba de precios'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [C1 precios: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(%L, %L::jsonb, %L)', v_ea, '{"creditos_incluidos": 4, "tope_mensual": 5, "encendido": true}', 'prueba'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [C2 encender: ' || r || ']'; end if;
  select count(*) into n from public.editor_ia_ajustes_log; total := total + 1; if n < 2 then fallos := fallos + 1; resumen := resumen || ' [C3 sin registro de cambios]'; end if;
  r := pg_temp.intenta('postgres', v_sup, v_sup_em, 'update public.editor_ia_ajustes_log set motivo = motivo returning 1');
  total := total + 1; if r not like 'E55000%' then fallos := fallos + 1; resumen := resumen || ' [C4 registro reescribible: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or (j ->> 'encendido')::boolean is not true or (j #>> '{creditos,propone}') <> '2' then fallos := fallos + 1; resumen := resumen || ' [C5 estado encendido: ' || coalesce(j::text, 'error') || ']'; end if;
  -- la otra empresa sigue apagada
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, null, 1)', v_eb, 'propone', v_slug, 'estandar'));
  total := total + 1; if r <> 'E55000/apagado' then fallos := fallos + 1; resumen := resumen || ' [C6 la otra empresa: ' || r || ']'; end if;

  -- ═════════ D. EL CONTADOR ═════════
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  v_uso := (j ->> 'uso')::uuid;
  total := total + 1; if v_uso is null or (j ->> 'usados') <> '2' or (j ->> 'de_prueba') <> 'true' then fallos := fallos + 1; resumen := resumen || ' [D1 primera reserva: ' || coalesce(j::text, 'error') || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  v_uso2 := (j ->> 'uso')::uuid;
  total := total + 1; if v_uso2 is null or (j ->> 'usados') <> '4' or (j ->> 'de_prueba') <> 'false' then fallos := fallos + 1; resumen := resumen || ' [D2 segunda reserva: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_empresa' then fallos := fallos + 1; resumen := resumen || ' [D3 pasar del tope: ' || r || ']'; end if;
  select usados into n from public.editor_ia_saldo where empresa = v_ea and periodo = public._editor_ia_periodo();
  total := total + 1; if n <> 4 then fallos := fallos + 1; resumen := resumen || ' [D4 saldo tras el tope: ' || n || ']'; end if;
  select usados into n from public.editor_ia_saldo where empresa = '*' and periodo = public._editor_ia_periodo();
  total := total + 1; if n <> 4 then fallos := fallos + 1; resumen := resumen || ' [D5 saldo global: ' || n || ']'; end if;
  -- traducción de 2 párrafos: 2 créditos > 1 que queda
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 2)', v_ea, 'traduce_ia', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_empresa' then fallos := fallos + 1; resumen := resumen || ' [D6 traducción sobre el tope: ' || r || ']'; end if;
  -- la edge cierra la segunda como fallo: devuelve los créditos; cerrarla otra vez no devuelve dos veces
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, false, %L, 10, 0, 0, null, %L::jsonb)', v_uso2, 'm', '[]'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [D7 cierre fallido: ' || r || ']'; end if;
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, false, %L, 10, 0, 0, null, %L::jsonb)', v_uso2, 'm', '[]'));
  select usados into n from public.editor_ia_saldo where empresa = v_ea and periodo = public._editor_ia_periodo();
  total := total + 1; if n <> 2 then fallos := fallos + 1; resumen := resumen || ' [D8 devolución: ' || n || ']'; end if;
  -- la primera, bien, con marcas de traducción
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, true, %L, 120, 40, 0, %L, %L::jsonb)', v_uso, 'claude-opus-5-5', h1,
        json_build_array(json_build_object('lang', 'en', 'huella', h1), json_build_object('lang', 'id', 'huella', h2))));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [D9 cierre bueno: ' || r || ']'; end if;
  select count(*) into n from public.editor_ia_uso where id = v_uso and estado = 'hecho' and tokens_entrada = 120 and tokens_salida = 40 and huella_propuesta = h1;
  total := total + 1; if n <> 1 then fallos := fallos + 1; resumen := resumen || ' [D10 apunte del uso]'; end if;
  -- una marca rara no entra
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, true, %L, 1, 1, 0, null, %L::jsonb)', v_uso, 'm', '[{"lang":"xx","huella":"z"}]'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [D11 cierre repetido: ' || r || ']'; end if;   -- ya cerrado: no hace nada (false)

  -- ═════════ E. ACEPTAR Y MARCAS ═════════
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_aceptada(%L, %L)', v_uso, v_ver));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [E1 otra persona acepta: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_aceptada(%L, %L)', v_uso2, v_ver));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [E2 acepta una fallida: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_aceptada(%L, %L)', v_uso, v_ver));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [E3 aceptar: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_marcas(%L, %L, %L)', v_ea, v_slug, 'estandar'));
  total := total + 1; if j is null or jsonb_array_length(j) <> 2 then fallos := fallos + 1; resumen := resumen || ' [E4 marcas: ' || coalesce(j::text, 'error') || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select to_jsonb(public.editor_ia_marca_revisada(%L, %L, %L, %L, array[%L]))', v_ea, v_slug, 'estandar', 'en', h1));
  total := total + 1; if j is distinct from '1'::jsonb then fallos := fallos + 1; resumen := resumen || ' [E5 marcar revisado: ' || coalesce(j::text, 'error') || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_marcas(%L, %L, %L)', v_ea, v_slug, 'estandar'));
  total := total + 1; if j is null or jsonb_array_length(j) <> 1 then fallos := fallos + 1; resumen := resumen || ' [E6 marcas tras revisar: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_marcas(%L, %L, %L)', v_eb, v_slug, 'estandar'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [E7 marcas de otra empresa: ' || r || ']'; end if;

  -- ═════════ F. JAULA GLOBAL, TOPE POR MINUTO, APAGAR ═════════
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(%L, %L::jsonb, %L)', v_ea, '{"tope_mensual": 1000}', 'prueba'));
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"tope_global_mensual": 3}', 'prueba'));
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_global' then fallos := fallos + 1; resumen := resumen || ' [F1 jaula global: ' || r || ']'; end if;
  select usados into n from public.editor_ia_saldo where empresa = v_ea and periodo = public._editor_ia_periodo();
  total := total + 1; if n <> 2 then fallos := fallos + 1; resumen := resumen || ' [F2 la jaula deshace la suma de la empresa: ' || n || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"tope_global_mensual": 1000}', 'prueba'));
  -- ya hay 2 apuntes en este minuto (D1 y D2; las rechazadas se deshicieron); 4 más llegan a 6 y la séptima para
  for i in 1..4 loop
    perform pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  end loop;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_minuto' then fallos := fallos + 1; resumen := resumen || ' [F3 tope por minuto: ' || r || ']'; end if;
  -- vaciar un precio con la empresa encendida: el servidor deja de aceptar llamadas
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"precio_credito": null}', 'prueba'));
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or (j ->> 'encendido')::boolean is not false or position('precio' in coalesce(j ->> 'motivo', '')) = 0 then fallos := fallos + 1; resumen := resumen || ' [F4 precio vaciado: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(%L, %L::jsonb, %L)', v_ea, '{"encendido": false}', 'prueba'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [F5 apagar: ' || r || ']'; end if;

  -- ═════════ G. NINGÚN TEXTO EN LAS TABLAS, NINGÚN PERMISO DE MÁS ═════════
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name like 'editor\_ia\_%' and column_name ~ '(texto|instruccion|cuerpo|prompt|parrafo_html)';
  total := total + 1; if n <> 0 then fallos := fallos + 1; resumen := resumen || ' [G1 columnas de texto: ' || n || ']'; end if;
  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name like 'editor\_ia\_%' and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role');
  total := total + 1; if n <> 0 then fallos := fallos + 1; resumen := resumen || ' [G2 tablas con permisos directos: ' || n || ']'; end if;
  select count(*) into n from information_schema.routine_privileges g
   where g.specific_schema = 'public' and g.routine_name like 'editor\_ia\_%' and g.privilege_type = 'EXECUTE' and g.grantee in ('PUBLIC', 'anon');
  total := total + 1; if n <> 0 then fallos := fallos + 1; resumen := resumen || ' [G3 funciones abiertas a anon: ' || n || ']'; end if;
  select count(*) into n from information_schema.routine_privileges g
   where g.specific_schema = 'public' and g.routine_name like '\_editor\_ia\_%' and g.privilege_type = 'EXECUTE' and g.grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role');
  total := total + 1; if n <> 0 then fallos := fallos + 1; resumen := resumen || ' [G4 ayudantes ejecutables: ' || n || ']'; end if;

  raise exception 'FALLOS=% de % casos |%', fallos, total, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
