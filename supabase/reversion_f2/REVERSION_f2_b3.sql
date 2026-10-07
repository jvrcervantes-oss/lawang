-- Reversion del BLOQUE 3 (Fase 2 empresas, 7-oct-2026): clientes/KYC, comunicados, CRM/leads, notificaciones.
-- Devuelve las funciones y policies a su texto de antes (cada edicion se deshace con la misma aserción: si el texto vivo ya no es el que esta migracion dejo, aborta en vez de pisar nada).
-- Valida mientras nadie tenga rol de empresa ni comunicados de empresa. Orden inverso al de aplicar. Las tablas/columnas nuevas se quitan al final (con guarda).
-- destructivo-ok: reversion de este mismo encargo; solo quita objetos creados por el (crm_origen_empresa, comunicados.empresa y funciones nuevas), con guarda si ya tienen datos
-- REVERTIR: es la reversion
begin;
create or replace function pg_temp.f2_edita(p_fn text, p_viejo text, p_nuevo text, p_viejo2 text default null, p_nuevo2 text default null, p_viejo3 text default null, p_nuevo3 text default null) returns void language plpgsql as $f$
declare d text; n int;
begin
  d := pg_get_functiondef(p_fn::regprocedure);
  n := (length(d) - length(replace(d, p_viejo, ''))) / length(p_viejo);
  if n <> 1 then raise exception 'f2_edita %: el fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo, 70); end if;
  d := replace(d, p_viejo, p_nuevo);
  if p_viejo2 is not null then
    n := (length(d) - length(replace(d, p_viejo2, ''))) / length(p_viejo2);
    if n <> 1 then raise exception 'f2_edita %: el 2o fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo2, 70); end if;
    d := replace(d, p_viejo2, p_nuevo2);
  end if;
  if p_viejo3 is not null then
    n := (length(d) - length(replace(d, p_viejo3, ''))) / length(p_viejo3);
    if n <> 1 then raise exception 'f2_edita %: el 3er fragmento aparece % veces (esperaba 1): %', p_fn, n, left(p_viejo3, 70); end if;
    d := replace(d, p_viejo3, p_nuevo3);
  end if;
  execute d;
end $f$;

-- (5) notificaciones: la policy de antes
alter policy "cada uno ve lo suyo, el admin todo" on public.notificaciones
  using ((public.es_admin() and ((tipo is distinct from 'solicitud_pago') or public.puede('comisiones')))
      or ((destinatario is not null) and (destinatario = (select auth.email()))));

-- (4) CRM / leads
select pg_temp.f2_edita('public.crm_contrato_closer_set(uuid,text,text)',
  $v$if v_destino is not null and not (public.crm_usuario_activo(v_destino)
        and public.usuario_en_empresa(v_destino, public.empresa_de_contrato(p_contrato))) then$v$,
  $n$if v_destino is not null and not public.crm_usuario_activo(v_destino) then$n$);
select pg_temp.f2_edita('public.crm_contrato_closer_set(uuid,text,text)',
  $v$if not (public.puede('ranking') or public.es_admin_de(public.empresa_de_contrato(p_contrato))) then$v$,
  $n$if not (public.puede('ranking') or public.es_admin()) then$n$,
  $v$lower(v_destino) = lower(v_quien) and not public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) then$v$,
  $n$lower(v_destino) = lower(v_quien) and not public.es_super_admin() then$n$,
  $v$if not public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) and ($v$,
  $n$if not public.es_super_admin() and ($n$);
select pg_temp.f2_edita('public.crm_contratos_para_atribuir(boolean)',
  $v$where public.puede('ranking') and public._ve_empresa(public.empresa_de_contrato(c.id))$v$,
  $n$where public.puede('ranking')$n$);
select pg_temp.f2_edita('public.crm_ranking_closers(boolean)',
  $v$where coalesce(c.bloqueado, false)
       and public._ve_empresa(public.empresa_de_contrato(c.id))$v$,
  $n$where coalesce(c.bloqueado, false)$n$);
select pg_temp.f2_edita('public._crm_leads_nucleo()',
  $v$left join public.lead_estado e on e.lead_id = l.id
   where public._ve_empresa(public.empresa_de_lead(l.id))$v$,
  $n$left join public.lead_estado e on e.lead_id = l.id$n$);
select pg_temp.f2_edita('public.crm_serie_semanal(integer)',
  $v$where date_trunc('week', l.created_at)::date = r.semana
               and public._ve_empresa(public.empresa_de_lead(l.id)))$v$,
  $n$where date_trunc('week', l.created_at)::date = r.semana)$n$,
  $v$where date_trunc('week', i.fecha)::date = r.semana
               and public._ve_empresa(public.empresa_de_origen(i.cliente))$v$,
  $n$where date_trunc('week', i.fecha)::date = r.semana$n$);
select pg_temp.f2_edita('public.crm_automatismos(integer)',
  $v$where public.puede('leads') and public._ve_empresa(public.empresa_de_origen(a.campana))$v$,
  $n$where public.puede('leads')$n$);
select pg_temp.f2_edita('public.crm_campanas_conjuntos()',
  $v$where public.puede('leads') and public._ve_empresa(public.empresa_de_origen(c.cliente))$v$,
  $n$where public.puede('leads')$n$);
select pg_temp.f2_edita('public.crm_campanas()',
  $v$where public.puede('leads') and public._ve_empresa(public.empresa_de_origen(i.cliente))$v$,
  $n$where public.puede('leads')$n$);
select pg_temp.f2_edita('public.crm_reparto_config()',
  $v$where public.puede('reparto') and public._ve_empresa(public.empresa_de_origen(l.source))$v$,
  $n$where public.puede('reparto')$n$);
select pg_temp.f2_edita('public.crm_reparto_origen_set(text,boolean,integer,integer)',
  $v$if not public.puede('reparto') or not public._ve_empresa(public.empresa_de_origen(nullif(btrim(coalesce(p_source, '')), ''))) then$v$,
  $n$if not public.puede('reparto') then$n$);
select pg_temp.f2_edita('public.crm_reparto_closer_set(text,text,boolean)',
  $v$if not public.puede('reparto') or not public._ve_empresa(public.empresa_de_origen(nullif(btrim(coalesce(p_source, '')), ''))) then$v$,
  $n$if not public.puede('reparto') then$n$,
  $v$if v_mail = lower(v_quien) and not public.es_super_admin_de(public.empresa_de_origen(v_src)) then$v$,
  $n$if v_mail = lower(v_quien) and not public.es_super_admin() then$n$,
  $v$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
      and public.usuario_en_empresa(u.email, public.empresa_de_origen(v_src))$v$,
  $n$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')$n$);
select pg_temp.f2_edita('public.crm_lead_ficha_crear(uuid)',
  $v$lower(c.email) = v_email and c.tipo = 'persona'
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id));$v$,
  $n$lower(c.email) = v_email and c.tipo = 'persona';$n$);
select pg_temp.f2_edita('public.crm_lead_para_contrato(uuid)',
  $v$and lower(f.email) = v_email and f.tipo = 'persona'
       and (not (select public.alcance_restringido()) or public.cliente_visible(f.propietario, f.id))$v$,
  $n$and lower(f.email) = v_email and f.tipo = 'persona'$n$);
select pg_temp.f2_edita('public.crm_lead_contrato_sellar(uuid,uuid)',
  $v$if not exists (select 1 from public.contratos c where c.id = p_contrato)
     or (public.alcance_restringido() and not public.puede_ver_contrato(p_contrato)) then$v$,
  $n$if not exists (select 1 from public.contratos c where c.id = p_contrato) then$n$);
select pg_temp.f2_edita('public.crm_lead_accion_poner(uuid,text,date,text)',
  $v$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
         and public.usuario_en_empresa(u.email, public.empresa_de_lead(p_lead))$v$,
  $n$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')$n$);
select pg_temp.f2_edita('public.crm_lead_asignar(uuid,text,text)',
  $v$and not public.es_admin_de(public.empresa_de_lead(p_lead)) then$v$,
  $n$and not public.es_admin() then$n$,
  $v$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
         and public.usuario_en_empresa(u.email, public.empresa_de_lead(p_lead))$v$,
  $n$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')$n$);
select pg_temp.f2_edita('public.lead_a_mi_alcance(uuid)',
  $v$select public._ve_empresa(public.empresa_de_lead(p_lead)) and case$v$,
  $n$select case$n$);

-- (3) comunicados
alter policy comunicados_admin_select on public.comunicados using (public.es_admin() and public.puede('comunicacion'));
alter policy comunicado_envios_admin_select on public.comunicado_envios using (public.es_admin() and public.puede('comunicacion'));
select pg_temp.f2_edita('public.comunicado_prueba(uuid)',
  $v$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin() and public.puede('comunicacion')) then$n$,
  $v$perform 1 from public.comunicados where id = p_comunicado
     and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa)));$v$,
  $n$perform 1 from public.comunicados where id = p_comunicado;$n$);
select pg_temp.f2_edita('public.comunicado_encolar(uuid,uuid[])',
  $v$where u.user_id = any (p_user_ids) and u.activo and u.email is not null
       and (public.es_admin()
            or public.usuario_en_empresa(u.email, (select cm.empresa from public.comunicados cm where cm.id = p_comunicado)))$v$,
  $n$where u.user_id = any (p_user_ids) and u.activo and u.email is not null$n$);
select pg_temp.f2_edita('public.comunicado_encolar(uuid,uuid[])',
  $v$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin() and public.puede('comunicacion')) then$n$,
  $v$perform 1 from public.comunicados where id = p_comunicado
     and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa))) for update;$v$,
  $n$perform 1 from public.comunicados where id = p_comunicado for update;$n$);
select pg_temp.f2_edita('public.comunicado_guarda(uuid,jsonb)',
  $v$values (v.asunto, v.encabezado, v.cuerpo, v.cta_url, v.cta_texto, (select auth.uid()), public._comunicado_empresa_alta(p_datos))$v$,
  $n$values (v.asunto, v.encabezado, v.cuerpo, v.cta_url, v.cta_texto, (select auth.uid()))$n$);
select pg_temp.f2_edita('public.comunicado_guarda(uuid,jsonb)',
  $v$select * into v from public.comunicados c where c.id = p_id
       and (public.es_admin() or (c.empresa is not null and public.es_admin_de(c.empresa))) for update;$v$,
  $n$select * into v from public.comunicados c where c.id = p_id for update;$n$,
  $v$insert into public.comunicados (asunto, encabezado, cuerpo, cta_url, cta_texto, creado_por, empresa)$v$,
  $n$insert into public.comunicados (asunto, encabezado, cuerpo, cta_url, cta_texto, creado_por)$n$);
select pg_temp.f2_edita('public.comunicado_guarda(uuid,jsonb)',
  $v$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin() and public.puede('comunicacion')) then$n$,
  $v$if k not in ('asunto', 'encabezado', 'cuerpo', 'cta_url', 'cta_texto', 'empresa') then$v$,
  $n$if k not in ('asunto', 'encabezado', 'cuerpo', 'cta_url', 'cta_texto') then$n$);
select pg_temp.f2_edita('public.comunicado_borra(uuid)',
  $v$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin() and public.puede('comunicacion')) then$n$,
  $v$delete from public.comunicados where id = p_id
     and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa)));$v$,
  $n$delete from public.comunicados where id = p_id;$n$);
select pg_temp.f2_edita('public.comunicado_datos(uuid)',
  $v$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin() and public.puede('comunicacion')) then$n$,
  $v$from public.comunicados c where c.id = p_id
       and (public.es_admin() or (c.empresa is not null and public.es_admin_de(c.empresa)));$v$,
  $n$from public.comunicados c where c.id = p_id;$n$);
select pg_temp.f2_edita('public.comunicacion_datos(integer,uuid)',
  $v$where x.activo = true and coalesce(x.email, '') <> ''
             and (public.es_admin() or public.comparte_empresa_con(x.email))$v$,
  $n$where x.activo = true and coalesce(x.email, '') <> ''$n$);
select pg_temp.f2_edita('public.comunicacion_datos(integer,uuid)',
  $v$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin() and public.puede('comunicacion')) then$n$,
  $v$where (public.es_admin() or (c.empresa is not null and public.es_admin_de(c.empresa)))
       and (p_despues is null or (c.actualizado_en, c.id) < (v_ts, p_despues))$v$,
  $n$where p_despues is null or (c.actualizado_en, c.id) < (v_ts, p_despues)$n$);
revoke execute on function public.es_admin_en_alguna_empresa(), public.comparte_empresa_con(text) from lw_lector;

-- (2) clientes: primero la rama en linea de cliente_visible vuelve a ser la llamada (migracion 6), luego se quita (migracion 2)
select pg_temp.f2_edita('public.comprador_buscar(text)',
  $v$where (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))
       and (c.full_name ilike '%'||btrim(p_q)||'%'$v$,
  $n$where c.full_name ilike '%'||btrim(p_q)||'%'$n$,
  $v$= lower(btrim(p_q)))$v$,
  $n$= lower(btrim(p_q))$n$);
select pg_temp.f2_edita('public.comprador_ficha(uuid)',
  $v$if not public.es_admin_en_alguna_empresa() then$v$,
  $n$if not public.es_admin() then$n$);
select pg_temp.f2_edita('public.comprador_ficha(uuid)',
  $v$if not public.es_agente() then return; end if;
  if (select public.alcance_restringido())
     and not exists (select 1 from public.clients c0 where c0.id = p_id and public.cliente_visible(c0.propietario, c0.id)) then
    return;
  end if;$v$,
  $n$if not public.es_agente() then return; end if;$n$);
select pg_temp.f2_edita('public.traspasar_cliente_con_documentos(uuid,text,text)',
  $v$if not public.es_super_admin() and not public.comparte_empresa_con(p_nuevo_propietario) then
    raise exception 'El nuevo propietario debe ser de tu empresa' using errcode = '23514';
  end if;

  v_quien := auth.email();$v$,
  $n$v_quien := auth.email();$n$);
select pg_temp.f2_edita('public.traspasar_cliente_con_documentos(uuid,text,text)',
  $v$if not public.super_admin_de_cliente(p_client_id, true) then$v$,
  $n$if not public.es_super_admin() then$n$);
select pg_temp.f2_edita('public.borrar_comprador(uuid)',
  $v$if not public.super_admin_de_cliente(p_client_id, true) then$v$,
  $n$if not public.es_super_admin() then$n$);
select pg_temp.f2_edita('public.documento_kyc_retira(uuid,uuid,text)',
  $v$if not public.super_admin_de_cliente(v_c.id, true) then$v$,
  $n$if not public.es_super_admin() then$n$);
select pg_temp.f2_edita('public.documento_kyc_retira(uuid,uuid,text)',
  $v$select * into v_c from public.clients c where c.id = v_d.client_id for update;
  if not public.admin_de_cliente(v_c.id, true) then
    raise exception 'Retirar documentos lo hace un administrador de las empresas de este comprador' using errcode = '42501';
  end if;$v$,
  $n$select * into v_c from public.clients c where c.id = v_d.client_id for update;$n$);
select pg_temp.f2_edita('public.documento_kyc_retira(uuid,uuid,text)',
  $v$if not public.es_admin_en_alguna_empresa() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;$v$,
  $n$if not public.es_admin() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;$n$);
select pg_temp.f2_edita('public.cliente_traspasa(uuid,text,text)',
  $v$'Esa ficha de comprador no existe' using errcode = '22023'; end if;
  if not public.admin_de_cliente(p_id, true) then
    raise exception 'Traspasar una ficha lo hace un administrador de las empresas de este comprador' using errcode = '42501';
  end if;
  if not public.es_admin() and not public.comparte_empresa_con(v_nuevo) then
    raise exception 'El nuevo propietario debe ser de tu empresa' using errcode = '22023';
  end if;$v$,
  $n$'Esa ficha de comprador no existe' using errcode = '22023'; end if;$n$);
select pg_temp.f2_edita('public.cliente_traspasa(uuid,text,text)',
  $v$if not public.es_admin_en_alguna_empresa() then raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501'; end if;$v$,
  $n$if not public.es_admin() then raise exception 'Traspasar una ficha lo hace un administrador' using errcode = '42501'; end if;$n$);
select pg_temp.f2_edita('public.cliente_guarda(uuid,jsonb)',
  $v$v_admin boolean := public.es_admin_en_alguna_empresa();$v$,
  $n$v_admin boolean := public.es_admin();$n$);
select pg_temp.f2_edita('public.cliente_visible(text,uuid)',
  $v$or (p_propietario is not null and exists (
            select 1 from public.usuarios me
             where me.user_id = (select auth.uid()) and me.activo and me.ambito = 'empresa'
               and me.rol in ('admin_empresa','super_admin_empresa')
               and exists (select 1 from public.usuarios pr
                            where lower(pr.email) = lower(p_propietario) and pr.activo and pr.empresas && me.empresas)))$v$,
  $n$or public._propietario_en_mis_empresas(p_propietario)$n$);
select pg_temp.f2_edita('public.cliente_visible(text,uuid)',
  $v$or coalesce(p_propietario = (select auth.email()), false)
      or public._propietario_en_mis_empresas(p_propietario)$v$,
  $n$or coalesce(p_propietario = (select auth.email()), false)$n$);

-- (1) objetos nuevos
do $$ begin
  if exists (select 1 from public.comunicados where empresa is not null) then
    raise exception 'Hay comunicados con empresa: no se puede quitar la columna sin decidir antes que se hace con ellos';
  end if;
end $$;
alter table public.comunicados drop column if exists empresa;
drop function if exists public.portal_puede_gestionar(uuid[]);
drop function if exists public.mis_contratos_admin_empresa();
drop function if exists public._comunicado_empresa_alta(jsonb);
drop function if exists public.super_admin_de_cliente(uuid, boolean);
drop function if exists public.admin_de_cliente(uuid, boolean);
drop function if exists public._cliente_en_empresas(uuid, boolean, text[]);
drop function if exists public.es_admin_en_alguna_empresa();
drop function if exists public._propietario_en_mis_empresas(text);
drop function if exists public.comparte_empresa_con(text);
drop function if exists public.usuario_en_empresa(text, text);
drop function if exists public.empresa_de_lead(uuid);
drop function if exists public.empresa_de_origen(text);
drop table if exists public.crm_origen_empresa;
commit;
