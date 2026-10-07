-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 2 (7-oct-2026): CLIENTES y KYC por empresa.
--   Un administrador de empresa (admin_empresa) hace en SU empresa lo que un administrador global: dar de alta y editar fichas, aprobar KYC, traspasar y retirar documentos;
--   un super_admin_empresa, ademas, lo que solo hace un super (retirar KYC de quien ya tiene contratos/pagos, borrar una ficha vacia, traspasar con sus contratos y facturas).
--   Regla: se toca la ficha segun sus CONTRATOS (cliente_visible, ya con empresa desde 2A); un cliente SIN contratos lo ve su propietario, un administrador de la empresa de ese propietario
--   y los globales. Lo que no se deshace (retirar KYC, traspasar, borrar) exige ademas que TODO el cliente (contratos y facturas) este en sus empresas: un cliente en las dos empresas lo toca solo un global.
--   Las 13 fichas sin contratos con propietario sin empresas marcadas siguen cerradas a los roles de empresa (evidencia: ningun propietario de ellas tiene empresa).
--   comprador_ficha y comprador_buscar no miraban la visibilidad (cualquier agente leia cualquier ficha por id): para quien tiene alcance restringido ahora si.
-- Cada cambio es una EDICION CON ASERCION del texto vivo de la funcion (pg_temp.f2_edita): si el fragmento no aparece exactamente una vez, la migracion aborta; nada se reescribe a ojo.
-- destructivo-ok: create or replace de 9 funciones (solo anade condiciones); sin tocar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
create or replace function pg_temp.f2_edita(p_fn text, p_viejo text, p_nuevo text) returns void language plpgsql as $f$
declare d text; n int;
begin
  d := pg_get_functiondef(p_fn::regprocedure);
  n := (length(d) - length(replace(d, p_viejo, ''))) / length(p_viejo);
  if n <> 1 then raise exception 'f2_edita %: el fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo, 70); end if;
  execute replace(d, p_viejo, p_nuevo);
end $f$;

-- cliente_visible: el propietario de la ficha es de alguna de mis empresas
select pg_temp.f2_edita('public.cliente_visible(text,uuid)',
  $v$or coalesce(p_propietario = (select auth.email()), false)$v$,
  $n$or coalesce(p_propietario = (select auth.email()), false)
      or public._propietario_en_mis_empresas(p_propietario)$n$);

-- cliente_guarda: la puerta es «administrador en alguna empresa»; la visibilidad (cliente_visible) ya se exige antes de editar
select pg_temp.f2_edita('public.cliente_guarda(uuid,jsonb)',
  $v$v_admin boolean := public.es_admin();$v$,
  $n$v_admin boolean := public.es_admin_en_alguna_empresa();$n$);

-- cliente_traspasa
select pg_temp.f2_edita('public.cliente_traspasa(uuid,text,text)',
  $v$if not public.es_admin() then raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501'; end if;$v$,
  $n$if not public.es_admin_en_alguna_empresa() then raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501'; end if;$n$);
select pg_temp.f2_edita('public.cliente_traspasa(uuid,text,text)',
  $v$'Esa ficha de comprador no existe' using errcode = '22023'; end if;$v$,
  $n$'Esa ficha de comprador no existe' using errcode = '22023'; end if;
  if not public.admin_de_cliente(p_id, true) then
    raise exception 'Traspasar una ficha lo hace un administrador de las empresas de este comprador' using errcode = '42501';
  end if;
  if not public.es_admin() and not public.comparte_empresa_con(v_nuevo) then
    raise exception 'El nuevo propietario debe ser de tu empresa' using errcode = '22023';
  end if;$n$);

-- documento_kyc_retira
select pg_temp.f2_edita('public.documento_kyc_retira(uuid,uuid,text)',
  $v$if not public.es_admin() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;$v$,
  $n$if not public.es_admin_en_alguna_empresa() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;$n$);
select pg_temp.f2_edita('public.documento_kyc_retira(uuid,uuid,text)',
  $v$select * into v_c from public.clients c where c.id = v_d.client_id for update;$v$,
  $n$select * into v_c from public.clients c where c.id = v_d.client_id for update;
  if not public.admin_de_cliente(v_c.id, true) then
    raise exception 'Retirar documentos lo hace un administrador de las empresas de este comprador' using errcode = '42501';
  end if;$n$);
select pg_temp.f2_edita('public.documento_kyc_retira(uuid,uuid,text)',
  $v$if not public.es_super_admin() then$v$,
  $n$if not public.super_admin_de_cliente(v_c.id, true) then$n$);

-- borrar_comprador (solo una ficha vacia, la puerta sigue siendo la de super)
select pg_temp.f2_edita('public.borrar_comprador(uuid)',
  $v$if not public.es_super_admin() then$v$,
  $n$if not public.super_admin_de_cliente(p_client_id, true) then$n$);

-- traspasar_cliente_con_documentos (reescribe creado_por de sus contratos y facturas: solo si todo es de mis empresas)
select pg_temp.f2_edita('public.traspasar_cliente_con_documentos(uuid,text,text)',
  $v$if not public.es_super_admin() then$v$,
  $n$if not public.super_admin_de_cliente(p_client_id, true) then$n$);
select pg_temp.f2_edita('public.traspasar_cliente_con_documentos(uuid,text,text)',
  $v$v_quien := auth.email();$v$,
  $n$if not public.es_super_admin() and not public.comparte_empresa_con(p_nuevo_propietario) then
    raise exception 'El nuevo propietario debe ser de tu empresa' using errcode = '23514';
  end if;

  v_quien := auth.email();$n$);

-- comprador_ficha: con alcance restringido, solo fichas que ve (antes leia cualquiera por id); el tope de fichas por minuto no aplica a un administrador de empresa
select pg_temp.f2_edita('public.comprador_ficha(uuid)',
  $v$if not public.es_agente() then return; end if;$v$,
  $n$if not public.es_agente() then return; end if;
  if (select public.alcance_restringido())
     and not exists (select 1 from public.clients c0 where c0.id = p_id and public.cliente_visible(c0.propietario, c0.id)) then
    return;
  end if;$n$);
select pg_temp.f2_edita('public.comprador_ficha(uuid)',
  $v$if not public.es_admin() then$v$,
  $n$if not public.es_admin_en_alguna_empresa() then$n$);

-- comprador_buscar (el aviso de duplicados): con alcance restringido, solo entre las fichas que ve
select pg_temp.f2_edita('public.comprador_buscar(text)',
  $v$where c.full_name ilike '%'||btrim(p_q)||'%'$v$,
  $n$where (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))
       and (c.full_name ilike '%'||btrim(p_q)||'%'$n$);
select pg_temp.f2_edita('public.comprador_buscar(text)',
  $v$= lower(btrim(p_q))$v$,
  $n$= lower(btrim(p_q)))$n$);
