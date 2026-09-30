-- PRUEBA — retención PPh de los pagos de comisión, diseño del revisor
-- (20260930025652_pph_retencion_revisor, 30-sep-2026; sustituye a la prueba de 20260930022612).
-- Se ejecuta entera con execute_sql (MCP) o psql como postgres. NO ESCRIBE NADA: el bloque entero termina en
-- `raise exception 'RES: …'`, que deshace la preparación; cada caso de error va en un sub-bloque.
-- Cada caso comprueba el SQLSTATE **y** un trozo del mensaje: hay ~10 guardas con 22023 y 3 con 42501, y
-- solo el código daría «ok» con la guarda equivocada.
--
-- Cómo se prueba, y por qué así:
--  A. `authenticated` NO tiene EXECUTE de las RPC ni SELECT de la tabla (R2: sin llamador todavía) →
--     con `set local role authenticated` todo da 42501 «permission denied».
--  B-E. La lógica se prueba como postgres fijando request.jwt.claims (auth.uid() sale del claim `sub`):
--     así corre la RPC DEFINER tal cual correrá el día que se conceda el EXECUTE.
--  F. La lectura por user_id (S1): dentro del bloque se hace el GRANT SELECT que llegará con la pantalla,
--     `set local role authenticated`, y se cuenta con distintos claims. El raise final deshace el GRANT.
-- Base: una solicitud `comision_automatica` pendiente (moneda ≠ IDR), que aquí se aprueba y se paga.
-- Resultado: «RES: … | ok N/M». Un «FALLO» es una puerta abierta o un dato fiscal mal calculado.
do $$
declare
  r text := ''; v_sp uuid; v_otra uuid; v_imp numeric; v_mon text; v_half numeric; v_soc text;
  v_benef record; v_admin record; v_ajeno record;
  v_hoy date := (now() at time zone 'Asia/Makassar')::date;
  v_id1 uuid; v_id2 uuid; v_id3 uuid; v_n int; v_t text; v_ok int; v_tot int;
  c_admin text; c_benef text; c_ajeno text; c_ajeno_email_benef text;
begin
  select sp.id, sp.importe, sp.moneda into v_sp, v_imp, v_mon from public.solicitudes_pago sp
   where sp.origen = 'comision_automatica' and sp.estado = 'pendiente' and sp.moneda <> 'IDR'
   order by sp.numero limit 1;
  if v_sp is null then raise exception 'RES: sin solicitud automática pendiente en moneda ≠ IDR: la prueba no tiene base'; end if;
  v_half := round(v_imp / 2, 2);
  select sp.id into v_otra from public.solicitudes_pago sp where sp.estado = 'pendiente' and sp.id <> v_sp limit 1;
  select s.clave into v_soc from public.sociedades s order by s.clave limit 1;
  select u.user_id, u.email into v_benef from public.usuarios u
   where lower(u.email) = (select lower(beneficiario_email) from public.solicitudes_pago where id = v_sp);
  select u.user_id, u.email into v_admin from public.usuarios u
   where u.rol = 'super_admin' and u.activo and lower(u.email) <> lower(v_benef.email) order by u.email limit 1;
  select u.user_id, u.email into v_ajeno from public.usuarios u
   where u.activo and u.rol not in ('super_admin','admin') and lower(u.email) <> lower(v_benef.email)
   order by u.email limit 1;
  if v_benef.user_id is null or v_admin.user_id is null or v_ajeno.user_id is null or v_soc is null or v_otra is null then
    raise exception 'RES: faltan datos base (beneficiario/admin/ajeno/sociedad/otra solicitud)';
  end if;
  c_admin := json_build_object('sub', v_admin.user_id, 'email', v_admin.email, 'role', 'authenticated')::text;
  c_benef := json_build_object('sub', v_benef.user_id, 'email', v_benef.email, 'role', 'authenticated')::text;
  c_ajeno := json_build_object('sub', v_ajeno.user_id, 'email', v_ajeno.email, 'role', 'authenticated')::text;
  c_ajeno_email_benef := json_build_object('sub', v_ajeno.user_id, 'email', v_benef.email, 'role', 'authenticated')::text;

  -- preparación: aprobar y pagar como admin (lo deshace el raise final)
  perform set_config('request.jwt.claims', c_admin, true);
  update public.solicitudes_pago set estado = 'aprobada' where id = v_sp;
  update public.solicitudes_pago set estado = 'pagada', pago_referencia = 'PRUEBA-F0' where id = v_sp;

  -- ── A · authenticated: cerrado hasta la pantalla (42501) ────────────────
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_guarda(v_sp, '{}');
    raise exception 'ejecuto';
  exception when others then r := r || 'A1 auth EXECUTE guarda=' || (case when sqlstate = '42501' and sqlerrm like 'permission denied%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    perform public.solicitud_pago_retencion_rectifica(v_sp, 'batal', 'x');
    raise exception 'ejecuto';
  exception when others then r := r || 'A2 auth EXECUTE rectifica=' || (case when sqlstate = '42501' and sqlerrm like 'permission denied%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.solicitudes_pago_retencion;
    raise exception 'leyo';
  exception when others then r := r || 'A3 auth SELECT=' || (case when sqlstate = '42501' and sqlerrm like 'permission denied%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    execute 'set local role authenticated';
    select count(*) into v_n from public.solicitudes_pago_retencion_log;
    raise exception 'leyo';
  exception when others then r := r || 'A4 auth SELECT log=' || (case when sqlstate = '42501' and sqlerrm like 'permission denied%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- ── B · puertas y parseo (como postgres con claims) ─────────────────────
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_otra, '{}');
    raise exception 'escribio';
  exception when others then r := r || 'B0 no pagada=' || (case when sqlstate = '22023' and sqlerrm like '%solicitud pagada%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', '{}', true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{}');
    raise exception 'escribio';
  exception when others then r := r || 'B1 sin sesion=' || (case when sqlstate = '42501' and sqlerrm like 'Sin sesión%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_ajeno, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{}');
    raise exception 'escribio';
  exception when others then r := r || 'B2 ajeno=' || (case when sqlstate = '42501' and sqlerrm like 'Solo un administrador%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_benef, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{}');
    raise exception 'escribio';
  exception when others then r := r || 'B3 perceptor no admin=' || (case when sqlstate = '42501' and sqlerrm like 'Solo un administrador%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  -- R1/S3: lo que no se entiende es error 22023, nunca 0 ni 22P02
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"base":"abc"}');
    raise exception 'escribio';
  exception when others then r := r || 'B4a base ilegible=' || (case when sqlstate = '22023' and sqlerrm like 'La base no es%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"tarifa_pct":"dos"}');
    raise exception 'escribio';
  exception when others then r := r || 'B4b tarifa ilegible=' || (case when sqlstate = '22023' and sqlerrm like 'La tarifa no es%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"tipo_cambio_idr":"x"}');
    raise exception 'escribio';
  exception when others then r := r || 'B4c cambio ilegible=' || (case when sqlstate = '22023' and sqlerrm like 'El tipo de cambio no es%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"retencion_fecha":"2026-13-01"}');
    raise exception 'escribio';
  exception when others then r := r || 'B4d fecha ilegible=' || (case when sqlstate = '22023' and sqlerrm like '%no es una fecha válida%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"perceptor_residente":"quizá"}');
    raise exception 'escribio';
  exception when others then r := r || 'B4e booleano ilegible=' || (case when sqlstate = '22023' and sqlerrm like '%sí o no%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"base":"1"}');
    raise exception 'escribio';
  exception when others then r := r || 'B5 faltan datos=' || (case when sqlstate = '22023' and sqlerrm like 'Faltan datos%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
      'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'sí',
      'perceptor_id_fiscal', '1234567890123456', 'pph_tipo', 'pph21', 'tarifa_pct', '2.5', 'base', (v_imp + 1)::text));
    raise exception 'escribio';
  exception when others then r := r || 'B6 base>bruto=' || (case when sqlstate = '22023' and sqlerrm like '%no puede superar el bruto%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
      'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'sí',
      'perceptor_id_fiscal', '1234567890123456', 'pph_tipo', 'pph21', 'tarifa_pct', '2.5', 'base', v_half::text,
      'retencion_fecha', (v_hoy + 1)::text));
    raise exception 'escribio';
  exception when others then r := r || 'B7 fecha futura=' || (case when sqlstate = '22023' and sqlerrm like '%no puede ser futura%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  -- L1: PPh 26 ⇔ no residente; persona residente = 16 dígitos; no residente = país + TIN
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
      'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'sí',
      'perceptor_id_fiscal', '1234567890123456', 'pph_tipo', 'pph26', 'tarifa_pct', '20', 'base', v_half::text));
    raise exception 'escribio';
  exception when others then r := r || 'B8a pph26 residente=' || (case when sqlstate = '23514' and sqlerrm like '%retencion_pph26_no_residente%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
      'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'sí',
      'perceptor_id_fiscal', '123456789012345', 'pph_tipo', 'pph21', 'tarifa_pct', '2.5', 'base', v_half::text));
    raise exception 'escribio';
  exception when others then r := r || 'B8b persona 15 digitos=' || (case when sqlstate = '23514' and sqlerrm like '%retencion_id_residente%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
      'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'no',
      'pph_tipo', 'pph26', 'tarifa_pct', '20', 'base', v_half::text));
    raise exception 'escribio';
  exception when others then r := r || 'B8c no residente sin pais/TIN=' || (case when sqlstate = '23514' and sqlerrm like '%retencion_id_no_residente%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  -- A2: retenido 0 exige motivo y documento de la exención
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
      'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'sí',
      'perceptor_id_fiscal', '1234567890123456', 'pph_tipo', 'pph21', 'tarifa_pct', '0', 'base', v_half::text));
    raise exception 'escribio';
  exception when others then r := r || 'B9 exencion sin papel=' || (case when sqlstate = '23514' and sqlerrm like '%retencion_exencion%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- ── C · alta válida, cálculos del servidor, IDR, bukti y DJP ────────────
  perform set_config('request.jwt.claims', c_admin, true);
  v_id1 := public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('pemotong_entidad', v_soc,
    'perceptor_tipo', 'persona', 'perceptor_nombre_fiscal', 'PERCEPTOR DE PRUEBA', 'perceptor_residente', 'sí',
    'perceptor_id_fiscal', '12.3456.7890.1234-56', 'pph_tipo', 'PPH21', 'tarifa_pct', '2,5', 'base', v_half::text,
    'pph_retenido', '1', 'bruto', '1', 'perceptor_user_id', v_ajeno.user_id));
  select format('%s/%s/%s/%s/%s/%s/%s/%s', bruto = v_imp, perceptor_user_id = v_benef.user_id,
                perceptor_id_fiscal = '1234567890123456', pph_tipo = 'pph21',
                pph_retenido = round(v_half * 2.5 / 100, 2), masa_pajak = to_char(v_hoy, 'YYYY-MM'),
                version = 1 and estado = 'normal', creado_por = v_admin.user_id)
    into v_t from public.solicitudes_pago_retencion where id = v_id1;
  r := r || 'C1 alta (servidor pone perceptor/bruto; retenido=base×tarifa, ignora el del JSON)=' || coalesce(v_t, 'sin fila')
         || (case when v_t = 't/t/t/t/t/t/t/t' then ' ok; ' else ' FALLO; ' end);

  perform public.solicitud_pago_retencion_guarda(v_sp, '{"tipo_cambio_idr":"17000.5"}');
  select format('%s/%s/%s', bruto_idr = round(v_imp * 17000.5, 0), base_idr = round(v_half * 17000.5, 0),
                pph_retenido_idr = round(round(v_half * 17000.5, 0) * 2.5 / 100, 0))
    into v_t from public.solicitudes_pago_retencion where id = v_id1;
  r := r || 'C2 importes IDR=' || coalesce(v_t, 'sin fila') || (case when v_t = 't/t/t' then ' ok; ' else ' FALLO; ' end);

  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"bukti_potong_numero":"BP-PRUEBA-1"}');
    raise exception 'escribio';
  exception when others then r := r || 'C3 bukti sin fuente/fecha de cambio (moneda≠IDR)=' || (case when sqlstate = '22023' and sqlerrm like 'Antes de numerar%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('bukti_potong_numero', 'BP-PRUEBA-1',
      'tipo_cambio_fuente', 'kurs_pajak_kmk', 'tipo_cambio_fecha', v_hoy::text));
    raise exception 'escribio';
  exception when others then r := r || 'C4 bukti sin kode objek=' || (case when sqlstate = '23514' and sqlerrm like '%retencion_lista_para_bukti%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('tipo_cambio_fecha', (v_hoy - 8)::text));
    raise exception 'escribio';
  exception when others then r := r || 'C5 cambio fuera de la semana=' || (case when sqlstate = '23514' and sqlerrm like '%retencion_cambio_semana%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  perform set_config('request.jwt.claims', c_admin, true);
  perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('bukti_potong_numero', 'BP-PRUEBA-1',
    'kode_objek_pajak', '21-100-99', 'tipo_cambio_fuente', 'kurs_pajak_kmk', 'tipo_cambio_fecha', v_hoy::text));
  select format('%s/%s', bukti_potong_numero = 'BP-PRUEBA-1', bukti_potong_en is not null)
    into v_t from public.solicitudes_pago_retencion where id = v_id1;
  r := r || 'C6 bukti numerado=' || coalesce(v_t, 'sin fila') || (case when v_t = 't/t' then ' ok; ' else ' FALLO; ' end);

  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"base":"1"}');
    raise exception 'escribio';
  exception when others then r := r || 'C7 congelado tras el bukti=' || (case when sqlstate = '23514' and sqlerrm like '%ya está emitido%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('djp_ingresado_el', (v_hoy + 1)::text));
    raise exception 'escribio';
  exception when others then r := r || 'C8a ingreso DJP futuro=' || (case when sqlstate = '22023' and sqlerrm like '%no puede ser futura%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  perform set_config('request.jwt.claims', c_admin, true);
  perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('djp_ingresado_el', v_hoy::text, 'djp_justificante_ref', 'NTPN-PRUEBA'));
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('djp_ingresado_el', (v_hoy - 1)::text));
    raise exception 'escribio';
  exception when others then r := r || 'C8b ingreso DJP una vez=' || (case when sqlstate = '23514' and sqlerrm like '%ya está registrada%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- ── D · rectificación (A3) ──────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_rectifica(v_sp, 'pembetulan', '  ');
    raise exception 'escribio';
  exception when others then r := r || 'D1 sin motivo=' || (case when sqlstate = '22023' and sqlerrm like '%exige un motivo%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_rectifica(v_sp, 'borrar', 'x');
    raise exception 'escribio';
  exception when others then r := r || 'D2 accion desconocida=' || (case when sqlstate = '22023' and sqlerrm like 'Acción desconocida%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  perform set_config('request.jwt.claims', c_admin, true);
  v_id2 := public.solicitud_pago_retencion_rectifica(v_sp, 'pembetulan', 'Base mal calculada (prueba)');
  select format('%s/%s/%s/%s/%s', (select sustituida from public.solicitudes_pago_retencion where id = v_id1),
                n.version = 2, n.estado = 'pembetulan', n.sustituye_a = v_id1,
                n.bukti_potong_numero is null and n.djp_ingresado_el is null)
    into v_t from public.solicitudes_pago_retencion n where n.id = v_id2;
  r := r || 'D3 pembetulan=' || coalesce(v_t, 'sin fila') || (case when v_t = 't/t/t/t/t' then ' ok; ' else ' FALLO; ' end);

  begin
    update public.solicitudes_pago_retencion set sustituida = false where id = v_id1;
    raise exception 'escribio';
  exception when others then r := r || 'D4 des-sustituir=' || (case when sqlstate = '23514' and sqlerrm like '%ya está sustituida%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    update public.solicitudes_pago_retencion set sustituida = true where id = v_id2;
    raise exception 'escribio';
  exception when others then r := r || 'D5 sustituir sin rectificar=' || (case when sqlstate = '23514' and sqlerrm like '%solo se sustituye con la rectificación%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    perform public.solicitud_pago_retencion_rectifica(v_sp, 'batal', 'x');
    raise exception 'escribio';
  exception when others then r := r || 'D6 rectificar sin bukti=' || (case when sqlstate = '22023' and sqlerrm like '%aún no tiene bukti%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- ── E · nadie registra la suya (S1): el perceptor promovido a admin dentro del sub-bloque ──
  begin
    perform set_config('request.jwt.claims', c_admin, true);
    update public.usuarios set rol = 'super_admin', activo = true where user_id = v_benef.user_id;
    perform set_config('request.jwt.claims', c_benef, true);
    perform public.solicitud_pago_retencion_guarda(v_sp, '{"base":"1"}');
    raise exception 'escribio';
  exception when others then r := r || 'E admin perceptor=' || (case when sqlstate = '42501' and sqlerrm like 'Nadie registra%' then 'ok; ' else 'FALLO ' || sqlerrm || '; ' end); end;

  -- la versión 2 se edita (no tiene bukti), se numera y se anula (batal)
  perform set_config('request.jwt.claims', c_admin, true);
  perform public.solicitud_pago_retencion_guarda(v_sp, jsonb_build_object('base', round(v_half / 2, 2)::text));
  perform public.solicitud_pago_retencion_guarda(v_sp, '{"bukti_potong_numero":"BP-PRUEBA-2"}');
  v_id3 := public.solicitud_pago_retencion_rectifica(v_sp, 'batal', 'Anulación de prueba');
  select format('%s/%s/%s/%s', (select sustituida from public.solicitudes_pago_retencion where id = v_id2),
                n.estado = 'batal' and n.version = 3, n.bukti_potong_numero = 'BP-PRUEBA-2',
                (select count(*) from public.solicitudes_pago_retencion x
                  where x.solicitud_id = v_sp and x.estado <> 'batal' and not x.sustituida) = 0)
    into v_t from public.solicitudes_pago_retencion n where n.id = v_id3;
  r := r || 'D7 batal=' || coalesce(v_t, 'sin fila') || (case when v_t = 't/t/t/t' then ' ok; ' else ' FALLO; ' end);

  -- ── F · lectura por user_id (S1), con el GRANT que llegará con la pantalla ──
  begin
    execute 'grant select on public.solicitudes_pago_retencion to authenticated';
    execute 'set local role authenticated';
    v_t := '';
    perform set_config('request.jwt.claims', c_benef, true);
    select count(*) into v_n from public.solicitudes_pago_retencion where solicitud_id = v_sp;
    v_t := v_t || v_n || '/';
    perform set_config('request.jwt.claims', c_ajeno, true);
    select count(*) into v_n from public.solicitudes_pago_retencion where solicitud_id = v_sp;
    v_t := v_t || v_n || '/';
    perform set_config('request.jwt.claims', c_ajeno_email_benef, true);
    select count(*) into v_n from public.solicitudes_pago_retencion where solicitud_id = v_sp;
    v_t := v_t || v_n || '/';
    perform set_config('request.jwt.claims', c_admin, true);
    select count(*) into v_n from public.solicitudes_pago_retencion where solicitud_id = v_sp;
    v_t := v_t || v_n;
    raise exception 'LECT:%', v_t;
  exception when others then
    r := r || 'F lectura perceptor/ajeno/ajeno-con-email-del-perceptor/admin=' || sqlerrm
           || (case when sqlerrm = 'LECT:3/0/0/3' then ' ok; ' else ' FALLO; ' end);
  end;

  -- ── G · log: cada escritura, id fiscal enmascarado (S5) ─────────────────
  select format('%s/%s/%s',
    (select count(*) from public.solicitudes_pago_retencion_log where solicitud_id = v_sp) >= 9,
    (select bool_and(despues->>'perceptor_id_fiscal' like '…%') from public.solicitudes_pago_retencion_log where solicitud_id = v_sp),
    (select count(*) from public.solicitudes_pago_retencion_log where solicitud_id = v_sp
      and (despues::text like '%1234567890123456%' or coalesce(antes::text, '') like '%1234567890123456%')) = 0)
    into v_t;
  r := r || 'G log enmascarado=' || v_t || (case when v_t = 't/t/t' then ' ok; ' else ' FALLO; ' end);

  v_ok := (length(r) - length(replace(r, 'ok;', ''))) / 3;
  v_tot := v_ok + (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception 'RES: % | ok %/%', r, v_ok, v_tot;
end $$;
