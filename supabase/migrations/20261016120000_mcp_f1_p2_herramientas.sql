-- MCP de Lawang · F1-P2 (16-oct-2026): las 10 herramientas de lectura de Dirección y Contabilidad, `privado.mcp_<x>`.
-- Encargo: encargos/20261015_erp_mcp.md §3 «Mapa de herramientas» + Descomposición «Lawang F1-P2»; revisión de Seguridad #395.
--
-- !! REQUIERE 20261016110000_mcp_f1_p1_base.sql (P1), que crea: privado.mcp_puerta(text, jsonb) returns jsonb,
--    privado.mcp_cierra(bigint, int, text), el rol ia_puente_rol y su USAGE en `privado`. Sin P1 esta migración FALLA en
--    el primer `grant ... to ia_puente_rol` (a propósito: no hay modo «a medias» sin puerta). P1 NO tiene que dar nada a
--    lw_lector en `privado` (ni USAGE ni EXECUTE): ver «Dos capas».
--
-- QUÉ HACE (solo construye; ninguna tabla, ninguna policy, ningún revoke de lo existente):
--   1. Diez funciones `privado.mcp_<x>` (la puerta de cada herramienta): puerta común (privado.mcp_puerta: encendido,
--      cliente, permiso de IA, tope y registro) → la MISMA comprobación de herramienta que su pantalla → lectura →
--      privado.mcp_cierra. Una denegación se DEVUELVE ({error}) y la transacción se confirma: así queda su fila en el
--      registro (ASVS 16.3.2). Sin `stable` (la puerta escribe el registro), SECURITY DEFINER, `search_path = ''`, nombres
--      cualificados, sin EXECUTE dinámico ni format(), argumentos tipados (uuid/date y la clave de sociedad).
--   2. Ocho lectores `public.mcp_<x>_lee` (dueño lw_lector, STABLE, DEFINER, `search_path = ''`, sin EXECUTE para nadie):
--      la lectura con la RLS del usuario real. Las otras dos herramientas leen como postgres, explicado en su cabecera.
--   3. Esquema `privado` (Seguridad #395): anon y authenticated no tienen USAGE en él, así que no se llaman por /rpc.
--      revoke EXPLÍCITO a public, anon, authenticated y service_role en las 18 funciones, y EXECUTE de las 10 puertas solo
--      a ia_puente_rol, en este mismo fichero (sin ventana).
--   4. lw_lector recibe EXECUTE en public.facturas_pendiente_equipo() y public.factura_aplicado(uuid) (las dos STABLE),
--      que la pantalla de Facturas ya usa y authenticated ya ejecuta (medido el 16-oct: has_function_privilege = t):
--      lw_lector sigue siendo un subconjunto de authenticated, y la herramienta envuelve la función de su pantalla.
--
-- DOS CAPAS (decisión por defecto de Backend, 16-oct; el encargo pedía las mcp_* con dueño lw_lector en `privado`):
--   tools/salud_lawang.py, invariante «lw_lector es un lector» (líneas 866-935, regla de Seguridad L1 del 27-sep), da fila
--   (d) por CUALQUIER entrada de ACL de lw_lector en una función fuera de public — y ser su dueño la crea: tras el revoke
--   la ACL queda «lw_lector=X/lw_lector» (medido en comisiones_reparto_datos el 16-oct) —, (d) por EXECUTE de lw_lector en
--   algo que escribe (privado.mcp_puerta escribe el registro) y (e) por USAGE de lw_lector en `privado`. Con dueño lw_lector
--   en `privado`, cada una de las 8 daba fila y P1 tenía que abrir `privado` a lw_lector. Partido en dos: la puerta
--   (privado, postgres) hace puerta, comprobación y registro; el lector (public, lw_lector, STABLE, sin escribir, sin
--   EXECUTE para nadie: lo alcanza postgres por su pertenencia INHERIT a lw_lector, law338_l0:31) solo lee. Las
--   comprobaciones de herramienta (puede, es_admin, gastos_acceso…) miran la sesión, no el rol: dan lo mismo como
--   postgres. Descartado: añadir excepciones al invariante (debilita un guardarraíl de Seguridad). Vuelta atrás: fundir
--   cada lector en su puerta y darle dueño lw_lector.
--   Los cuerpos de los lectores no llevan comentarios: el invariante busca en `prosrc` palabras como perform, execute,
--   create, call, grant o comment. El sufijo `_lee` (y no `_datos`) es a propósito: no son lecturas de pantalla
--   (salud (a), erp/modulos.py:7298 y erp/contrato_front.py:629 exigen forma declarada a todo `*_datos`).
--
-- Lo que devuelve: solo ids, códigos (número de documento, código de parcela), importes, monedas, fechas, contadores y
-- vocabulario cerrado (estado, tipo, nivel, evento, vía). NUNCA datos de comprador, `contratos.datos`, correos, nombres
-- de persona ni texto libre (notas, concepto, motivo, detalle). `contratos_equipo()` y `facturas_equipo()` no se usan.
-- La sociedad sale como `sociedad_id` = `sociedades.clave`, que es su id. Tope: 500 filas por lista + `recortado`.
--
-- Fechas: «mes» y «semana» en Asia/Makassar (la zona de Lawang: 117 apariciones en supabase/migrations, ninguna otra).
-- Semana = los 7 días que acaban en p_hasta (por defecto hoy en Makassar), ambos incluidos.
--
-- Argumentos: uuid y date, más `p_sociedad text` en tres herramientas porque el id de una sociedad ES su clave de texto.
-- Se valida con una expresión fija (^[a-z0-9_]{1,64}$) y solo se compara por igualdad: no es una búsqueda.
--
-- Tiempos medidos el 16-oct-2026 en la base viva (solo lectura, `explain (analyze, timing off, summary on)`, 3 pasadas,
-- la última anotada). Ojo: la conexión de lectura (axw_lectura, BYPASSRLS, sin EXECUTE en las auxiliares) NO puede
-- tomar el rol lw_lector ni llamar a las funciones de la RLS: se mide el cuerpo de agregación sobre las tablas, sin el
-- coste de las policies (casi todas son initplans de una vez por consulta; unidad_visible/proyecto_visible van por
-- fila en unidades). Volumen de hoy: 565 unidades, 320 contratos (176 raíces), 554 documentos, 1.642 eventos, 0 gastos,
-- 0 movimientos de banco. Presupuesto: statement_timeout de 3 s.

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- LECTORES (public, dueño lw_lector, STABLE, sin EXECUTE para nadie). Cabecera de cada uno en su puerta, más abajo.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function public.mcp_parcelas_libres_lee(p_proyecto uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'datos', coalesce(jsonb_agg(jsonb_build_object('unidad_id', u.id, 'codigo', u.codigo, 'proyecto_id', u.proyecto_id,
                                                          'tipo', u.tipo, 'superficie_m2', u.superficie_m2, 'precio', u.precio,
                                                          'moneda', u.moneda) order by u.rn) filter (where u.rn <= 500), '[]'::jsonb),
           'recortado', count(*) > 500,
           'filas', least(count(*), 500))
    from (select x.id, x.codigo, x.proyecto_id, x.tipo, x.superficie_m2, x.moneda,
                 coalesce(x.precio, nullif(coalesce(x.precio_suelo, 0) + coalesce(x.precio_construccion, 0), 0)) as precio,
                 row_number() over (order by x.proyecto_id, x.codigo, x.id) as rn
            from public.unidades x
           where x.estado = 'disponible'
             and (p_proyecto is null or x.proyecto_id = p_proyecto)
           order by x.proyecto_id, x.codigo, x.id
           limit 501) u
$$;

create or replace function public.mcp_comisiones_pendientes_lee()
returns jsonb language sql stable security definer set search_path = '' as $$
  with r as (select public.comisiones_reparto_datos() as j),
  q as (
    select t.e, t.o,
           (select u.user_id from public.usuarios u
             where lower(u.email) = lower(t.e->>'beneficiario_email') order by u.user_id limit 1) as uid,
           row_number() over (order by t.o) as rn
      from r cross join lateral jsonb_array_elements(coalesce(r.j->'devengadas', '[]'::jsonb)) with ordinality as t(e, o)
     where t.e->>'estado' = 'pendiente')
  select jsonb_build_object(
           'datos', coalesce((select jsonb_agg(jsonb_build_object(
                                'devengada_id', q.e->>'id', 'contrato_raiz_id', q.e->>'contrato_raiz_id',
                                'beneficiario_usuario_id', q.uid, 'nivel', q.e->>'nivel',
                                'importe', (q.e->>'importe')::numeric, 'importe_ajustado', (q.e->>'importe_ajustado')::numeric,
                                'moneda', q.e->>'moneda', 'disparado_en', q.e->>'disparado_en') order by q.o)
                                from q where q.rn <= 500), '[]'::jsonb),
           'recortado', (select count(*) from q) > 500 or coalesce((select r.j->'recortado' from r), '[]'::jsonb) ? 'devengadas',
           'filas', least((select count(*) from q), 500))
$$;

create or replace function public.mcp_cobros_por_proyecto_mes_lee(p_desde date, p_hasta date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'datos', coalesce(jsonb_agg(jsonb_build_object('proyecto_id', z.proyecto_id, 'moneda', z.moneda,
                                                          'cobrado_mes', z.cobrado, 'recibis_mes', z.n_recibis,
                                                          'pendiente_hoy', z.pendiente) order by z.rn) filter (where z.rn <= 500), '[]'::jsonb),
           'recortado', count(*) > 500,
           'filas', least(count(*), 500))
    from (select x.proyecto_id, x.moneda, sum(x.cobrado) as cobrado, sum(x.es_recibi)::int as n_recibis,
                 sum(x.pendiente) as pendiente,
                 row_number() over (order by x.proyecto_id, x.moneda) as rn
            from (select r.proyecto_id, r.moneda, r.total as cobrado, 1 as es_recibi, 0::numeric as pendiente
                    from public.facturas r
                   where r.tipo = 'recibi' and not coalesce(r.anulada, false)
                     and coalesce(r.fecha_emision, (r.created_at at time zone 'Asia/Makassar')::date) >= p_desde
                     and coalesce(r.fecha_emision, (r.created_at at time zone 'Asia/Makassar')::date) <  p_hasta
                  union all
                  select f.proyecto_id, f.moneda, 0, 0, pe.pendiente
                    from public.facturas_pendiente_equipo() pe
                    join public.facturas f on f.id = pe.factura_id
                   where coalesce(pe.pendiente, 0) <> 0) x
           group by x.proyecto_id, x.moneda) z
$$;

create or replace function public.mcp_contratos_sin_firmar_lee(p_proyecto uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'datos', coalesce(jsonb_agg(jsonb_build_object(
                      'contrato_id', c.id, 'numero', c.numero, 'tipo', c.tipo, 'unidad_id', c.unidad_id, 'proyecto_id', c.proyecto_id,
                      'dias_desde_alta', (now() at time zone 'Asia/Makassar')::date - (c.created_at at time zone 'Asia/Makassar')::date,
                      'firmas_pendientes', (select count(*) from public.contrato_firmas k
                                             where k.contrato_id = c.id and k.estado = 'pendiente' and k.anulado_en is null),
                      'firmas_hechas', (select count(*) from public.contrato_firmas k
                                         where k.contrato_id = c.id and k.estado = 'firmado' and k.anulado_en is null))
                      order by c.rn) filter (where c.rn <= 500), '[]'::jsonb),
           'recortado', count(*) > 500,
           'filas', least(count(*), 500))
    from (select x.id, x.numero, x.tipo, x.unidad_id, x.proyecto_id, x.created_at,
                 row_number() over (order by x.created_at, x.id) as rn
            from public.contratos x
           where not coalesce(x.bloqueado, false) and x.liberado_en is null
             and (p_proyecto is null or x.proyecto_id = p_proyecto)
           order by x.created_at, x.id
           limit 501) c
$$;

create or replace function public.mcp_resumen_semana_lee(p_desde date, p_hasta date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with m as (
    select x.moneda, sum(x.n_ventas)::int as n_ventas, sum(x.imp_ventas) as imp_ventas, sum(x.cobrado) as cobrado
      from (select c.moneda, 1 as n_ventas, coalesce(c.precio_total, 0) as imp_ventas, 0::numeric as cobrado
              from public.contratos c
             where coalesce(c.bloqueado, false) and c.fecha_firma between p_desde and p_hasta
            union all
            select r.moneda, 0, 0, r.total
              from public.facturas r
             where r.tipo = 'recibi' and not coalesce(r.anulada, false)
               and coalesce(r.fecha_emision, (r.created_at at time zone 'Asia/Makassar')::date) between p_desde and p_hasta) x
     group by x.moneda)
  select jsonb_build_object(
           'datos', jsonb_build_object(
              'por_moneda', coalesce((select jsonb_agg(jsonb_build_object('moneda', m.moneda, 'ventas_firmadas', m.n_ventas,
                                                                         'ventas_firmadas_importe', m.imp_ventas, 'cobrado', m.cobrado)
                                                       order by m.moneda) from m), '[]'::jsonb),
              'reservas_caidas', (select count(*) from public.contrato_eventos e
                                   where e.evento = 'reserva_liberada'
                                     and e.creado_en >= (p_desde::timestamp at time zone 'Asia/Makassar')
                                     and e.creado_en < ((p_hasta + 1)::timestamp at time zone 'Asia/Makassar')),
              'obra', jsonb_build_object(
                 'entregas_con_fecha', (select count(*) from public.unidades u where u.obra_fecha_entrega is not null),
                 'partes', (select count(*) from public.obra_partes_trabajo o))),
           'recortado', (select count(*) from m) > 500,
           'filas', (select count(*) from m))
$$;

create or replace function public.mcp_facturas_no_cobradas_lee(p_sociedad text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'datos', coalesce(jsonb_agg(jsonb_build_object(
                      'factura_id', z.id, 'numero', z.numero, 'sociedad_id', z.sociedad, 'contrato_id', z.contrato_id,
                      'proyecto_id', z.proyecto_id, 'moneda', z.moneda, 'total', z.total, 'cobrado', z.total - z.pendiente,
                      'pendiente', z.pendiente, 'fecha_emision', z.fecha_emision, 'vencimiento', z.vencimiento)
                      order by z.rn) filter (where z.rn <= 500), '[]'::jsonb),
           'recortado', count(*) > 500,
           'filas', least(count(*), 500))
    from (select f.id, f.numero, f.sociedad, f.contrato_id, f.proyecto_id, f.moneda, f.total, pe.pendiente, f.fecha_emision,
                 case when (f.datos->'fields'->>'fecha_vencimiento') ~ '^\d{4}-\d{2}-\d{2}$'
                      then (f.datos->'fields'->>'fecha_vencimiento')::date end as vencimiento,
                 row_number() over (order by f.sociedad, f.fecha_emision, f.numero, f.id) as rn
            from public.facturas_pendiente_equipo() pe
            join public.facturas f on f.id = pe.factura_id
           where pe.pendiente > 0
             and (p_sociedad is null or f.sociedad = p_sociedad)) z
$$;

create or replace function public.mcp_recibis_sin_aplicar_lee(p_sociedad text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
           'datos', coalesce(jsonb_agg(jsonb_build_object(
                      'recibi_id', z.id, 'numero', z.numero, 'sociedad_id', z.sociedad, 'contrato_id', z.contrato_id,
                      'moneda', z.moneda, 'total', z.total, 'aplicado', z.aplicado, 'sin_aplicar', z.total - z.aplicado,
                      'fecha_emision', z.fecha_emision) order by z.rn) filter (where z.rn <= 500), '[]'::jsonb),
           'recortado', count(*) > 500,
           'filas', least(count(*), 500))
    from (select y.*, row_number() over (order by y.sociedad, y.fecha_emision, y.numero, y.id) as rn
            from (select r.id, r.numero, r.sociedad, r.contrato_id, r.moneda, r.total, r.fecha_emision,
                         coalesce((select sum(ra.importe_aplicado)
                                     from public.recibi_aplicaciones ra
                                     join public.facturas f2 on f2.id = ra.factura_id
                                    where ra.recibi_id = r.id
                                      and f2.contrato_id is not null
                                      and not coalesce(f2.anulada, false)), 0) as aplicado
                    from public.facturas r
                   where r.tipo = 'recibi' and not coalesce(r.anulada, false)
                     and (p_sociedad is null or r.sociedad = p_sociedad)) y
           where y.total - y.aplicado > 0) z
$$;

create or replace function public.mcp_movimientos_mes_sociedad_lee(p_desde date, p_hasta date, p_sociedad text,
                                                                   p_facturas boolean, p_recibis boolean,
                                                                   p_gastos boolean, p_bancos boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  with fa as (
    select f.sociedad, f.moneda, count(*)::int as n, sum(f.total) as t
      from public.facturas f
     where p_facturas and f.tipo = 'factura' and not coalesce(f.anulada, false)
       and coalesce(f.fecha_emision, (f.created_at at time zone 'Asia/Makassar')::date) >= p_desde
       and coalesce(f.fecha_emision, (f.created_at at time zone 'Asia/Makassar')::date) <  p_hasta
       and (p_sociedad is null or f.sociedad = p_sociedad)
     group by f.sociedad, f.moneda),
  re as (
    select r.sociedad, r.moneda, count(*)::int as n, sum(r.total) as t
      from public.facturas r
     where p_recibis and r.tipo = 'recibi' and not coalesce(r.anulada, false)
       and coalesce(r.fecha_emision, (r.created_at at time zone 'Asia/Makassar')::date) >= p_desde
       and coalesce(r.fecha_emision, (r.created_at at time zone 'Asia/Makassar')::date) <  p_hasta
       and (p_sociedad is null or r.sociedad = p_sociedad)
     group by r.sociedad, r.moneda),
  ga as (
    select g.sociedad, g.moneda, count(*)::int as n, sum(g.total) as t
      from public.gastos g
     where p_gastos and g.estado <> 'anulado' and g.fecha >= p_desde and g.fecha < p_hasta
       and (p_sociedad is null or g.sociedad = p_sociedad)
     group by g.sociedad, g.moneda),
  co as (
    select y.soc as sociedad, y.moneda, count(*)::int as n, sum(y.importe_mov) as t
      from (select c.importe_mov, m.moneda,
                   case when c.tipo = 'recibi' then (select f.sociedad from public.facturas f where f.id = c.ref_id)
                        when c.tipo in ('gasto', 'pph') then (select g.sociedad from public.gastos g where g.id = c.ref_id)
                   end as soc
              from public.bancos_conciliacion c
              join public.bancos_movimientos m on m.id = c.movimiento_id
             where p_bancos and c.anulado_en is null and m.fecha >= p_desde and m.fecha < p_hasta) y
     where p_sociedad is null or y.soc = p_sociedad
     group by y.soc, y.moneda)
  select jsonb_build_object(
           'datos', jsonb_build_object(
              'facturas', case when p_facturas then coalesce((select jsonb_agg(jsonb_build_object('sociedad_id', s.sociedad, 'moneda', s.moneda,
                                     'numero', s.n, 'importe', s.t) order by s.sociedad, s.moneda) from (select * from fa order by 1, 2 limit 500) s), '[]'::jsonb) end,
              'recibis', case when p_recibis then coalesce((select jsonb_agg(jsonb_build_object('sociedad_id', s.sociedad, 'moneda', s.moneda,
                                     'numero', s.n, 'importe', s.t) order by s.sociedad, s.moneda) from (select * from re order by 1, 2 limit 500) s), '[]'::jsonb) end,
              'gastos', case when p_gastos then coalesce((select jsonb_agg(jsonb_build_object('sociedad_id', s.sociedad, 'moneda', s.moneda,
                                     'numero', s.n, 'importe', s.t) order by s.sociedad, s.moneda) from (select * from ga order by 1, 2 limit 500) s), '[]'::jsonb) end,
              'conciliados', case when p_bancos then coalesce((select jsonb_agg(jsonb_build_object('sociedad_id', s.sociedad, 'moneda', s.moneda,
                                     'numero', s.n, 'importe', s.t) order by s.sociedad nulls last, s.moneda) from (select * from co order by 1 nulls last, 2 limit 500) s), '[]'::jsonb) end,
              'sin_permiso', to_jsonb(array_remove(array[case when not p_facturas then 'facturas' end,
                                                         case when not p_recibis then 'recibis' end,
                                                         case when not p_gastos then 'gastos' end,
                                                         case when not p_bancos then 'conciliados' end], null))),
           'recortado', (select count(*) from fa) > 500 or (select count(*) from re) > 500
                        or (select count(*) from ga) > 500 or (select count(*) from co) > 500,
           'filas', least((select count(*) from fa), 500) + least((select count(*) from re), 500)
                    + least((select count(*) from ga), 500) + least((select count(*) from co), 500))
$$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 1. parcelas_libres (D2) · lector lw_lector
--    Pantalla: Proyectos › parcelas, intranet/v4/proyectos/index.html:3 `data-herramienta="unidades"`, que
--    contracts/assets/guard.js:351 exige con la regla de puede() (super admin todo; el resto, la casilla en su ficha).
--    Comprobación copiada: public.puede('unidades').
--    Filas: public.unidades bajo su policy «agentes leen unidades de sus proyectos» (es_agente() and
--    unidad_visible(proyecto_id)), la MISMA que filtra la vista unidades_estado (security_invoker) que lee la pantalla.
--    No se envuelve la vista: hace un LATERAL unidad_cobro_reparto_v2 por parcela (0,6 → 2,2 s medidos en la prueba
--    precio_cadena_vigente V8) para dar cobrado y contrato, que esta herramienta no devuelve; y trae comprador_nombre,
--    notas y el correo del creador. El precio es la expresión literal de la vista:
--    coalesce(precio, nullif(coalesce(precio_suelo,0) + coalesce(precio_construccion,0), 0)).
--    Medido: 4,2 ms. Devuelve por unidad_id: código, proyecto_id, tipo, m², precio, moneda.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_parcelas_libres(p_proyecto uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
begin
  v_p := privado.mcp_puerta('parcelas_libres', jsonb_build_object('p_proyecto', p_proyecto));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if not public.puede('unidades') then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_parcelas_libres_lee(p_proyecto);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return v_r - 'filas';
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 2. comisiones_pendientes (D5) · lector lw_lector · ENVUELVE public.comisiones_reparto_datos()
--    Pantalla: Comisiones › Reparto a closers («Mis comisiones» para un agente), intranet/v4/reparto/index.html:3
--    `data-herramienta="comisiones_reparto"` (guard.js:351). Comprobación copiada: public.puede('comisiones_reparto').
--    comisiones_reparto_datos (law338_l3, 20261010062215; dueño lw_lector) no comprueba herramienta: solo sesión y la
--    policy comision_visible. Se le pone delante la casilla de la pantalla y se proyecta su salida:
--      fuera beneficiario_email, ajuste_motivo, anulado_motivo, pagado_por y disparado_por_snapshot;
--      el beneficiario sale como usuario_id (usuarios.user_id con el mismo correo, leído con la RLS de usuarios: si el
--      usuario no puede ver esa ficha, sale null). Solo estado = 'pendiente'. La función solo trae los niveles del
--      reparto (closer, setter, team_lead): las de manager/estándar/propia son otra pantalla («Pagos de %marca»).
--    Medido: 0,2 ms la tabla (27 devengadas en la viva; la función no la ejecuta axw_lectura).
--    Devuelve por devengada_id: contrato_raiz_id, beneficiario_usuario_id, nivel, importe, importe_ajustado, moneda,
--    disparado_en.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_comisiones_pendientes()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
begin
  v_p := privado.mcp_puerta('comisiones_pendientes', '{}'::jsonb);
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if not public.puede('comisiones_reparto') then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_comisiones_pendientes_lee();
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return v_r - 'filas';
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 3. cobros_por_proyecto_mes (D1) · lector lw_lector · ENVUELVE public.facturas_pendiente_equipo() para el pendiente
--    Pantalla: Finanzas › Resumen, intranet/v4/finanzas/index.html:3 `data-rol="admin"` (sin casilla). guard.js:371
--    rolBasta → contracts/assets/roles.js:28 LW_ROL.esAdmin: rol efectivo admin o super_admin, y roles.js:24 cuenta
--    admin_empresa como admin y super_admin_empresa como super. Comprobación copiada (en la base): es_admin() o el
--    cuerpo de public._rol_empresa() (u.activo, ámbito empresa, rol admin_empresa/super_admin_empresa), escrito en línea
--    sobre la ficha de la sesión (_rol_empresa no la ejecuta authenticated: no se concede a nadie nuevo).
--    Esa pantalla saca el pendiente de facturas_pendiente_equipo() (intranet/v4/assets/panel-finanzas.js) y el cobrado
--    de contratos_cobrado_equipo(), que es por contrato y de siempre, no por mes: el cobrado del mes sale de los
--    recibís vivos con fecha_emision (o, sin ella, el día de alta en Makassar) dentro del mes, con la RLS de facturas.
--    Medido: 1,8 ms. Devuelve por proyecto_id y moneda: cobrado_mes, recibis_mes y pendiente_hoy (facturas vivas sin
--    cobrar a hoy, la cifra del Resumen; no depende del mes).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_cobros_por_proyecto_mes(p_mes date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
  v_d0 date := date_trunc('month', coalesce(p_mes, (now() at time zone 'Asia/Makassar')::date))::date;
begin
  v_p := privado.mcp_puerta('cobros_por_proyecto_mes', jsonb_build_object('p_mes', p_mes));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if not (public.es_admin()
          or exists (select 1 from public.usuarios u
                      where u.user_id = public.uid_sesion() and u.activo and u.ambito = 'empresa'
                        and u.rol in ('admin_empresa', 'super_admin_empresa'))) then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_cobros_por_proyecto_mes_lee(v_d0, (v_d0 + interval '1 month')::date);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return (v_r - 'filas') || jsonb_build_object('mes', to_char(v_d0, 'YYYY-MM'));
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 4. cambios_estado_semana (D3) · lee como POSTGRES (excepción escrita en el encargo y en la revisión #395)
--    Por qué postgres: public.unidades_log no la lee ni authenticated ni lw_lector (medido el 16-oct:
--    has_table_privilege = f para los dos y 0 policies en la viva). Ninguna pantalla la lee hoy: no hay comprobación
--    de pantalla que copiar. La puerta es la del encargo: public.es_admin(), la misma que tenía la última policy de
--    lectura que hubo, «log de parcelas: lo ve un admin» (supabase/migrations/20260927010000_frontera_parcelas_
--    proyectos_rpc.sql:31; ya no existe en la viva).
--    Como postgres se salta la RLS, cada fila repite a mano la policy de su tabla:
--      · unidades: «agentes leen unidades de sus proyectos» = es_agente() and unidad_visible(proyecto_id);
--      · contrato_eventos: «super_admin ve todo, el resto solo eventos normales de sus contratos» = es_super_admin() or
--        (es_agente() and (evento no es uno de los 6 reservados or super_de_contrato(contrato_id)) and contrato_id is
--        not null and (es_admin() or contrato_id = any(mis_contratos_visibles()))), copiada de pg_policies el 16-oct.
--    Sin texto: de unidades_log solo antes->>'estado' y despues->>'estado' (las fotos completas llevan `notas`), y
--    solo valores del CHECK unidades_estado_check; la vía, solo su vocabulario; el «quién» (`por`, `quien`: un correo,
--    un uuid o una marca de sistema) sale como usuario_id si casa con una ficha de usuarios, y si no, sin usuario y con
--    vía «sistema». De contrato_eventos solo el nombre del evento, de una lista cerrada (nunca `detalle`).
--    Medido: 1,3 ms (tablas, sin las funciones de la policy). Devuelve por unidad_id / contrato_id: estado antes y
--    después (unidad) o evento (contrato), cuándo, usuario_id y vía.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_cambios_estado_semana(p_hasta date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_d jsonb; v_n int;
  v_d1 date := coalesce(p_hasta, (now() at time zone 'Asia/Makassar')::date);
  v_t0 timestamptz; v_t1 timestamptz;
  c_estados constant text[] := array['disponible', 'reservada', 'vendida', 'bloqueada', 'no_disponible', 'cobrada'];
  c_vias constant text[] := array['alta', 'automatico', 'csv', 'ficha', 'sql directo'];
  c_eventos constant text[] := array['creado', 'enviado_a_firma', 'firma_recogida', 'firma_anulada', 'firmado_del_todo',
                                     'traspaso', 'reserva_liberada', 'reserva_liberacion_deshecha', 'reserva_prorrogada',
                                     'desbloqueado', 'desbloqueado_estando_firmado'];
  c_reservados constant text[] := array['editado_estando_firmado', 'desbloqueado_estando_firmado', 'factura_sin_bloquear',
                                        'cobro_a_factura_huerfana', 'cobro_a_otro_comprador', 'comprador_sin_ficha'];
begin
  v_t0 := (v_d1 - 6)::timestamp at time zone 'Asia/Makassar';
  v_t1 := (v_d1 + 1)::timestamp at time zone 'Asia/Makassar';
  v_p := privado.mcp_puerta('cambios_estado_semana', jsonb_build_object('p_hasta', p_hasta));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if public.uid_sesion() is null or not public.es_admin() then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'tipo', q.tipo, 'unidad_id', q.unidad_id, 'contrato_id', q.contrato_id,
           'estado_antes', q.antes, 'estado_despues', q.despues, 'evento', q.evento,
           'en', q.en, 'usuario_id', q.uid, 'via', q.via)) order by q.rn) filter (where q.rn <= 500), '[]'::jsonb),
         count(*)::int
    into v_d, v_n
    from (select s.*, row_number() over (order by s.en desc, s.tipo, s.unidad_id, s.contrato_id) as rn
            from (select 'unidad'::text as tipo, l.unidad_id, null::uuid as contrato_id,
                         case when l.antes->>'estado' = any (c_estados) then l.antes->>'estado' end as antes,
                         case when l.despues->>'estado' = any (c_estados) then l.despues->>'estado' end as despues,
                         null::text as evento, l.en,
                         (select uu.user_id from public.usuarios uu
                           where lower(uu.email) = lower(l.por) order by uu.user_id limit 1) as uid,
                         case when l.via = any (c_vias) then l.via else 'otro' end as via
                    from public.unidades_log l
                    join public.unidades u on u.id = l.unidad_id
                   where l.en >= v_t0 and l.en < v_t1
                     and (l.antes->>'estado') is distinct from (l.despues->>'estado')
                     and public.es_agente() and public.unidad_visible(u.proyecto_id)
                  union all
                  select 'contrato', c.unidad_id, e.contrato_id, null, null, e.evento, e.creado_en, w.uid,
                         case when w.uid is null then 'sistema' else 'persona' end
                    from public.contrato_eventos e
                    join public.contratos c on c.id = e.contrato_id
                    cross join lateral (select (select uu.user_id from public.usuarios uu
                                                 where lower(uu.email) = lower(e.quien) or uu.user_id::text = e.quien
                                                 order by uu.user_id limit 1) as uid) w
                   where e.creado_en >= v_t0 and e.creado_en < v_t1
                     and e.evento = any (c_eventos)
                     and (public.es_super_admin()
                          or (public.es_agente()
                              and (e.evento <> all (c_reservados) or public.super_de_contrato(e.contrato_id))
                              and e.contrato_id is not null
                              and (public.es_admin() or e.contrato_id = any (public.mis_contratos_visibles()))))) s) q;
  perform privado.mcp_cierra(v_l, least(v_n, 500), 'ok');
  return jsonb_build_object('datos', v_d, 'desde', v_d1 - 6, 'hasta', v_d1, 'recortado', v_n > 500);
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 5. contratos_sin_firmar (D4) · lector lw_lector
--    Pantalla: Contratos, intranet/v4/contratos/index.html:3 `data-herramienta="contratos"` (guard.js:351).
--    Comprobación copiada: public.puede('contratos').
--    No se envuelve contratos_equipo() (prohibida: fila entera con pasaporte, correo y teléfono en `datos`). Se lee
--    public.contratos con columnas acotadas (nunca `datos`, `comprador_nombre`, `nombre_contrato`, `identificadores`)
--    bajo su policy «agentes leen sus contratos», y contrato_firmas bajo la suya, solo para CONTAR (nunca el correo ni
--    el nombre del firmante). «Sin firmar» = bloqueado falso (la vista unidades_estado lo llama contrato_firmado) y no
--    liberado.
--    Medido: 3,3 ms. Devuelve por contrato_id: número, tipo, unidad_id, proyecto_id, días desde el alta (Makassar),
--    firmas pendientes y firmas hechas.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_contratos_sin_firmar(p_proyecto uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
begin
  v_p := privado.mcp_puerta('contratos_sin_firmar', jsonb_build_object('p_proyecto', p_proyecto));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if not public.puede('contratos') then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_contratos_sin_firmar_lee(p_proyecto);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return v_r - 'filas';
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 6. resumen_semana (D6) · lector lw_lector
--    Pantalla: Finanzas › Resumen, intranet/v4/finanzas/index.html:3 `data-rol="admin"`: la misma comprobación de rol
--    que cobros_por_proyecto_mes (es_admin() o rol de empresa, guard.js:371 + roles.js:24/28).
--    No se reutilizan finanzas_resumen_semanal ni resumen_manana (solo service_role: ven todo). Tampoco se envuelve
--    finanzas_panel_datos (devuelve las listas enteras de comisiones y gastos, que aquí no se piden) ni
--    obra_cifras_datos: sus dos cifras son count(*) de unidades_estado con obra_fecha_entrega y count(*) de
--    obra_partes_trabajo (cuerpo vivo, 16-oct); la vista es unidades ⟕ contratos por id ⟕ LATERAL … ON true, que no
--    cambia el número de filas, así que contar en public.unidades con la misma RLS da EXACTAMENTE la misma cifra sin
--    pagar el LATERAL por parcela (0,6-2,2 s, ver parcelas_libres), que con el resto se acercaría a los 3 s.
--    Cifras por moneda (con la RLS de cada tabla): ventas firmadas (contratos con bloqueado y fecha_firma en la semana:
--    número e importe de precio_total), cobrado (recibís vivos con fecha en la semana) y, aparte, reservas caídas
--    (eventos reserva_liberada en la semana) y obra.
--    Medido: 0,9 ms (+0,2 ms los dos conteos de obra).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_resumen_semana(p_hasta date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
  v_d1 date := coalesce(p_hasta, (now() at time zone 'Asia/Makassar')::date);
begin
  v_p := privado.mcp_puerta('resumen_semana', jsonb_build_object('p_hasta', p_hasta));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if not (public.es_admin()
          or exists (select 1 from public.usuarios u
                      where u.user_id = public.uid_sesion() and u.activo and u.ambito = 'empresa'
                        and u.rol in ('admin_empresa', 'super_admin_empresa'))) then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_resumen_semana_lee(v_d1 - 6, v_d1);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return (v_r - 'filas') || jsonb_build_object('desde', v_d1 - 6, 'hasta', v_d1);
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 7. facturas_no_cobradas (C1) · lector lw_lector · ENVUELVE public.facturas_pendiente_equipo()
--    Pantalla: Cobros › Facturas, intranet/v4/facturas/index.html:3 `data-herramienta="facturas"` (guard.js:351); la
--    lista de la pantalla (intranet/facturas/index.html) pide facturas_pendiente_equipo(). Comprobación copiada:
--    public.puede('facturas').
--    pendiente = el de la pantalla: facturas_pendiente_equipo() = total - factura_aplicado(id) (recibís vivos
--    aplicados; cuerpo vivo, 16-oct). Las columnas de cada factura salen de public.facturas con su RLS, nunca de
--    facturas_equipo() (prohibida). De `datos` solo se lee fields->>'fecha_vencimiento' y solo si tiene forma de fecha.
--    Medido: 2,4 ms. Devuelve por factura_id: número, sociedad_id, contrato_id, proyecto_id, moneda, total, cobrado,
--    pendiente, fecha_emision, vencimiento. Solo pendiente > 0.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_facturas_no_cobradas(p_sociedad text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
begin
  v_p := privado.mcp_puerta('facturas_no_cobradas', jsonb_build_object('p_sociedad', p_sociedad));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if p_sociedad is not null and p_sociedad !~ '^[a-z0-9_]{1,64}$' then
    perform privado.mcp_cierra(v_l, 0, 'argumento_invalido');
    return jsonb_build_object('error', 'argumento_invalido');
  end if;
  if not public.puede('facturas') then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_facturas_no_cobradas_lee(p_sociedad);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return v_r - 'filas';
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 8. recibis_sin_aplicar (C2) · lector lw_lector
--    Pantalla: Cobros › Recibos, intranet/v4/recibos/index.html:3 `data-herramienta="recibos"` (guard.js:351).
--    Comprobación copiada: public.puede('recibos').
--    «Sin aplicar» = el `a_cuenta` de contrato_saldo (cuerpo vivo, 16-oct; mismo sumando que _contrato_cobrado_interno):
--    total del recibí menos lo aplicado a facturas CON contrato y sin anular. Aquí por recibí y no por venta, y sin
--    llamar a contrato_saldo por cada venta.
--    Leído con la RLS de facturas y recibi_aplicaciones: para un admin la cifra es la de contrato_saldo. Para un agente
--    que ve el recibí pero NO la factura a la que se aplicó, esa aplicación no se resta (sale más «sin aplicar» que en
--    contrato_saldo, que es DEFINER de postgres): ver el informe de P2.
--    Medido: 1,3 ms. Devuelve por recibi_id: número, sociedad_id, contrato_id, moneda, total, aplicado, sin_aplicar,
--    fecha_emision. Solo sin_aplicar > 0.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_recibis_sin_aplicar(p_sociedad text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
begin
  v_p := privado.mcp_puerta('recibis_sin_aplicar', jsonb_build_object('p_sociedad', p_sociedad));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if p_sociedad is not null and p_sociedad !~ '^[a-z0-9_]{1,64}$' then
    perform privado.mcp_cierra(v_l, 0, 'argumento_invalido');
    return jsonb_build_object('error', 'argumento_invalido');
  end if;
  if not public.puede('recibos') then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_recibis_sin_aplicar_lee(p_sociedad);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return v_r - 'filas';
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 9. ventas_facturadas_de_mas (C3) · lee como POSTGRES
--    Pantalla: Cobros › Facturas, ficha de una factura: intranet/v4/assets/datos.js:2091 pinta el saldo de su contrato
--    con contrato_saldo() (también el editor de facturas, editores.js:2848-2865); la página es
--    intranet/v4/facturas/index.html:3 `data-herramienta="facturas"`. Comprobación copiada: public.puede('facturas')
--    + POR VENTA la puerta literal de contrato_saldo (cuerpo vivo, 16-oct):
--      es_super_admin_de(empresa_de_contrato(id)) or (es_agente() and puede_ver_contrato(id)).
--    Por qué postgres: el precio de una venta lo da public._cadena_saldo → _cadena_saldo_en → _venta_obras_vigentes
--    (la regla de qué obra cuenta, 20261015101833_precio_cadena_vigente), y ninguna la ejecuta authenticated ni
--    lw_lector (medido el 16-oct). Copiar esa regla en un agregado nuevo sería la cuarta copia de la regla que el
--    15-oct se dejó en una sola (comentario de _venta_obras_vigentes). Se llama a _cadena_saldo, el núcleo que usa
--    contrato_saldo, una vez por raíz visible: no a contrato_saldo, que además arma las líneas de cada factura.
--    Equivalencia, línea a línea con contrato_saldo(raíz):
--      precio = v_s.precio, sin_precio = v_s.sin_precio, facturado = v_s.facturado;
--      facturado_de_mas = case when v_s.sin_precio or coalesce(v_s.precio,0) <= 0 then null
--                              else greatest(v_s.facturado - v_s.precio, 0) end   ← literal de contrato_saldo.
--    contrato_saldo(hijo) devuelve lo mismo que contrato_saldo(raíz) (_cadena_saldo sube a la raíz), así que basta con
--    las raíces (contrato_padre_id is null). La RLS no aplica (postgres): el único filtro es la puerta por venta, la
--    misma con la que contrato_saldo contesta 42501.
--    Medido: 7,0 ms la copia en línea de _cadena_saldo_en + _venta_obras_vigentes sobre las 176 raíces (axw_lectura no
--    ejecuta las funciones); la llamada real añade una invocación plpgsql por raíz y puede_ver_contrato por raíz.
--    Devuelve por contrato_raiz_id: número, moneda, precio, facturado, facturado_de_mas, sin_precio. Salen las que
--    tienen facturado_de_mas > 0 y las «sin tope» (sin precio y ya facturadas).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_ventas_facturadas_de_mas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_d jsonb; v_n int;
begin
  v_p := privado.mcp_puerta('ventas_facturadas_de_mas', '{}'::jsonb);
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if public.uid_sesion() is null or not public.puede('facturas') then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'contrato_raiz_id', z.id, 'numero', z.raiz_numero, 'moneda', z.moneda, 'precio', z.precio,
           'facturado', z.facturado, 'facturado_de_mas', z.de_mas, 'sin_precio', z.sin_precio)
           order by z.rn) filter (where z.rn <= 500), '[]'::jsonb),
         count(*)::int
    into v_d, v_n
    from (select y.*, row_number() over (order by y.de_mas desc nulls last, y.raiz_numero, y.id) as rn
            from (select c.id, s.raiz_numero, s.moneda, s.precio, s.sin_precio, s.facturado,
                         case when s.sin_precio or coalesce(s.precio, 0) <= 0 then null
                              else greatest(s.facturado - s.precio, 0) end as de_mas
                    from public.contratos c
                    cross join lateral public._cadena_saldo(c.id, null) s
                   where c.contrato_padre_id is null
                     and (public.es_super_admin_de(public.empresa_de_contrato(c.id))
                          or (public.es_agente() and public.puede_ver_contrato(c.id)))) y
           where y.de_mas > 0 or (y.sin_precio and y.facturado > 0)) z;
  perform privado.mcp_cierra(v_l, least(v_n, 500), 'ok');
  return jsonb_build_object('datos', v_d, 'recortado', v_n > 500);
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 10. movimientos_mes_sociedad (C4) · lector lw_lector · cada parte con la puerta de SU pantalla
--    · facturas emitidas: Cobros › Facturas (v4/facturas/index.html:3) → public.puede('facturas');
--    · recibís: Cobros › Recibos (v4/recibos/index.html:3) → public.puede('recibos');
--    · gastos: Gastos (v4/gastos/index.html:3 data-rol="admin" + data-herramienta="gastos") → public.gastos_acceso(),
--      la misma que exige gastos_panel_datos (cuerpo vivo: «if not public.gastos_acceso() then raise 42501»);
--    · movimientos conciliados: Tesorería (v4/bancos/index.html:3 data-rol="admin" + data-herramienta="bancos") →
--      public.bancos_acceso(), la de panel_bancos_datos («if not public.bancos_acceso() then raise 42501»).
--    Sin ninguna de las cuatro: «sin_permiso». La parte que no se puede ver sale null y su nombre en `sin_permiso`.
--    No se envuelven panel_bancos_datos ni gastos_panel_datos: paginan por id/fecha sin filtro de mes (1.000 por
--    página), traen concepto, referencia, nota, ignorado_motivo, notas y los correos y teléfonos de proveedores, y
--    lanzan 42501 en vez de devolver la denegación (que borraría la fila del registro).
--    Sociedad de un movimiento: bancos_movimientos no tiene sociedad (solo cuenta_clave → cuentas_bancarias.empresa,
--    que es la EMPRESA, no la sociedad emisora). Se usa la sociedad del documento conciliado: tipo 'recibi' →
--    facturas.sociedad; 'gasto' y 'pph' → gastos.sociedad (ref_id); el resto de tipos (comision, traspaso,
--    comision_bancaria, retencion_sufrida, otro) no tiene documento con sociedad y sale con sociedad_id null (y no
--    sale si se pide una sociedad). Medido: 0,7 ms (hoy 0 gastos y 0 movimientos en la viva).
--    Devuelve por sociedad_id y moneda del mes: facturas (número e importe), recibís, gastos y movimientos conciliados;
--    nunca el concepto bancario.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.mcp_movimientos_mes_sociedad(p_mes date default null, p_sociedad text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_p jsonb; v_l bigint; v_r jsonb;
  v_d0 date := date_trunc('month', coalesce(p_mes, (now() at time zone 'Asia/Makassar')::date))::date;
  v_vf boolean; v_vr boolean; v_vg boolean; v_vb boolean;
begin
  v_p := privado.mcp_puerta('movimientos_mes_sociedad', jsonb_build_object('p_mes', p_mes, 'p_sociedad', p_sociedad));
  if not coalesce((v_p->>'ok')::boolean, false) then
    return jsonb_build_object('error', coalesce(v_p->>'resultado', 'no_disponible'));
  end if;
  v_l := (v_p->>'llamada')::bigint;
  if p_sociedad is not null and p_sociedad !~ '^[a-z0-9_]{1,64}$' then
    perform privado.mcp_cierra(v_l, 0, 'argumento_invalido');
    return jsonb_build_object('error', 'argumento_invalido');
  end if;
  v_vf := coalesce(public.puede('facturas'), false);
  v_vr := coalesce(public.puede('recibos'), false);
  v_vg := coalesce(public.gastos_acceso(), false);
  v_vb := coalesce(public.bancos_acceso(), false);
  if not (v_vf or v_vr or v_vg or v_vb) then
    perform privado.mcp_cierra(v_l, 0, 'sin_permiso');
    return jsonb_build_object('error', 'sin_permiso');
  end if;
  v_r := public.mcp_movimientos_mes_sociedad_lee(v_d0, (v_d0 + interval '1 month')::date, p_sociedad, v_vf, v_vr, v_vg, v_vb);
  perform privado.mcp_cierra(v_l, (v_r->>'filas')::int, 'ok');
  return (v_r - 'filas') || jsonb_build_object('mes', to_char(v_d0, 'YYYY-MM'));
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Dueños, permisos y grants (sin ventana: todo en este fichero)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Las dos funciones de la pantalla de Facturas que envuelven los lectores 3 y 7: authenticated ya las ejecuta, y las dos
-- son STABLE (el invariante «lw_lector es un lector» no admite EXECUTE de lw_lector en una volátil de public).
grant execute on function public.facturas_pendiente_equipo() to lw_lector;
grant execute on function public.factura_aplicado(uuid) to lw_lector;

-- Lectores: dueño lw_lector. ALTER OWNER exige CREATE en el esquema al nuevo dueño: se da y se quita aquí (law338_l3).
grant create on schema public to lw_lector;
alter function public.mcp_parcelas_libres_lee(uuid) owner to lw_lector;
alter function public.mcp_comisiones_pendientes_lee() owner to lw_lector;
alter function public.mcp_cobros_por_proyecto_mes_lee(date, date) owner to lw_lector;
alter function public.mcp_contratos_sin_firmar_lee(uuid) owner to lw_lector;
alter function public.mcp_resumen_semana_lee(date, date) owner to lw_lector;
alter function public.mcp_facturas_no_cobradas_lee(text) owner to lw_lector;
alter function public.mcp_recibis_sin_aplicar_lee(text) owner to lw_lector;
alter function public.mcp_movimientos_mes_sociedad_lee(date, date, text, boolean, boolean, boolean, boolean) owner to lw_lector;
revoke create on schema public from lw_lector;
-- Nadie más los ejecuta: solo su dueño (y postgres, que hereda de lw_lector, law338_l0:31).
revoke all on function public.mcp_parcelas_libres_lee(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mcp_comisiones_pendientes_lee() from public, anon, authenticated, service_role;
revoke all on function public.mcp_cobros_por_proyecto_mes_lee(date, date) from public, anon, authenticated, service_role;
revoke all on function public.mcp_contratos_sin_firmar_lee(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mcp_resumen_semana_lee(date, date) from public, anon, authenticated, service_role;
revoke all on function public.mcp_facturas_no_cobradas_lee(text) from public, anon, authenticated, service_role;
revoke all on function public.mcp_recibis_sin_aplicar_lee(text) from public, anon, authenticated, service_role;
revoke all on function public.mcp_movimientos_mes_sociedad_lee(date, date, text, boolean, boolean, boolean, boolean) from public, anon, authenticated, service_role;

-- Puertas: dueño postgres, EXECUTE solo a ia_puente_rol.
alter function privado.mcp_parcelas_libres(uuid) owner to postgres;
alter function privado.mcp_comisiones_pendientes() owner to postgres;
alter function privado.mcp_cobros_por_proyecto_mes(date) owner to postgres;
alter function privado.mcp_cambios_estado_semana(date) owner to postgres;
alter function privado.mcp_contratos_sin_firmar(uuid) owner to postgres;
alter function privado.mcp_resumen_semana(date) owner to postgres;
alter function privado.mcp_facturas_no_cobradas(text) owner to postgres;
alter function privado.mcp_recibis_sin_aplicar(text) owner to postgres;
alter function privado.mcp_ventas_facturadas_de_mas() owner to postgres;
alter function privado.mcp_movimientos_mes_sociedad(date, text) owner to postgres;
revoke all on function privado.mcp_parcelas_libres(uuid) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_comisiones_pendientes() from public, anon, authenticated, service_role;
revoke all on function privado.mcp_cobros_por_proyecto_mes(date) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_cambios_estado_semana(date) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_contratos_sin_firmar(uuid) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_resumen_semana(date) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_facturas_no_cobradas(text) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_recibis_sin_aplicar(text) from public, anon, authenticated, service_role;
revoke all on function privado.mcp_ventas_facturadas_de_mas() from public, anon, authenticated, service_role;
revoke all on function privado.mcp_movimientos_mes_sociedad(date, text) from public, anon, authenticated, service_role;
grant execute on function privado.mcp_parcelas_libres(uuid) to ia_puente_rol;
grant execute on function privado.mcp_comisiones_pendientes() to ia_puente_rol;
grant execute on function privado.mcp_cobros_por_proyecto_mes(date) to ia_puente_rol;
grant execute on function privado.mcp_cambios_estado_semana(date) to ia_puente_rol;
grant execute on function privado.mcp_contratos_sin_firmar(uuid) to ia_puente_rol;
grant execute on function privado.mcp_resumen_semana(date) to ia_puente_rol;
grant execute on function privado.mcp_facturas_no_cobradas(text) to ia_puente_rol;
grant execute on function privado.mcp_recibis_sin_aplicar(text) to ia_puente_rol;
grant execute on function privado.mcp_ventas_facturadas_de_mas() to ia_puente_rol;
grant execute on function privado.mcp_movimientos_mes_sociedad(date, text) to ia_puente_rol;

-- VUELTA ATRÁS (a mano, solo construye: no hay datos que perder):
--   drop function privado.mcp_parcelas_libres(uuid), privado.mcp_comisiones_pendientes(),
--     privado.mcp_cobros_por_proyecto_mes(date), privado.mcp_cambios_estado_semana(date),
--     privado.mcp_contratos_sin_firmar(uuid), privado.mcp_resumen_semana(date), privado.mcp_facturas_no_cobradas(text),
--     privado.mcp_recibis_sin_aplicar(text), privado.mcp_ventas_facturadas_de_mas(),
--     privado.mcp_movimientos_mes_sociedad(date, text);
--   drop function public.mcp_parcelas_libres_lee(uuid), public.mcp_comisiones_pendientes_lee(),
--     public.mcp_cobros_por_proyecto_mes_lee(date, date), public.mcp_contratos_sin_firmar_lee(uuid),
--     public.mcp_resumen_semana_lee(date, date), public.mcp_facturas_no_cobradas_lee(text),
--     public.mcp_recibis_sin_aplicar_lee(text),
--     public.mcp_movimientos_mes_sociedad_lee(date, date, text, boolean, boolean, boolean, boolean);
--   revoke execute on function public.facturas_pendiente_equipo(), public.factura_aplicado(uuid) from lw_lector;

-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- DESPACHO (sustituye el stub de P1; conserva su dueño ia_puente_rol y su ACL vacía: «create or replace» no los cambia).
-- Lista CASE literal: nunca format()/EXECUTE sobre el nombre (#395, punto 2). Argumentos TIPADOS y con nombre exacto por
-- herramienta: una clave de más, una fecha o un uuid mal formados → error sin llamar a la puerta (no cuenta en el tope).
-- Los nombres y esquemas de entrada de cara al asistente viven en supabase/functions/mcp/herramientas.js (mismas claves).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function privado.ia_despacha(p_herramienta text, p_args jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  a jsonb := coalesce(p_args, '{}'::jsonb);
  permitidas text[];
  v_uuid uuid; v_fecha date; v_soc text; k text;
begin
  if jsonb_typeof(a) <> 'object' then return jsonb_build_object('error', 'argumento_invalido'); end if;
  permitidas := case p_herramienta
    when 'parcelas_libres'          then array['proyecto_id']
    when 'comisiones_pendientes'    then array[]::text[]
    when 'cobros_por_proyecto_mes'  then array['mes']
    when 'cambios_estado_semana'    then array['hasta']
    when 'contratos_sin_firmar'     then array['proyecto_id']
    when 'resumen_semana'           then array['hasta']
    when 'facturas_no_cobradas'     then array['sociedad']
    when 'recibis_sin_aplicar'      then array['sociedad']
    when 'ventas_facturadas_de_mas' then array[]::text[]
    when 'movimientos_mes_sociedad' then array['mes', 'sociedad']
  end;
  if permitidas is null then return jsonb_build_object('error', 'herramienta_desconocida'); end if;
  for k in select jsonb_object_keys(a) loop
    if not (k = any (permitidas)) then return jsonb_build_object('error', 'argumento_invalido', 'argumento', left(k, 40)); end if;
  end loop;
  -- tipos: uuid y fecha ISO por regex ANTES del cast; la sociedad es su clave (sociedades.clave, su id)
  if a ? 'proyecto_id' and jsonb_typeof(a -> 'proyecto_id') <> 'null' then
    if coalesce(a ->> 'proyecto_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', 'argumento_invalido', 'argumento', 'proyecto_id');
    end if;
    v_uuid := (a ->> 'proyecto_id')::uuid;
  end if;
  k := coalesce(a ->> 'mes', a ->> 'hasta');
  if k is not null then
    if k !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'argumento_invalido', 'argumento', 'fecha'); end if;
    begin
      v_fecha := k::date;
    exception when others then
      return jsonb_build_object('error', 'argumento_invalido', 'argumento', 'fecha');
    end;
  end if;
  if a ? 'sociedad' and jsonb_typeof(a -> 'sociedad') <> 'null' then
    v_soc := a ->> 'sociedad';
    if v_soc !~ '^[a-z0-9_]{1,40}$' then return jsonb_build_object('error', 'argumento_invalido', 'argumento', 'sociedad'); end if;
  end if;
  case p_herramienta
    when 'parcelas_libres'          then return privado.mcp_parcelas_libres(v_uuid);
    when 'comisiones_pendientes'    then return privado.mcp_comisiones_pendientes();
    when 'cobros_por_proyecto_mes'  then return privado.mcp_cobros_por_proyecto_mes(v_fecha);
    when 'cambios_estado_semana'    then return privado.mcp_cambios_estado_semana(v_fecha);
    when 'contratos_sin_firmar'     then return privado.mcp_contratos_sin_firmar(v_uuid);
    when 'resumen_semana'           then return privado.mcp_resumen_semana(v_fecha);
    when 'facturas_no_cobradas'     then return privado.mcp_facturas_no_cobradas(v_soc);
    when 'recibis_sin_aplicar'      then return privado.mcp_recibis_sin_aplicar(v_soc);
    when 'ventas_facturadas_de_mas' then return privado.mcp_ventas_facturadas_de_mas();
    when 'movimientos_mes_sociedad' then return privado.mcp_movimientos_mes_sociedad(v_fecha, v_soc);
    else return jsonb_build_object('error', 'herramienta_desconocida');
  end case;
end $$;
