-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 4 (7-oct-2026): CRM de LEADS por empresa.
--   La empresa de un lead sale de su origen (leads.source -> crm_origen_empresa); la de una campana, de su etiqueta; la de un contrato, de su proyecto. Origen sin mapear = sin empresa = solo globales (nace cerrado).
--   * lead_a_mi_alcance: quien tiene empresas marcadas o es un rol de empresa solo alcanza los leads de sus empresas (antes, con «ranking» o «reparto» alcanzaba todos).
--   * Asignar/reasignar un lead, poner acciones, elegir closers del reparto y atribuir una venta: el destinatario debe ser de la empresa del lead/origen/contrato, y reasignar o apuntarse a uno mismo
--     exige ser administrador (o super) DE ESA EMPRESA, no global.
--   * Agregados (campanas de Meta, conjuntos, automatismos, serie semanal, resumen, reparto, ranking de closers, contratos por atribuir): solo la empresa que ve quien llama.
--   * crm_lead_ficha_crear / crm_lead_para_contrato no entregan una ficha de cliente que quien llama no ve; sellar un lead con un contrato exige ver el contrato.
--   crm_estado_* (columnas del tablero) es un catalogo compartido: sigue siendo solo de un super global (LAW-E7).
--   Los 34 usuarios de hoy no tienen restriccion de empresa: _ve_empresa() les da true y es_admin_de()/es_super_admin_de() equivalen a es_admin()/es_super_admin(): sin cambio.
--   Las puertas por herramienta (puede('leads'), puede('ranking'), puede('reparto')) se mantienen: el owner da a un rol de empresa las herramientas que necesite.
--   crm_contrato_closer_set cuelga del CRM (atribuir ventas) aunque alimente comisiones: se toca aqui solo la puerta por empresa y el destinatario; las comisiones son del bloque 4.
-- Cada cambio es una EDICION CON ASERCION del texto vivo (pg_temp.f2_edita).
-- destructivo-ok: create or replace de 17 funciones (solo anaden condiciones); sin tocar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
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

-- alcance de un lead: ademas de lo de siempre, que sea de una empresa que ve
select pg_temp.f2_edita('public.lead_a_mi_alcance(uuid)',
  $v$select case$v$,
  $n$select public._ve_empresa(public.empresa_de_lead(p_lead)) and case$n$);

-- asignar un lead
select pg_temp.f2_edita('public.crm_lead_asignar(uuid,text,text)',
  $v$and not public.es_admin() then$v$,
  $n$and not public.es_admin_de(public.empresa_de_lead(p_lead)) then$n$,
  $v$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')$v$,
  $n$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
         and public.usuario_en_empresa(u.email, public.empresa_de_lead(p_lead))$n$);

-- accion de seguimiento: el responsable debe ser de la empresa del lead
select pg_temp.f2_edita('public.crm_lead_accion_poner(uuid,text,date,text)',
  $v$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')$v$,
  $n$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
         and public.usuario_en_empresa(u.email, public.empresa_de_lead(p_lead))$n$);

-- sellar un lead con un contrato: el contrato debe estar a la vista de quien llama
select pg_temp.f2_edita('public.crm_lead_contrato_sellar(uuid,uuid)',
  $v$if not exists (select 1 from public.contratos c where c.id = p_contrato) then$v$,
  $n$if not exists (select 1 from public.contratos c where c.id = p_contrato)
     or (public.alcance_restringido() and not public.puede_ver_contrato(p_contrato)) then$n$);

-- no entregar la ficha de un cliente que quien llama no ve
select pg_temp.f2_edita('public.crm_lead_para_contrato(uuid)',
  $v$and lower(f.email) = v_email and f.tipo = 'persona'$v$,
  $n$and lower(f.email) = v_email and f.tipo = 'persona'
       and (not (select public.alcance_restringido()) or public.cliente_visible(f.propietario, f.id))$n$);
select pg_temp.f2_edita('public.crm_lead_ficha_crear(uuid)',
  $v$lower(c.email) = v_email and c.tipo = 'persona';$v$,
  $n$lower(c.email) = v_email and c.tipo = 'persona'
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id));$n$);

-- reparto de leads entre closers
select pg_temp.f2_edita('public.crm_reparto_closer_set(text,text,boolean)',
  $v$if not public.puede('reparto') then$v$,
  $n$if not public.puede('reparto') or not public._ve_empresa(public.empresa_de_origen(nullif(btrim(coalesce(p_source, '')), ''))) then$n$,
  $v$if v_mail = lower(v_quien) and not public.es_super_admin() then$v$,
  $n$if v_mail = lower(v_quien) and not public.es_super_admin_de(public.empresa_de_origen(v_src)) then$n$,
  $v$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')$v$,
  $n$and ('leads' = any(u.herramientas) or u.rol = 'super_admin')
      and public.usuario_en_empresa(u.email, public.empresa_de_origen(v_src))$n$);
select pg_temp.f2_edita('public.crm_reparto_origen_set(text,boolean,integer,integer)',
  $v$if not public.puede('reparto') then$v$,
  $n$if not public.puede('reparto') or not public._ve_empresa(public.empresa_de_origen(nullif(btrim(coalesce(p_source, '')), ''))) then$n$);
select pg_temp.f2_edita('public.crm_reparto_config()',
  $v$where public.puede('reparto')$v$,
  $n$where public.puede('reparto') and public._ve_empresa(public.empresa_de_origen(l.source))$n$);

-- campanas, conjuntos, automatismos y serie semanal: solo las de la empresa que ve
select pg_temp.f2_edita('public.crm_campanas()',
  $v$where public.puede('leads')$v$,
  $n$where public.puede('leads') and public._ve_empresa(public.empresa_de_origen(i.cliente))$n$);
select pg_temp.f2_edita('public.crm_campanas_conjuntos()',
  $v$where public.puede('leads')$v$,
  $n$where public.puede('leads') and public._ve_empresa(public.empresa_de_origen(c.cliente))$n$);
select pg_temp.f2_edita('public.crm_automatismos(integer)',
  $v$where public.puede('leads')$v$,
  $n$where public.puede('leads') and public._ve_empresa(public.empresa_de_origen(a.campana))$n$);
select pg_temp.f2_edita('public.crm_serie_semanal(integer)',
  $v$where date_trunc('week', l.created_at)::date = r.semana)$v$,
  $n$where date_trunc('week', l.created_at)::date = r.semana
               and public._ve_empresa(public.empresa_de_lead(l.id)))$n$,
  $v$where date_trunc('week', i.fecha)::date = r.semana$v$,
  $n$where date_trunc('week', i.fecha)::date = r.semana
               and public._ve_empresa(public.empresa_de_origen(i.cliente))$n$);

-- resumen de leads (lo usa tambien el resumen de la manana, que corre sin sesion: _ve_empresa da true)
select pg_temp.f2_edita('public._crm_leads_nucleo()',
  $v$left join public.lead_estado e on e.lead_id = l.id$v$,
  $n$left join public.lead_estado e on e.lead_id = l.id
   where public._ve_empresa(public.empresa_de_lead(l.id))$n$);

-- ranking de closers y contratos por atribuir: solo contratos de las empresas que ve
select pg_temp.f2_edita('public.crm_ranking_closers(boolean)',
  $v$where coalesce(c.bloqueado, false)$v$,
  $n$where coalesce(c.bloqueado, false)
       and public._ve_empresa(public.empresa_de_contrato(c.id))$n$);
select pg_temp.f2_edita('public.crm_contratos_para_atribuir(boolean)',
  $v$where public.puede('ranking')$v$,
  $n$where public.puede('ranking') and public._ve_empresa(public.empresa_de_contrato(c.id))$n$);

-- atribuir una venta a un closer
select pg_temp.f2_edita('public.crm_contrato_closer_set(uuid,text,text)',
  $v$if not (public.puede('ranking') or public.es_admin()) then$v$,
  $n$if not (public.puede('ranking') or public.es_admin_de(public.empresa_de_contrato(p_contrato))) then$n$,
  $v$lower(v_destino) = lower(v_quien) and not public.es_super_admin() then$v$,
  $n$lower(v_destino) = lower(v_quien) and not public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) then$n$,
  $v$if not public.es_super_admin() and ($v$,
  $n$if not public.es_super_admin_de(public.empresa_de_contrato(p_contrato)) and ($n$);
select pg_temp.f2_edita('public.crm_contrato_closer_set(uuid,text,text)',
  $v$if v_destino is not null and not public.crm_usuario_activo(v_destino) then$v$,
  $n$if v_destino is not null and not (public.crm_usuario_activo(v_destino)
        and public.usuario_en_empresa(v_destino, public.empresa_de_contrato(p_contrato))) then$n$);
