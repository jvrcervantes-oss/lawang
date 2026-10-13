-- Prueba por PERFILES de E10 «contrato entero desde una frase» (migración 20261013235000_editor_ia_redacta, 13-oct-2026).
-- destructivo-ok: prueba en transacción que termina en raise (rollback); no se borra nada.
-- Veredicto en el mensaje «FALLOS=0 de N casos | …». Solo cuentas y códigos: ningún dato personal ni texto de un contrato real.
-- Perfiles reales: super admin global, un admin de la empresa lawang (alcance a UNA empresa), un agente raso, anon y service_role.
-- El margen se pone DENTRO de la transacción (se deshace al final): en producción sigue vacío hasta que lo ponga el owner (LAW-542).
-- La huella canónica se compara con la que calcula motor.js (node) para la MISMA propuesta: si una cambia sin la otra, esto falla (H0).
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_sup uuid; v_sup_em text; v_ae uuid; v_ae_em text; v_ea text := 'lawang'; v_eb text; v_ag uuid; v_ag_em text;
  r text; j jsonb; v_red uuid; v_en uuid; v_id uuid; v_viejo uuid; n numeric; i int; v_slug text; v_body text; v_np int;
  -- la propuesta de prueba (mismo objeto que PROPUESTA_PRUEBA en supabase/functions/editor-ia/editor-ia.test.js)
  P constant jsonb := $j${
    "nombre": "Prueba E10 compromiso del pack",
    "campos": [
      {"clave": "cx_e10_precio", "tipo": "importe", "etiqueta_es": "Precio del pack", "etiqueta_en": "Pack price", "etiqueta_id": "Harga paket", "opciones": []},
      {"clave": "cx_e10_moneda", "tipo": "lista", "etiqueta_es": "Moneda", "etiqueta_en": "Currency", "etiqueta_id": "Mata uang", "opciones": ["IDR", "USD", "EUR"]},
      {"clave": "cx_e10_reuso", "tipo": "texto", "etiqueta_es": "Referencia", "etiqueta_en": "Reference", "etiqueta_id": "Referensi", "opciones": []},
      {"clave": "cx_e10_choca", "tipo": "fecha", "etiqueta_es": "Fecha límite", "etiqueta_en": "Deadline", "etiqueta_id": "Batas waktu", "opciones": []}
    ],
    "clausulas": [
      {"titulo": {"es": "Objeto", "en": "Purpose", "id": "Objek"},
       "parrafos": [{"es": "El comprador se compromete a comprar el pack por {{cx_e10_precio}} en {{cx_e10_moneda}}.",
                     "en": "The buyer undertakes to buy the pack for {{cx_e10_precio}} in {{cx_e10_moneda}}.",
                     "id": "Pembeli berjanji membeli paket seharga {{cx_e10_precio}} dalam {{cx_e10_moneda}}."}]},
      {"titulo": {"es": "Garantía", "en": "Warranty", "id": "Garansi"},
       "parrafos": [{"es": "Los defectos de fabricación los cubre la garantía del fabricante; el pago íntegro vence el {{cx_e10_choca}}.",
                     "en": "Manufacturing defects are covered by the manufacturer's warranty; full payment is due on {{cx_e10_choca}}.",
                     "id": "Cacat produksi ditanggung garansi pabrik; pembayaran penuh jatuh tempo pada {{cx_e10_choca}}."},
                    {"es": "Referencia {{cx_e10_reuso}} & anexos técnicos.", "en": "Reference {{cx_e10_reuso}} & technical schedules.",
                     "id": "Referensi {{cx_e10_reuso}} & lampiran teknis."}]}
    ]}$j$::jsonb;
  HUELLA_JS_ES constant text := '1e123aacd6ef92e3db7a9fdf242c87b79d8105bafc3b88951bc2e70def6b2bd2';    -- node supabase/functions/editor-ia/editor-ia.test.js --huella-prueba
  P2 jsonb;
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
        return jsonb_build_object('error', sqlstate, 'mensaje', left(sqlerrm, 300));
      end;
    end $g$;
  $f$;
  select user_id, email into v_sup, v_sup_em from public.usuarios where rol = 'super_admin' and activo order by user_id limit 1;
  select user_id, email into v_ae, v_ae_em from public.usuarios
   where rol in ('admin_empresa', 'super_admin_empresa') and ambito = 'empresa' and activo and empresas = array[v_ea] order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and activo order by user_id limit 1;
  select e.clave into v_eb from public.empresas e where e.clave <> v_ea and e.activa order by e.clave limit 1;
  if v_sup is null or v_ae is null or v_ag is null or v_eb is null then
    raise exception 'FALLOS=1 | sin perfiles de prueba (super %, admin de lawang %, agente %, otra empresa %)', v_sup is not null, v_ae is not null, v_ag is not null, v_eb is not null;
  end if;

  -- ═════════ H. LA HUELLA CANÓNICA ES LA MISMA EN LA BASE Y EN LA EDGE ═════════
  total := total + 1; if public._editor_ia_huella_redaccion(P, 'es') is distinct from HUELLA_JS_ES then
    fallos := fallos + 1; resumen := resumen || ' [H0 huella base ' || public._editor_ia_huella_redaccion(P, 'es') || ' <> node ' || HUELLA_JS_ES || ']'; end if;
  total := total + 1; if public._editor_ia_huella_redaccion(P, 'en') = public._editor_ia_huella_redaccion(P, 'id')
     or public._editor_ia_huella_redaccion(jsonb_set(P, '{clausulas,0,parrafos,0,es}', '"Otro texto"'), 'es') = public._editor_ia_huella_redaccion(P, 'es')
     or public._editor_ia_huella_redaccion(jsonb_set(P, '{nombre}', '"Otro nombre"'), 'es') <> public._editor_ia_huella_redaccion(P, 'es') then
    fallos := fallos + 1; resumen := resumen || ' [H1 la huella no distingue lo que debe (o cuenta el nombre)]'; end if;

  -- ═════════ P. PERMISOS: lo nuevo nace cerrado ═════════
  total := total + 1; if has_table_privilege('authenticated', 'public.editor_ia_redaccion', 'select') or has_table_privilege('anon', 'public.editor_ia_redaccion', 'select')
     or has_table_privilege('service_role', 'public.editor_ia_redaccion', 'insert') then fallos := fallos + 1; resumen := resumen || ' [P1 tabla abierta]'; end if;
  total := total + 1; if has_function_privilege('authenticated', 'public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text)', 'execute')
     or not has_function_privilege('service_role', 'public.editor_ia_redaccion_paso(uuid, text, text, integer, integer, integer, text)', 'execute') then
    fallos := fallos + 1; resumen := resumen || ' [P2 paso de la edge mal abierto]'; end if;
  total := total + 1; if has_function_privilege('anon', 'public.plantilla_contrato_crea_desde_asistente(text, uuid, jsonb, boolean, boolean)', 'execute')
     or has_function_privilege('anon', 'public.editor_ia_redaccion_reserva(text, text, uuid, text, text)', 'execute')
     or has_function_privilege('authenticated', 'public._plantilla_esqueleto_en_blanco(text, text[], text)', 'execute')
     or has_function_privilege('authenticated', 'public._plantilla_cuerpo_asistente(text, text[], text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public._editor_ia_huella_redaccion(jsonb, text)', 'execute')
     or has_function_privilege('authenticated', 'public._editor_ia_peso_de(text, timestamptz, timestamptz, numeric, numeric)', 'execute') then
    fallos := fallos + 1; resumen := resumen || ' [P3 función abierta de más]'; end if;
  total := total + 1; if position('editor_ia_redaccion' in pg_get_functiondef('public.editor_ia_reserva'::regproc)) = 0 then
    fallos := fallos + 1; resumen := resumen || ' [P4 el tope por minuto del editor no cuenta las redacciones]'; end if;

  -- ═════════ E9 SIGUE: el contrato en blanco a mano trae partes, ley, idioma y firmas, y no nombra a otra sociedad ═════════
  select count(*) into v_np from public.plantillas_contrato;
  foreach r in array array[v_ea, v_eb] loop
    j := pg_temp.pide('authenticated', v_sup, v_sup_em, format('select public.plantilla_contrato_nuevo_crea(%L, %L, %L, null, null, %L::jsonb)', r, 'Prueba E10 en blanco', 'blanco', '[]'));
    total := total + 1;
    if j ? 'error' then fallos := fallos + 1; resumen := resumen || ' [E9 blanco ' || r || ': ' || j::text || ']';
    else
      select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = (j ->> 'version_id')::uuid;
      if v_body not like '%<!--bloque-fijo:partes-->%' or v_body not like '%<!--bloque-fijo:foro_ley-->%' or v_body not like '%<!--bloque-fijo:firmas-->%'
         or v_body not like '%<!--if:adq1_tipo=empresa-->%' or v_body not like '%{{contrato_num}}%' or v_body not like '%<!--extra-clauses-->%'
         or v_body not like '%<!--firmas-adquirientes-->%' or v_body not like '%prevalecer%' or v_body not like '%<span data-lang="id">Nama</span>%'
         or cardinality(public._plantilla_otra_sociedad(v_body, r)) > 0 or (j ->> 'activable')::boolean is not false
         or position('textos de ejemplo' in coalesce(j ->> 'bloqueo', '')) = 0 or position('otra sociedad' in coalesce(j ->> 'bloqueo', '')) > 0 then
        fallos := fallos + 1; resumen := resumen || ' [E9 cuerpo en blanco de ' || r || ': ' || left(coalesce(j ->> 'bloqueo', ''), 200) || ']';
      end if;
    end if;
  end loop;

  -- ═════════ A. SIN MARGEN NO ARRANCA ═════════
  update public.servicios_axisworks_ajustes set margen_pct = null where id;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  total := total + 1; if r <> 'E55000/apagado' then fallos := fallos + 1; resumen := resumen || ' [A1 sin margen: ' || r || ']'; end if;
  update public.servicios_axisworks_ajustes set margen_pct = 25 where id;

  -- ═════════ B. QUIÉN PUEDE ═════════
  r := pg_temp.intenta('authenticated', v_ag, v_ag_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B1 agente reserva: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_eb, 'redacta'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B2 otra empresa: ' || r || ']'; end if;
  r := pg_temp.intenta('anon', null, null, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B3 anon: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_redaccion_paso(%L, %L)', gen_random_uuid(), 'enviada'));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [B4 un navegador marca un paso: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, %L, null)', v_ea, 'redacta', 'en'));
  total := total + 1; if r <> 'E22023/' then fallos := fallos + 1; resumen := resumen || ' [B5 redacta con idioma: ' || r || ']'; end if;

  -- ═════════ T. EL TOPE: solo empieza si cabe la creación ENTERA (redacta + 2 × traducción = 0,344 + 0,768 = 1,112 USD) ═════════
  insert into public.servicios_axisworks_empresa (empresa) values (v_ea) on conflict (empresa) do nothing;
  update public.servicios_axisworks_empresa set tope_usd = 1 where empresa = v_ea;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  total := total + 1; if r <> 'EP0001/tope_empresa' then fallos := fallos + 1; resumen := resumen || ' [T1 empieza sin hueco para terminar: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  total := total + 1; if (j #>> '{puede,redacta_completo}')::boolean is not false or (j #>> '{coste_max,redacta_completo}')::numeric <> 1.112
     or (j #>> '{precio_max,redacta_completo}')::numeric <> 1.39 or (j #>> '{coste_max,redacta}')::numeric <> 0.344 then
    fallos := fallos + 1; resumen := resumen || ' [T2 estado de redacta: ' || coalesce(j::text, 'error') || ']'; end if;
  total := total + 1; if (j #>> '{puede,redacta}')::boolean is not false or (j #>> '{puede,propone}')::boolean is not true then
    fallos := fallos + 1; resumen := resumen || ' [T2b puede.redacta no dice lo mismo que la reserva: ' || coalesce(j ->> 'puede', 'null') || ']'; end if;
  -- T3: dos redacciones a la vez con hueco para UNA creación entera: la segunda no empieza (lo de traducir queda apartado)
  update public.servicios_axisworks_empresa set tope_usd = 1.5 where empresa = v_ea;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  total := total + 1; if j ? 'error' or r <> 'EP0001/tope_empresa' then
    fallos := fallos + 1; resumen := resumen || ' [T3 dos redacciones con hueco para una: ' || coalesce(j::text, 'null') || ' / ' || r || ']'; end if;
  -- (se cierra como fallo sin enviar: deja de pesar; sin DELETE, que no_destruir.py para aunque sea dentro de la prueba)
  update public.editor_ia_redaccion set estado = 'fallo', cerrada_en = now() where id = (j ->> 'uso')::uuid;
  update public.servicios_axisworks_empresa set tope_usd = null where empresa = v_ea;

  -- ═════════ R. PASO (a): redacta ═════════
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  v_red := (j ->> 'uso')::uuid;
  total := total + 1; if v_red is null or (j ->> 'coste_max_usd')::numeric <> 0.344 then fallos := fallos + 1; resumen := resumen || ' [R1 reserva: ' || coalesce(j::text, 'error') || ']'; end if;
  n := public._servicios_gasto_mes(v_ea, public._editor_ia_periodo());
  total := total + 1; if n < 1.112 then fallos := fallos + 1; resumen := resumen || ' [R2 la reserva en vuelo no pesa lo suyo + lo apartado para traducir (1,112): ' || n || ']'; end if;
  -- traducir antes de que el paso (a) termine: no
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', public._editor_ia_huella_redaccion(P, 'es')));
  total := total + 1; if r <> 'E22023/origen' then fallos := fallos + 1; resumen := resumen || ' [R3 traduce sin terminar: ' || r || ']'; end if;
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L)', v_red, 'enviada'));
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L, %L, 2000, 3000, null, %L)', v_red, 'hecho', 'claude-opus-5-5', public._editor_ia_huella_redaccion(P, 'es')));
  total := total + 1; if r <> 'OK:1' or not exists (select 1 from public.editor_ia_redaccion where id = v_red and estado = 'hecho' and coste_usd = 0.068 and importe_usd = 0.085) then
    fallos := fallos + 1; resumen := resumen || ' [R4 cierre (2000 + 3000 tokens = 0,068 USD; +25 % = 0,085): ' || r || ']'; end if;
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L, %L, 1, 1, null, %L)', v_red, 'hecho', 'x', repeat('c', 64)));
  total := total + 1; if not exists (select 1 from public.editor_ia_redaccion where id = v_red and coste_usd = 0.068 and huella_propuesta = public._editor_ia_huella_redaccion(P, 'es')) then
    fallos := fallos + 1; resumen := resumen || ' [R5 un cierre repetido cambia el apunte]'; end if;

  -- ═════════ S. PASO (b): traducción con la MISMA huella; una viva por idioma ═════════
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', repeat('d', 64)));
  total := total + 1; if r <> 'E22023/huella' then fallos := fallos + 1; resumen := resumen || ' [S1 español alterado: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', public._editor_ia_huella_redaccion(P, 'es')));
  total := total + 1; if r <> 'E22023/origen' then fallos := fallos + 1; resumen := resumen || ' [S2 otra persona traduce mi redacción: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', public._editor_ia_huella_redaccion(P, 'es')));
  v_en := (j ->> 'uso')::uuid;
  total := total + 1; if v_en is null or (j ->> 'coste_max_usd')::numeric <> 0.384 then fallos := fallos + 1; resumen := resumen || ' [S3 reserva en: ' || coalesce(j::text, 'error') || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', public._editor_ia_huella_redaccion(P, 'es')));
  total := total + 1; if r <> 'EP0001/ya_traducido' then fallos := fallos + 1; resumen := resumen || ' [S4 segundo inglés a la vez: ' || r || ']'; end if;
  -- el inglés falla (el proveedor contesta 529): coste 0, y el idioma queda libre para reintentar
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L)', v_en, 'enviada'));
  r := pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L, null, 0, 0, 529, null)', v_en, 'rechazada'));
  total := total + 1; if r <> 'OK:1' or not exists (select 1 from public.editor_ia_redaccion where id = v_en and estado = 'fallo' and coste_usd = 0 and rechazada_http = 529) then
    fallos := fallos + 1; resumen := resumen || ' [S5 rechazo del proveedor: ' || r || ']'; end if;
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', public._editor_ia_huella_redaccion(P, 'es')));
  v_en := (j ->> 'uso')::uuid;
  total := total + 1; if v_en is null then fallos := fallos + 1; resumen := resumen || ' [S6 reintento tras un 529: ' || coalesce(j::text, 'error') || ']'; end if;
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L)', v_en, 'enviada'));
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L, %L, 1500, 2500, null, %L)', v_en, 'hecho', 'claude-opus-5-5', public._editor_ia_huella_redaccion(P, 'en')));
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'id', public._editor_ia_huella_redaccion(P, 'es')));
  v_id := (j ->> 'uso')::uuid;
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L)', v_id, 'enviada'));
  perform pg_temp.intenta('service_role', null, null, format('select public.editor_ia_redaccion_paso(%L, %L, %L, 1500, 2500, null, %L)', v_id, 'hecho', 'claude-opus-5-5', public._editor_ia_huella_redaccion(P, 'id')));
  total := total + 1; if (select count(*) from public.editor_ia_redaccion where origen = v_red and estado = 'hecho') <> 2 then fallos := fallos + 1; resumen := resumen || ' [S7 dos traducciones hechas]'; end if;
  total := total + 1; if (select reserva_traduccion_usd from public.editor_ia_redaccion where id = v_red) <> 0 then
    fallos := fallos + 1; resumen := resumen || ' [S8 lo apartado para traducir no se ha descontado]'; end if;

  -- ═════════ C. CREAR: aviso, huellas, sensibles, campos, todo o nada ═════════
  -- dos campos que ya existen: uno con el mismo tipo (se reutiliza sin tocarlo) y otro con otro tipo (el nuevo se renombra)
  perform pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_campo_propio_guarda(%L, %L, %L, %L, %L, %L, null, false, true)', v_ea, 'cx_e10_reuso', 'Referencia', 'Reference', 'Referensi', 'texto'));
  perform pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_campo_propio_guarda(%L, %L, %L, null, null, %L, null, false, true)', v_ea, 'cx_e10_precio', 'Otro precio', 'importe'));
  perform pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_campo_propio_guarda(%L, %L, %L, null, null, %L, null, false, true)', v_ea, 'cx_e10_choca', 'Choca', 'texto'));
  select count(*) into v_np from public.plantillas_contrato;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, false)', v_ea, v_red, P));
  total := total + 1; if r <> 'E22023/aviso' then fallos := fallos + 1; resumen := resumen || ' [C1 sin aceptar el aviso: ' || r || ']'; end if;
  P2 := jsonb_set(P, '{clausulas,0,parrafos,0,es}', '"El comprador paga lo que quiera por {{cx_e10_precio}} en {{cx_e10_moneda}}."');
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true)', v_ea, v_red, P2));
  total := total + 1; if r <> 'E22023/huella' then fallos := fallos + 1; resumen := resumen || ' [C2 texto cambiado en el navegador: ' || r || ']'; end if;
  P2 := jsonb_set(P, '{clausulas,1,parrafos,0,id}', '"Teks lain {{cx_e10_choca}}."');
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true)', v_ea, v_red, P2));
  total := total + 1; if r <> 'E22023/huella' then fallos := fallos + 1; resumen := resumen || ' [C3 indonesio cambiado: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_sup, v_sup_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true)', v_ea, v_red, P));
  total := total + 1; if r <> 'E22023/origen' then fallos := fallos + 1; resumen := resumen || ' [C4 otra persona crea con mi redacción: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true, true)', v_ea, v_red, jsonb_set(P, '{nombre}', '"   "')));
  total := total + 1; if r <> 'E22023/nombre' then fallos := fallos + 1; resumen := resumen || ' [N1 nombre vacío: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true, true)', v_ea, v_red, jsonb_set(P, '{nombre}', to_jsonb('Prueba ' || chr(1564) || 'E10 marca'))));
  total := total + 1; if r <> 'E22023/nombre' then fallos := fallos + 1; resumen := resumen || ' [N2 marca de dirección U+061C en el nombre (20261014000000): ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true, true)', v_ea, v_red, jsonb_set(P, '{clausulas,0,parrafos}', '"x"')));
  total := total + 1; if r <> 'E22023/forma' then fallos := fallos + 1; resumen := resumen || ' [F1 párrafos que no son lista: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true, true)', v_ea, v_red, jsonb_set(P, '{clausulas,0,parrafos,0}', '"texto suelto"')));
  total := total + 1; if r <> 'E22023/forma' then fallos := fallos + 1; resumen := resumen || ' [F2 párrafo que no es objeto: ' || r || ']'; end if;
  -- «defectos» es parte sensible: sin confirmar, la base para y NO queda nada (ni contrato ni campos nuevos)
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true)', v_ea, v_red, P));
  total := total + 1; if not (j ? 'error') or position('partes sensibles' in coalesce(j ->> 'mensaje', '')) = 0
     or (select count(*) from public.plantillas_contrato) <> v_np or exists (select 1 from public.plantilla_campos_propios where empresa = v_ea and clave = 'cx_e10_moneda') then
    fallos := fallos + 1; resumen := resumen || ' [C5 sensible sin confirmar: ' || coalesce(j::text, 'null') || ']'; end if;
  -- confirmado: se crea entero
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true, true)', v_ea, v_red, P));
  v_slug := j ->> 'slug';
  total := total + 1; if v_slug is null or j ->> 'nombre' <> 'Prueba E10 compromiso del pack (IA)' then fallos := fallos + 1; resumen := resumen || ' [C6 crear: ' || coalesce(j::text, 'null') || ']'; end if;
  if v_slug is not null then
    select c.cuerpo_html into v_body from public.plantilla_contrato_cuerpos c where c.version_id = (j ->> 'version_id')::uuid;
    total := total + 1; if v_body is null or v_body like '%[Escribe%' or v_body not like '%2. Garantía%' or v_body not like '%{{cx_e10_choca_2}}%'
       or v_body like '%{{cx_e10_choca}}%' or v_body not like '%{{cx_e10_precio_2}}%' or v_body like '%{{cx_e10_precio}}%' or v_body not like '%{{cx_e10_reuso}}%' or v_body not like '%anexos técnicos%' or v_body not like '%&amp; anexos%' or v_body not like '%<!--bloque-fijo:partes-->%' then
      fallos := fallos + 1; resumen := resumen || ' [C7 cuerpo: ' || left(coalesce(v_body, 'null'), 120) || ']'; end if;
    total := total + 1; if not exists (select 1 from public.plantilla_contrato_versiones v where v.id = (j ->> 'version_id')::uuid and v.estado = 'borrador' and v.activable)
       or exists (select 1 from public.plantilla_contrato_versiones v where v.slug = v_slug and v.estado = 'activa') then
      fallos := fallos + 1; resumen := resumen || ' [C8 debe quedar en borrador activable, sin activar]'; end if;
    total := total + 1; if not exists (select 1 from public.plantilla_campos_propios where empresa = v_ea and clave = 'cx_e10_reuso' and etiqueta_es = 'Referencia' and tipo = 'texto')
       or exists (select 1 from public.plantilla_campos_propios where empresa = v_ea and clave = 'cx_e10_reuso_2')
       or not exists (select 1 from public.plantilla_campos_propios where empresa = v_ea and clave = 'cx_e10_precio_2' and etiqueta_es = 'Precio del pack')
       or j #>> '{renombrados,cx_e10_precio}' is distinct from 'cx_e10_precio_2'
       or not exists (select 1 from public.plantilla_campos_propios where empresa = v_ea and clave = 'cx_e10_choca_2' and tipo = 'fecha' and sensible)
       or not exists (select 1 from public.plantilla_campos_propios where empresa = v_ea and clave = 'cx_e10_moneda' and tipo = 'lista' and opciones = '["IDR", "USD", "EUR"]'::jsonb)
       or j #>> '{renombrados,cx_e10_choca}' is distinct from 'cx_e10_choca_2' then
      fallos := fallos + 1; resumen := resumen || ' [C9 campos: ' || coalesce(j::text, 'null') || ']'; end if;
    total := total + 1; if (select count(*) from public.editor_ia_redaccion where (id = v_red or origen = v_red) and aceptada_en is not null and aviso_aceptado = 'legal-2026-10-13'
                                                                    and slug_creado = v_slug) <> 3 then
      fallos := fallos + 1; resumen := resumen || ' [C10 apunte del aviso aceptado]'; end if;
    total := total + 1; if not exists (select 1 from public.plantilla_bloque_cambios b where b.slug = v_slug and b.aviso_confirmado) then
      fallos := fallos + 1; resumen := resumen || ' [C11 sin registro de la parte sensible confirmada]'; end if;
    -- el editor abre el contrato (lo mismo que lee la pantalla y la edge)
    j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_edicion(%L, %L, %L)', v_ea, v_slug, 'estandar'));
    total := total + 1; if j ? 'error' or j ->> 'cuerpo_html' is null then fallos := fallos + 1; resumen := resumen || ' [C12 el editor no lo abre: ' || left(j::text, 200) || ']'; end if;
  end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.plantilla_contrato_crea_desde_asistente(%L, %L, %L::jsonb, true, true)', v_ea, v_red, P));
  total := total + 1; if r <> 'E22023/usada' then fallos := fallos + 1; resumen := resumen || ' [C13 dos contratos con la misma redacción: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, %L, %L, %L)', v_ea, 'redacta_traduce', v_red, 'en', public._editor_ia_huella_redaccion(P, 'es')));
  total := total + 1; if r <> 'E22023/origen' then fallos := fallos + 1; resumen := resumen || ' [C14 traducir una redacción ya usada: ' || r || ']'; end if;

  -- ═════════ D. EL DINERO SUMA LAS DOS TABLAS ═════════
  j := pg_temp.pide('authenticated', v_ae, v_ae_em, format('select public.editor_ia_estado(%L)', v_ea));
  -- facturado = 0,085 (a) + 2 × (1500 × 4 + 2500 × 20) / 1e6 × 1,25 = 0,085 + 2 × 0,07 = 0,225
  total := total + 1; if (j ->> 'facturado_usd')::numeric <> 0.23 then fallos := fallos + 1; resumen := resumen || ' [D1 facturado del mes: ' || coalesce(j ->> 'facturado_usd', 'null') || ']'; end if;
  j := pg_temp.pide('authenticated', v_sup, v_sup_em, 'select public.servicios_axisworks_datos()');
  total := total + 1; if not exists (select 1 from jsonb_array_elements(j -> 'extracto') e where e ->> 'empresa' = v_ea and (e ->> 'redacciones')::int = 2   -- la de T3 (cerrada como fallo) y la de R1
                                       and (e ->> 'aceptadas')::int = 1 and (e ->> 'total_sin_impuestos_usd')::numeric >= 0.22) then
    fallos := fallos + 1; resumen := resumen || ' [D2 extracto: ' || left(coalesce((j -> 'extracto')::text, 'null'), 300) || ']'; end if;
  n := public._servicios_gasto_mes(v_ea, public._editor_ia_periodo());
  total := total + 1; if n < 0.18 then fallos := fallos + 1; resumen := resumen || ' [D3 gasto del mes con redacciones: ' || n || ']'; end if;

  -- ═════════ M. TOPE POR MINUTO: una redacción solo empieza si caben ella y sus dos traducciones (20261014000000) ═════════
  -- (todo va en una transacción: now() es fijo, así que las 5 filas de esta persona cuentan como «del último minuto»)
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.editor_ia_redaccion_reserva(%L, %L, null, null, null)', v_ea, 'redacta'));
  total := total + 1; if r <> 'EP0001/tope_minuto' then fallos := fallos + 1; resumen := resumen || ' [M1 redacta con 5 consultas en el minuto: ' || r || ']'; end if;

  -- ═════════ K. CADUCIDAD: una reserva de redacción olvidada caduca bajo el mismo candado ═════════
  insert into public.editor_ia_redaccion (empresa, usuario, autor, fecha, periodo, accion, coste_max_usd, margen_pct)
  values (v_ea, v_ae, 'prueba', now() - interval '11 minutes', public._editor_ia_periodo(), 'redacta', 0.344, 25) returning id into v_viejo;
  perform public._editor_ia_caduca();
  total := total + 1; if not exists (select 1 from public.editor_ia_redaccion where id = v_viejo and estado = 'caducada') then fallos := fallos + 1; resumen := resumen || ' [K1 no caduca]'; end if;
  total := total + 1; if public._editor_ia_peso_de('reservado', null, now() - interval '11 minutes', null, 1) <> 0
     or public._editor_ia_peso_de('reservado', now(), now(), null, 1) <> 1 or public._editor_ia_peso_de('fallo', now(), now(), null, 1) <> 1
     or public._editor_ia_peso_de('hecho', now(), now(), 0.5, 1) <> 0.5 or public._editor_ia_peso_de('fallo', null, now(), null, 1) <> 0 then
    fallos := fallos + 1; resumen := resumen || ' [K2 la fórmula del peso]'; end if;

  raise exception 'FALLOS=% de % casos |%', fallos, total, resumen;
end $t$;
