-- Prueba del paso 2A (Fase 2, 7-oct-2026): ¿ve cada rol de empresa EXACTAMENTE lo de sus empresas? Todo dentro de una transaccion que acaba en raise (rollback, sin rastro).
-- No crea usuarios: convierte 4 fichas de agente existentes (con los claims del propietario, como haria la pantalla) en
--   ae = admin_empresa/lawang · se = super_admin_empresa/sandal_woods · pm = project_manager GLOBAL restringido a {lawang} supervisando TODOS los proyectos
--   a2 = admin_empresa con las DOS empresas {lawang,sandal_woods}: ve las dos (32 proyectos) y nunca Karana (sin empresa)
-- y mide, con JWT simulado (email) + set local role authenticated, el recuento de lo que ve cada uno contra el esperado calculado como postgres.
-- Cada linea: OK/FALLO nombre actual esperado. Debe terminar con «FALLOS=0».
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); el unico «drop» no existe
do $t$
declare
  jv uuid; ya uuid; cr uuid; bl uuid; ad uuid;
  e_ya text; e_cr text; e_bl text; e_ad text;
  r text := ''; fallos int := 0; ids uuid[]; ems text[]; i int; emp text[] := array['lawang','sandal_woods','lawang','lawang,sandal_woods']; ad4 uuid; e_ad4 text;
  n bigint; x bigint; cmp uuid; kyc int;
  nuevo uuid := '8d8fde63-fb66-42d5-80a6-c383f293aab8';
  exp_p bigint; exp_u bigint; exp_c bigint; exp_f bigint; exp_v bigint; exp_cl bigint; exp_s bigint; exp_k bigint; exp_pdf bigint;
  tot_c bigint; tot_f bigint; tot_p bigint; tot_u bigint; tot_cl bigint;
begin
  select user_id, email into jv, e_ad from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into bl, e_bl from public.usuarios where email='blueicrm@gmail.com';
  select user_id into ad from public.usuarios where email='andreabenimeli@gmail.com';
  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas='{comisiones}', tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{comisiones}', tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='project_manager', ambito='global', empresas='{lawang}', herramientas='{}', tipos_contrato='{}',
         proyectos=(select array_agg(id) from public.proyectos), proyectos_supervisados=(select array_agg(id) from public.proyectos) where user_id=bl;
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas='{comisiones}', tipos_contrato='{}' where user_id=ad4;
  ids := array[ya, cr, bl, ad4]; ems := array[e_ya, e_cr, e_bl, e_ad4];
  -- cliente con contratos en las DOS empresas (si existe)
  select cc.client_id into cmp from public.contrato_compradores cc join public.contratos c on c.id=cc.contrato_id join public.proyectos p on p.id=c.proyecto_id
   group by cc.client_id having count(distinct p.empresa) filter (where p.empresa in ('lawang','sandal_woods')) = 2 limit 1;
  for i in 1..4 loop
    -- ESPERADOS, como postgres (sin RLS)
    select count(*) into exp_p from public.proyectos where empresa = any (string_to_array(emp[i], ','));
    select count(*) into exp_u from public.unidades un join public.proyectos p on p.id=un.proyecto_id where p.empresa = any (string_to_array(emp[i], ','));
    select count(*) into exp_c from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa = any (string_to_array(emp[i], ',')) and c.id <> nuevo;
    select count(*) into exp_f from public.facturas f join public.proyectos p on p.id=f.proyecto_id where p.empresa = any (string_to_array(emp[i], ','));
    select count(*) into exp_v from public.contrato_vencimientos v join public.contratos c on c.id=v.contrato_id join public.proyectos p on p.id=c.proyecto_id where p.empresa = any (string_to_array(emp[i], ',')) and c.id <> nuevo;
    select count(*) into exp_cl from public.clients cl where cl.propietario = ems[i]
        or exists (select 1 from public.contrato_compradores cc join public.contratos c on c.id=cc.contrato_id join public.proyectos p on p.id=c.proyecto_id where cc.client_id=cl.id and p.empresa = any (string_to_array(emp[i], ',')));
    select count(*) into exp_k from public.documents d where d.retirado_el is null and exists (select 1 from public.clients cl where cl.id=d.client_id and (cl.propietario = ems[i]
        or exists (select 1 from public.contrato_compradores cc join public.contratos c on c.id=cc.contrato_id join public.proyectos p on p.id=c.proyecto_id where cc.client_id=cl.id and p.empresa = any (string_to_array(emp[i], ',')))));
    select count(*) into exp_pdf from public.contratos c join public.proyectos p on p.id=c.proyecto_id where p.empresa = any (string_to_array(emp[i], ',')) and c.id <> nuevo and c.pdf_firmado_path is not null;
    if i <> 3 then
      select count(*) into exp_s from public.solicitudes_pago s where exists (select 1 from public.contratos c join public.proyectos p on p.id=c.proyecto_id where c.id=s.contrato_id and p.empresa = any (string_to_array(emp[i], ',')))
         or (s.creado_por = ids[i] and s.origen is distinct from 'comision_automatica') or s.beneficiario_email = ems[i];
    else exp_s := (select count(*) from public.solicitudes_pago s where (s.creado_por = ids[i] and s.origen is distinct from 'comision_automatica') or s.beneficiario_email = ems[i]); end if;
    -- REAL, con su JWT
    perform set_config('request.jwt.claims', json_build_object('sub',ids[i],'role','authenticated','email',ems[i])::text, true);
    set local role authenticated;
    select count(*) into n from public.proyectos; r := r || case when n=exp_p then 'OK   ' else 'FALLO' end || format(' %s proyectos %s/%s', i, n, exp_p) || E'\n'; if n<>exp_p then fallos:=fallos+1; end if;
    select count(*) into n from public.unidades; r := r || case when n=exp_u then 'OK   ' else 'FALLO' end || format(' %s unidades %s/%s', i, n, exp_u) || E'\n'; if n<>exp_u then fallos:=fallos+1; end if;
    select count(*) into n from public.contratos where id <> nuevo; r := r || case when n=exp_c then 'OK   ' else 'FALLO' end || format(' %s contratos %s/%s', i, n, exp_c) || E'\n'; if n<>exp_c then fallos:=fallos+1; end if;
    select count(*) into n from public.facturas; r := r || case when n=exp_f then 'OK   ' else 'FALLO' end || format(' %s facturas %s/%s', i, n, exp_f) || E'\n'; if n<>exp_f then fallos:=fallos+1; end if;
    select count(*) into n from public.contrato_vencimientos where contrato_id <> nuevo; r := r || case when n=exp_v then 'OK   ' else 'FALLO' end || format(' %s vencimientos %s/%s', i, n, exp_v) || E'\n'; if n<>exp_v then fallos:=fallos+1; end if;
    select count(*) into n from public.clients; r := r || case when n=exp_cl then 'OK   ' else 'FALLO' end || format(' %s clientes %s/%s', i, n, exp_cl) || E'\n'; if n<>exp_cl then fallos:=fallos+1; end if;
    select count(*) into n from public.solicitudes_pago; r := r || case when n=exp_s then 'OK   ' else 'FALLO' end || format(' %s solicitudes_pago %s/%s', i, n, exp_s) || E'\n'; if n<>exp_s then fallos:=fallos+1; end if;
    -- storage por sus funciones: KYC y PDF firmado
    select count(*) into n from public.documents d where d.retirado_el is null and public.agente_ve_kyc(d.storage_path); r := r || case when n=exp_k then 'OK   ' else 'FALLO' end || format(' %s kyc %s/%s', i, n, exp_k) || E'\n'; if n<>exp_k then fallos:=fallos+1; end if;
    select count(*) into n from public.contratos c where c.id <> nuevo and c.pdf_firmado_path is not null and public.agente_ve_contrato_pdf(c.pdf_firmado_path); r := r || case when n=exp_pdf then 'OK   ' else 'FALLO' end || format(' %s pdf_firmado %s/%s', i, n, exp_pdf) || E'\n'; if n<>exp_pdf then fallos:=fallos+1; end if;
    -- puertas
    r := r || case when not public.es_admin() and not public.es_super_admin() then 'OK   ' else 'FALLO' end || format(' %s no es admin global', i) || E'\n'; if public.es_admin() or public.es_super_admin() then fallos:=fallos+1; end if;
    if i < 3 then
      r := r || case when public.es_admin_de(emp[i]) and not public.es_admin_de(case when i=1 then 'sandal_woods' else 'lawang' end) then 'OK   ' else 'FALLO' end || format(' %s es_admin_de solo la suya', i) || E'\n';
      if not (public.es_admin_de(emp[i]) and not public.es_admin_de(case when i=1 then 'sandal_woods' else 'lawang' end)) then fallos:=fallos+1; end if;
    end if;
    -- proyecto sin empresa (Karana) y proyecto de la otra empresa: ni verlo ni por URL directa
    select count(*) into n from public.proyectos where empresa is null or not (empresa = any (string_to_array(emp[i], ','))); r := r || case when n=0 then 'OK   ' else 'FALLO' end || format(' %s proyectos ajenos/sin empresa visibles=%s', i, n) || E'\n'; if n<>0 then fallos:=fallos+1; end if;
    select count(*) into n from public.contratos c where c.proyecto_id is null or c.proyecto_id in (select id from public.proyectos where not coalesce(empresa = any (string_to_array(emp[i], ',')), false)); r := r || case when n=0 then 'OK   ' else 'FALLO' end || format(' %s contratos ajenos/sin proyecto visibles=%s', i, n) || E'\n'; if n<>0 then fallos:=fallos+1; end if;
    -- cliente compartido: ve su ficha pero solo los contratos de su empresa
    if cmp is not null and i <> 3 then
      select count(*) into n from public.clients where id = cmp; r := r || case when n=1 then 'OK   ' else 'FALLO' end || format(' %s ficha del cliente compartido visible=%s', i, n) || E'\n'; if n<>1 then fallos:=fallos+1; end if;
      select count(*) into n from public.contratos c join public.contrato_compradores cc on cc.contrato_id=c.id where cc.client_id = cmp and c.id <> nuevo;
      reset role;
      select count(*) into x from public.contratos c join public.contrato_compradores cc on cc.contrato_id=c.id join public.proyectos p on p.id=c.proyecto_id where cc.client_id = cmp and p.empresa = any (string_to_array(emp[i], ',')) and c.id <> nuevo;
      set local role authenticated;
      r := r || case when n=x then 'OK   ' else 'FALLO' end || format(' %s contratos del cliente compartido %s/%s', i, n, x) || E'\n'; if n<>x then fallos:=fallos+1; end if;
    end if;
    reset role;
  end loop;
  -- admin GLOBAL (Andrea) no cambia: ve todo
  perform set_config('request.jwt.claims', json_build_object('sub',ad,'role','authenticated','email','andreabenimeli@gmail.com')::text, true);
  select count(*) into tot_c from public.contratos where id <> nuevo; select count(*) into tot_f from public.facturas; select count(*) into tot_p from public.proyectos; select count(*) into tot_u from public.unidades; select count(*) into tot_cl from public.clients;
  set local role authenticated;
  select count(*) into n from public.contratos where id <> nuevo; r := r || case when n=tot_c then 'OK   ' else 'FALLO' end || format(' admin global contratos %s/%s', n, tot_c) || E'\n'; if n<>tot_c then fallos:=fallos+1; end if;
  select count(*) into n from public.facturas; r := r || case when n=tot_f then 'OK   ' else 'FALLO' end || format(' admin global facturas %s/%s', n, tot_f) || E'\n'; if n<>tot_f then fallos:=fallos+1; end if;
  select count(*) into n from public.proyectos; r := r || case when n=tot_p then 'OK   ' else 'FALLO' end || format(' admin global proyectos (incl. Karana) %s/%s', n, tot_p) || E'\n'; if n<>tot_p then fallos:=fallos+1; end if;
  select count(*) into n from public.unidades; r := r || case when n=tot_u then 'OK   ' else 'FALLO' end || format(' admin global unidades %s/%s', n, tot_u) || E'\n'; if n<>tot_u then fallos:=fallos+1; end if;
  select count(*) into n from public.clients; r := r || case when n=tot_cl then 'OK   ' else 'FALLO' end || format(' admin global clientes %s/%s', n, tot_cl) || E'\n'; if n<>tot_cl then fallos:=fallos+1; end if;
  reset role;
  raise exception E'F2_2A_EMPRESAS\ncliente_compartido=%\n%FALLOS=%', coalesce(cmp::text,'ninguno'), r, fallos;
end $t$;
