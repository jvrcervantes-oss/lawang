-- destructivo-ok: prueba que se deshace sola (raise exception final); los delete/truncate/update solo INTENTAN tocar correo_plantillas y todo se revierte.
-- PRUEBA — Ajustes del ERP, S5.1 (20261002100000_correo_plantillas). 2-oct-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md → «Plan de S5». Criterio: la tabla está cerrada a public/anon/authenticated y a
-- service_role salvo SELECT; la RPC solo la ejecuta service_role y solo guarda para un super admin ACTIVO (anónimo, comprador del portal,
-- agente, admin que no es super y super dado de baja → 42501); solo UPDATE; clave y catálogo sellados; borrar/vaciar imposible; el texto
-- plano se valida igual que valida.ts; el historial queda en ajustes_log en la misma transacción; correos_enviados admite plantilla+versión.
--
-- Se ejecuta ENTERA como postgres (MCP execute_sql / psql) y CAMBIA de rol dentro (`set local role …`) para probar GRANT y permisos de
-- verdad. NO ESCRIBE NADA: termina en `raise exception 'FIN DE PRUEBAS…'`, que deshace la transacción entera.
--   Lawang:  se pega este fichero en execute_sql (contracts/sql/prueba_correo_plantillas.sql).
--   Maestro: python erp/pruebas/corre.py <instancia> correo_plantillas.sql   (mismo cuerpo).
-- Antes de pegarla hay que tener APLICADA la migración 20261002100000 (o pegar la migración justo antes en la misma ejecución).
do $$
declare
  r text := '';
  u_sa uuid := gen_random_uuid();  m_sa text := 'super.plantillas@pruebas.test';
  u_ad uuid := gen_random_uuid();  m_ad text := 'admin.plantillas@pruebas.test';
  u_ag uuid := gen_random_uuid();  m_ag text := 'agente.plantillas@pruebas.test';
  u_of uuid := gen_random_uuid();  m_of text := 'super.baja.plantillas@pruebas.test';
  u_po uuid := gen_random_uuid();  m_po text := 'portal.plantillas@pruebas.test';
  claves constant text[] := array['enlace_firma_cadena','copia_firmada_comprador','copia_firmada_portal','copia_firmada_manual','aviso_anulacion','factura_primer_hito','proforma_total','factura_vencimiento'];
  k text; n int; n2 int; v jsonb; f record; st text; ok boolean; quien uuid; rol text;
  v_asu constant text := 'Tu contrato firmado · {{numero}}';
  v_cue constant text := E'{{saludo}},\n\nAquí tienes tu copia del contrato {{contrato_proyecto}}.\n\nUn saludo.';
  v_ban  text[];
  caso   record;
  cid    uuid;
begin
  -- ── Preparación (como postgres) ───────────────────────────────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  insert into auth.users (id, email, aud, role) values
    (u_sa, m_sa, 'authenticated', 'authenticated'), (u_ad, m_ad, 'authenticated', 'authenticated'),
    (u_ag, m_ag, 'authenticated', 'authenticated'), (u_of, m_of, 'authenticated', 'authenticated'),
    (u_po, m_po, 'authenticated', 'authenticated');
  insert into public.usuarios (user_id, email, nombre, rol, herramientas, activo, numero_usuario) values
    (u_sa, m_sa, 'Super Plantillas', 'super_admin', '{}', true, 'USR-PRBPL-1'),
    (u_ad, m_ad, 'Admin Plantillas', 'admin', array['ajustes'], true, 'USR-PRBPL-2'),
    (u_ag, m_ag, 'Agente Plantillas', 'agente', array['ajustes'], true, 'USR-PRBPL-3'),
    (u_of, m_of, 'Super de baja', 'super_admin', '{}', false, 'USR-PRBPL-4');
  execute 'set local session_replication_role = origin';

  -- ── A. Siembra ────────────────────────────────────────────────────────────────────────────────────────────
  select count(*) into n from public.correo_plantillas where clave = any (claves) and not activa and asunto is null and cuerpo is null and cuerpo_alt is null and version = 0;
  r := r || format(E'\nA1 las 8 claves sembradas, inactivas, sin texto y en versión 0: %s de 8 → %s', n, case when n = 8 then 'ok' else 'FALLA' end);
  select count(*) into n from public.correo_plantillas;
  r := r || format(E'\nA2 no hay más filas que esas 8: %s → %s', n, case when n = 8 then 'ok' else 'FALLA' end);
  select count(*) into n from public.correo_plantillas where jsonb_typeof(variables -> 'permitidas') = 'array' and (variables ->> 'variantes') in ('1','2')
     and (variables -> 'permitidas') ? 'marca';
  r := r || format(E'\nA3 cada catálogo tiene la forma esperada (permitidas, obligatorias, variantes, marca): %s de 8 → %s', n, case when n = 8 then 'ok' else 'FALLA' end);

  -- ── B. Permisos: la tabla y la RPC por perfil ─────────────────────────────────────────────────────────────
  foreach rol in array array['anon', 'authenticated'] loop
    -- cada perfil de authenticated lleva su JWT; el permiso es del ROL, así que el resultado es el mismo para todos
    for caso in select * from (values ('anónimo', null::uuid, 'anon'), ('super admin', u_sa, 'authenticated'), ('admin', u_ad, 'authenticated'),
                                       ('agente', u_ag, 'authenticated'), ('comprador del portal', u_po, 'authenticated')) t(nombre, uid, rl) where rl = rol loop
      perform set_config('request.jwt.claims', case when caso.uid is null then '{"role":"anon"}' else json_build_object('sub', caso.uid, 'role', 'authenticated')::text end, true);
      execute format('set local role %I', rol);
      begin perform 1 from public.correo_plantillas limit 1; st := 'LEYÓ'; exception when insufficient_privilege then st := '42501'; end;
      begin update public.correo_plantillas set activa = true where clave = claves[1]; st := st || '/ESCRIBIÓ'; exception when insufficient_privilege then st := st || '/42501'; end;
      begin perform public.correo_plantilla_guardar(coalesce(caso.uid, u_sa), claves[1], v_asu, v_cue, null, false, 'x'); st := st || '/EJECUTÓ'; exception when insufficient_privilege then st := st || '/42501'; end;
      execute 'reset role';
      r := r || format(E'\nB1 %s (%s): leer / actualizar / ejecutar la RPC → %s → %s', caso.nombre, rol, st, case when st = '42501/42501/42501' then 'ok' else 'FALLA' end);
    end loop;
  end loop;
  execute 'set local role service_role';
  begin perform 1 from public.correo_plantillas limit 1; st := 'lee'; exception when insufficient_privilege then st := 'NO LEE'; end;
  begin update public.correo_plantillas set activa = false where clave = claves[1]; st := st || '/ESCRIBE'; exception when insufficient_privilege then st := st || '/no escribe'; end;
  begin insert into public.correo_plantillas (clave, variables) values ('x', '{}'); st := st || '/INSERTA'; exception when insufficient_privilege or check_violation then st := st || '/no inserta'; end;
  execute 'reset role';
  r := r || format(E'\nB2 service_role: %s → %s', st, case when st = 'lee/no escribe/no inserta' then 'ok' else 'FALLA' end);

  -- ── C. La RPC solo guarda para un super admin ACTIVO ──────────────────────────────────────────────────────
  execute 'set local role service_role';
  n := 0;
  foreach quien in array array[u_ad, u_ag, u_po, u_of, gen_random_uuid()] loop
    begin perform public.correo_plantilla_guardar(quien, claves[2], v_asu, v_cue, null, true, 'no debe pasar'); exception when insufficient_privilege then n := n + 1; end;
  end loop;
  begin perform public.correo_plantilla_guardar(null, claves[2], v_asu, v_cue, null, true, 'actor nulo'); exception when insufficient_privilege then n := n + 1; end;
  execute 'reset role';
  r := r || format(E'\nC1 admin, agente, comprador de portal, super de baja, uuid desconocido y actor nulo → 42501: %s de 6 → %s', n, case when n = 6 then 'ok' else 'FALLA' end);
  select version into n from public.correo_plantillas where clave = claves[2];
  r := r || format(E'\nC2 ninguno de esos intentos tocó la fila: versión %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- ── D. El super admin guarda: versión, historial, mismo valor, restaurar ──────────────────────────────────
  execute 'set local role service_role';
  v := public.correo_plantilla_guardar(u_sa, claves[2], v_asu, v_cue, null, true, 'prueba S5.1');
  execute 'reset role';
  select * into f from public.ajustes_log where tabla = 'correo_plantillas' and clave = claves[2] order by id desc limit 1;
  r := r || format(E'\nD1 super admin guarda: cambiado=%s versión=%s · log(quien=%s, motivo=%s, antes.version=%s, despues.version=%s, despues.asunto ok=%s) → %s',
        v ->> 'cambiado', v ->> 'version', f.quien, f.motivo, f.antes ->> 'version', f.despues ->> 'version', (f.despues ->> 'asunto') = v_asu,
        case when v ->> 'cambiado' = 'true' and v ->> 'version' = '1' and f.quien = m_sa and f.motivo = 'prueba S5.1'
                  and f.antes ->> 'version' = '0' and f.despues ->> 'version' = '1' and (f.despues ->> 'asunto') = v_asu then 'ok' else 'FALLA' end);
  select count(*) into n from public.ajustes_log where tabla = 'correo_plantillas';
  execute 'set local role service_role';
  v := public.correo_plantilla_guardar(u_sa, claves[2], v_asu, v_cue, null, true, 'igual');
  execute 'reset role';
  select count(*) into n2 from public.ajustes_log where tabla = 'correo_plantillas';
  r := r || format(E'\nD2 guardar lo mismo: cambiado=%s, versión %s y el log no crece (%s → %s) → %s', v ->> 'cambiado', v ->> 'version', n, n2,
        case when v ->> 'cambiado' = 'false' and v ->> 'version' = '1' and n = n2 then 'ok' else 'FALLA' end);
  select * into f from public.correo_plantillas where clave = claves[2];
  r := r || format(E'\nD3 la fila: activa=%s, versión=%s, actualizado_por=%s → %s', f.activa, f.version, f.actualizado_por,
        case when f.activa and f.version = 1 and f.actualizado_por = m_sa then 'ok' else 'FALLA' end);
  execute 'set local role service_role';
  v := public.correo_plantilla_guardar(u_sa, claves[2], null, null, null, false, 'restaurar');
  execute 'reset role';
  select * into f from public.correo_plantillas where clave = claves[2];
  r := r || format(E'\nD4 restaurar fábrica: activa=%s, texto nulo=%s, versión=%s → %s', f.activa, f.asunto is null and f.cuerpo is null, f.version,
        case when not f.activa and f.asunto is null and f.cuerpo is null and f.version = 2 then 'ok' else 'FALLA' end);

  -- ── E. Texto plano: lo que se rechaza (22023) y lo que pasa; mismos casos que plantillas_motor.test.js ────────
  n := 0; n2 := 0;
  for caso in select * from (values
      (1, 'HTML',                 'Tu contrato firmado · {{numero}}', E'{{saludo}}, <b>hola</b> {{contrato_proyecto}}'),
      (2, 'URL',                  'Tu contrato firmado · {{numero}}', E'{{saludo}}, mira https://malo.example {{contrato_proyecto}}'),
      (3, 'correo suelto',        'Tu contrato firmado · {{numero}}', E'{{saludo}}, escribe a x@malo.example {{contrato_proyecto}}'),
      (4, 'variable desconocida', 'Tu contrato firmado · {{numero}}', E'{{saludo}} {{importe}} {{contrato_proyecto}}'),
      (5, 'falta obligatoria',    'Tu contrato firmado', E'{{saludo}} {{contrato_proyecto}}'),
      (6, 'llave suelta',         'Tu contrato firmado · {{numero}}', E'{{saludo}} {contrato_proyecto}} {{contrato_proyecto}}'),
      (7, 'asunto con salto',     E'Tu contrato\nfirmado · {{numero}}', E'{{saludo}} {{contrato_proyecto}}'),
      (8, 'carácter de control',  'Tu contrato firmado · {{numero}}', E'{{saludo}} \u0007 {{contrato_proyecto}}'),
      (9, 'demasiado largo',      'Tu contrato firmado · {{numero}}', E'{{saludo}} {{contrato_proyecto}} ' || repeat('a', 5001)),
      (10,'javascript:',          'Tu contrato firmado · {{numero}}', E'{{saludo}} javascript:alert {{contrato_proyecto}}'),
      (11,'vacío',                'Tu contrato firmado · {{numero}}', '   ')
    ) t(id, nombre, asu, cue) loop
    execute 'set local role service_role';
    begin
      perform public.correo_plantilla_guardar(u_sa, claves[2], caso.asu, caso.cue, null, true, 'caso');
      r := r || format(E'\nE%s %s PASÓ y debía rechazarse → FALLA', caso.id, caso.nombre);
    exception when sqlstate '22023' then n := n + 1;
              when others then r := r || format(E'\nE%s %s dio otro error (%s) → FALLA', caso.id, caso.nombre, sqlstate);
    end;
    execute 'reset role';
  end loop;
  r := r || format(E'\nE1 11 textos inválidos rechazados con 22023: %s de 11 → %s', n, case when n = 11 then 'ok' else 'FALLA' end);
  -- reglas de la plantilla de dos cuerpos (aviso_anulacion) y de un cuerpo
  execute 'set local role service_role';
  n := 0;
  begin perform public.correo_plantilla_guardar(u_sa, claves[2], v_asu, v_cue, 'sobra', true, 'x'); exception when sqlstate '22023' then n := n + 1; end;
  begin perform public.correo_plantilla_guardar(u_sa, claves[5], 'Actualización {{numero}}', E'{{saludo}} {{numero}}', null, true, 'x'); exception when sqlstate '22023' then n := n + 1; end;
  begin perform public.correo_plantilla_guardar(u_sa, claves[5], 'Actualización {{numero}}', E'{{saludo}} {{numero}}', E'{{saludo}} {{numero}} sin motivo', true, 'x'); exception when sqlstate '22023' then n := n + 1; end;
  begin perform public.correo_plantilla_guardar(u_sa, claves[2], v_asu, null, null, true, 'x'); exception when sqlstate '22023' then n := n + 1; end;
  begin perform public.correo_plantilla_guardar(u_sa, claves[2], null, null, null, true, 'x'); exception when sqlstate '22023' then n := n + 1; end;
  begin perform public.correo_plantilla_guardar(u_sa, 'otra_clave', v_asu, v_cue, null, true, 'x'); exception when sqlstate '22023' then n := n + 1; end;
  begin perform public.correo_plantilla_guardar(u_sa, claves[2], v_asu, v_cue, null, true, repeat('m', 501)); exception when sqlstate '22023' then n := n + 1; end;
  v := public.correo_plantilla_guardar(u_sa, claves[5], 'Actualización {{numero}}', E'{{saludo}} {{numero}}', E'{{saludo}} {{numero}}\n{{bloque_motivo}}', true, 'ok dos cuerpos');
  execute 'reset role';
  r := r || format(E'\nE2 un cuerpo con alt, dos cuerpos sin alt, alt sin motivo, asunto sin cuerpo, activar sin texto, clave ajena y motivo largo → 22023: %s de 7; y el de dos cuerpos válido guarda (cambiado=%s) → %s',
        n, v ->> 'cambiado', case when n = 7 and v ->> 'cambiado' = 'true' then 'ok' else 'FALLA' end);

  -- ── F. Sellado: clave y catálogo no cambian; no se borra ni se vacía (ni siendo postgres) ─────────────────────
  n := 0;
  begin update public.correo_plantillas set clave = 'enlace_firma_cadena' where clave = claves[3]; exception when others then if sqlstate in ('42501', '23505') then n := n + 1; end if; end;
  begin update public.correo_plantillas set variables = '{"permitidas":[],"obligatorias":{"asunto":[],"cuerpo":[],"cuerpo_alt":[]},"variantes":1}'::jsonb where clave = claves[3]; exception when sqlstate '42501' then n := n + 1; end;
  begin delete from public.correo_plantillas where clave = claves[3]; exception when sqlstate '42501' then n := n + 1; end;
  begin truncate public.correo_plantillas; exception when sqlstate '42501' then n := n + 1; end;
  r := r || format(E'\nF1 cambiar la clave, cambiar el catálogo, borrar y vaciar → rechazados: %s de 4 → %s', n, case when n = 4 then 'ok' else 'FALLA' end);
  begin insert into public.correo_plantillas (clave, variables) values ('inventada', '{"permitidas":[],"obligatorias":{},"variantes":1}'::jsonb); ok := false; exception when check_violation then ok := true; end;
  r := r || format(E'\nF2 no se puede crear una clave fuera de las 8 (CHECK) → %s', case when ok then 'ok' else 'FALLA' end);

  -- ── G. correos_enviados: plantilla + versión, nullable y acotadas ─────────────────────────────────────────────
  select id into cid from public.contratos limit 1;   -- cualquier contrato: las filas de prueba se deshacen
  n := 0;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via) values (cid, 'a@pruebas.test', 'sin plantilla', 'manual'); n := n + 1; exception when others then null; end;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via, plantilla, plantilla_version) values (cid, 'a@pruebas.test', 'con plantilla', 'firma', 'copia_firmada_portal', 'f:0a1b2c3d'); n := n + 1; exception when others then null; end;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via, plantilla, plantilla_version) values (cid, 'a@pruebas.test', 'editada', 'firma', 'copia_firmada_portal', 'v12'); n := n + 1; exception when others then null; end;
  r := r || format(E'\nG1 filas sin plantilla, con versión de fábrica y con versión editada se guardan: %s de 3 → %s', n, case when n = 3 then 'ok' else 'FALLA' end);
  n := 0;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via, plantilla, plantilla_version) values (cid, 'a@pruebas.test', 'x', 'firma', 'otra', 'v1'); exception when check_violation then n := n + 1; end;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via, plantilla, plantilla_version) values (cid, 'a@pruebas.test', 'x', 'firma', 'copia_firmada_portal', 'versión con el texto'); exception when check_violation then n := n + 1; end;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via, plantilla, plantilla_version) values (cid, 'a@pruebas.test', 'x', 'firma', null, 'v1'); exception when check_violation then n := n + 1; end;
  begin insert into public.correos_enviados (contrato_id, para, asunto, via, plantilla) values (cid, 'a@pruebas.test', 'x', 'firma', 'copia_firmada_portal'); exception when check_violation then n := n + 1; end;
  r := r || format(E'\nG2 clave ajena, versión con texto, versión sin plantilla y plantilla sin versión → CHECK: %s de 4 → %s', n, case when n = 4 then 'ok' else 'FALLA' end);
  begin insert into public.correos_enviados (para, asunto, via, plantilla, plantilla_version) values ('a@pruebas.test', 'sin ancla', 'firma', 'copia_firmada_portal', 'v1'); ok := false; exception when check_violation then ok := true; end;
  r := r || format(E'\nG3 el CHECK correos_con_ancla (contrato o factura) sigue vigente con plantilla → %s', case when ok then 'ok' else 'FALLA' end);

  -- ── H. Permisos de las auxiliares ─────────────────────────────────────────────────────────────────────────────
  n := 0;
  foreach rol in array array['anon', 'authenticated', 'service_role'] loop
    execute format('set local role %I', rol);
    begin perform public._correo_plantilla_error('x', 'cuerpo', '{}'::jsonb); exception when insufficient_privilege then n := n + 1; end;
    execute 'reset role';
  end loop;
  r := r || format(E'\nH1 _correo_plantilla_error no la ejecuta nadie fuera de la RPC (anon, authenticated, service_role): %s de 3 → %s', n, case when n = 3 then 'ok' else 'FALLA' end);

  raise exception 'FIN DE PRUEBAS — correo_plantillas (se deshace todo): %', r;
end $$;
