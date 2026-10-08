-- Prueba por PERFILES de «Reclamar pago» (8-oct-2026). Se ejecuta DESPUES de aplicar la migracion 20261010070000_reclamo_pago_parcela.sql
-- (o, antes de aplicarla, en el MISMO envio que ella: migracion + este bloque). Todo en una transaccion que acaba en `raise exception`
-- (rollback, sin rastro): el veredicto sale en el mensaje: «FALLOS=0 de N casos | ...». Solo cuenta y codigos: ningun dato personal.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback). El unico «drop» es la funcion temporal pg_temp.intenta.
-- Perfiles: admin de empresa propia, admin de empresa ajena (empresa distinta de la parcela), agente, comprador del portal
-- (sesion autenticada que NO esta en usuarios), anon, cuenta desactivada, propietario (admin global). Un caso permitido y uno denegado por perfil
-- donde el perfil puede tener los dos. Usa usuarios y datos EXISTENTES (el candado de alta impide crear admin_empresa de prueba) y solo
-- modifica, dentro de la transaccion, usuarios.activo y empresas.sociedad_clave. No toca contratos (decenas de triggers).
do $t$
declare
  fallos int := 0; total int := 0; resumen text := '';
  v_prop uuid; v_prop_em text;
  v_ae uuid; v_ae_em text; v_ea text; v_eb text;
  v_ag uuid; v_ag_em text;
  v_por uuid := gen_random_uuid();
  u_a uuid; cl_a uuid; u_a2 uuid; cl_a2 uuid; u_b uuid; cl_b uuid; cl_otra uuid;
  u_disc uuid; cl_disc uuid; u_firma uuid; cl_firma uuid;
  r text; n1 bigint; n2 bigint; j jsonb; v_cola uuid; v_rec uuid; v_ok boolean;
  v_para text; v_ctr uuid; v_parc text; v_nota text; v_cnt int;
begin
  -- ── función temporal: ejecuta SQL como un perfil y devuelve 'OK:<filas>' o 'E<sqlstate>/<hint>' ──
  execute $f$
    create function pg_temp.intenta(p_rol text, p_sub uuid, p_email text, p_sql text) returns text
    language plpgsql as $g$
    declare n bigint; v_h text;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', p_rol, 'email', p_email)::text, true);
      execute format('set local role %I', p_rol);
      begin
        execute 'select count(*) from (' || p_sql || ') t' into n;
        reset role;
        return 'OK:' || n;
      exception when others then
        get stacked diagnostics v_h = pg_exception_hint;
        reset role;
        return 'E' || sqlstate || '/' || coalesce(v_h, '');
      end;
    end $g$;
  $f$;

  -- ── perfiles reales (sin literales) ──
  select user_id, email into v_prop, v_prop_em from public.usuarios where es_propietario and activo limit 1;
  select user_id, email, empresas[1] into v_ae, v_ae_em, v_ea from public.usuarios
   where rol = 'admin_empresa' and ambito = 'empresa' and activo and cardinality(empresas) = 1 order by user_id limit 1;
  select user_id, email into v_ag, v_ag_em from public.usuarios where rol = 'agente' and ambito = 'global' and activo order by user_id limit 1;
  select e.clave into v_eb from public.empresas e where e.clave <> v_ea order by e.clave limit 1;
  if v_prop is null or v_ae is null or v_ag is null or v_eb is null then
    raise exception 'FALLOS=1 | sin perfiles de prueba (propietario %, admin_empresa %, agente %, otra empresa %)', v_prop is not null, v_ae is not null, v_ag is not null, v_eb is not null;
  end if;

  -- ── datos de prueba: parcelas con un destinatario seleccionable según la propia función de candidatos ──
  select x.uid, x.cl into u_a, cl_a from (
    select u.id uid, c.client_id cl from public.unidades u join public.proyectos p on p.id = u.proyecto_id and p.empresa = v_ea
      cross join lateral public._reclamo_pago_candidatos(u.id) c where c.orden = 1 and c.seleccionable order by u.id limit 1) x;
  select x.uid, x.cl into u_a2, cl_a2 from (
    select u.id uid, c.client_id cl from public.unidades u join public.proyectos p on p.id = u.proyecto_id and p.empresa = v_ea
      cross join lateral public._reclamo_pago_candidatos(u.id) c where c.orden = 1 and c.seleccionable and u.id <> u_a and c.client_id <> cl_a
       and c.client_id not in (select k.client_id from public._reclamo_pago_candidatos(u_a) k where k.client_id is not null) order by u.id limit 1) x;
  select x.uid, x.cl into u_b, cl_b from (
    select u.id uid, c.client_id cl from public.unidades u join public.proyectos p on p.id = u.proyecto_id and p.empresa = v_eb
      cross join lateral public._reclamo_pago_candidatos(u.id) c where c.orden = 1 and c.seleccionable order by u.id limit 1) x;
  -- una persona de OTRA parcela de la misma empresa (que no sea compradora de u_a)
  cl_otra := cl_a2;
  -- parcela con contrato firmado pero sociedad que no coincide con la del proyecto (natural: 7 el 8-oct)
  select x.uid, x.cl into u_disc, cl_disc from (
    select u.id uid, c.client_id cl from public.unidades u cross join lateral public._reclamo_pago_candidatos(u.id) c
     where c.orden = 1 and c.motivo = 'sociedad_discordante' order by u.id limit 1) x;
  -- parcela con contrato sin firmar y ficha completa (natural: 1 el 8-oct)
  select x.uid, x.cl into u_firma, cl_firma from (
    select u.id uid, c.client_id cl from public.unidades u cross join lateral public._reclamo_pago_candidatos(u.id) c
     where c.orden = 1 and c.motivo = 'sin_firmar' and c.client_id is not null order by u.id limit 1) x;
  if u_a is null or u_a2 is null or u_b is null then
    raise exception 'FALLOS=1 | faltan parcelas de prueba (propia %, propia2 %, ajena %)', u_a is not null, u_a2 is not null, u_b is not null;
  end if;

  -- helper de contabilidad: cada caso es (nombre, resultado esperado como patron LIKE sobre lo devuelto)
  -- ═════════ A. PERMISOS POR PERFIL ═════════
  -- A1 admin de empresa PROPIA: permitido (destinatarios y historial)
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select * from public.reclamo_pago_destinatarios(%L)', u_a));
  total := total + 1; if r not like 'OK:%' or r = 'OK:0' then fallos := fallos + 1; resumen := resumen || ' [A1 destinatarios admin propio: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select * from public.reclamo_pago_historial(%L)', u_a));
  total := total + 1; if r not like 'OK:%' then fallos := fallos + 1; resumen := resumen || ' [A1b historial admin propio: ' || r || ']'; end if;
  -- A2 admin de empresa AJENA: denegado en las tres
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select * from public.reclamo_pago_destinatarios(%L)', u_b));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A2 destinatarios admin ajeno: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select * from public.reclamo_pago_historial(%L)', u_b));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A2b historial admin ajeno: ' || r || ']'; end if;
  select count(*) into n1 from public.reclamos_pago;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_b, cl_b));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A2c encolar admin ajeno: ' || r || ']'; end if;
  select count(*) into n2 from public.reclamos_pago;
  total := total + 1; if n2 <> n1 then fallos := fallos + 1; resumen := resumen || ' [A2d el denegado dejó filas en el libro]'; end if;
  -- A3 agente: denegado
  r := pg_temp.intenta('authenticated', v_ag, v_ag_em, format('select * from public.reclamo_pago_destinatarios(%L)', u_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A3 destinatarios agente: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ag, v_ag_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_a, cl_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A3b encolar agente: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ag, v_ag_em, format('select * from public.reclamo_pago_historial(%L)', u_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A3c historial agente: ' || r || ']'; end if;
  -- A4 comprador del portal (sesion autenticada que no esta en usuarios): denegado
  r := pg_temp.intenta('authenticated', v_por, 'comprador@example.test', format('select * from public.reclamo_pago_destinatarios(%L)', u_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A4 destinatarios comprador: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_por, 'comprador@example.test', format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_a, cl_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A4b encolar comprador: ' || r || ']'; end if;
  -- A5 anon: sin EXECUTE (42501 permission denied)
  r := pg_temp.intenta('anon', null, null, format('select * from public.reclamo_pago_destinatarios(%L)', u_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A5 destinatarios anon: ' || r || ']'; end if;
  r := pg_temp.intenta('anon', null, null, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_a, cl_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A5b encolar anon: ' || r || ']'; end if;
  -- A6 tabla y funciones internas cerradas para authenticated/anon (sin policies ni grants)
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, 'select * from public.reclamos_pago');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A6 select tabla admin: ' || r || ']'; end if;
  r := pg_temp.intenta('anon', null, null, 'select * from public.reclamos_pago');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A6b select tabla anon: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_datos(%L)', gen_random_uuid()));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A6c reclamo_pago_datos authenticated: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select * from public._reclamo_pago_candidatos(%L)', u_a));
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A6d candidatos authenticated: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, 'select * from public.correo_cola_reclamar(1)');
  total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [A6e reclamar authenticated: ' || r || ']'; end if;
  -- A7 el propietario (admin global): permitido sobre las dos empresas
  r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select * from public.reclamo_pago_destinatarios(%L)', u_b));
  total := total + 1; if r not like 'OK:%' or r = 'OK:0' then fallos := fallos + 1; resumen := resumen || ' [A7 propietario otra empresa: ' || r || ']'; end if;

  -- ═════════ B. REGLAS DE NEGOCIO (admin de empresa propia) ═════════
  -- B1 nota con enlace / www / @ / >300 / controles: rechazada, sin filas
  select count(*) into n1 from public.reclamos_pago;
  foreach v_nota in array array['mira http://x.test', 'entra en www.x.test', 'escribe a alguien@x.test', repeat('a', 301)] loop
    r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], %L)', u_a, cl_a, v_nota));
    total := total + 1; if r not like 'E22023/nota_invalida' then fallos := fallos + 1; resumen := resumen || ' [B1 nota "' || left(v_nota, 12) || '": ' || r || ']'; end if;
  end loop;
  select count(*) into n2 from public.reclamos_pago;
  total := total + 1; if n2 <> n1 then fallos := fallos + 1; resumen := resumen || ' [B1b nota rechazada dejó filas]'; end if;
  -- B2 persona de OTRA parcela en el lote: se rechaza el lote ENTERO (ni siquiera la válida queda)
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_encolar(%L, array[%L, %L]::uuid[], null)', u_a, cl_a, cl_otra));
  total := total + 1; if r not like 'E22023/destinatario_ajeno_a_la_parcela' then fallos := fallos + 1; resumen := resumen || ' [B2 client de otra parcela: ' || r || ']'; end if;
  select count(*) into n2 from public.reclamos_pago;
  total := total + 1; if n2 <> n1 then fallos := fallos + 1; resumen := resumen || ' [B2b lote rechazado dejó filas]'; end if;
  -- B3 más de 10 (distintos) y vacío
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_encolar(%L, (select array_agg(gen_random_uuid()) from generate_series(1, 11)), null)', u_a));
  total := total + 1; if r not like 'E22023/demasiados_destinatarios' then fallos := fallos + 1; resumen := resumen || ' [B3 11 ids: ' || r || ']'; end if;
  r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_encolar(%L, array[]::uuid[], null)', u_a));
  total := total + 1; if r not like 'E22023/sin_destinatarios' then fallos := fallos + 1; resumen := resumen || ' [B3b vacío: ' || r || ']'; end if;
  -- B4 contrato sin firmar (si hay caso natural)
  if u_firma is not null and exists (select 1 from public.proyectos p join public.unidades u on u.proyecto_id = p.id where u.id = u_firma and p.empresa = v_ea) then
    r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_firma, cl_firma));
  elsif u_firma is not null then
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_firma, cl_firma));
  else r := 'SIN_CASO_NATURAL'; end if;
  total := total + 1;
  if r = 'SIN_CASO_NATURAL' then resumen := resumen || ' [B4 sin firmar: sin caso natural, no probado]';
  elsif r not like 'E22023/sin_firmar' then fallos := fallos + 1; resumen := resumen || ' [B4 sin firmar: ' || r || ']'; end if;
  -- B5 sociedad del contrato distinta de la del proyecto (si hay caso natural; lo lanza el propietario: es admin global)
  if u_disc is not null then
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_disc, cl_disc));
    total := total + 1; if r not like 'E22023/sociedad_discordante' then fallos := fallos + 1; resumen := resumen || ' [B5 sociedad discordante: ' || r || ']'; end if;
  else total := total + 1; resumen := resumen || ' [B5 sociedad discordante: sin caso natural, no probado]'; end if;
  -- B6 sociedad NULA del proyecto (se anula la sociedad de la empresa dentro de la transacción)
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);
    update public.empresas set sociedad_clave = null where clave = v_ea;
    r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_a, cl_a));
    total := total + 1; if r not like 'E22023/sociedad_proyecto_sin_definir' then fallos := fallos + 1; resumen := resumen || ' [B6 sociedad proyecto nula: ' || r || ']'; end if;
    select count(*) into n1 from public._reclamo_pago_candidatos(u_a) c where c.seleccionable;
    total := total + 1; if n1 <> 0 then fallos := fallos + 1; resumen := resumen || ' [B6c con sociedad de proyecto nula quedan seleccionables: ' || n1 || ']'; end if;
  exception when others then
    total := total + 1; fallos := fallos + 1; resumen := resumen || ' [B6 no se pudo anular la sociedad de la empresa: ' || sqlstate || ']';
  end;
  -- (la sociedad de la empresa sigue nula hasta el rollback: lo que sigue usa una parcela de la OTRA empresa para no depender de ella)

  -- ═════════ C. CAMINO FELIZ, DOBLE CLIC, SIN LÍMITE, COLA ═════════
  -- se usa la parcela u_b (otra empresa) con el propietario, que no depende de la sociedad anulada arriba
  u_a := u_b; cl_a := cl_b;
  -- C1 encolar con nota limpia: 1 libro + 1 cola pendiente anclada al reclamo
  r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L, %L, %L]::uuid[], %L)', u_a, cl_a, cl_a, cl_a, '  Pago de la 2ª cuota,   gracias  '));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [C1 encolar propietario: ' || r || ']'; end if;
  select count(*) into n1 from public.reclamos_pago where unidad_id = u_a and client_id = cl_a;
  total := total + 1; if n1 <> 1 then fallos := fallos + 1; resumen := resumen || ' [C1b dedup de ids repetidos: filas=' || n1 || ']'; end if;
  select r2.id, r2.cola_id, r2.contrato_id, r2.nota into v_rec, v_cola, v_ctr, v_nota from public.reclamos_pago r2 where r2.unidad_id = u_a and r2.client_id = cl_a;
  total := total + 1; if v_nota is distinct from 'Pago de la 2ª cuota, gracias' then fallos := fallos + 1; resumen := resumen || ' [C1c nota normalizada: ' || coalesce(v_nota, 'null') || ']'; end if;
  total := total + 1; if not exists (select 1 from public.correos_cola q where q.id = v_cola and q.reclamo_id = v_rec and q.clave = 'reclamo_pago' and q.estado = 'pendiente') then
    fallos := fallos + 1; resumen := resumen || ' [C1d fila de cola ausente o mal anclada]'; end if;
  total := total + 1; if not exists (select 1 from public.reclamos_pago x where x.id = v_rec and x.creado_por = lower(v_prop_em) and x.creado_por_uid = v_prop) then
    fallos := fallos + 1; resumen := resumen || ' [C1e autor no sale de la sesión]'; end if;
  -- C2 doble clic inmediato: rechazado
  r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], null)', u_a, cl_a));
  total := total + 1; if r not like 'E22023/doble_clic' then fallos := fallos + 1; resumen := resumen || ' [C2 doble clic: ' || r || ']'; end if;
  -- C3 SIN límite de frecuencia: pasada la ventana corta, vuelve a entrar y la cola NO se lo traga (indice unico)
  update public.reclamos_pago set creado_en = now() - interval '5 minutes' where id = v_rec;
  r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select public.reclamo_pago_encolar(%L, array[%L]::uuid[], %L)', u_a, cl_a, 'Segundo recordatorio'));
  total := total + 1; if r <> 'OK:1' then fallos := fallos + 1; resumen := resumen || ' [C3 segundo reclamo tras la ventana: ' || r || ']'; end if;
  select count(*) into n1 from public.correos_cola q join public.reclamos_pago x on x.id = q.reclamo_id where x.unidad_id = u_a and x.client_id = cl_a;
  total := total + 1; if n1 <> 2 then fallos := fallos + 1; resumen := resumen || ' [C3b filas de cola para la persona=' || n1 || ' (esperadas 2)]'; end if;
  -- C4 historial lo ve el propietario con las dos filas
  r := pg_temp.intenta('authenticated', v_prop, v_prop_em, format('select * from public.reclamo_pago_historial(%L)', u_a));
  total := total + 1; if r <> 'OK:2' then fallos := fallos + 1; resumen := resumen || ' [C4 historial: ' || r || ']'; end if;
  -- C5 la edge puede resolver el reclamo: reclamar como service_role devuelve la fila con destinatario y contrato
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  select q.id into v_cola from public.correos_cola q join public.reclamos_pago x on x.id = q.reclamo_id
   where x.id = v_rec;
  select count(*) into n1 from public.correos_cola where estado in ('pendiente', 'enviando') and clave <> 'reclamo_pago';
  set local role service_role;
  select count(*), max(c.para), max(c.contrato_id::text)::uuid into v_cnt, v_para, v_ctr from public.correo_cola_reclamar(10) c where c.id = v_cola;
  reset role;
  total := total + 1; if n1 < 10 and (v_cnt <> 1 or v_para is null or v_ctr is null) then
    fallos := fallos + 1; resumen := resumen || ' [C5 reclamar no devuelve el reclamo con destinatario: n=' || v_cnt || ']'; end if;
  total := total + 1; if n1 < 10 and (select q.estado from public.correos_cola q where q.id = v_cola) <> 'enviando' then
    fallos := fallos + 1; resumen := resumen || ' [C5b la fila no quedó enviando]'; end if;
  set local role service_role;
  select count(*) into n1 from public.reclamo_pago_datos(v_cola) d where d.para is not null and d.parcela is not null and d.proyecto is not null and d.empresa_razon is not null and d.nota = 'Pago de la 2ª cuota, gracias';
  reset role;
  total := total + 1; if n1 <> 1 then fallos := fallos + 1; resumen := resumen || ' [C6 reclamo_pago_datos: filas completas=' || n1 || ']'; end if;
  -- C7 cerrar ok escribe en correos_enviados (via reclamo_pago, contrato del libro) y NO revienta
  if n1 = 1 then
    set local role service_role;
    v_ok := public.correo_cola_ok(v_cola, coalesce(v_para, 'x@example.test'), 'v1');
    reset role;
    total := total + 1; if not coalesce(v_ok, false) then fallos := fallos + 1; resumen := resumen || ' [C7 correo_cola_ok devolvió false]'; end if;
    total := total + 1; if not exists (select 1 from public.correos_enviados e where e.via = 'reclamo_pago' and e.plantilla = 'reclamo_pago' and e.contrato_id = v_ctr) then
      fallos := fallos + 1; resumen := resumen || ' [C7b sin registro en correos_enviados]'; end if;
  end if;
  -- C8 el catalogo antiguo no se rompe: la regla de las otras claves sigue igual y correo_encolar rechaza la nueva
  select count(*) into n1 from public._correo_cola_regla('enlace_firma_cadena') r2 where r2.soportada and r2.max_intentos = 10;
  total := total + 1; if n1 <> 1 then fallos := fallos + 1; resumen := resumen || ' [C8 regla de enlace_firma_cadena alterada]'; end if;
  begin
    set local role service_role;
    perform public.correo_encolar('reclamo_pago', null, u_a, null, '{}'::jsonb);
    reset role;
    total := total + 1; fallos := fallos + 1; resumen := resumen || ' [C8b correo_encolar acepto reclamo_pago]';
  exception when others then
    reset role; total := total + 1;
  end;

  -- ═════════ D. CUENTA DESACTIVADA ═════════
  perform set_config('request.jwt.claims', json_build_object('sub', v_prop, 'role', 'authenticated', 'email', v_prop_em)::text, true);
  begin
    update public.usuarios set activo = false where user_id = v_ae;
    r := pg_temp.intenta('authenticated', v_ae, v_ae_em, format('select * from public.reclamo_pago_destinatarios(%L)', u_a2));
    total := total + 1; if r not like 'E42501%' then fallos := fallos + 1; resumen := resumen || ' [D1 cuenta desactivada: ' || r || ']'; end if;
  exception when others then
    total := total + 1; fallos := fallos + 1; resumen := resumen || ' [D1 no se pudo desactivar la cuenta de prueba: ' || sqlstate || ']';
  end;

  raise exception 'FALLOS=% de % casos |%', fallos, total, case when resumen = '' then ' todo en verde' else resumen end;
end $t$;
