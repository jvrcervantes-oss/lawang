-- Trazabilidad de comisiones: «falta por firmar» (owner 12-oct-2026).
--
-- Qué pasó: Gus reclamó 10.720 € por C5 (RP00140) y el sistema le daba 4.120 €. Los dos tenían razón a
-- medias: la base de la comisión cuenta solo contratos firmados (regla del owner del 28-sep) y en C5 solo
-- está firmada la reserva de parcela (41.200 €); la carta de 107.200 € está sin firmar y no hay contrato de
-- construcción. Nada en la pantalla lo decía. Owner: «hay que poner trazabilidad aquí para ver si falta algo
-- por firmar y avisar que no se cobra entera porque falta por firmar».
--
-- Qué hace: comision_trazabilidad() devuelve además
--   por_firmar        = contratos vivos de la venta sin firmar que entrarían en la base al firmarse (no la
--                       carta de reserva hija, que nunca cuenta). Un borrador NO cuenta si ya hay firmado
--                       otro del mismo tipo: es el que se sustituyó (C8: CC00114/CC00122 frente a CC00123).
--                       Con números de contrato solo para quien ve la operación completa; si no, '[]'.
--   sin_contrato_obra = precio de construcción de la parcela cuando la venta no tiene ningún contrato de
--                       construcción vivo Y lo firmado no llega al precio de la parcela (suelo + obra); si el
--                       contrato principal ya incluye la obra (paquetes de Tamarind) no avisa. null si no aplica.
--   falta_por_firmar  = suma de los dos. 0 = la comisión ya es la entera.
-- Criterio comprobado el 12-oct contra todas las ventas con comisión viva: avisa en 5 (B7, C5, RP00164, B6,
-- D8) y en ninguna con descuento pactado (C7: 76.500 firmado frente a 79.000 de la parcela) ni con borradores
-- sustituidos (C8). Una diferencia de precio NO es «falta por firmar».
-- Solo lectura: no cambia la base, el motor, los importes ni quién ve qué (mismo criterio de entrada).
-- El resto del cuerpo es el vivo del 12-oct-2026, copiado sin cambios.

create or replace function public.comision_trazabilidad(p_devengo uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare d public.comisiones_devengadas; v_yo text := lower(coalesce(auth.email(), '')); v_completa boolean;
  v_base numeric; v_operacion numeric; v_hay_obra boolean; v_pc numeric;
  v_por_firmar jsonb; v_suma_pend numeric; v_sin_obra numeric;
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_yo = '' then raise exception 'Tu sesión no trae correo: no se puede ver la trazabilidad' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- F4: el criterio de entrada es comision_visible, el mismo que la RLS de comisiones_devengadas
  if not found or not public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id) then
    raise exception 'No encuentro esa comisión entre las que puedes ver' using errcode = '42501';
  end if;
  v_completa := public.puede_reparto_de(public._empresa_de_contrato_int(d.contrato_raiz_id))
                or (d.nivel in ('closer', 'setter', 'team_lead') and (
                      public.es_manager_de_equipo((select c.equipo_id from public.condiciones_comision c where c.id = d.condicion_id))
                   or public.es_manager_de_equipo((select k.equipo_id from public.contrato_closer k where k.contrato_id = d.contrato_raiz_id))));

  -- falta por firmar (12-oct-2026): lo que entraría en la base y aún no está firmado
  v_base := public._comisiones_precio_total(d.contrato_raiz_id);
  select coalesce(jsonb_agg(jsonb_build_object('numero', c.numero, 'tipo', c.tipo, 'precio_total', c.precio_total,
                                               'moneda', c.moneda) order by c.created_at), '[]'::jsonb),
         coalesce(sum(c.precio_total), 0)
    into v_por_firmar, v_suma_pend
    from public.contratos c
   where (c.id = d.contrato_raiz_id or c.contrato_padre_id = d.contrato_raiz_id)
     and not coalesce(c.bloqueado, false) and c.liberado_en is null
     and not (c.contrato_padre_id is not null and c.tipo like 'carta_reserva%')
     and not exists (select 1 from public.contratos s
                      where (s.id = d.contrato_raiz_id or s.contrato_padre_id = d.contrato_raiz_id)
                        and s.tipo = c.tipo and coalesce(s.bloqueado, false) and s.liberado_en is null);
  select coalesce(sum(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0)), 0),
         coalesce(sum(coalesce(u.precio_construccion, 0)), 0)
    into v_operacion, v_pc
    from public.unidades u where u.contrato_id = d.contrato_raiz_id;
  v_hay_obra := exists (select 1 from public.contratos h
                         where h.contrato_padre_id = d.contrato_raiz_id
                           and h.tipo like 'construccion%' and h.liberado_en is null);
  v_sin_obra := case when v_pc > 0 and not v_hay_obra and v_base < v_operacion then v_pc end;

  return jsonb_build_object(
    'venta', d.contrato_raiz_id,
    'completa', v_completa,
    'base_hoy', v_base,
    'por_firmar', case when v_completa then v_por_firmar else '[]'::jsonb end,
    'sin_contrato_obra', v_sin_obra,
    'falta_por_firmar', v_suma_pend + coalesce(v_sin_obra, 0),
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
end
$function$;
