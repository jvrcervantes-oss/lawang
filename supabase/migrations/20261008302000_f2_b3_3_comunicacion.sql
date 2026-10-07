-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · BLOQUE 3 · migracion 3 (7-oct-2026): COMUNICADOS por empresa.
--   comunicados.empresa (nula = global, solo administradores globales). Un administrador de empresa con la herramienta «Comunicacion» ve, crea, edita, borra, prueba y envia SOLO los comunicados de sus empresas,
--   y solo a personas de la empresa del comunicado (los destinatarios se vuelven a filtrar en el servidor, no se fia de la lista que mande el navegador).
--   Destinatario valido de un comunicado de empresa X = usuario activo con X marcada, o sin restriccion alguna (los 34 de hoy trabajan para las dos).
--   Las puertas mantienen puede('comunicacion'): quien administra una empresa necesita ademas la herramienta, igual que un admin global.
--   Sin cambio para los administradores globales (la primera rama de cada condicion es la de siempre).
--   referidos_datos / solicitudes_alta_datos y sus policies NO se tocan: no tienen empresa ni proyecto de donde deducirla; quedan cerradas a los roles de empresa (LAW-E7).
-- Cada cambio es una EDICION CON ASERCION del texto vivo (pg_temp.f2_edita).
-- destructivo-ok: create or replace de 6 funciones y alter de 2 policies (solo anaden condiciones); sin tocar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b3.sql
create or replace function pg_temp.f2_edita(p_fn text, p_viejo text, p_nuevo text, p_viejo2 text default null, p_nuevo2 text default null) returns void language plpgsql as $f$
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
  execute d;
end $f$;

-- comunicacion_datos y comunicado_datos pertenecen a lw_lector (G1): lo que llaman directamente debe poder ejecutarlo lw_lector
grant execute on function public.es_admin_en_alguna_empresa(), public.comparte_empresa_con(text) to lw_lector;

-- comunicacion_datos: la pagina de comunicados y la lista de destinatarios, acotadas a la empresa
select pg_temp.f2_edita('public.comunicacion_datos(integer,uuid)',
  $v$if not (public.es_admin() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$n$,
  $v$where p_despues is null or (c.actualizado_en, c.id) < (v_ts, p_despues)$v$,
  $n$where (public.es_admin() or (c.empresa is not null and public.es_admin_de(c.empresa)))
       and (p_despues is null or (c.actualizado_en, c.id) < (v_ts, p_despues))$n$);
select pg_temp.f2_edita('public.comunicacion_datos(integer,uuid)',
  $v$where x.activo = true and coalesce(x.email, '') <> ''$v$,
  $n$where x.activo = true and coalesce(x.email, '') <> ''
             and (public.es_admin() or public.comparte_empresa_con(x.email))$n$);

-- comunicado_datos
select pg_temp.f2_edita('public.comunicado_datos(uuid)',
  $v$if not (public.es_admin() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$n$,
  $v$from public.comunicados c where c.id = p_id;$v$,
  $n$from public.comunicados c where c.id = p_id
       and (public.es_admin() or (c.empresa is not null and public.es_admin_de(c.empresa)));$n$);

-- comunicado_borra
select pg_temp.f2_edita('public.comunicado_borra(uuid)',
  $v$if not (public.es_admin() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$n$,
  $v$delete from public.comunicados where id = p_id;$v$,
  $n$delete from public.comunicados where id = p_id
     and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa)));$n$);

-- comunicado_guarda: la empresa se fija al crear (no se cambia despues); editar exige ser administrador de la empresa del comunicado
select pg_temp.f2_edita('public.comunicado_guarda(uuid,jsonb)',
  $v$if not (public.es_admin() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$n$,
  $v$if k not in ('asunto', 'encabezado', 'cuerpo', 'cta_url', 'cta_texto') then$v$,
  $n$if k not in ('asunto', 'encabezado', 'cuerpo', 'cta_url', 'cta_texto', 'empresa') then$n$);
select pg_temp.f2_edita('public.comunicado_guarda(uuid,jsonb)',
  $v$select * into v from public.comunicados c where c.id = p_id for update;$v$,
  $n$select * into v from public.comunicados c where c.id = p_id
       and (public.es_admin() or (c.empresa is not null and public.es_admin_de(c.empresa))) for update;$n$,
  $v$insert into public.comunicados (asunto, encabezado, cuerpo, cta_url, cta_texto, creado_por)$v$,
  $n$insert into public.comunicados (asunto, encabezado, cuerpo, cta_url, cta_texto, creado_por, empresa)$n$);
select pg_temp.f2_edita('public.comunicado_guarda(uuid,jsonb)',
  $v$values (v.asunto, v.encabezado, v.cuerpo, v.cta_url, v.cta_texto, (select auth.uid()))$v$,
  $n$values (v.asunto, v.encabezado, v.cuerpo, v.cta_url, v.cta_texto, (select auth.uid()), public._comunicado_empresa_alta(p_datos))$n$);

-- comunicado_encolar: solo comunicados de sus empresas y solo destinatarios de la empresa del comunicado
select pg_temp.f2_edita('public.comunicado_encolar(uuid,uuid[])',
  $v$if not (public.es_admin() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$n$,
  $v$perform 1 from public.comunicados where id = p_comunicado for update;$v$,
  $n$perform 1 from public.comunicados where id = p_comunicado
     and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa))) for update;$n$);
select pg_temp.f2_edita('public.comunicado_encolar(uuid,uuid[])',
  $v$where u.user_id = any (p_user_ids) and u.activo and u.email is not null$v$,
  $n$where u.user_id = any (p_user_ids) and u.activo and u.email is not null
       and (public.es_admin()
            or public.usuario_en_empresa(u.email, (select cm.empresa from public.comunicados cm where cm.id = p_comunicado)))$n$);

-- comunicado_prueba
select pg_temp.f2_edita('public.comunicado_prueba(uuid)',
  $v$if not (public.es_admin() and public.puede('comunicacion')) then$v$,
  $n$if not (public.es_admin_en_alguna_empresa() and public.puede('comunicacion')) then$n$,
  $v$perform 1 from public.comunicados where id = p_comunicado;$v$,
  $n$perform 1 from public.comunicados where id = p_comunicado
     and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa)));$n$);

-- policies de lectura (el rol authenticated no tiene SELECT directo hoy: se dejan coherentes por si se concede)
alter policy comunicados_admin_select on public.comunicados
  using (public.puede('comunicacion') and (public.es_admin() or (empresa is not null and public.es_admin_de(empresa))));
alter policy comunicado_envios_admin_select on public.comunicado_envios
  using (public.puede('comunicacion') and (public.es_admin()
         or exists (select 1 from public.comunicados c where c.id = comunicado_id and c.empresa is not null and public.es_admin_de(c.empresa))));
