-- destructivo-ok: solo drop+create de 12 policies de SELECT (se rehacen con la misma semántica, paridad probada); no borra datos
-- =====================================================================================
-- F3 · AJUSTES (30-sep-2026), sobre la F3 ya aplicada (20260930065223_f3_visibilidad_por_equipo).
-- Pedidos por el revisor de código y por las consultas de Seguridad y Datos. Se escriben sobre
-- los cuerpos VIVOS: las funciones que se parchean llevan marca con recuento exacto (si la marca
-- no está exactamente las veces previstas, la migración aborta sin tocar nada).
--
-- A. _sm_ve_venta y la rama SM de puede_ver_contrato exigen además que quien consulta esté ACTIVO
--    en usuarios. Porqué: un SM dado de baja cuyo equipo siguiera activo seguía viendo las ventas
--    del equipo si entraba con un JWT de agente sin fila en usuarios (es_agente cae al JWT).
-- B. crm_contrato_closer_set: además de su puerta (ranking/admin) exige puede_ver_contrato. Porqué:
--    quien tiene el permiso «ranking» podía reatribuir el closer de una venta que no ve. Se
--    responde PT404 sin distinguir «no existe» de «no lo ves» (no filtra la existencia del id).
--    Lo que ya bloqueaba (devengos / reclamación → solo super_admin) sigue igual.
-- C. usuario_supervisa_proyecto: asignar un proyecto supervisado a quien no es project_manager
--    se rechaza (22023). Porqué: desde F3 la supervisión por proyecto solo cuenta para PM; asignarla
--    a un SM era un dato muerto que la pantalla enseñaba como si diera visibilidad (LAW-468).
--    Quitar sigue permitido para cualquier rol (limpieza).
-- D. Rendimiento: mis_contratos_visibles() y mis_proyectos_supervisados() devuelven, UNA vez por
--    consulta, los ids que el usuario ve. Las policies de SELECT de contratos, facturas,
--    recibi_aplicaciones y las 8 hijas que F3 rehizo (más storage «contratos-anexos») pasan de
--    llamar a puede_ver_contrato / documento_visible FILA A FILA (medido: facturas de un SM
--    630-750 ms) a comparar contra ese array envuelto en (select …), que el planificador evalúa una
--    sola vez (initPlan). Misma semántica que puede_ver_contrato — probada con diferencia simétrica
--    vacía en contracts/sql/prueba_f3_visibilidad.sql (parte 2). puede_ver_contrato(id) se queda
--    para las RPC de un solo contrato. clients y documents no se tocan (cliente_visible tiene otra
--    semántica: el agente raso no gana compradores por ser autor del contrato).
-- E (drop de contrato_visible y vaciado de supervisados de los SM) va en su propia migración,
--    20260930081234_f3_ajustes_destructivo.sql, para que A-D no dependan de su aprobación.
-- =====================================================================================

-- ---------------------------------------------------------------- guardia: cuerpos vivos
-- _sm_ve_venta y puede_ver_contrato se reescriben enteros: si alguien los cambió desde que se leyeron
-- (30-sep-2026, tras F3), la migración aborta en vez de pisar ese cambio.
do $g$
begin
  if md5(replace(pg_get_functiondef('public._sm_ve_venta(uuid)'::regprocedure), E'\r', '')) <> 'ad69a80e2e70d2294d2ffc13759b2b45'
     or md5(replace(pg_get_functiondef('public.puede_ver_contrato(uuid)'::regprocedure), E'\r', '')) <> 'f2281df8949e4cf7952f309051532a3d' then
    raise exception 'F3 ajustes: _sm_ve_venta o puede_ver_contrato cambiaron desde que se leyeron; rehacer sobre la versión viva';
  end if;
end
$g$;

-- ---------------------------------------------------------------- A. SM activo
create or replace function public._sm_ve_venta(p_contrato uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select p_contrato is not null
     and coalesce((select auth.email()), '') <> ''
     and exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo)
     and exists (select 1 from public.equipos_venta ev
                  where ev.activo
                    and ev.id = public._venta_equipo(p_contrato)
                    and lower(ev.manager_email) = lower((select auth.email())))
$function$;

-- La puerta de un solo contrato: igual que en F3, con la rama SM exigiendo usuario activo.
create or replace function public.puede_ver_contrato(p_contrato uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select p_contrato is not null and (
    public.es_admin()
    or (public.es_agente() and exists (
          select 1 from public.contratos c
           where c.id = p_contrato
             and (coalesce(c.creado_por = (select auth.email()), false)
                  or exists (select 1 from public.usuarios u
                              where u.user_id = (select auth.uid()) and u.activo
                                and u.rol = 'project_manager'
                                and c.proyecto_id = any (u.proyectos_supervisados))
                  or (exists (select 1 from public.usuarios ua
                               where ua.user_id = (select auth.uid()) and ua.activo)
                      and exists (select 1 from public.equipos_venta ev
                                   where ev.activo
                                     and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))
                                     and ev.id = public._venta_equipo(c.id)))))))
$function$;

-- ---------------------------------------------------------------- D. los arrays por consulta
-- Mismas tres ramas que puede_ver_contrato, en conjunto. _venta_equipo solo se evalúa si quien
-- consulta manda algún equipo activo y está activo (v_eq vacío corta antes). Admin → todos.
create or replace function public.mis_contratos_visibles()
 returns uuid[]
 language sql
 stable security definer
 set search_path to ''
as $function$
  with yo as (
    select (select auth.email()) email,
           (select auth.uid()) uid
  ), pm as (
    select coalesce((select u.proyectos_supervisados from public.usuarios u, yo
                      where u.user_id = yo.uid and u.activo and u.rol = 'project_manager'), '{}'::uuid[]) ps
  ), eq as (
    select coalesce(array_agg(ev.id), '{}'::uuid[]) ids
      from public.equipos_venta ev, yo
     where ev.activo
       and lower(ev.manager_email) = lower(coalesce(yo.email, ''))
       and exists (select 1 from public.usuarios ua where ua.user_id = yo.uid and ua.activo)
  )
  select case
    when public.es_admin() then (select coalesce(array_agg(c.id), '{}'::uuid[]) from public.contratos c)
    when not public.es_agente() then '{}'::uuid[]
    else (select coalesce(array_agg(c.id), '{}'::uuid[])
            from public.contratos c, yo, pm, eq
           where coalesce(c.creado_por = yo.email, false)
              or c.proyecto_id = any (pm.ps)
              or (cardinality(eq.ids) > 0 and public._venta_equipo(c.id) = any (eq.ids)))
  end
$function$;

-- Proyectos que supervisa quien consulta, solo si es project_manager activo (la rama PM de
-- documento_visible, para facturas sin contrato o de otro proyecto).
create or replace function public.mis_proyectos_supervisados()
 returns uuid[]
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce((select u.proyectos_supervisados from public.usuarios u
                    where u.user_id = (select auth.uid()) and u.activo and u.rol = 'project_manager'),
                  '{}'::uuid[])
$function$;

revoke all on function public.mis_contratos_visibles() from public, anon;
revoke all on function public.mis_proyectos_supervisados() from public, anon;
grant execute on function public.mis_contratos_visibles() to authenticated, lw_lector, service_role;
grant execute on function public.mis_proyectos_supervisados() to authenticated, lw_lector, service_role;

-- ---------------------------------------------------------------- B y C. parches con recuento exacto
do $aj$
declare r record; v_def text; v_n int;
begin
  for r in
    select * from (values
      (1, 'public.crm_contrato_closer_set(uuid,text,text)',
          $q$  if not exists (select 1 from public.contratos c where c.id = p_contrato) then$q$,
          $q$  if not public.puede_ver_contrato(p_contrato) then
    raise exception 'Ese contrato no existe o no esta a tu alcance' using errcode = 'PT404';
  end if;
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then$q$, 1),
      (2, 'public.usuario_supervisa_proyecto(uuid,uuid,boolean)',
          $q$  if p_asignar then
    update public.usuarios$q$,
          $q$  if p_asignar and v_rol <> 'project_manager' then
    raise exception 'Solo un project_manager supervisa proyectos: el sales_manager ve las ventas de su equipo' using errcode = '22023';
  end if;

  if p_asignar then
    update public.usuarios$q$, 1)
    ) t(orden, fn, viejo, nuevo, veces)
    order by orden
  loop
    v_def := replace(pg_get_functiondef(r.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, r.viejo, ''))) / length(r.viejo);
    if v_n <> r.veces then
      raise exception 'F3 ajustes parche %: % tiene % apariciones de la marca (se esperaban %). Rehacer sobre la versión viva.',
        r.orden, r.fn, v_n, r.veces;
    end if;
    execute replace(v_def, r.viejo, r.nuevo);
  end loop;
end
$aj$;

-- ---------------------------------------------------------------- D. policies (una evaluación por consulta)
-- Equivalencias con la F3: puede_ver_contrato(x) = x no nulo AND (admin OR (agente AND x ∈ mis)).
-- Por eso las hijas conservan «contrato_id is not null» (el admin NO veía filas sin contrato).
-- El «::uuid[]» tras (select …) no sobra: sin él, «= any (subconsulta)» compara el uuid con cada
-- FILA de la subconsulta (uuid = uuid[], error 42883); con él es un escalar evaluado una vez.
drop policy "agentes leen sus contratos" on public.contratos;
create policy "agentes leen sus contratos" on public.contratos
  for select to authenticated, lw_lector
  using ((select public.es_admin())
         or ((select public.es_agente())
             and (coalesce(creado_por = (select auth.email()), false)
                  or id = any ((select public.mis_contratos_visibles())::uuid[]))));

drop policy "agentes leen firmas de sus contratos" on public.contrato_firmas;
create policy "agentes leen firmas de sus contratos" on public.contrato_firmas
  for select to authenticated, lw_lector
  using ((select public.es_agente()) and contrato_id is not null
         and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy prorrogas_select on public.contrato_prorrogas;
create policy prorrogas_select on public.contrato_prorrogas
  for select to authenticated, lw_lector
  using ((select public.es_agente()) and contrato_id is not null
         and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy vencimientos_select on public.contrato_vencimientos;
create policy vencimientos_select on public.contrato_vencimientos
  for select to authenticated, lw_lector
  using ((select public.es_agente()) and contrato_id is not null
         and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos;
create policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos
  for select to authenticated, lw_lector
  using ((select public.es_super_admin())
         or ((select public.es_agente())
             and evento <> all (array['editado_estando_firmado', 'desbloqueado_estando_firmado',
                                      'factura_sin_bloquear', 'cobro_a_factura_huerfana',
                                      'cobro_a_otro_comprador', 'comprador_sin_ficha']::text[])
             and contrato_id is not null
             and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))));

drop policy "anexos: el equipo lee las paginas de sus contratos" on public.contrato_anexo_paginas;
create policy "anexos: el equipo lee las paginas de sus contratos" on public.contrato_anexo_paginas
  for select to authenticated
  using ((select public.es_agente()) and contrato_id is not null
         and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy "correos: leer lo propio o del contrato visible" on public.correos_enviados;
create policy "correos: leer lo propio o del contrato visible" on public.correos_enviados
  for select to authenticated, lw_lector
  using ((select public.es_agente())
         and ((select public.es_admin())
              or coalesce(enviado_por = (select auth.email()), false)
              or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy "bot_consultas: quien ve el contrato ve sus consultas" on public.bot_consultas;
create policy "bot_consultas: quien ve el contrato ve sus consultas" on public.bot_consultas
  for select to authenticated, lw_lector
  using ((select public.es_agente()) and contrato_id is not null
         and ((select public.es_admin()) or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy "bot_respuestas_copiadas: quien ve la consulta ve la copia" on public.bot_respuestas_copiadas;
create policy "bot_respuestas_copiadas: quien ve la consulta ve la copia" on public.bot_respuestas_copiadas
  for select to authenticated, lw_lector
  using ((select public.es_agente())
         and exists (select 1 from public.bot_consultas q
                      where q.id = bot_respuestas_copiadas.consulta_id
                        and q.contrato_id is not null
                        and ((select public.es_admin()) or q.contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))));

drop policy "contratos-anexos: el equipo lee las paginas de sus contratos" on storage.objects;
create policy "contratos-anexos: el equipo lee las paginas de sus contratos" on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos-anexos'
         and (select public.es_agente())
         and exists (select 1 from public.contrato_anexo_paginas p
                      where p.path = objects.name
                        and p.contrato_id is not null
                        and ((select public.es_admin()) or p.contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))));

-- facturas y recibís: documento_visible(autor, proyecto, contrato) = admin OR autor OR PM del
-- proyecto de la factura OR contrato visible.
drop policy "agentes leen sus facturas" on public.facturas;
create policy "agentes leen sus facturas" on public.facturas
  for select to authenticated, lw_lector
  using ((select public.es_agente())
         and ((select public.es_admin())
              or coalesce(creado_por = (select auth.email()), false)
              or proyecto_id = any ((select public.mis_proyectos_supervisados())::uuid[])
              or contrato_id = any ((select public.mis_contratos_visibles())::uuid[])));

drop policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones;
create policy "agentes leen aplicaciones de sus documentos" on public.recibi_aplicaciones
  for select to authenticated, lw_lector
  using ((select public.es_agente())
         and exists (select 1 from public.facturas d
                      where d.id = any (array[recibi_aplicaciones.recibi_id, recibi_aplicaciones.factura_id])
                        and ((select public.es_admin())
                             or coalesce(d.creado_por = (select auth.email()), false)
                             or d.proyecto_id = any ((select public.mis_proyectos_supervisados())::uuid[])
                             or d.contrato_id = any ((select public.mis_contratos_visibles())::uuid[]))));

-- ---------------------------------------------------------------- aserción final
do $chk$
begin
  if exists (select 1 from pg_policies
              where schemaname in ('public', 'storage')
                and tablename in ('contratos', 'facturas', 'recibi_aplicaciones', 'contrato_firmas',
                                  'contrato_prorrogas', 'contrato_vencimientos', 'contrato_eventos',
                                  'contrato_anexo_paginas', 'correos_enviados', 'bot_consultas',
                                  'bot_respuestas_copiadas', 'objects')
                and cmd = 'SELECT'
                and coalesce(qual, '') ~ '(puede_ver_contrato|documento_visible)\(') then
    raise exception 'F3 ajustes: queda una policy de SELECT evaluando la puerta fila a fila';
  end if;
end
$chk$;
