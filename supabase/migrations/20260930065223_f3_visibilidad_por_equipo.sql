-- destructivo-ok: solo drop+create de 10 policies de SELECT (se rehacen sobre la puerta); no borra datos. Orden del owner 30-sep-2026
-- =====================================================================================
-- APLICADA el 30-sep-2026 por orden explícita del owner («Aplica F3 ya», 30-sep-2026),
-- sabiendo que balianhills pasaba de 106 contratos a 8 si seguía de sales_manager (al aplicar
-- ya era project_manager, igual que juanjortega81: no pierden nada). Antes de aplicar se
-- comprobaron los 28 marcadores contra el catálogo vivo tras F2 y F4 (todos con el recuento
-- previsto: F4 no tocó ninguna pieza de F3) y se pasó contracts/sql/prueba_f3_visibilidad.sql
-- en sus tres tramos dentro de ROLLBACK, todo en verde.
-- =====================================================================================
--
-- F3 del encargo 20260930_lawang_equipos_venta_asistente · Puerta única de visibilidad.
--
-- POR QUÉ (D1, owner 30-sep-2026): el Sales Manager ve TODO lo de las ventas de SU EQUIPO,
-- en cualquier proyecto; la supervisión por proyecto (usuarios.proyectos_supervisados) queda
-- solo para project_manager. Hasta hoy el SM veía por proyecto: veía ventas de otros equipos
-- en «sus» proyectos y no veía las de su equipo fuera de ellos. Revisión previa #162
-- (Seguridad): una sola puerta, puede_ver_contrato(p_contrato), porque contrato_visible no
-- recibe el id del contrato (no puede mirar el equipo de la venta) y había funciones DEFINER
-- que decidían por su cuenta.
--
-- QUÉ HACE
--  1. Tres funciones nuevas:
--     · _venta_equipo(contrato): el equipo de la venta, leído SIEMPRE de la RAÍZ (los hijos
--       heredan). Congelada → contrato_closer.equipo_id; sin congelar → el equipo del closer
--       en coalesce(fecha_venta, raíz.created_at en Asia/Makassar), con el mismo join, filtro
--       y orden que _venta_congela_equipo tras F2 (requisito cazado en F2: motor y
--       visibilidad en el mismo ancla).
--     · _sm_ve_venta(contrato): quien consulta es el manager_email de ese equipo (activo).
--     · puede_ver_contrato(contrato) = admin OR (agente AND (autor OR PM del proyecto OR SM
--       de la venta)).
--  2. es_manager_de pasa a ser SOLO project_manager (y admin). puede_proyecto(text) igual.
--  3. _puede_ver_contrato delega; cliente_visible y documento_visible usan la puerta;
--     contrato_visible se queda sin llamadores y se le quita EXECUTE a los roles de sesión.
--  4. Se parchean 22 funciones DEFINER (28 parches) con reemplazo literal y recuento exacto (patrón de
--     Lawang: la definición viva NO es la del repo; si la marca no está exactamente las
--     veces previstas, la migración aborta sin tocar nada).
--  5. Se rehacen 10 policies de SELECT (9 en public + 1 en storage.objects) sobre la puerta.
--  6. Aserción estructural final: ningún cuerpo ni policy llama ya a contrato_visible, y
--     es_manager_de solo queda donde la decisión es «solo PM» (lista cerrada con recuento).
--
-- DECISIONES POR PIEZA (inventario de F1: supabase/vivo/20260930/INVENTARIO_es_manager_de.txt)
--  Policies → puerta: contratos, contrato_firmas, contrato_prorrogas, contrato_vencimientos,
--    contrato_eventos (conserva el filtro de eventos sensibles), contrato_anexo_paginas,
--    correos_enviados, bot_consultas, bot_respuestas_copiadas, storage «contratos-anexos».
--  Heredan por helper sin tocarse: clients y documents (cliente_visible), facturas y
--    recibi_aplicaciones (documento_visible), proyectos (proyecto_visible → solo PM).
--  Delegan en la puerta: _contrato_anexo_check, agente_escribe_fichero_contrato,
--    agente_reescribe_pdf_manual, agente_ve_contrato_pdf, contrato_firma_estado,
--    contrato_firmas_anula, contrato_poder_vincula, contrato_guarda (rama UPDATE y la
--    búsqueda del padre), vencimiento_ajusta_fecha, unidad_parte_cobrada_split,
--    comprador_contratos_resumen, contratos_del_mismo_comprador, contratos_cobrado_equipo,
--    guardar_recibi, solicitud_cambio_pide, solicitud_pago_guarda, factura_guarda (contrato).
--  SM de la venta (sin «autor» añadido, porque ya exigen rol sales_manager):
--    prorroga_reserva, libera_reserva (el SM libera las reservas de SU equipo).
--  Factura: _factura_puede_editar y factura_guarda (cheque tras UPDATE) = autor OR PM del
--    proyecto OR SM de la venta del contrato de la factura. Factura SIN contrato → solo PM
--    (antes el SM veía y editaba las facturas sueltas de «su» proyecto).
--  Solo PM (sin cambio de texto; cambian al cambiar es_manager_de): contrato_guarda rama
--    INSERT (el SM da de alta en los proyectos de su lista usuarios.proyectos, como cualquier
--    agente), parcela_traspaso_estado, proyecto_visible, unidad_visible, puede_proyecto_id,
--    puede_proyecto(text), y documento_visible para facturas sin contrato.
--  cliente_visible: la guarda es_gestor() pasa a «es gestor O manda un equipo activo», para
--    que un manager de equipo vea a los compradores de las ventas de su equipo sea cual sea su
--    rol; sigue cortando barato para el agente raso, que NO gana compradores (no se usa la
--    puerta completa, que incluye «autor del contrato»).
--  Avisos (_avisar_managers, no estaba en el inventario de F1): el SM recibe los avisos de una
--    venta (contrato firmado/bloqueado, solicitud de pago) solo si la venta es de su equipo;
--    los avisos sin contrato (estado de una unidad) siguen por los proyectos de su lista.
--  Fuera de F3 (no se tocan): funciones con es_manager_de_equipo y comisiones (F4).
-- =====================================================================================

-- ---------------------------------------------------------------- 1. helpers nuevos
create or replace function public._venta_equipo(p_contrato uuid)
 returns uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
           when k.equipo_congelado_en is not null then k.equipo_id
           else (select em.equipo_id
                   from public.equipo_miembros em
                   join public.equipos_venta ev on ev.id = em.equipo_id and ev.activo
                  where lower(em.closer_email) = lower(k.closer_email)
                    and em.desde <= coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date)
                    and (em.hasta is null
                         or em.hasta >= coalesce(k.fecha_venta, (rz.created_at at time zone 'Asia/Makassar')::date))
                  order by em.created_at desc
                  limit 1)
         end
    from public.contratos c
    join public.contratos rz on rz.id = coalesce(c.contrato_padre_id, c.id)
    join public.contrato_closer k on k.contrato_id = rz.id
   where c.id = p_contrato
$function$;

create or replace function public._sm_ve_venta(p_contrato uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select p_contrato is not null
     and coalesce((select auth.email()), '') <> ''
     and exists (select 1 from public.equipos_venta ev
                  where ev.activo
                    and ev.id = public._venta_equipo(p_contrato)
                    and lower(ev.manager_email) = lower((select auth.email())))
$function$;

-- es_manager_de: SOLO project_manager (D1). Antes también sales_manager.
create or replace function public.es_manager_de(p_proyecto_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and u.rol = 'project_manager'
         and p_proyecto_id = any (u.proyectos_supervisados))
  end
$function$;

-- La puerta. Se evalúa POR FILA en las policies: autor, PM y SM se miran aquí dentro (mismas
-- reglas que es_suyo, es_manager_de y _sm_ve_venta) en vez de llamar a esas funciones, porque
-- cada llamada a otra función DEFINER con search_path fijo cuesta ~0,1 ms por fila (medido el
-- 30-sep: llamándolas, la lista de contratos de un agente pasaba de 170 a 420 ms). _venta_equipo
-- solo se ejecuta si quien consulta manda algún equipo activo (el filtro barato va antes).
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
                  or exists (select 1 from public.equipos_venta ev
                              where ev.activo
                                and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))
                                and ev.id = public._venta_equipo(c.id))))))
$function$;

-- ---------------------------------------------------------------- 2. helpers que delegan
create or replace function public._puede_ver_contrato(p_contrato uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select public.puede_ver_contrato(p_contrato)
$function$;

create or replace function public.cliente_visible(p_propietario text, p_client_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or ((public.es_gestor()
           or exists (select 1 from public.equipos_venta ev
                       where ev.activo and lower(ev.manager_email) = lower(coalesce((select auth.email()), ''))))
          and exists (
            select 1
              from public.contrato_compradores cc
              join public.contratos c on c.id = cc.contrato_id
             where cc.client_id = p_client_id
               and (public.es_manager_de(c.proyecto_id) or public._sm_ve_venta(c.id))));
$function$;

create or replace function public.documento_visible(p_autor text, p_proyecto_id uuid, p_contrato_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- Por fila en facturas y recibís: autor y PM en línea (mismas reglas que es_suyo y
  -- es_manager_de) para no encadenar llamadas DEFINER; la venta, por la puerta.
  select public.es_admin()
      or coalesce(p_autor = (select auth.email()), false)
      or (p_proyecto_id is not null and exists (
            select 1 from public.usuarios u
             where u.user_id = (select auth.uid()) and u.activo
               and u.rol = 'project_manager'
               and p_proyecto_id = any (u.proyectos_supervisados)))
      or (p_contrato_id is not null and public.puede_ver_contrato(p_contrato_id))
$function$;

-- ---------------------------------------------------------------- 3. parches con recuento exacto
do $f3$
declare
  r record; v_oid regprocedure; v_def text; v_n int;
begin
  for r in
    select * from (values
      (1,  'public._contrato_anexo_check(uuid)',
           $q$public.contrato_visible(v_autor, v_proy)$q$,
           $q$public.puede_ver_contrato(p_contrato)$q$, 1),
      (2,  'public._contrato_anexo_check(uuid)',
           $q$(public.es_suyo(v_autor) or public.es_manager_de(v_proy))$q$,
           $q$public.puede_ver_contrato(p_contrato)$q$, 1),
      (3,  'public._factura_puede_editar(public.facturas)',
           $q$(public.es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id))$q$,
           $q$(public.es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id) or public._sm_ve_venta(f.contrato_id))$q$, 1),
      (4,  'public.agente_escribe_fichero_contrato(text)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (5,  'public.agente_reescribe_pdf_manual(text)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (6,  'public.agente_ve_contrato_pdf(text)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (7,  'public.contrato_firma_estado(uuid)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (8,  'public.contrato_firmas_anula(uuid,text,boolean,text)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (9,  'public.contrato_poder_vincula(uuid)',
           $q$public.contrato_visible(p.creado_por, p.proyecto_id)$q$,
           $q$public.puede_ver_contrato(p.id)$q$, 1),
      (10, 'public.contrato_poder_vincula(uuid)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (11, 'public.contrato_poder_vincula(uuid)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (12, 'public.contrato_guarda(uuid,jsonb)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 3),
      (13, 'public.contrato_guarda(uuid,jsonb)',
           $q$(public.es_suyo(v_old.creado_por) or public.es_manager_de(v_old.proyecto_id))$q$,
           $q$public.puede_ver_contrato(v_old.id)$q$, 1),
      (14, 'public.contrato_guarda(uuid,jsonb)',
           $q$(public.es_suyo(v_row.creado_por) or public.es_manager_de(v_row.proyecto_id))$q$,
           $q$public.puede_ver_contrato(v_row.id)$q$, 1),
      (15, 'public.vencimiento_ajusta_fecha(uuid,date)',
           $q$(public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (16, 'public.unidad_parte_cobrada_split(uuid)',
           $q$or public.es_manager_de(c0.proyecto_id)$q$,
           $q$or public.puede_ver_contrato(c0.id)$q$, 1),
      (17, 'public.comprador_contratos_resumen(uuid)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (18, 'public.contratos_del_mismo_comprador(uuid)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (19, 'public.contratos_cobrado_equipo()',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (20, 'public.guardar_recibi(uuid,jsonb,jsonb)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (21, 'public.solicitud_cambio_pide(text,uuid,jsonb,text,text)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (22, 'public.solicitud_pago_guarda(uuid,jsonb)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (23, 'public.factura_guarda(uuid,jsonb)',
           $q$public.contrato_visible(c.creado_por, c.proyecto_id)$q$,
           $q$public.puede_ver_contrato(c.id)$q$, 1),
      (24, 'public.factura_guarda(uuid,jsonb)',
           $q$(public.es_suyo(v_autor) or public.es_manager_de(v_proy))$q$,
           $q$(public.es_suyo(v_autor) or public.es_manager_de(v_proy) or public._sm_ve_venta(v_contrato))$q$, 1),
      (25, 'public.libera_reserva(uuid,uuid,text,text)',
           $q$not public.es_manager_de(u2.proyecto_id)$q$,
           $q$not public._sm_ve_venta(p_contrato_id)$q$, 1),
      (26, 'public.prorroga_reserva(uuid,integer,text,boolean)',
           $q$and public.es_manager_de(c.proyecto_id);$q$,
           $q$and public._sm_ve_venta(c.id);$q$, 1),
      (27, 'public.puede_proyecto(text)',
           $q$u.rol in ('sales_manager', 'project_manager') and p.id = any (u.proyectos_supervisados)$q$,
           $q$u.rol = 'project_manager' and p.id = any (u.proyectos_supervisados)$q$, 1),
      -- Avisos: el SM recibe los de una VENTA solo si es de su equipo (antes: todos los de los
      -- proyectos de su lista, con el nombre del comprador de ventas de otros equipos). Los
      -- avisos sin contrato (estado de una unidad) siguen por proyecto, como proyecto_visible.
      (28, 'public._avisar_managers(uuid,text,text,text,text,uuid)',
           $q$   where u.activo and u.rol in ('sales_manager','project_manager')
     and p_proyecto_id = any(u.proyectos);$q$,
           $q$   where u.activo
     and ((u.rol = 'project_manager' and p_proyecto_id = any(u.proyectos))
          or (u.rol = 'sales_manager' and p_contrato_id is null and p_proyecto_id = any(u.proyectos))
          or (u.rol = 'sales_manager' and p_contrato_id is not null
              and exists (select 1 from public.equipos_venta ev
                           where ev.activo and lower(ev.manager_email) = lower(u.email)
                             and ev.id = public._venta_equipo(p_contrato_id))));$q$, 1)
    ) t(orden, fn, viejo, nuevo, veces)
    order by orden
  loop
    v_oid := r.fn::regprocedure;
    v_def := replace(pg_get_functiondef(v_oid), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, r.viejo, ''))) / length(r.viejo);
    if v_n <> r.veces then
      raise exception 'F3 parche %: % tiene % apariciones de la marca (se esperaban %). La función cambió desde que se escribió esta migración: rehacer el parche sobre la versión viva.',
        r.orden, r.fn, v_n, r.veces;
    end if;
    execute replace(v_def, r.viejo, r.nuevo);
  end loop;
end
$f3$;

-- ---------------------------------------------------------------- 4. policies sobre la puerta
-- (drop + create de policies de SELECT: DDL que construye; el USING nuevo es el viejo con
--  la puerta en lugar de es_suyo/es_manager_de/contrato_visible.)
drop policy "agentes leen sus contratos" on public.contratos;
create policy "agentes leen sus contratos" on public.contratos
  for select to authenticated, lw_lector
  using (public.puede_ver_contrato(id));  -- la puerta ya exige es_agente()

drop policy "agentes leen firmas de sus contratos" on public.contrato_firmas;
create policy "agentes leen firmas de sus contratos" on public.contrato_firmas
  for select to authenticated, lw_lector
  using (public.es_agente() and public.puede_ver_contrato(contrato_id));

drop policy prorrogas_select on public.contrato_prorrogas;
create policy prorrogas_select on public.contrato_prorrogas
  for select to authenticated, lw_lector
  using (public.es_agente() and public.puede_ver_contrato(contrato_id));

drop policy vencimientos_select on public.contrato_vencimientos;
create policy vencimientos_select on public.contrato_vencimientos
  for select to authenticated, lw_lector
  using (public.es_agente() and public.puede_ver_contrato(contrato_id));

drop policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos;
create policy "super_admin ve todo, el resto solo eventos normales de sus cont" on public.contrato_eventos
  for select to authenticated, lw_lector
  using (public.es_super_admin()
         or (public.es_agente()
             and evento <> all (array['editado_estando_firmado', 'desbloqueado_estando_firmado',
                                      'factura_sin_bloquear', 'cobro_a_factura_huerfana',
                                      'cobro_a_otro_comprador', 'comprador_sin_ficha']::text[])
             and public.puede_ver_contrato(contrato_id)));

drop policy "anexos: el equipo lee las paginas de sus contratos" on public.contrato_anexo_paginas;
create policy "anexos: el equipo lee las paginas de sus contratos" on public.contrato_anexo_paginas
  for select to authenticated
  using (public.es_agente() and public.puede_ver_contrato(contrato_id));

drop policy "correos: leer lo propio o del contrato visible" on public.correos_enviados;
create policy "correos: leer lo propio o del contrato visible" on public.correos_enviados
  for select to authenticated, lw_lector
  using (public.es_agente()
         and (public.es_admin()
              or coalesce(enviado_por = (select auth.email()), false)
              or public.puede_ver_contrato(contrato_id)));

drop policy "bot_consultas: quien ve el contrato ve sus consultas" on public.bot_consultas;
create policy "bot_consultas: quien ve el contrato ve sus consultas" on public.bot_consultas
  for select to authenticated, lw_lector
  using (public.es_agente() and public.puede_ver_contrato(contrato_id));

drop policy "bot_respuestas_copiadas: quien ve la consulta ve la copia" on public.bot_respuestas_copiadas;
create policy "bot_respuestas_copiadas: quien ve la consulta ve la copia" on public.bot_respuestas_copiadas
  for select to authenticated, lw_lector
  using (exists (select 1 from public.bot_consultas q
                  where q.id = bot_respuestas_copiadas.consulta_id
                    and public.es_agente()
                    and public.puede_ver_contrato(q.contrato_id)));

drop policy "contratos-anexos: el equipo lee las paginas de sus contratos" on storage.objects;
create policy "contratos-anexos: el equipo lee las paginas de sus contratos" on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos-anexos'
         and public.es_agente()
         and exists (select 1 from public.contrato_anexo_paginas p
                      where p.path = objects.name
                        and public.puede_ver_contrato(p.contrato_id)));

-- ---------------------------------------------------------------- 5. permisos (nace cerrado)
-- La puerta la evalúan policies con el rol de sesión: authenticated y lw_lector.
revoke all on function public.puede_ver_contrato(uuid) from public, anon;
grant execute on function public.puede_ver_contrato(uuid) to authenticated, lw_lector, service_role;
-- Los dos internos solo los llaman funciones DEFINER (corren como su dueño): sin EXECUTE
-- para los roles de sesión (un SM no puede preguntar el equipo de un contrato cualquiera).
revoke all on function public._venta_equipo(uuid) from public, anon, authenticated;
revoke all on function public._sm_ve_venta(uuid) from public, anon, authenticated;
grant execute on function public._venta_equipo(uuid) to service_role;
grant execute on function public._sm_ve_venta(uuid) to service_role;
-- contrato_visible se queda sin llamadores (aserción de abajo): se cierra, no se borra
-- todavía por si algo fuera de la base la llamara (grep del repo 30-sep: ninguno).
revoke execute on function public.contrato_visible(text, uuid) from public, anon, authenticated, lw_lector;

-- ---------------------------------------------------------------- 6. aserción estructural
do $f3chk$
declare v_malo text;
begin
  -- 6a. nadie llama ya a contrato_visible (ni función ni policy)
  select string_agg(x, ', ') into v_malo from (
    select p.oid::regprocedure::text x from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
       and p.proname <> 'contrato_visible'
       and pg_get_functiondef(p.oid) ~ 'contrato_visible\('
    union all
    select schemaname || '.' || tablename || ' / ' || policyname from pg_policies
     where coalesce(qual, '') || coalesce(with_check, '') ~ 'contrato_visible\(') s;
  if v_malo is not null then
    raise exception 'F3: siguen llamando a contrato_visible: %', v_malo;
  end if;

  -- 6b. es_manager_de solo donde la decisión es «solo PM» (o PM como una rama más), con el
  --     recuento exacto: un llamador nuevo o no migrado hace fallar la migración.
  select string_agg(fn || '=' || n, ', ') into v_malo from (
    select p.proname fn,
           (select count(*) from regexp_matches(pg_get_functiondef(p.oid), 'es_manager_de\(', 'g')) n
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
       and pg_get_functiondef(p.oid) ~ 'es_manager_de\(') s
   where (fn, n) not in (
      ('es_manager_de', 1),            -- su propia definición
      ('contrato_visible', 1),         -- envoltorio viejo sin llamadores ni EXECUTE (6a lo vigila)
      ('proyecto_visible', 1),         -- solo PM
      ('cliente_visible', 1),          -- rama PM
      ('_factura_puede_editar', 1),    -- rama PM
      ('factura_guarda', 1),           -- rama PM (cheque tras UPDATE)
      ('contrato_guarda', 1),          -- rama INSERT: solo PM
      ('parcela_traspaso_estado', 1)); -- solo PM
  if v_malo is not null then
    raise exception 'F3: es_manager_de fuera de la lista «solo PM»: %', v_malo;
  end if;

  if exists (select 1 from pg_policies
              where coalesce(qual, '') || coalesce(with_check, '') ~ 'es_manager_de\(') then
    raise exception 'F3: queda una policy con es_manager_de';
  end if;
end
$f3chk$;
