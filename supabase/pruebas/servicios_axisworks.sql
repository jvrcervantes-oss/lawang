-- Prueba por PERFILES de «Servicios de AxisWorks» y el asistente IA a coste + margen (migraciones 20261013210000 y 20261013220000, 13-oct-2026).
-- Sustituye a supabase/pruebas/editor_ia.sql (modelo de créditos, retirado). Conserva sus casos de permisos y de «sin texto».
-- destructivo-ok: prueba en transacción que termina en raise (rollback); no se borra nada.
-- Veredicto en el mensaje «FALLOS=0 de N casos | …». Solo cuentas y códigos: ningún dato personal ni texto de contrato.
-- Perfiles reales: super admin global, un admin de la empresa lawang (alcance a UNA empresa), un agente raso, anon y service_role.
-- Lo que no prueba un bloque: dos peticiones a la vez (una sola sesión) — eso va aparte (ver encargo, «dos peticiones a la vez»).
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_sup uuid; v_sup_em text; v_ae uuid; v_ae_em text; v_ea text := 'lawang'; v_eb text; v_ag uuid; v_ag_em text;
  v_slug text; v_ver uuid; r text; j jsonb; v_uso uuid; v_uso2 uuid; v_red uuid; n numeric; i int;
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
  select user_id, email into v_sup, v_sup_em from public.usuarios where rol = 'super_admin' and activo order by user_id limit 1;
  select user_id, email into v_ae, v_ae_em from public.usuarios
   where rol in ('admin_empresa', 'super_admin_empresa') and ambito = 'empresa' and activo and empresas = array[v_ea] order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and activo order by user_id limit 1;
  select e.clave into v_eb from public.empresas e where e.clave <> v_ea and e.activa order by e.clave limit 1;
  select v.slug, v.id into v_slug, v_ver from public.plantilla_contrato_versiones v
   where v.empresa = v_ea and v.variante = 'estandar' and v.borrada_en is null order by v.slug, v.version limit 1;
  if v_sup is null or v_ae is null or v_ag is null or v_eb is null or v_slug is null then
    raise exception 'FALLOS=1 | sin perfiles de prueba (super %, admin de lawang %, agente %, otra empresa %, plantilla %)',
      v_sup is not null, v_ae is not null, v_ag is not null, v_eb is not null, v_slug is not null;
  end if;
  if exists (select 1 from public.editor_ia_uso) then
    raise exception 'FALLOS=1 | la prueba cuenta con un mes sin consultas y ya hay apuntes: correla en una rama de ensayo';
  end if;

  -- ═════════ A. LAWANG NACE ENCENDIDA PERO SIN MARGEN: NO SE LLAMA A NADIE ═════════
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or (j ->> 'encendido')::boolean is not false or position('margen' in coalesce(j ->> 'motivo', '')) = 0 or j ->> 'motivo_clave' is distinct from 'sin_configurar' then fallos := fallos + 1; resumen := resumen || ' [A1 sin margen: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'E55000/apagado' then fallos := fallos + 1; resumen := resumen || ' [A2 reserva sin margen: ' || r || ']'; end if;
  select count(*) into i from public.editor_ia_uso; total := total + 1; if i <> 0 then fallos := fallos + 1; resumen := resumen || ' [A3 apunte sin margen]'; end if;
  total := total + 1; if exists (select 1 from public.editor_ia_empresa where encendido and empresa <> 'lawang') then fallos := fallos + 1; resumen := resumen || ' [A4 otra empresa encendida]'; end if;

  -- ═════════ B. QUIÉN PUEDE QUÉ ═════════
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, 'select public.servicios_axisworks_datos()');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B1 admin de empresa lee servicios: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"margen_pct": 0}', 'prueba'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B2 admin de empresa pone margen: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.servicios_axisworks_guarda(%L, %L::jsonb, %L)', v_ea, '{"suspendido": false}', 'prueba'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B3 admin de empresa se quita la suspension: ' || r || ']'; end if;
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
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, 'select * from public.servicios_axisworks_ajustes');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B10 tabla de servicios legible: ' || r || ']'; end if;
  -- las de precios en créditos se quedan sin permiso (se retiran del todo con LAW-555)
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, 'select public.editor_ia_ajustes_datos()');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B11 precios en créditos aún ejecutable: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_ajustes_guarda(null, %L::jsonb, %L)', '{"precio_credito": 0}', 'prueba'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B11b guarda en créditos aún ejecutable: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"margen_pct": "25"}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B12 texto por número: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"tope_usd_defecto": null}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B13 tope vacío: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"precio_credito": 1}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B14 clave de créditos: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"margen_pct": -1}', 'prueba'));
  total := total + 1; if r not like 'E23514%' then fallos := fallos + 1; resumen := resumen || ' [B15 margen negativo: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"margen_pct": null}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B16 margen vaciado: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"tarifa_entrada_usd_mtok": 0}', 'prueba'));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [B17 tarifa a cero: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_rechazada(%L, 429)', gen_random_uuid()));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B18 un navegador marca un rechazo: ' || r || ']'; end if;

  -- ═════════ C. EL OWNER PONE EL MARGEN ═════════
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"margen_pct": 25}', 'prueba de margen'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [C1 margen: ' || r || ']'; end if;
  total := total + 1; if not exists (select 1 from public.servicios_axisworks_log where motivo = 'prueba de margen' and (despues ->> 'margen_pct')::numeric = 25) then
    fallos := fallos + 1; resumen := resumen || ' [C2 sin registro del cambio]'; end if;
  r := pg_temp.intenta('postgres', v_sup, v_sup_em, 'update public.servicios_axisworks_log set motivo = motivo returning 1');
  total := total + 1; if r not like 'E55000%' then fallos := fallos + 1; resumen := resumen || ' [C3 registro reescribible: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or (j ->> 'encendido')::boolean is not true or (j ->> 'tope_usd')::numeric <> 20 or (j #>> '{coste_max,propone}')::numeric <> 0.352
     or (j #>> '{precio_max,propone}')::numeric <> 0.44 or (j ->> 'lleno')::boolean is not false or (j #>> '{puede,traduce_ia}')::boolean is not true
     or (j ->> 'deepl')::boolean is not false then fallos := fallos + 1; resumen := resumen || ' [C4 estado encendido: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, null, 1)', v_eb, 'propone', v_slug, 'estandar'));
  total := total + 1; if r <> 'E55000/apagado' then fallos := fallos + 1; resumen := resumen || ' [C5 la otra empresa sigue apagada: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'traduce_deepl', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'E55000/no_configurado' then fallos := fallos + 1; resumen := resumen || ' [C6 DeepL sin configurar: ' || r || ']'; end if;
  -- impago: el owner suspende y el asistente se para; lo quita y vuelve
  perform pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(%L, %L::jsonb, %L)', v_ea, '{"suspendido": true}', 'prueba impago'));
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'E55000/apagado' then fallos := fallos + 1; resumen := resumen || ' [C7 suspendida reserva: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or j ->> 'motivo_clave' is distinct from 'suspendido' then fallos := fallos + 1; resumen := resumen || ' [C8 clave de suspendida: ' || coalesce(j::text, 'error') || ']'; end if;
  perform pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(%L, %L::jsonb, %L)', v_ea, '{"suspendido": false, "tope_usd": 1}', 'prueba'));

  -- ═════════ D. EL TOPE EN DÓLARES, CON EL PEOR CASO (tope de la empresa = 1 USD; propuesta = 0,352 USD como mucho) ═════════
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  v_uso := (j ->> 'uso')::uuid;
  total := total + 1; if v_uso is null or (j ->> 'coste_max_usd')::numeric <> 0.352 then fallos := fallos + 1; resumen := resumen || ' [D1 reserva: ' || coalesce(j::text, 'error') || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  v_uso2 := (j ->> 'uso')::uuid;
  total := total + 1; if v_uso2 is null then fallos := fallos + 1; resumen := resumen || ' [D2 segunda reserva: ' || coalesce(j::text, 'error') || ']'; end if;
  -- la pantalla dice lo mismo que la reserva: con 0,704 apartados de 1 USD no cabe otra propuesta (0,352)
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if j is null or (j ->> 'lleno')::boolean is not true or j ->> 'lleno_por' is distinct from 'empresa' or (j #>> '{puede,propone}')::boolean is not false then
    fallos := fallos + 1; resumen := resumen || ' [D2b estado lleno como la reserva: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_empresa' then fallos := fallos + 1; resumen := resumen || ' [D3 tercera pasa del tope con dos en vuelo: ' || r || ']'; end if;
  -- la segunda se envía y se corta sin saber sus tokens: no se factura, pero sigue pesando al peor caso
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_enviada(%L)', v_uso2));
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, false, %L, 0, 0, 0, null, %L::jsonb)', v_uso2, 'm', '[]'));
  total := total + 1; if r <> 'OK:1' or exists (select 1 from public.editor_ia_uso where id = v_uso2 and (coste_usd is not null or importe_usd is not null)) then
    fallos := fallos + 1; resumen := resumen || ' [D4 fallo cortado: ' || r || ']'; end if;
  n := public._servicios_gasto_mes(v_ea, public._editor_ia_periodo());
  total := total + 1; if n <> 0.704 then fallos := fallos + 1; resumen := resumen || ' [D5 gasto con un fallo cortado: ' || n || ']'; end if;
  -- la primera se envía y termina bien: coste real 1000 de entrada y 500 de salida = 0,014 USD; con 25 % de margen = 0,0175
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_enviada(%L)', v_uso));
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, true, %L, 1000, 500, 0, %L, %L::jsonb)', v_uso, 'claude-opus-5-5', h1, '[]'));
  total := total + 1; if r <> 'OK:1' or not exists (select 1 from public.editor_ia_uso where id = v_uso and estado = 'hecho' and coste_usd = 0.014 and importe_usd = 0.0175 and margen_pct = 25) then
    fallos := fallos + 1; resumen := resumen || ' [D6 cierre bueno: ' || r || ']'; end if;
  n := public._servicios_gasto_mes(v_ea, public._editor_ia_periodo());
  total := total + 1; if n <> 0.366 then fallos := fallos + 1; resumen := resumen || ' [D7 gasto con el coste real: ' || n || ']'; end if;
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, true, %L, 1, 1, 0, null, %L::jsonb)', v_uso, 'm', '[]'));
  total := total + 1; if r <> 'OK:1' or not exists (select 1 from public.editor_ia_uso where id = v_uso and coste_usd = 0.014) then fallos := fallos + 1; resumen := resumen || ' [D8 cierre repetido cambia el apunte]'; end if;
  -- cambiar el margen no recalcula lo ya hecho
  perform pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"margen_pct": 50}', 'prueba'));
  total := total + 1; if not exists (select 1 from public.editor_ia_uso where id = v_uso and margen_pct = 25 and importe_usd = 0.0175) then fallos := fallos + 1; resumen := resumen || ' [D9 el margen nuevo recalcula lo hecho]'; end if;

  -- ═════════ E. UNA SEGUNDA LLAMADA HECHA, YA CON EL MARGEN NUEVO (50 %) ═════════
  -- traducción con IA de 3 párrafos: coste real 800 de entrada y 3000 de salida = 0,0632 USD; con 50 % = 0,0948
  perform pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(%L, %L::jsonb, %L)', v_ea, '{"tope_usd": 20}', 'prueba'));
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 3)', v_ea, 'traduce_ia', v_slug, 'estandar', v_ver));
  v_red := (j ->> 'uso')::uuid;
  total := total + 1; if v_red is null or (j ->> 'coste_max_usd')::numeric <> 0.384 then fallos := fallos + 1; resumen := resumen || ' [E1 reserva de traducción: ' || coalesce(j::text, 'error') || ']'; end if;
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_enviada(%L)', v_red));
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, true, %L, 800, 3000, 0, %L, %L::jsonb)', v_red, 'claude-opus-5-5', h2, '[]'));
  total := total + 1; if r <> 'OK:1' or not exists (select 1 from public.editor_ia_uso where id = v_red and coste_usd = 0.0632 and importe_usd = 0.0948 and margen_pct = 50) then
    fallos := fallos + 1; resumen := resumen || ' [E2 cierre con margen 50: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 2)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [E3 propuesta de 2 párrafos: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'redacta', v_slug, 'estandar', v_ver));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [E4 acción de E10 antes de su migración: ' || r || ']'; end if;

  -- ═════════ F. TOPE POR MINUTO Y TOPE DE LA INSTANCIA ═════════
  -- el admin lleva 3 apuntes en el último minuto (D1, D2, E1): tres más llegan a 6 y el séptimo para
  for i in 1 .. 3 loop
    r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
    total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [F0 reserva ' || i || ' antes del tope: ' || r || ']'; end if;
  end loop;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_minuto' then fallos := fallos + 1; resumen := resumen || ' [F1 tope por minuto: ' || r || ']'; end if;
  perform pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"tope_instancia_usd": 1}', 'prueba'));
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  total := total + 1; if r <> 'EP0001/tope_global' then fallos := fallos + 1; resumen := resumen || ' [F2 tope de la instancia: ' || r || ']'; end if;
  perform pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.servicios_axisworks_guarda(null, %L::jsonb, %L)', '{"tope_instancia_usd": 20}', 'prueba'));
  -- una reserva abandonada caduca a los 10 minutos y deja de pesar (no se envió)
  j := pg_temp.pide('authenticated', v_sup, v_sup_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  v_uso2 := (j ->> 'uso')::uuid;
  n := public._servicios_gasto_mes(v_ea, public._editor_ia_periodo());
  update public.editor_ia_uso set fecha = now() - interval '11 minutes' where id = v_uso2;
  perform public._editor_ia_caduca();
  total := total + 1; if not exists (select 1 from public.editor_ia_uso where id = v_uso2 and estado = 'caducada')
     or public._servicios_gasto_mes(v_ea, public._editor_ia_periodo()) <> n - 0.352 then
    fallos := fallos + 1; resumen := resumen || ' [F3 la abandonada sigue pesando: ' || n || ']'; end if;

  -- el proveedor RECHAZA una llamada (429): no cobra, cierra con coste 0 y no pesa contra el tope
  j := pg_temp.pide('authenticated', v_sup, v_sup_em, format('select public.editor_ia_reserva(%L, %L, %L, %L, %L, 1)', v_ea, 'propone', v_slug, 'estandar', v_ver));
  v_uso2 := (j ->> 'uso')::uuid;
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_rechazada(%L, 429)', v_uso2));
  total := total + 1; if r not like 'E22023%' then fallos := fallos + 1; resumen := resumen || ' [R1 rechazo sin enviar: ' || r || ']'; end if;
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_enviada(%L)', v_uso2));
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_rechazada(%L, 429)', v_uso2));
  total := total + 1; if r <> 'OK:1' or not exists (select 1 from public.editor_ia_uso where id = v_uso2 and estado = 'fallo' and coste_usd = 0 and importe_usd is null and rechazada_http = 429) then
    fallos := fallos + 1; resumen := resumen || ' [R2 rechazo: ' || r || ']'; end if;
  total := total + 1; if public._servicios_gasto_mes(v_ea, public._editor_ia_periodo()) <> n - 0.352 then
    fallos := fallos + 1; resumen := resumen || ' [R3 el rechazo pesa: ' || public._servicios_gasto_mes(v_ea, public._editor_ia_periodo()) || ']'; end if;
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_cierra(%L, true, %L, 1, 1, 0, null, %L::jsonb)', v_uso2, 'm', '[]'));
  total := total + 1; if not exists (select 1 from public.editor_ia_uso where id = v_uso2 and estado = 'fallo' and coste_usd = 0) then fallos := fallos + 1; resumen := resumen || ' [R4 cierre tras rechazo cambia el apunte]'; end if;

  -- ═════════ H. EXTRACTO: SE FACTURA SOLO LO HECHO, AL MARGEN CONGELADO, REDONDEADO AL FINAL ═════════
  j := pg_temp.pide('authenticated', v_sup, v_sup_em, 'select public.servicios_axisworks_datos()');
  select x into j from jsonb_array_elements(j -> 'extracto') x where x ->> 'empresa' = v_ea and (x ->> 'periodo')::date = public._editor_ia_periodo();
  -- hechas: D (0,014 → 0,0175 a 25 %) y E1 (800/3000 = 0,0632 → 0,0948 a 50 %): total 0,1123 → 0,11; coste facturable 0,0772 → 0,08
  total := total + 1; if j is null or (j ->> 'hechas') <> '2' or (j ->> 'coste_facturable_usd')::numeric <> 0.08 or (j ->> 'total_sin_impuestos_usd')::numeric <> 0.11
     or (j ->> 'coste_incompleto')::boolean is not true or jsonb_array_length(j -> 'margenes_pct') <> 2
     or (j ->> 'margen_usd')::numeric <> 0.03 or (j ->> 'rechazadas') <> '1'
     or (j ->> 'coste_facturable_usd')::numeric + (j ->> 'margen_usd')::numeric <> (j ->> 'total_sin_impuestos_usd')::numeric
     or (j ->> 'coste_facturable_usd')::numeric + (j ->> 'coste_no_repercutido_usd')::numeric <> (j ->> 'coste_proveedor_usd')::numeric then
    fallos := fallos + 1; resumen := resumen || ' [H1 extracto: ' || coalesce(j::text, 'error') || ']'; end if;

  -- ═════════ G. NINGÚN TEXTO EN LAS TABLAS, NINGÚN PERMISO DE MÁS ═════════
  select count(*) into i from information_schema.columns
   where table_schema = 'public' and (table_name like 'editor\_ia\_%' or table_name like 'servicios\_axisworks\_%') and column_name ~ '(texto|instruccion|cuerpo|prompt|frase|parrafo_html)';
  total := total + 1; if i <> 0 then fallos := fallos + 1; resumen := resumen || ' [G1 columnas de texto: ' || i || ']'; end if;
  select count(*) into i from information_schema.role_table_grants
   where table_schema = 'public' and (table_name like 'editor\_ia\_%' or table_name like 'servicios\_axisworks\_%') and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role');
  total := total + 1; if i <> 0 then fallos := fallos + 1; resumen := resumen || ' [G2 tablas con permisos directos: ' || i || ']'; end if;
  select count(*) into i from information_schema.routine_privileges g
   where g.specific_schema = 'public' and (g.routine_name like 'editor\_ia\_%' or g.routine_name like 'servicios\_axisworks\_%') and g.privilege_type = 'EXECUTE' and g.grantee in ('PUBLIC', 'anon');
  total := total + 1; if i <> 0 then fallos := fallos + 1; resumen := resumen || ' [G3 funciones abiertas a anon: ' || i || ']'; end if;
  select count(*) into i from information_schema.routine_privileges g
   where g.specific_schema = 'public' and (g.routine_name like '\_editor\_ia\_%' or g.routine_name like '\_servicios\_%') and g.privilege_type = 'EXECUTE'
     and g.grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role');
  total := total + 1; if i <> 0 then fallos := fallos + 1; resumen := resumen || ' [G4 ayudantes ejecutables: ' || i || ']'; end if;

  raise exception 'FALLOS=% de % casos |%', fallos, total, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
