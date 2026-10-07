-- Prueba del BLOQUE 11.2 (7-oct-2026, LAW-E55): comprador_ficha deja de dar pasaporte, nacimiento y direccion a un agente SIN alcance acotado sobre clientes que no ve.
-- Se pega DESPUES de las migraciones 20261008960000 y 20261008960100 (el caso del directorio mira la lista). Una sola peticion: A/B por cada usuario + casos + raise final que lo revierte todo.
-- A/B (la «foto de los usuarios»): para CADA usuario de public.usuarios, tal como esta, y 12 clientes fijos: lo que da la funcion NUEVA frente a la regla de ANTES
--   (es_agente y (sin alcance acotado o cliente_visible)). Debe cumplirse: nunca da mas que antes; quien tiene alcance acotado, un admin global o esta desactivado, EXACTAMENTE lo mismo;
--   y todo lo demas = cliente_visible o ver algun contrato de ese cliente (puede_ver_contrato). Los cambios solo pueden ser de agentes sin alcance acotado y no admin.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); sin drop de datos (comprador_ficha inserta un registro de acceso que el raise revierte)
create function pg_temp.t(p_uid uuid, p_email text, p_sql text, p_esp text, p_et text, p_rol text default 'authenticated') returns text language plpgsql as $f$
declare got text; r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_uid,'role',p_rol,'email',p_email)::text, true);
  execute format('set local role %I', p_rol);
  begin execute p_sql into r; got := coalesce(r,'null'); exception when others then got := sqlstate; end;
  reset role;
  return case when got = p_esp then 'OK   ' else 'FALLO' end || ' ' || p_et || ' [' || got || ' esp ' || p_esp || ']';
end $f$;
do $t$
declare
  jv uuid; ya uuid; cr uuid; ad4 uuid; ctl uuid; adm uuid;
  e_ya text; e_cr text; e_ad4 text; e_ctl text; e_adm text;
  cl uuid; cs uuid; c_oc uuid; c_ct uuid; c_cv uuid; total int;
  r text := ''; fallos int; u record; k record; jm jsonb; cid uuid; prop text;
  n_new int; n_old int; n_exp int; es_r boolean; es_a boolean; es_ag boolean;
  n_usu int := 0; n_par int := 0; n_cambian int := 0; n_mal int := 0; n_mas int := 0; n_raros int := 0;
  hs text := '{comisiones,leads,ranking,reparto,comunicacion,compradores,usuarios}';
begin
  select user_id into jv from public.usuarios where email='jvr.cervantes@gmail.com';
  select user_id, email into ya, e_ya from public.usuarios where email='yanayjefferson@gmail.com';
  select user_id, email into cr, e_cr from public.usuarios where email='cris.blueiestates@gmail.com';
  select user_id, email into ad4, e_ad4 from public.usuarios where email='adenovit.b@gmail.com';
  select user_id, email into ctl, e_ctl from public.usuarios
   where activo and ambito='global' and cardinality(coalesce(empresas,'{}'))=0 and rol not in ('admin','super_admin') and user_id not in (ya,cr,ad4) order by email limit 1;
  select user_id, email into adm, e_adm from public.usuarios where activo and rol='admin' and ambito='global' order by email limit 1;
  if adm is null then select user_id, email into adm, e_adm from public.usuarios where activo and rol='super_admin' and ambito='global' order by email limit 1; end if;
  select count(*) into total from public.clients;
  select jsonb_agg(jsonb_build_object('id', z.id, 'p', z.propietario) order by z.id) into jm from (select id, propietario from public.clients order by id limit 12) z;

  -- 1. A/B de TODOS los usuarios, antes de tocar nada (los tres que luego se convierten van tal cual estan)
  for u in select user_id, email from public.usuarios order by email loop
    n_usu := n_usu + 1;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    for k in select value v from jsonb_array_elements(jm) loop
      cid := (k.v->>'id')::uuid; prop := k.v->>'p';
      reset role;
      es_ag := public.es_agente(); es_r := public.alcance_restringido(); es_a := public.es_admin();
      n_old := case when es_ag and (not es_r or public.cliente_visible(prop, cid)) then 1 else 0 end;
      n_exp := case when es_ag and (public.cliente_visible(prop, cid)
                 or (not es_r and exists (select 1 from public.contrato_compradores cc where cc.client_id = cid and public.puede_ver_contrato(cc.contrato_id)))) then 1 else 0 end;
      set local role authenticated;
      select count(*) into n_new from public.comprador_ficha(cid);
      reset role;
      n_par := n_par + 1;
      if n_new > n_old then n_mas := n_mas + 1; end if;
      if n_new <> n_exp then n_mal := n_mal + 1; end if;
      if n_new <> n_old then
        n_cambian := n_cambian + 1;
        if es_r or es_a or not es_ag then n_raros := n_raros + 1; end if;
      end if;
    end loop;
  end loop;
  r := r || case when n_mas = 0 then 'OK   ' else 'FALLO' end || ' A/B: ningun usuario recibe MAS fichas que antes [' || n_mas || ' de ' || n_par || ' pares usuario-cliente, ' || n_usu || ' usuarios]' || E'\n';
  r := r || case when n_mal = 0 then 'OK   ' else 'FALLO' end || ' A/B: lo que se entrega = cliente_visible o ver un contrato de ese cliente [' || n_mal || ' discrepancias]' || E'\n';
  r := r || case when n_raros = 0 then 'OK   ' else 'FALLO' end || ' A/B: quien tiene alcance acotado, es admin o esta desactivado recibe EXACTAMENTE lo de antes [' || n_raros || ' cambios]' || E'\n';
  r := r || 'INFO  pares que cambian (agentes sin alcance acotado, no admin, sobre clientes que no ven): ' || n_cambian || E'\n';

  perform set_config('request.jwt.claims', json_build_object('sub',jv,'role','authenticated','email','jvr.cervantes@gmail.com')::text, true);
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ya;
  update public.usuarios set rol='super_admin_empresa', ambito='empresa', empresas='{sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=cr;
  update public.usuarios set rol='admin_empresa', ambito='empresa', empresas='{lawang,sandal_woods}', proyectos='{}', proyectos_supervisados='{}', herramientas=hs::text[], tipos_contrato='{}' where user_id=ad4;
  select c.id into cl from public.clients c
   where exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id)
     and not exists (select 1 from public.contrato_compradores cc join public.contratos k2 on k2.id=cc.contrato_id left join public.proyectos pr on pr.id=k2.proyecto_id where cc.client_id=c.id and pr.empresa is distinct from 'lawang')
     and c.passport_number is not null order by c.id limit 1;
  select c.id into cs from public.clients c
   where exists (select 1 from public.contrato_compradores cc where cc.client_id=c.id)
     and not exists (select 1 from public.contrato_compradores cc join public.contratos k2 on k2.id=cc.contrato_id left join public.proyectos pr on pr.id=k2.proyecto_id where cc.client_id=c.id and pr.empresa is distinct from 'sandal_woods')
     and c.passport_number is not null order by c.id limit 1;
  -- muestras para el agente de control (sin alcance acotado, no admin): uno que NO ve, uno que ve solo por un contrato, uno que ve por cliente_visible
  perform set_config('request.jwt.claims', json_build_object('sub',ctl,'role','authenticated','email',e_ctl)::text, true);
  for k in select id, propietario, passport_number from public.clients order by id loop
    exit when c_oc is not null and c_ct is not null and c_cv is not null;
    if public.cliente_visible(k.propietario, k.id) then
      if c_cv is null then c_cv := k.id; end if;
    elsif exists (select 1 from public.contrato_compradores cc where cc.client_id = k.id and public.puede_ver_contrato(cc.contrato_id)) then
      if c_ct is null then c_ct := k.id; end if;
    elsif c_oc is null and k.passport_number is not null then c_oc := k.id;
    end if;
  end loop;

  -- 2. casos
  if c_oc is not null then
    r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L)', c_oc), '0', 'LAW-E55: agente sin alcance acotado NO recibe la ficha entera de un cliente que no ve') || E'\n';
    r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L) where passport_number is not null or date_of_birth is not null or address is not null', c_oc), '0', '...ni pasaporte, ni nacimiento, ni direccion') || E'\n';
    r := r || pg_temp.t(adm, e_adm, format('select count(*)::text from public.comprador_ficha(%L)', c_oc), '1', 'admin global sigue abriendo esa misma ficha') || E'\n';
    r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.compradores_lista() where id = %L', c_oc), '1', 'la ficha BASICA de ese cliente sigue en el directorio del agente (bloque 11.1)') || E'\n';
  else r := r || 'FALLO sin muestra: no hay cliente oculto para el agente de control' || E'\n'; end if;
  if c_cv is not null then r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L)', c_cv), '1', 'agente sin alcance acotado SI abre la ficha de un cliente que ve (cliente_visible)') || E'\n';
  else r := r || 'INFO  sin muestra cliente_visible para el agente de control' || E'\n'; end if;
  if c_ct is not null then r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L)', c_ct), '1', 'agente sin alcance acotado SI abre la ficha de un cliente cuyo contrato ve') || E'\n';
  else r := r || 'INFO  sin muestra «ve el contrato» para el agente de control (no hay caso en los datos)' || E'\n'; end if;
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_ficha(%L)', cs), '0', 'ya (admin Lawang) NO abre la ficha entera del cliente de Sandal Woods (igual que antes)') || E'\n';
  r := r || pg_temp.t(ya, e_ya, format('select count(*)::text from public.comprador_ficha(%L)', cl), '1', 'ya abre la ficha entera de su cliente (igual que antes)') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select count(*)::text from public.comprador_ficha(%L)', cl), '0', 'cr (super Sandal Woods) NO abre la ficha entera del cliente de Lawang (igual que antes)') || E'\n';
  r := r || pg_temp.t(cr, e_cr, format('select count(*)::text from public.comprador_ficha(%L)', cs), '1', 'cr abre la ficha entera de su cliente (igual que antes)') || E'\n';
  r := r || pg_temp.t(ad4, e_ad4, format('select count(*)::text from public.comprador_ficha(%L)', cs), '1', 'ad4 (admin de las dos) abre la del cliente de Sandal Woods') || E'\n';
  r := r || pg_temp.t(adm, e_adm, format('select count(*)::text from public.comprador_ficha(%L)', cs), '1', 'admin global abre cualquiera') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, 'select count(*)::text from public.compradores_lista()', total::text, 'el directorio basico sigue entero para el agente de control') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'cuenta.portal.b112@example.com', format('select count(*)::text from public.comprador_ficha(%L)', cl), '0', 'una cuenta del portal (sin ficha de equipo) NO recibe la ficha') || E'\n';
  r := r || pg_temp.t(ctl, e_ctl, format('select count(*)::text from public.comprador_ficha(%L)', gen_random_uuid()), '0', 'un id que no existe: nada, sin error') || E'\n';
  r := r || pg_temp.t(gen_random_uuid(), 'anon@example.com', format('select count(*)::text from public.comprador_ficha(%L)', cl), '42501', 'anon no tiene EXECUTE', 'anon') || E'\n';
  fallos := (length(r) - length(replace(r, 'FALLO', ''))) / 5;
  raise exception E'\n%FALLOS=%', r, fallos;
end $t$;
