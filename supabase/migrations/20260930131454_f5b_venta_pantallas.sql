-- APLICADA el 30-sep-2026 por la sesión principal como 20260930131454_f5b_venta_pantallas; OK del owner: "Sí, aplícala".
-- Cómo: apply_migration con este contenido + tools/supabase_fetch_seguro.py (baja el fichero con su versión real a
-- migrations/) y borrar este. NO aterrizar la pantalla F5b sin aplicarla antes: sin ella el campo Venta dice «no he
-- podido comprobar» y la bandeja del SM enseña dos errores de lectura.
-- Probada el 30-sep por Datos empalmada en una transacción con ROLLBACK (motor sustituido por un stub dentro de la
-- misma transacción para no gastar series): ver el informe de la sesión.
--
-- F5b · pantallas de «por su cuenta» (30-sep-2026, encargo 20260930_lawang_equipos_venta_asistente).
-- Exposición, lectura y el permiso de objetar: NO toca contrato_guarda, el motor ni el interruptor (sigue APAGADO; se
-- enciende después con la consulta de Administración). Reducir la exposición: cada pieza lleva su llamador con nombre.
--
-- Quién es «el Sales Manager de la venta» (decisión del owner, F3): el SM de HOY del equipo de la venta ve todo el
-- histórico del equipo, y el anterior deja de verlo; equipo desactivado → su SM deja de verlo. Es el criterio de
-- public._sm_ve_venta() (equipo de la venta por _venta_equipo → equipos_venta.manager_email actual, equipo activo,
-- usuario activo). Las tres piezas de abajo que miraban contrato_closer.manager_email (el SM CONGELADO al firmar)
-- pasan a llamar a _sm_ve_venta(): ventas_por_su_cuenta_equipo, ventas_por_su_cuenta_cuota y venta_objecion_crear.
-- El congelado se sigue guardando (reparto de comisiones), pero ya no da acceso.
--
-- 1) modo_obligatorio_activo(): el formulario clásico y el asistente necesitan saber si el campo «Venta» es
--    obligatorio. comisiones_interruptor no tiene grant para el navegador (y no debe: lleva notas y errores del
--    motor), así que se expone SOLO el booleano.
--    Llamadores: contracts/assets/asistente-contrato.js (campo «Venta» del formulario clásico de contracts/app.html y
--    paso «modo» del asistente) e intranet/v4/assets/datos.js (texto de la bandeja «Ventas por su cuenta»).
-- 2) ventas_por_su_cuenta_cuota(): cuota «por su cuenta» por closer para la bandeja del SM. Solo recuentos, sin
--    cifras ni datos del cliente. Denominador = ventas del equipo en las que se DECLARÓ el modo (modo is not null):
--    las anteriores a F5 no dicen nada de cómo vende nadie. Mismo predicado de acceso que
--    ventas_por_su_cuenta_equipo (_sm_ve_venta, o admin con comisiones_reparto).
--    No se usa comisiones_ventas_equipo porque recalcula el equipo a fecha en vez de leer el congelado k.equipo_id.
--    Llamador: intranet/v4/assets/datos.js (pintaVentasPorSuCuenta, /intranet/v4/equipos-venta/).
-- 3) Re-concesión de EXECUTE a authenticated de las cuatro RPC de F5 revocadas en 20260930080806, que ahora tienen
--    pantalla:
--    · ventas_por_su_cuenta_equipo()          → datos.js pintaVentasPorSuCuenta (bandeja «Ventas por su cuenta»)
--    · venta_objecion_crear(uuid, text)       → editores.js, data-accion="vpc-objetar" (el SM)
--    · venta_objecion_resolver(uuid,text,text)→ editores.js, data-accion="vpc-resolver" (admin)
--    · venta_modo_admin(uuid, text, text)     → editores.js, data-accion="vpc-modo" (admin)
--    venta_objecion_resolver y venta_modo_admin, sin cambios en su cuerpo. ventas_por_su_cuenta_equipo y
--    venta_objecion_crear cambian SOLO el predicado del SM (y la primera gana equipo_id, punto 4).
--    Con el interruptor apagado no hay ninguna venta con modo (0 filas a 30-sep): la bandeja sale vacía y las tres
--    de escritura no tienen sobre qué actuar salvo venta_modo_admin, que ya exigía es_admin() + comisiones_reparto.

create or replace function public.modo_obligatorio_activo()
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $$
  select case when auth.uid() is null then false
              else coalesce((select i.modo_obligatorio from public.comisiones_interruptor i where i.id), false) end
$$;
comment on function public.modo_obligatorio_activo() is
  'F5b: ¿exige contrato_guarda declarar la venta (equipo / por su cuenta)? Solo el booleano del interruptor. Llamadores: contracts/assets/asistente-contrato.js e intranet/v4/assets/datos.js.';

create or replace function public.ventas_por_su_cuenta_cuota()
 returns table(equipo_id uuid, closer_email text, declaradas integer, por_su_cuenta integer)
 language sql
 stable
 security definer
 set search_path to ''
as $$
  select k.equipo_id, lower(k.closer_email),
         count(*)::integer,
         count(*) filter (where k.modo = 'propia')::integer
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id and c.contrato_padre_id is null
   where k.modo is not null and k.equipo_id is not null
     and coalesce(auth.email(), '') <> ''
     and (public._sm_ve_venta(k.contrato_id)
          or (public.es_admin() and public.puede('comisiones_reparto')))
   group by k.equipo_id, lower(k.closer_email)
   order by 2
$$;
comment on function public.ventas_por_su_cuenta_cuota() is
  'F5b: por closer y equipo, ventas con modo declarado y cuántas son por su cuenta. Solo recuentos. Acceso: SM de hoy del equipo de la venta (_sm_ve_venta) o admin con comisiones_reparto. Llamador: intranet/v4/assets/datos.js (bandeja del SM).';

revoke all on function public.modo_obligatorio_activo(), public.ventas_por_su_cuenta_cuota() from public, anon;
grant execute on function public.modo_obligatorio_activo(), public.ventas_por_su_cuenta_cuota() to authenticated;

-- 4) ventas_por_su_cuenta_equipo() gana equipo_id al FINAL (revisión de código F5b, 30-sep): sin él, el filtro de
--    equipo de la bandeja casaba por «quién estuvo alguna vez en ese equipo» y enseñaba ventas de otro equipo de un
--    closer trasladado; y la pantalla no sabía qué filas son del equipo que dirige quien mira (admin que también es
--    SM). Cuerpo vivo de 20260930074916 + k.equipo_id + predicado _sm_ve_venta. Cambia el tipo devuelto → drop +
--    create (función de lectura, sin datos).
drop function if exists public.ventas_por_su_cuenta_equipo(); -- destructivo-ok: owner 30-sep «Sí, aplícala» — drop+create de ventas_por_su_cuenta_equipo para añadir equipo_id (función de lectura, sin datos)
create function public.ventas_por_su_cuenta_equipo()
 returns table(raiz_id uuid, numero text, closer_email text, origen text, origen_texto text, declarado_en timestamptz,
               espera_hasta timestamptz, cruces jsonb, objecion_id uuid, objecion_estado text, objecion_decision text,
               objecion_motivo text, objecion_resolucion text, equipo_id uuid)
 language sql stable security definer set search_path to ''
as $$
  select k.contrato_id, c.numero, lower(k.closer_email), k.modo_origen, k.modo_origen_texto, k.modo_declarado_en,
         k.modo_espera_hasta, k.modo_cruces, o.id, o.estado, o.resolucion, o.motivo, o.motivo_resolucion, k.equipo_id
    from public.contrato_closer k
    join public.contratos c on c.id = k.contrato_id
    left join lateral (select r.* from public.reclamaciones_venta_propia r
                        where r.contrato_raiz_id = k.contrato_id and r.tipo = 'objecion'
                        order by (r.estado = 'pendiente') desc, r.creado_en desc limit 1) o on true
   where k.modo = 'propia' and k.equipo_id is not null
     and coalesce(auth.email(), '') <> ''
     and (public._sm_ve_venta(k.contrato_id)
          or (public.es_admin() and public.puede('comisiones_reparto')))
   order by k.modo_declarado_en desc nulls last
$$;
comment on function public.ventas_por_su_cuenta_equipo() is
  'F5b: ventas «por su cuenta» dentro de un equipo, con su última objeción. Acceso: SM de hoy del equipo de la venta (_sm_ve_venta) o admin con comisiones_reparto. Llamador: intranet/v4/assets/datos.js (pintaVentasPorSuCuenta).';
revoke all on function public.ventas_por_su_cuenta_equipo() from public, anon;
grant execute on function public.ventas_por_su_cuenta_equipo() to authenticated;

-- 5) venta_objecion_crear: cuerpo vivo, con el permiso del SM por _sm_ve_venta(p_raiz) en vez de
--    «k.manager_email congelado = yo AND SM actual del k.equipo_id = yo» (que dejaba sin objetar al SM de hoy si el
--    equipo cambió de manager). La objeción guarda manager_email = quien objeta (el SM de hoy), como antes.
create or replace function public.venta_objecion_crear(p_raiz uuid, p_motivo text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
  k     public.contrato_closer;
  v_id  uuid;
  v_num text;
begin
  if auth.uid() is null or v_yo = '' then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_mot is null then raise exception 'Explica por qué la venta es del equipo' using errcode = '22023'; end if;
  if length(v_mot) > 2000 then raise exception 'El motivo admite como mucho 2000 caracteres' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));
  select * into k from public.contrato_closer where contrato_id = p_raiz for update;
  if not found or k.modo is distinct from 'propia' or k.equipo_id is null then
    raise exception 'Esa venta no está marcada «por su cuenta» dentro de un equipo' using errcode = '22023';
  end if;
  if not public._sm_ve_venta(p_raiz) then
    raise exception 'Solo el Sales Manager del equipo de esa venta puede objetar' using errcode = '42501';
  end if;
  if lower(k.closer_email) = v_yo then raise exception 'No puedes objetar tu propia venta' using errcode = '42501'; end if;
  if k.modo_espera_hasta is null or now() >= k.modo_espera_hasta then
    raise exception 'El plazo para objetar esta venta ya terminó' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r where r.contrato_raiz_id = p_raiz and r.tipo = 'objecion' and r.estado = 'pendiente') then
    raise exception 'Ya hay una objeción abierta en esta venta' using errcode = '23505';
  end if;

  insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo, tipo)
  values (p_raiz, v_yo, k.equipo_id, v_yo, v_mot, 'objecion')
  returning id into v_id;

  select c.numero into v_num from public.contratos c where c.id = p_raiz;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select 'venta_objecion', 'Objeción a una venta por su cuenta · ' || coalesce(v_num, '?'),
         'El Sales Manager ' || v_yo || ' objeta que la venta ' || coalesce(v_num, '?') || ' de ' || lower(k.closer_email)
           || ' sea por su cuenta. La comisión queda en espera hasta que la resuelva un administrador.',
         u.email, p_raiz, '/intranet/v4/comisiones/', true
    from public.usuarios u where u.activo and u.rol in ('admin', 'super_admin');
  return v_id;
end $function$;

revoke all on function public.venta_objecion_crear(uuid, text) from public, anon;
grant execute on function public.venta_objecion_crear(uuid, text) to authenticated;
grant execute on function public.venta_objecion_resolver(uuid, text, text) to authenticated;
grant execute on function public.venta_modo_admin(uuid, text, text) to authenticated;
