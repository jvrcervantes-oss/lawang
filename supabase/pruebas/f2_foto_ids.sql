-- Foto REFORZADA de visibilidad (Fase 2 · 2A, 7-oct-2026): como f2_foto.sql pero, en vez de contar filas, saca el md5 de LOS IDS visibles
-- (proyectos, unidades, contratos, facturas, clients, contrato_vencimientos, solicitudes_pago) por usuario, con JWT simulado (email) + set local role authenticated.
-- Segundo bloque, como postgres con los mismos claims (sin RLS de por medio): el resultado de las FUNCIONES que alimentan storage y otras policies
-- (puede_ver_contrato, documento_visible, cliente_visible, proyecto_visible, puede_proyecto_id, puede_proyecto(nombre)) sobre TODAS las filas.
-- El storage no se fotografia directo: 34 usuarios x ~685 objetos exceden el tiempo del MCP, y agente_ve_kyc/agente_ve_contrato_pdf/agente_ve_justificante
-- delegan 1:1 en cliente_visible / puede_ver_contrato / documento_visible, que SI estan en el segundo bloque.
-- Termina en raise (sin rastro). El md5 debe ser identico ANTES y DESPUES de cada migracion del 2A (ANTES, 7-oct-2026: ver f2_foto_ids_previa.txt).
-- NOTA: produccion esta viva. El contrato PA00010 (8d8fde63..., creado a las 00:54 UTC del 7-oct, DESPUES de la foto previa) se excluye de contratos, vencimientos,
-- puede_ver_contrato y mis_contratos_visibles para que el md5 siga siendo comparable. Si aparecen mas filas nuevas, hay que excluirlas igual (o rehacer la foto previa).
-- destructivo-ok: solo lectura; termina en raise
do $t$
declare u record; out text := ''; out2 text := ''; o text; h text; t text; w text; nuevo uuid := '8d8fde63-fb66-42d5-80a6-c383f293aab8';
begin
  for u in select user_id, email from public.usuarios order by email loop
    o := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array array['proyectos','unidades','contratos','facturas','clients','contrato_vencimientos','solicitudes_pago'] loop
      w := case t when 'contratos' then format(' where id <> %L', nuevo) when 'contrato_vencimientos' then format(' where contrato_id <> %L', nuevo) else '' end;
      begin execute format('select md5(coalesce(string_agg(id::text, '','' order by id::text),'''')) from public.%I%s', t, w) into h; o := o||'|'||left(h,6);
      exception when others then o := o||'|ERR'||sqlstate; end;
    end loop;
    reset role;
    out := out || o || E'\n';
    -- bloque 2: funciones sobre todas las filas, como postgres con los claims del usuario
    o := u.email;
    select md5(coalesce(string_agg(id::text, ',' order by id::text) filter (where public.puede_ver_contrato(id)),'')) into h from public.contratos where id <> nuevo; o := o||'|pvc'||left(h,6);
    select md5(coalesce(string_agg(id::text, ',' order by id::text) filter (where public.documento_visible(creado_por, proyecto_id, contrato_id)),'')) into h from public.facturas; o := o||'|dv'||left(h,6);
    select md5(coalesce(string_agg(id::text, ',' order by id::text) filter (where public.cliente_visible(propietario, id)),'')) into h from public.clients; o := o||'|cv'||left(h,6);
    select md5(coalesce(string_agg(id::text, ',' order by id::text) filter (where public.proyecto_visible(id)),'')) into h from public.proyectos; o := o||'|pv'||left(h,6);
    select md5(coalesce(string_agg(id::text, ',' order by id::text) filter (where public.puede_proyecto_id(id)),'')) into h from public.proyectos; o := o||'|ppi'||left(h,6);
    select md5(coalesce(string_agg(id::text, ',' order by id::text) filter (where public.puede_proyecto(nombre)),'')) into h from public.proyectos; o := o||'|ppn'||left(h,6);
    select md5(coalesce(string_agg(x::text, ',' order by x::text),'')) into h from unnest(public.mis_contratos_visibles()) x where x <> nuevo; o := o||'|mcv'||left(h,6);
    select md5(coalesce(string_agg(x::text, ',' order by x::text),'')) into h from unnest(public.mis_proyectos_supervisados()) x; o := o||'|mps'||left(h,6);
    out2 := out2 || o || E'\n';
  end loop;
  raise exception E'FOTOIDS\nMD5_TABLAS=%\nMD5_FUNCIONES=%', md5(out), md5(out2);
end $t$;
