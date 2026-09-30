-- VOLCADO DE PRODUCCION (Supabase Lawang) del 2026-09-30: pg_get_functiondef(public.comision_trazabilidad).
-- NO es una migracion: no se aplica. Referencia para construir sobre el cuerpo VIVO (encargo 20260930_lawang_equipos_venta_asistente, F1).
-- Nota: el cuerpo vivo usa finales de linea CRLF; aqui van normalizados a LF (la huella se comprueba sin \r).
-- ---- fin cabecera ----
CREATE OR REPLACE FUNCTION public.comision_trazabilidad(p_devengo uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), ''));
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- mismo criterio que la policy de lectura de comisiones_devengadas
  if not found or not (
       (public.es_admin() and public.puede('comisiones_reparto'))
       or lower(d.beneficiario_email) = v_yo
       or (d.nivel in ('closer', 'setter', 'team_lead')
           and public.es_manager_de_equipo(public._equipo_de_condicion_comision(d.condicion_id)))) then
    raise exception 'No encuentro esa comisión entre las que puedes ver' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'venta', d.contrato_raiz_id,
    'base_hoy', public._comisiones_precio_total(d.contrato_raiz_id),
    'operacion', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'numero', c.numero, 'tipo', c.tipo, 'precio_total', c.precio_total, 'moneda', c.moneda,
               'firmado', coalesce(c.bloqueado, false), 'fecha_firma', c.fecha_firma,
               'liberado', c.liberado_en is not null, 'es_raiz', c.id = d.contrato_raiz_id,
               'cuenta_en_base', coalesce(c.bloqueado, false) and c.liberado_en is null
                                 and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%'))
             order by (c.id = d.contrato_raiz_id) desc, c.created_at), '[]'::jsonb)
        from public.contratos c
       where c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id),
    'parcelas', (
      select coalesce(jsonb_agg(jsonb_build_object('codigo', u.codigo, 'proyecto', u.proyecto) order by u.codigo_orden, u.codigo), '[]'::jsonb)
        from public.unidades u where u.contrato_id = d.contrato_raiz_id),
    'solicitud', (
      select jsonb_build_object('numero', sp.numero, 'estado', sp.estado, 'importe', sp.importe, 'moneda', sp.moneda)
        from public.solicitudes_pago sp where sp.id = d.solicitud_id),
    'diferencias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', x.id, 'numero', x.numero, 'importe', x.importe, 'estado', x.estado, 'motivo', x.motivo,
               'base_antes', x.base_antes, 'base_despues', x.base_despues, 'vigente', x.importe_vigente,
               'nuevo', x.importe_nuevo, 'origen', x.origen, 'provocado_por', x.provocado_por,
               'resuelto_por', x.resuelto_por, 'resuelto_en', x.resuelto_en, 'resolucion_motivo', x.resolucion_motivo,
               'solicitud', (select jsonb_build_object('numero', sp.numero, 'estado', sp.estado)
                               from public.solicitudes_pago sp where sp.id = x.solicitud_id),
               'creada', x.created_at) order by x.created_at), '[]'::jsonb)
        from public.comisiones_diferencias x where x.devengo_id = d.id),
    'historial', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'en', l.creado_en, 'tabla', l.tabla, 'accion', l.accion, 'antes', l.importe_antes, 'despues', l.importe_despues,
               'estado_antes', l.estado_antes, 'estado_despues', l.estado_despues, 'motivo', l.motivo, 'quien', l.actor_email)
             order by l.creado_en), '[]'::jsonb)
        from public.comisiones_ajustes_log l
       where (l.tabla = 'comisiones_devengadas' and l.fila_id = d.id)
          or (l.tabla = 'solicitudes_pago' and l.fila_id = d.solicitud_id)
          or (l.tabla = 'comisiones_diferencias' and l.fila_id in (select x.id from public.comisiones_diferencias x where x.devengo_id = d.id)))
  );
end $function$
