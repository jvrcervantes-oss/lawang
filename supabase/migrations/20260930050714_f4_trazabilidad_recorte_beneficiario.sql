-- F4 · arreglo del revisor de código (30-sep-2026): comision_trazabilidad recorta lo que ve el BENEFICIARIO (resuelve LAW-465).
--
-- Porqué: tras 20260930041708 el closer/beneficiario seguía recibiendo por esta RPC lo que la SELECT por columnas de
-- comisiones_diferencias (20260930044759) ya le niega: diferencias.origen (precio antes/después y quién editó el contrato),
-- provocado_por, resuelto_por, historial.quien (actor_email) y operacion.precio_total de los demás contratos de la venta.
-- Un grant recortado en la tabla no sirve si una DEFINER lo devuelve entero.
--
-- Recorte copiado del ERP maestro (erp/migraciones/20260930140000_b3b_comisiones_recalculo_diferencia.sql, §11):
--   · completa  = admin con Reparto, o manager del equipo de la condición / del equipo congelado en la venta
--                 (niveles closer/setter/team_lead) → lo ve todo, como antes.
--   · recortada = el beneficiario (y solo si comision_visible le deja ver su comisión): sin contratos ni parcelas de la
--                 venta, sin correos ajenos (provocó, resolvió, quién actuó) y del origen solo la fecha y QUÉ campo cambió.
-- Quién entra sigue siendo comision_visible (el mismo predicado que la RLS de comisiones_devengadas). Cuerpo de partida: el
-- VIVO de 20260930041708 (pg_get_functiondef leído el 30-sep), no el del maestro: la visibilidad de Lawang es la suya.
-- Llamador: proyectos/Lawang/intranet/v4/assets/datos.js (sb.rpc('comision_trazabilidad')) — ficha de la comisión.

create or replace function public.comision_trazabilidad(p_devengo uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), '')); v_completa boolean;
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_yo = '' then raise exception 'Tu sesión no trae correo: no se puede ver la trazabilidad' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- F4: el criterio de entrada es comision_visible, el mismo que la RLS de comisiones_devengadas
  if not found or not public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id) then
    raise exception 'No encuentro esa comisión entre las que puedes ver' using errcode = '42501';
  end if;
  v_completa := (public.es_admin() and public.puede('comisiones_reparto'))
                or (d.nivel in ('closer', 'setter', 'team_lead') and (
                      public.es_manager_de_equipo((select c.equipo_id from public.condiciones_comision c where c.id = d.condicion_id))
                   or public.es_manager_de_equipo((select k.equipo_id from public.contrato_closer k where k.contrato_id = d.contrato_raiz_id))));

  return jsonb_build_object(
    'venta', d.contrato_raiz_id,
    'completa', v_completa,
    'base_hoy', public._comisiones_precio_total(d.contrato_raiz_id),
    'operacion', case when not v_completa then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'numero', c.numero, 'tipo', c.tipo, 'precio_total', c.precio_total, 'moneda', c.moneda,
               'firmado', coalesce(c.bloqueado, false), 'fecha_firma', c.fecha_firma,
               'liberado', c.liberado_en is not null, 'es_raiz', c.id = d.contrato_raiz_id,
               'cuenta_en_base', coalesce(c.bloqueado, false) and c.liberado_en is null
                                 and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%'))
             order by (c.id = d.contrato_raiz_id) desc, c.created_at), '[]'::jsonb)
        from public.contratos c
       where c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id) end,
    'parcelas', case when not v_completa then '[]'::jsonb else (
      select coalesce(jsonb_agg(jsonb_build_object('codigo', u.codigo, 'proyecto', u.proyecto) order by u.codigo_orden, u.codigo), '[]'::jsonb)
        from public.unidades u where u.contrato_id = d.contrato_raiz_id) end,
    'solicitud', (
      select jsonb_build_object('numero', sp.numero, 'estado', sp.estado, 'importe', sp.importe, 'moneda', sp.moneda)
        from public.solicitudes_pago sp where sp.id = d.solicitud_id),
    'diferencias', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', x.id, 'numero', x.numero, 'importe', x.importe, 'estado', x.estado, 'motivo', x.motivo,
               'base_antes', x.base_antes, 'base_despues', x.base_despues, 'vigente', x.importe_vigente,
               'nuevo', x.importe_nuevo,
               'origen', case when v_completa then x.origen
                              else jsonb_build_object('en', x.origen->'en', 'cambio', coalesce((
                                     select jsonb_agg(k.campo order by k.campo)
                                       from (values ('precio_total'), ('firmado'), ('padre'), ('tipo'), ('liberado'), ('moneda')) k(campo)
                                      where x.origen->k.campo->'antes' is distinct from x.origen->k.campo->'despues'
                                        and x.origen ? k.campo), '[]'::jsonb)) end,
               'provocado_por', case when v_completa then x.provocado_por end,
               'resuelto_por', case when v_completa then x.resuelto_por end,
               'resuelto_en', x.resuelto_en, 'resolucion_motivo', x.resolucion_motivo,
               'solicitud', (select jsonb_build_object('numero', sp.numero, 'estado', sp.estado)
                               from public.solicitudes_pago sp where sp.id = x.solicitud_id),
               'creada', x.created_at) order by x.created_at), '[]'::jsonb)
        from public.comisiones_diferencias x where x.devengo_id = d.id),
    'historial', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'en', l.creado_en, 'tabla', l.tabla, 'accion', l.accion, 'antes', l.importe_antes, 'despues', l.importe_despues,
               'estado_antes', l.estado_antes, 'estado_despues', l.estado_despues, 'motivo', l.motivo,
               'quien', case when v_completa then l.actor_email end)
             order by l.creado_en), '[]'::jsonb)
        from public.comisiones_ajustes_log l
       where (l.tabla = 'comisiones_devengadas' and l.fila_id = d.id)
          or (l.tabla = 'solicitudes_pago' and l.fila_id = d.solicitud_id)
          or (l.tabla = 'comisiones_diferencias' and l.fila_id in (select x.id from public.comisiones_diferencias x where x.devengo_id = d.id)))
  );
end $$;
revoke execute on function public.comision_trazabilidad(uuid) from public, anon;
grant execute on function public.comision_trazabilidad(uuid) to authenticated, service_role;
