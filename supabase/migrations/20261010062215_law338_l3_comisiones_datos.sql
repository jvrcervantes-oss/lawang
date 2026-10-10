-- LAW-338 L3 (10-oct-2026): comisiones, equipos de venta, condiciones de comisión y gastos se leen por el SERVIDOR.
-- Encargo: encargos/20260927_lawang_law338_lecturas_bloques.md (L3) · pareja del maestro: erp/migraciones/
-- 20261008139650_b10a_l3_comisiones_datos.sql (mismos nombres, argumentos y forma del jsonb; FORMAS_DATOS).
-- Aditiva: solo create function + dueño + grants. NINGÚN revoke de tabla: el cierre va en supabase/por_aplicar/
-- hasta que producción sirva el front que llama a estas RPC (orden: publicar → curl → revoke, con OK del owner).
--
-- Reglas de la forma (LAW-338 §diseño, revisión previa #128):
--  · DEFINER con dueño lw_lector: dentro, la RLS se evalúa como lw_lector con las claims del usuario real, así que
--    cada RPC devuelve las MISMAS filas que la lectura directa de hoy. La regla vive en la policy, no aquí.
--  · search_path '', stable, sin auth.* en el cuerpo (public.uid_sesion()), 1.ª línea: sin sesión → 42501.
--  · Columnas explícitas = las que pide hoy cada pantalla, ni una más. Tope en servidor + `recortado` (fila de más).
--  · Llamadores con nombre (§1.ter, seguridad_2026.md): todos del navegador salvo gasto_estado_datos (edge
--    `ficheros`, con el JWT del usuario). Ninguna edge con service_role, cron ni PHP: fuera public/anon/service_role.
--
-- Datos medidos el 10-oct en la base viva: 14 devengadas, 8 equipos, 22 miembros, 21 condiciones, 20 tramos,
-- 0 gastos, 15 categorías. Todas las escrituras de estas tablas van por funciones DEFINER de postgres
-- (authenticated solo tiene SELECT), así que cerrar la lectura no rompe ninguna escritura.

-- ── 1. Equipos de venta y sus miembros (catálogo corto que usan seis pantallas) ─────────────────────────────────
-- Llamadores: v4 equipos de venta, condiciones, comisiones (reparto), editor de condiciones (equipos del manager y
-- alta), comisiones-equipo.js (ventas del equipo) y contracts/assets/asistente-contrato.js (equipo del vendedor).
-- Cada pantalla filtra/ordena lo suyo (activo, empresa…): aquí va la unión de columnas que piden.
create or replace function public.equipos_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_eq jsonb; v_neq int; v_mi jsonb; v_nmi int;
begin
  if public.uid_sesion() is null then
    raise exception 'equipos_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'manager_email', e.manager_email,
                                               'activo', e.activo, 'created_at', e.created_at,
                                               'closers_ven_comision', e.closers_ven_comision, 'empresa', e.empresa)
                            order by e.rn) filter (where e.rn <= 1000), '[]'::jsonb), count(*)::int
    into v_eq, v_neq
    from (select x.id, x.nombre, x.manager_email, x.activo, x.created_at, x.closers_ven_comision, x.empresa,
                 row_number() over (order by x.nombre, x.id) as rn
            from public.equipos_venta x order by x.nombre, x.id limit 1001) e;
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'equipo_id', m.equipo_id, 'closer_email', m.closer_email,
                                               'desde', m.desde, 'hasta', m.hasta, 'rol', m.rol, 'rol_nombre', m.rol_nombre)
                            order by m.rn) filter (where m.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_mi, v_nmi
    from (select x.id, x.equipo_id, x.closer_email, x.desde, x.hasta, x.rol, x.rol_nombre,
                 row_number() over (order by x.desde desc, x.id) as rn
            from public.equipo_miembros x order by x.desde desc, x.id limit 5001) m;
  return jsonb_build_object('equipos', v_eq, 'miembros', v_mi,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'equipos' k where v_neq > 1000
                                            union all select 'miembros' where v_nmi > 5000) r));
end $$;

-- ── 2. Condiciones de comisión con sus tramos (pantalla /v4/condiciones/ y su editor) ────────────────────────────
create or replace function public.condiciones_comision_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_co jsonb; v_nco int; v_tr jsonb; v_ntr int;
begin
  if public.uid_sesion() is null then
    raise exception 'condiciones_comision_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'equipo_id', c.equipo_id, 'proyecto_id', c.proyecto_id,
                                               'nivel', c.nivel, 'closer_email', c.closer_email,
                                               'pct_comision', c.pct_comision, 'base_calculo', c.base_calculo,
                                               'importe_fijo', c.importe_fijo, 'activo', c.activo,
                                               'vigente_desde', c.vigente_desde, 'vigente_hasta', c.vigente_hasta,
                                               'created_at', c.created_at, 'sustituye_a', c.sustituye_a,
                                               'empresa', c.empresa)
                            order by c.rn) filter (where c.rn <= 2000), '[]'::jsonb), count(*)::int
    into v_co, v_nco
    from (select x.id, x.equipo_id, x.proyecto_id, x.nivel, x.closer_email, x.pct_comision, x.base_calculo,
                 x.importe_fijo, x.activo, x.vigente_desde, x.vigente_hasta, x.created_at, x.sustituye_a, x.empresa,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.condiciones_comision x order by x.created_at desc, x.id limit 2001) c;
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'condicion_id', t.condicion_id, 'orden', t.orden,
                                               'disparador_tipo', t.disparador_tipo, 'umbral', t.umbral,
                                               'pct_tramo', t.pct_tramo)
                            order by t.rn) filter (where t.rn <= 10000), '[]'::jsonb), count(*)::int
    into v_tr, v_ntr
    from (select x.id, x.condicion_id, x.orden, x.disparador_tipo, x.umbral, x.pct_tramo,
                 row_number() over (order by x.orden, x.id) as rn
            from public.condicion_tramos x order by x.orden, x.id limit 10001) t;
  return jsonb_build_object('condiciones', v_co, 'tramos', v_tr,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'condiciones' k where v_nco > 2000
                                            union all select 'tramos' where v_ntr > 10000) r));
end $$;

-- ── 3. Reparto de equipo (/v4/comisiones/ y /v4/reparto/): lo que el manager paga a closer/setter/team lead, y las
--       diferencias por cambio de contrato con el devengo del que salen. Las diferencias solo con las 7 columnas que
--       pide la pantalla (su SELECT es por columnas desde LAW-465: nada de origen/provocado_por/resuelto_por).
create or replace function public.comisiones_reparto_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_de jsonb; v_nde int; v_di jsonb; v_ndi int;
begin
  if public.uid_sesion() is null then
    raise exception 'comisiones_reparto_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'contrato_raiz_id', d.contrato_raiz_id,
                                               'beneficiario_email', d.beneficiario_email, 'nivel', d.nivel,
                                               'importe', d.importe, 'importe_ajustado', d.importe_ajustado,
                                               'ajuste_motivo', d.ajuste_motivo, 'anulado_motivo', d.anulado_motivo,
                                               'moneda', d.moneda, 'estado', d.estado, 'disparado_en', d.disparado_en,
                                               'pagado_por', d.pagado_por, 'pagado_en', d.pagado_en,
                                               'disparado_por_snapshot', d.disparado_por_snapshot)
                            order by d.rn) filter (where d.rn <= 20000), '[]'::jsonb), count(*)::int
    into v_de, v_nde
    from (select x.id, x.contrato_raiz_id, x.beneficiario_email, x.nivel, x.importe, x.importe_ajustado, x.ajuste_motivo,
                 x.anulado_motivo, x.moneda, x.estado, x.disparado_en, x.pagado_por, x.pagado_en,
                 x.disparado_por_snapshot,
                 row_number() over (order by x.disparado_en desc, x.id) as rn
            from public.comisiones_devengadas x
           where x.nivel in ('closer', 'setter', 'team_lead')
           order by x.disparado_en desc, x.id limit 20001) d;
  -- el devengo de cada diferencia se lee con la RLS de comisiones_devengadas (como el embebido de PostgREST):
  -- si el lector no lo ve, sale null.
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'numero', f.numero, 'devengo_id', f.devengo_id,
                                               'importe', f.importe, 'estado', f.estado, 'motivo', f.motivo,
                                               'created_at', f.created_at,
                                               'devengo', case when f.d_id is not null then
                                                 jsonb_build_object('nivel', f.d_nivel,
                                                                    'beneficiario_email', f.d_benef,
                                                                    'contrato_raiz_id', f.d_raiz,
                                                                    'moneda', f.d_moneda) end)
                            order by f.rn) filter (where f.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_di, v_ndi
    from (select x.id, x.numero, x.devengo_id, x.importe, x.estado, x.motivo, x.created_at,
                 d.id as d_id, d.nivel as d_nivel, d.beneficiario_email as d_benef, d.contrato_raiz_id as d_raiz,
                 d.moneda as d_moneda,
                 row_number() over (order by x.created_at desc, x.id) as rn
            from public.comisiones_diferencias x
            left join public.comisiones_devengadas d on d.id = x.devengo_id
           order by x.created_at desc, x.id limit 5001) f;
  return jsonb_build_object('devengadas', v_de, 'diferencias', v_di,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'devengadas' k where v_nde > 20000
                                            union all select 'diferencias' where v_ndi > 5000) r));
end $$;

-- ── 4. La comisión de Lawang (manager/estándar/propia) que nació con una solicitud de pago: ficha de la solicitud
--       en /v4/comisiones/. null si no hay exactamente una visible (lo que antes daba maybeSingle: 0 filas o error).
create or replace function public.comision_de_solicitud_datos(p_solicitud uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lista jsonb; v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'comision_de_solicitud_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('estado', x.estado, 'pagado_en', x.pagado_en, 'importe', x.importe,
                                               'importe_ajustado', x.importe_ajustado, 'moneda', x.moneda)), '[]'::jsonb),
         count(*)::int
    into v_lista, v_n
    from (select d.estado, d.pagado_en, d.importe, d.importe_ajustado, d.moneda
            from public.comisiones_devengadas d
           where d.solicitud_id = p_solicitud and d.nivel in ('manager', 'estandar', 'propia')
           limit 2) x;
  return jsonb_build_object('comision', case when v_n = 1 then v_lista -> 0 end);
end $$;

-- ── 5. Comisiones de una operación que se va a borrar (diálogo «Borrar la operación» de /v4/operaciones/): cuántas
--       se purgarían y cuántas ya están pagadas. Tope de 200 contratos por llamada (una operación tiene 1-5).
create or replace function public.operacion_comisiones_datos(p_contratos uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lista jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'operacion_comisiones_datos: sin sesión' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_contratos), 0) > 200 then
    raise exception 'operacion_comisiones_datos: como mucho 200 contratos' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'estado', d.estado, 'solicitud_id', d.solicitud_id)
                            order by d.id), '[]'::jsonb)
    into v_lista
    from (select x.id, x.estado, x.solicitud_id from public.comisiones_devengadas x
           where x.contrato_raiz_id = any(coalesce(p_contratos, '{}'::uuid[])) limit 2000) d;
  return jsonb_build_object('comisiones', v_lista);
end $$;

-- ── 6. ¿Cuántas comisiones citan esta condición? (editor de condiciones, antes de borrar/editar). Mismo recuento que
--       la lectura directa de hoy (las que la RLS deja ver); quien decide de verdad es el trigger de la base.
create or replace function public.condicion_usos_datos(p_condicion uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'condicion_usos_datos: sin sesión' using errcode = '42501';
  end if;
  select count(*)::int into v_n from public.comisiones_devengadas d where d.condicion_id = p_condicion;
  return jsonb_build_object('devengadas', v_n);
end $$;

-- ── 7. Panel de finanzas (/v4/finanzas/, panel-finanzas.js): las dos fuentes de L3. Cada una solo si la pantalla
--       la pide (la decide su casilla: comisiones_reparto / gastos); si no, null («sin permiso», nunca «0 €»).
--       El resto de fuentes del panel (contratos, facturas, unidades…) siguen por su camino hasta L6/L7.
create or replace function public.finanzas_panel_datos(p_comisiones boolean, p_gastos boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_co jsonb; v_nco int; v_ga jsonb; v_nga int;
begin
  if public.uid_sesion() is null then
    raise exception 'finanzas_panel_datos: sin sesión' using errcode = '42501';
  end if;
  if coalesce(p_comisiones, false) then
    select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'estado', d.estado, 'importe', d.importe,
                                                 'importe_ajustado', d.importe_ajustado, 'moneda', d.moneda,
                                                 'solicitud_id', d.solicitud_id, 'pagado_en', d.pagado_en,
                                                 'anulado_en', d.anulado_en, 'contrato_raiz_id', d.contrato_raiz_id)
                              order by d.id) filter (where d.rn <= 20000), '[]'::jsonb), count(*)::int
      into v_co, v_nco
      from (select x.id, x.estado, x.importe, x.importe_ajustado, x.moneda, x.solicitud_id, x.pagado_en, x.anulado_en,
                   x.contrato_raiz_id, row_number() over (order by x.id) as rn
              from public.comisiones_devengadas x order by x.id limit 20001) d;
  end if;
  if coalesce(p_gastos, false) then
    -- proyecto y grupo con la RLS de sus tablas (como el embebido de PostgREST): si no se ven, null.
    select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'estado', g.estado, 'moneda', g.moneda, 'total', g.total,
                                                 'base', g.base, 'pph_retenido', g.pph_retenido,
                                                 'pph_ingresado_el', g.pph_ingresado_el, 'fecha', g.fecha,
                                                 'vence_el', g.vence_el, 'pagado_el', g.pagado_el,
                                                 'sociedad', g.sociedad, 'proyecto_nombre', g.proyecto_nombre,
                                                 'grupo', g.grupo)
                              order by g.id) filter (where g.rn <= 20000), '[]'::jsonb), count(*)::int
      into v_ga, v_nga
      from (select x.id, x.estado, x.moneda, x.total, x.base, x.pph_retenido, x.pph_ingresado_el, x.fecha, x.vence_el,
                   x.pagado_el, x.sociedad, p.nombre as proyecto_nombre, c.grupo,
                   row_number() over (order by x.id) as rn
              from public.gastos x
              left join public.proyectos p on p.id = x.proyecto_id
              left join public.gasto_categorias c on c.clave = x.categoria
             order by x.id limit 20001) g;
  end if;
  return jsonb_build_object('comisiones', v_co, 'gastos', v_ga,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'comisiones' k where v_nco > 20000
                                            union all select 'gastos' where v_nga > 20000) r));
end $$;

-- ── 8. Estado de un gasto para la edge `ficheros` (subir justificante): la edge pregunta con el JWT del usuario si
--       ese gasto existe PARA ÉL y si está anulado. null = no lo ve (la edge responde 403 gasto_no_visible).
create or replace function public.gasto_estado_datos(p_gasto uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_g jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'gasto_estado_datos: sin sesión' using errcode = '42501';
  end if;
  select jsonb_build_object('id', g.id, 'estado', g.estado) into v_g from public.gastos g where g.id = p_gasto;
  return jsonb_build_object('gasto', v_g);
end $$;

-- ── Dueño lector (hereda la RLS de quien llama: nunca postgres), fuera PUBLIC/anon/service_role, EXECUTE authenticated ─
grant create on schema public to lw_lector;
alter function public.equipos_datos() owner to lw_lector;
alter function public.condiciones_comision_datos() owner to lw_lector;
alter function public.comisiones_reparto_datos() owner to lw_lector;
alter function public.comision_de_solicitud_datos(uuid) owner to lw_lector;
alter function public.operacion_comisiones_datos(uuid[]) owner to lw_lector;
alter function public.condicion_usos_datos(uuid) owner to lw_lector;
alter function public.finanzas_panel_datos(boolean, boolean) owner to lw_lector;
alter function public.gasto_estado_datos(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;

revoke all on function public.equipos_datos() from public, anon, service_role;
revoke all on function public.condiciones_comision_datos() from public, anon, service_role;
revoke all on function public.comisiones_reparto_datos() from public, anon, service_role;
revoke all on function public.comision_de_solicitud_datos(uuid) from public, anon, service_role;
revoke all on function public.operacion_comisiones_datos(uuid[]) from public, anon, service_role;
revoke all on function public.condicion_usos_datos(uuid) from public, anon, service_role;
revoke all on function public.finanzas_panel_datos(boolean, boolean) from public, anon, service_role;
revoke all on function public.gasto_estado_datos(uuid) from public, anon, service_role;
grant execute on function public.equipos_datos() to authenticated;
grant execute on function public.condiciones_comision_datos() to authenticated;
grant execute on function public.comisiones_reparto_datos() to authenticated;
grant execute on function public.comision_de_solicitud_datos(uuid) to authenticated;
grant execute on function public.operacion_comisiones_datos(uuid[]) to authenticated;
grant execute on function public.condicion_usos_datos(uuid) to authenticated;
grant execute on function public.finanzas_panel_datos(boolean, boolean) to authenticated;
grant execute on function public.gasto_estado_datos(uuid) to authenticated;

-- si el dueño, el proacl o el CREATE no cuadran, la migración no se aplica
do $chk$
declare f text; v_acl text; v_dueno text;
begin
  foreach f in array array['public.equipos_datos()', 'public.condiciones_comision_datos()',
                           'public.comisiones_reparto_datos()', 'public.comision_de_solicitud_datos(uuid)',
                           'public.operacion_comisiones_datos(uuid[])', 'public.condicion_usos_datos(uuid)',
                           'public.finanzas_panel_datos(boolean,boolean)', 'public.gasto_estado_datos(uuid)'] loop
    select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno from pg_proc p where p.oid = f::regprocedure;
    if v_dueno <> 'lw_lector' then raise exception '%: dueño % (esperado lw_lector)', f, v_dueno; end if;
    if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
      raise exception '%: proacl % (esperado lw_lector + authenticated)', f, v_acl;
    end if;
  end loop;
  if has_schema_privilege('lw_lector', 'public', 'create') then raise exception 'lw_lector conserva CREATE en public'; end if;
end $chk$;
