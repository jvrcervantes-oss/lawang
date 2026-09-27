-- LAW-338 · bloque L1 (piloto) — la pantalla /v4/bancos/ lee por UNA RPC del servidor.
-- Diseño y revisiones previas #128 (Seguridad + Datos): encargos/20260927_lawang_law338_lecturas_bloques.md
--
-- public.panel_bancos_datos(p_anio, p_limit, p_despues) sustituye las 8 lecturas directas de
-- intranet/v4/assets/panel-bancos.js (bancos_movimientos, bancos_conciliacion, cuentas_bancarias,
-- bancos_perfiles, bancos_resumen, facturas_equipo→recibís, gastos, comisiones_devengadas pagadas).
--
-- Por qué así (y no copiando filtros):
--  · SECURITY DEFINER con dueño lw_lector (sin BYPASSRLS): dentro, la RLS se evalúa como lw_lector y
--    auth.uid() sigue siendo el usuario de la sesión ⇒ mismas filas que hoy; la regla vive solo en la policy.
--  · El cuerpo no nombra `auth` (lw_lector no tiene USAGE, Seguridad #128): usa public.uid_sesion().
--  · Sin permiso NO lanza: devuelve lo mismo que hoy da la lectura directa (listas vacías por RLS,
--    cuentas_bancarias con su policy `true`, resumen null). Lanzar cambiaría la pantalla, que distingue
--    «tu usuario no ve los bancos» por resumen == null. Solo lanza sin sesión (42501, falla en voz alta).
--  · Recibís: se lee public.facturas directamente, NO facturas_equipo(): esa es INVOKER y VOLATILE (la pata
--    (d) del invariante de salud prohíbe a lw_lector ejecutar funciones no-stable) y su único filtro extra,
--    es_agente(), ya está dentro de la policy «agentes leen sus facturas». Paridad medida por md5 de ids.
--  · bancos_resumen(int): se llama por dentro con EXECUTE a lw_lector. Es DEFINER-postgres (salta la RLS),
--    pero su gate es exactamente es_admin() and puede('bancos'), el mismo qual de las 3 policies bancarias,
--    y es STABLE: no mete filas que el usuario no vea hoy.
--  · Paginación: solo crecen sin techo los movimientos (y sus líneas). Cursor por id (uuid, mismo orden
--    que el `order('id')` de la paginación anterior), tope 1000 por página; las líneas de conciliación
--    vienen por movimiento_id de la página (FK bancos_conciliacion_movimiento_id_fkey: ninguna huérfana).
--    El resto de listas va entero solo en la primera página, con tope 5000 y `recortado` si se toca —
--    la pantalla lo dice, no se calla un recorte.
--  · Columnas explícitas: solo las que pinta la pantalla.

create or replace function public.panel_bancos_datos(
  p_anio int default null,
  p_limit int default 1000,
  p_despues uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lim  int := least(greatest(coalesce(p_limit, 1000), 1), 1000);
  v_tope int := 5000;
  v_anio int := coalesce(p_anio, extract(year from current_date)::int);
  v_ids  uuid[];
  v_movs jsonb;
  v_res  jsonb;
  v_rec  text[] := '{}';
  v_cuentas jsonb; v_perfiles jsonb; v_recibis jsonb; v_gastos jsonb; v_comis jsonb;
  v_n int;
begin
  if public.uid_sesion() is null then
    raise exception 'panel_bancos_datos: sin sesión' using errcode = '42501';
  end if;

  -- movimientos de esta página (RLS de bancos_movimientos como lw_lector)
  select coalesce(array_agg(m.id order by m.id), '{}'),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'cuenta_clave', m.cuenta_clave, 'fecha', m.fecha, 'fecha_valor', m.fecha_valor,
           'concepto', m.concepto, 'referencia', m.referencia, 'importe', m.importe, 'moneda', m.moneda,
           'saldo', m.saldo, 'orden', m.orden, 'conciliado', m.conciliado, 'estado', m.estado,
           'ignorado_motivo', m.ignorado_motivo) order by m.id), '[]'::jsonb)
    into v_ids, v_movs
    from (select b.id, b.cuenta_clave, b.fecha, b.fecha_valor, b.concepto, b.referencia, b.importe, b.moneda,
                 b.saldo, b.orden, b.conciliado, b.estado, b.ignorado_motivo
            from public.bancos_movimientos b
           where p_despues is null or b.id > p_despues
           order by b.id limit v_lim) m;

  v_res := jsonb_build_object(
    'movimientos', v_movs,
    'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', c.id, 'movimiento_id', c.movimiento_id, 'tipo', c.tipo, 'ref_id', c.ref_id,
                 'importe_mov', c.importe_mov, 'importe_doc', c.importe_doc, 'moneda_doc', c.moneda_doc,
                 'tipo_cambio', c.tipo_cambio, 'naturaleza', c.naturaleza, 'nota', c.nota) order by c.id), '[]'::jsonb)
                 from public.bancos_conciliacion c
                where c.anulado_en is null and c.movimiento_id = any(v_ids)),
    'siguiente', case when cardinality(v_ids) = v_lim then v_ids[v_lim] end);

  if p_despues is not null then
    return v_res;
  end if;

  -- primera página: el resto de lo que pinta la pantalla
  select coalesce(jsonb_agg(jsonb_build_object(
           'clave', cb.clave, 'label', cb.label, 'banco', cb.banco, 'es_escrow', cb.es_escrow,
           'es_propia', cb.es_propia, 'activa', cb.activa, 'orden', cb.orden) order by cb.orden, cb.clave), '[]'::jsonb),
         count(*)
    into v_cuentas, v_n
    from (select x.clave, x.label, x.banco, x.es_escrow, x.es_propia, x.activa, x.orden
            from public.cuentas_bancarias x order by orden, clave limit v_tope) cb;
  if v_n = v_tope then v_rec := v_rec || 'cuentas'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('cuenta_clave', p.cuenta_clave, 'mapeo', p.mapeo) order by p.cuenta_clave), '[]'::jsonb),
         count(*)
    into v_perfiles, v_n
    from (select x.cuenta_clave, x.mapeo from public.bancos_perfiles x order by cuenta_clave limit v_tope) p;
  if v_n = v_tope then v_rec := v_rec || 'perfiles'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'numero', f.numero, 'total', f.total, 'moneda', f.moneda,
           'fecha_emision', f.fecha_emision, 'created_at', f.created_at, 'proyecto_nombre', f.proyecto_nombre) order by f.id), '[]'::jsonb),
         count(*)
    into v_recibis, v_n
    from (select x.id, x.numero, x.total, x.moneda, x.fecha_emision, x.created_at, x.proyecto_nombre
            from public.facturas x
           where x.tipo = 'recibi' and x.anulada is not true
           order by x.id limit v_tope) f;
  if v_n = v_tope then v_rec := v_rec || 'recibis'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id, 'concepto', g.concepto, 'referencia', g.referencia, 'total', g.total,
           'pph_retenido', g.pph_retenido, 'pph_ingresado_el', g.pph_ingresado_el, 'moneda', g.moneda,
           'estado', g.estado, 'pagado_el', g.pagado_el) order by g.id), '[]'::jsonb),
         count(*)
    into v_gastos, v_n
    from (select x.id, x.concepto, x.referencia, x.total, x.pph_retenido, x.pph_ingresado_el, x.moneda, x.estado, x.pagado_el
            from public.gastos x where x.estado <> 'anulado' order by x.id limit v_tope) g;
  if v_n = v_tope then v_rec := v_rec || 'gastos'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'importe', d.importe, 'importe_ajustado', d.importe_ajustado,
           'moneda', d.moneda, 'pagado_en', d.pagado_en) order by d.id), '[]'::jsonb),
         count(*)
    into v_comis, v_n
    from (select x.id, x.importe, x.importe_ajustado, x.moneda, x.pagado_en
            from public.comisiones_devengadas x where x.estado = 'pagada' order by x.id limit v_tope) d;
  if v_n = v_tope then v_rec := v_rec || 'comisiones'; end if;

  return v_res || jsonb_build_object(
    'cuentas', v_cuentas,
    'perfiles', v_perfiles,
    'resumen', public.bancos_resumen(v_anio),
    'recibis', v_recibis,
    'gastos', v_gastos,
    'comisiones', v_comis,
    'recortado', to_jsonb(v_rec));
end $$;

-- bancos_resumen por dentro (ver cabecera: stable y mismo gate que las policies)
grant execute on function public.bancos_resumen(int) to lw_lector;

-- dueño lw_lector (necesita CREATE en public solo durante el ALTER; #128 Datos punto 1)
grant create on schema public to lw_lector;
alter function public.panel_bancos_datos(int, int, uuid) owner to lw_lector;
revoke create on schema public from lw_lector;

revoke all on function public.panel_bancos_datos(int, int, uuid) from public, anon, service_role;
grant execute on function public.panel_bancos_datos(int, int, uuid) to authenticated;

-- comprobación en la misma migración: si el dueño o los permisos no son los esperados, no se aplica
do $$
declare v_acl text; v_dueno text;
begin
  select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno
    from pg_proc p where p.oid = 'public.panel_bancos_datos(int, int, uuid)'::regprocedure;
  if v_dueno <> 'lw_lector' then raise exception 'panel_bancos_datos: dueño % (esperado lw_lector)', v_dueno; end if;
  if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
    raise exception 'panel_bancos_datos: proacl % (esperado lw_lector + authenticated)', v_acl;
  end if;
  if has_schema_privilege('lw_lector', 'public', 'create') then raise exception 'lw_lector conserva CREATE en public'; end if;
end $$;
