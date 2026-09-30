-- destructivo-ok: los DROP POLICY van seguidos del CREATE POLICY del mismo nombre (sustitucion de
-- policy, DDL que construye segun departamentos/datos/prompt.md). Cero filas borradas, RLS sigue activa.
-- ════════════════════════════════════════════════════════════════════════════
-- F4 · COMISIÓN OCULTA — predicado único `comision_visible` (30-sep-2026)
-- Encargo: encargos/20260930_lawang_equipos_venta_asistente.md (Decisiones «Comisión oculta»,
-- «SM único perceptor»; revisión previa #162 Seguridad + Datos).
-- ════════════════════════════════════════════════════════════════════════════
-- POR QUÉ. Varios Sales Manager no quieren que sus closers sepan lo que cobran. Hasta hoy la comisión
-- se escapaba por cinco sitios que decidían cada uno a su manera:
--   · policy «comisiones_devengadas: leer»: el beneficiario veía su fila siempre, sin interruptor;
--   · comision_trazabilidad (DEFINER): copiaba ese criterio a mano;
--   · comisiones_diferencias: heredaba de devengos sin decirlo;
--   · «condiciones_comision: leer» y condicion_tramos: el miembro leía las condiciones GENÉRICAS de
--     su equipo (closer_email null) — el % del equipo;
--   · solicitudes_pago: `creado_por = yo` enseña la solicitud del BOTE al closer si el motor corrió en
--     su sesión (comisiones_evaluar_contrato pone creado_por = coalesce(auth.uid(), ...), y el
--     recálculo automático está ENCENDIDO desde el 28-sep); y el aviso «Tu solicitud…» se lo mandaba a él.
-- Desde aquí todas esas salidas preguntan a UNA función. tools/salud_lawang.py falla si una policy o
-- una función DEFINER de lectura lee comisiones_devengadas sin pasar por ella.
--
-- REGLAS (owner, 30-sep):
--   · niveles que paga Lawang (estandar, propia, manager y cualquiera futuro que no sea de equipo):
--     los ve su beneficiario, SIEMPRE, con el interruptor como esté; más admin con casilla.
--   · niveles que paga el SM de su bolsillo (closer, setter, team_lead): los ve el SM del equipo
--     (el de la condición o el congelado en la venta) y admin con casilla; el beneficiario SOLO si el
--     equipo CONGELADO en la venta (contrato_closer.equipo_id; si no está congelado, el de la
--     condición) tiene `closers_ven_comision` encendido.
--   · el bote (nivel manager) nunca lo ve un closer: solo su beneficiario (el SM) y admin.
--   · condiciones: el closer ve solo las SUYAS (closer_email = él) y, si son de equipo, solo con el
--     interruptor encendido; nunca las genéricas del equipo. El SM y admin, como antes.
--
-- NO toca: comisiones_evaluar_contrato, _venta_congela_equipo, _equipo_recongela_sin_equipo,
-- equipo_miembro_guarda (otra tarea), contrato_visible/cliente_visible/_puede_ver_contrato/
-- documento_visible (F3), la vista «mi condición» (LAW-449, F6), solicitudes_pago_retencion (cerrada).
--
-- REVERSIÓN (una pegada): recrear las policies con su texto anterior —
--   «comisiones_devengadas: leer» USING ((es_admin() AND puede('comisiones_reparto')) OR
--     (lower(beneficiario_email) = lower((select auth.email()))) OR ((nivel = ANY (ARRAY['closer','setter',
--     'team_lead'])) AND es_manager_de_equipo(_equipo_de_condicion_comision(condicion_id)))) TO authenticated, lw_lector
--   «comisiones_diferencias: leer» USING (EXISTS (SELECT 1 FROM comisiones_devengadas d WHERE d.id =
--     comisiones_diferencias.devengo_id)) TO public
--   «condiciones_comision: leer» USING (es_admin() OR ((nivel = ANY (ARRAY['closer','setter','team_lead'])) AND
--     ((closer_email = (select auth.email())) OR ((closer_email IS NULL) AND (EXISTS (SELECT 1 FROM equipo_miembros em
--     WHERE em.equipo_id = condiciones_comision.equipo_id AND em.closer_email = (select auth.email()) AND
--     em.desde <= CURRENT_DATE AND (em.hasta IS NULL OR em.hasta >= CURRENT_DATE)))))) OR ((nivel = 'manager') AND
--     (EXISTS (SELECT 1 FROM equipos_venta ev WHERE ev.id = condiciones_comision.equipo_id AND ev.manager_email =
--     (select auth.email()))))) TO authenticated, lw_lector
--   «condicion_tramos: leer» USING (EXISTS (SELECT 1 FROM condiciones_comision c WHERE c.id = condicion_tramos.condicion_id
--     AND (<mismo predicado que condiciones_comision: leer, sobre c>))) TO authenticated, lw_lector
--   «solicitudes: cada uno lee las suyas, admin con casilla todas» USING ((es_admin() AND puede('comisiones')) OR
--     (creado_por = (select auth.uid())) OR (beneficiario_email = (select auth.email()))) TO public
--   y los cuerpos de comision_trazabilidad y _trg_solicitud_pago_aviso de supabase/vivo/20260930/ (el segundo,
--   el de la migración 20260910091817_avisos_manager_email.sql); drop function comision_visible (las dos firmas).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. El predicado ─────────────────────────────────────────────────────────
-- Forma por FILA: la usan las policies (no vuelve a leer la fila que ya tienen delante).
create or replace function public.comision_visible(p_nivel text, p_beneficiario text, p_condicion uuid, p_raiz uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  with yo as (select lower(coalesce(auth.email(), '')) as e),
  eq as (
    select (select c.equipo_id from public.condiciones_comision c where c.id = p_condicion) as de_condicion,
           (select k.equipo_id from public.contrato_closer k where k.contrato_id = p_raiz) as congelado
  )
  select yo.e <> '' and (
       (public.es_admin() and public.puede('comisiones_reparto'))
    or (p_nivel in ('closer', 'setter', 'team_lead') and (
          public.es_manager_de_equipo(eq.de_condicion)
          or public.es_manager_de_equipo(eq.congelado)
          or (lower(coalesce(p_beneficiario, '')) = yo.e
              and coalesce((select ev.closers_ven_comision from public.equipos_venta ev
                             where ev.id = coalesce(eq.congelado, eq.de_condicion)), true))))
    or (p_nivel not in ('closer', 'setter', 'team_lead') and lower(coalesce(p_beneficiario, '')) = yo.e)
  )
  from yo, eq
$function$;

-- Forma por ID: la usan las funciones DEFINER que reciben un devengo (comision_trazabilidad, las que vengan).
create or replace function public.comision_visible(p_devengo uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce((select public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id)
                     from public.comisiones_devengadas d where d.id = p_devengo), false)
$function$;

comment on function public.comision_visible(text, text, uuid, uuid) is
  'F4 (30-sep-2026): ¿quien consulta puede ver esta cifra de comision? Unico criterio para la RLS y toda salida. Ver migracion 20260930041708_f4_comision_visible.';
comment on function public.comision_visible(uuid) is
  'F4 (30-sep-2026): comision_visible por id de devengo, para funciones DEFINER.';

revoke all on function public.comision_visible(text, text, uuid, uuid) from public, anon;
revoke all on function public.comision_visible(uuid) from public, anon;
grant execute on function public.comision_visible(text, text, uuid, uuid) to authenticated, lw_lector, service_role;
grant execute on function public.comision_visible(uuid) to authenticated, service_role;  -- authenticated se retira en 20260930042130

-- ── 2. RLS ──────────────────────────────────────────────────────────────────
drop policy if exists "comisiones_devengadas: leer" on public.comisiones_devengadas;
create policy "comisiones_devengadas: leer" on public.comisiones_devengadas
  for select to authenticated, lw_lector
  using (public.comision_visible(nivel, beneficiario_email, condicion_id, contrato_raiz_id));

-- explícito, no heredado: una diferencia es una cifra de comisión
drop policy if exists "comisiones_diferencias: leer" on public.comisiones_diferencias;
create policy "comisiones_diferencias: leer" on public.comisiones_diferencias
  for select to authenticated, lw_lector
  using (exists (select 1 from public.comisiones_devengadas d
                  where d.id = comisiones_diferencias.devengo_id
                    and public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id)));

-- condiciones: fuera las genéricas del equipo para el miembro; las suyas de equipo, solo con interruptor.
-- «condiciones: el manager lee las de su equipo» sigue igual (el SM).
drop policy if exists "condiciones_comision: leer" on public.condiciones_comision;
create policy "condiciones_comision: leer" on public.condiciones_comision
  for select to authenticated, lw_lector
  using (
    public.es_admin()
    or (nivel in ('closer', 'setter', 'team_lead')
        and lower(coalesce(closer_email, '')) = lower(coalesce((select auth.email()), '-'))
        and (equipo_id is null
             or coalesce((select ev.closers_ven_comision from public.equipos_venta ev where ev.id = condiciones_comision.equipo_id), true)))
    or (nivel = 'manager'
        and exists (select 1 from public.equipos_venta ev
                     where ev.id = condiciones_comision.equipo_id
                       and lower(ev.manager_email) = lower(coalesce((select auth.email()), '-'))))
  );

-- tramos: los de una condición que ya ves (la RLS de condiciones_comision decide; un solo criterio).
-- «tramos: el manager lee los de su equipo» sigue igual.
drop policy if exists "condicion_tramos: leer" on public.condicion_tramos;
create policy "condicion_tramos: leer" on public.condicion_tramos
  for select to authenticated, lw_lector
  using (exists (select 1 from public.condiciones_comision c where c.id = condicion_tramos.condicion_id));

-- solicitudes: la automática de comisión (bote o estándar) es de su BENEFICIARIO, no de quien tenía la
-- sesión abierta cuando corrió el motor.
drop policy if exists "solicitudes: cada uno lee las suyas, admin con casilla todas" on public.solicitudes_pago;
create policy "solicitudes: cada uno lee las suyas, admin con casilla todas" on public.solicitudes_pago
  for select to public
  using (
    (public.es_admin() and public.puede('comisiones'))
    or (creado_por = (select auth.uid()) and origen is distinct from 'comision_automatica')
    or (beneficiario_email = (select auth.email()))
  );

-- ── 3. comision_trazabilidad: el mismo cuerpo vivo, con el criterio en comision_visible ──
create or replace function public.comision_trazabilidad(p_devengo uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare d public.comisiones_devengadas;
begin
  if auth.uid() is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  select * into d from public.comisiones_devengadas where id = p_devengo;
  -- F4 (30-sep-2026): el criterio es comision_visible, el mismo que la RLS de comisiones_devengadas
  if not found or not public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id) then
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
end $function$;

-- ── 4. Aviso de solicitud resuelta: la automática avisa a su beneficiario, no a quien tenía la sesión ──
create or replace function public._trg_solicitud_pago_aviso()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_email text; v_nombre text; v_proyecto_id uuid; v_proyecto_nombre text; v_automatica boolean;
begin
  v_automatica := new.origen = 'comision_automatica' and new.beneficiario_email is not null;
  if tg_op = 'INSERT' then
    select u.nombre into v_nombre from public.usuarios u where u.user_id = new.creado_por;
    insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
    values ('solicitud_pago',
            'Solicitud de pago SP-' || new.numero,
            coalesce(v_nombre, 'Un comercial') || ' pide un pago: ' || new.concepto,
            null, new.contrato_id,
            '/intranet/solicitudes/?id=' || new.id::text);
  elsif tg_op = 'UPDATE' and new.estado is distinct from old.estado and new.estado <> 'pendiente' then
    -- F4 (30-sep-2026): la automática es de su beneficiario (el motor puede haber corrido en la sesión de otro)
    if v_automatica then
      v_email := new.beneficiario_email;
    else
      select u.email into v_email from public.usuarios u where u.user_id = new.creado_por;
    end if;
    if v_email is not null and new.estado <> 'anulada' then
      insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace)
      values ('solicitud_pago',
              'Tu solicitud SP-' || new.numero || ' — ' ||
                case new.estado when 'aprobada' then 'aprobada'
                                when 'rechazada' then 'rechazada'
                                when 'pagada' then 'pagada' end,
              case when new.estado = 'rechazada' then new.motivo_rechazo
                   when new.estado = 'pagada' then coalesce(new.pago_referencia, new.concepto)
                   else new.concepto end,
              v_email, new.contrato_id,
              '/intranet/solicitudes/?id=' || new.id::text);
    end if;
    if new.estado <> 'anulada' and new.contrato_id is not null then
      select c.proyecto_id, c.proyecto_nombre into v_proyecto_id, v_proyecto_nombre
        from public.contratos c where c.id = new.contrato_id;
      if v_automatica then
        select coalesce(u.nombre, u.email) into v_nombre
          from public.usuarios u where lower(u.email) = lower(new.beneficiario_email) limit 1;
      else
        select coalesce(u.nombre, u.email) into v_nombre
          from public.usuarios u where u.user_id = new.creado_por;
      end if;
      perform public._avisar_managers(
        v_proyecto_id, 'solicitud_pago',
        'Solicitud SP-' || new.numero || ' — ' || new.estado,
        coalesce(v_nombre, 'Un comercial') || ' · ' || coalesce(v_proyecto_nombre, 'proyecto') || ' · ' || new.estado,
        '/intranet/solicitudes/?id=' || new.id::text, new.contrato_id);
    end if;
  end if;
  return new;
exception when others then
  return new;
end;
$function$;
