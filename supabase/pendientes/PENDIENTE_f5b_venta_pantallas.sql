-- PENDIENTE DE APLICAR (30-sep-2026): escrita en F5b, el apply por MCP lo denegó el clasificador de permisos.
-- NO aterrizar la pantalla F5b sin aplicarla antes: sin ella el campo Venta dice «no he podido comprobar» y la
-- bandeja del SM enseña dos errores de lectura. Al aplicarla: apply_migration + tools/supabase_fetch_seguro.py
-- (baja el fichero con su versión real a migrations/) y borrar este.
-- F5b · pantallas de «por su cuenta» (30-sep-2026, encargo 20260930_lawang_equipos_venta_asistente).
-- Solo exposición y lectura: NO toca contrato_guarda, el motor ni el interruptor (sigue APAGADO; se enciende
-- después con la consulta de Administración). Reducir la exposición: cada pieza lleva su llamador con nombre.
--
-- 1) modo_obligatorio_activo(): el formulario clásico y el asistente necesitan saber si el campo «Venta» es
--    obligatorio. comisiones_interruptor no tiene grant para el navegador (y no debe: lleva notas y errores del
--    motor), así que se expone SOLO el booleano.
--    Llamadores: contracts/assets/asistente-contrato.js (campo «Venta» del formulario clásico de contracts/app.html y
--    paso «modo» del asistente) e intranet/v4/assets/datos.js (texto de la bandeja «Ventas por su cuenta»).
-- 2) ventas_por_su_cuenta_cuota(): cuota «por su cuenta» por closer para la bandeja del SM. Solo recuentos, sin
--    cifras ni datos del cliente. Denominador = ventas del equipo en las que se DECLARÓ el modo (modo is not null):
--    las anteriores a F5 no dicen nada de cómo vende nadie. Mismo predicado de acceso que
--    ventas_por_su_cuenta_equipo (SM congelado de la venta, o admin con comisiones_reparto).
--    No se usa comisiones_ventas_equipo porque recalcula el equipo a fecha en vez de leer el congelado k.equipo_id.
--    Llamador: intranet/v4/assets/datos.js (pintaVentasPorSuCuenta, /intranet/v4/equipos-venta/).
-- 3) Re-concesión de EXECUTE a authenticated de las cuatro RPC de F5 revocadas en 20260930080806, que ahora tienen
--    pantalla. Sin cambios en su cuerpo:
--    · ventas_por_su_cuenta_equipo()          → datos.js pintaVentasPorSuCuenta (bandeja «Ventas por su cuenta»)
--    · venta_objecion_crear(uuid, text)       → editores.js, data-accion="vpc-objetar" (el SM)
--    · venta_objecion_resolver(uuid,text,text)→ editores.js, data-accion="vpc-resolver" (admin)
--    · venta_modo_admin(uuid, text, text)     → editores.js, data-accion="vpc-modo" (admin)
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
     and (lower(coalesce(k.manager_email, '')) = lower(auth.email())
          or (public.es_admin() and public.puede('comisiones_reparto')))
   group by k.equipo_id, lower(k.closer_email)
   order by 2
$$;
comment on function public.ventas_por_su_cuenta_cuota() is
  'F5b: por closer y equipo, ventas con modo declarado y cuántas son por su cuenta. Solo recuentos. Llamador: intranet/v4/assets/datos.js (bandeja del SM).';

revoke all on function public.modo_obligatorio_activo(), public.ventas_por_su_cuenta_cuota() from public, anon;
grant execute on function public.modo_obligatorio_activo(), public.ventas_por_su_cuenta_cuota() to authenticated;

-- 4) ventas_por_su_cuenta_equipo() gana equipo_id al FINAL (revisión de código F5b, 30-sep): sin él, el filtro de
--    equipo de la bandeja casaba por «quién estuvo alguna vez en ese equipo» y enseñaba ventas de otro equipo de un
--    closer trasladado; y la pantalla no sabía qué filas son del equipo que dirige quien mira (admin que también es
--    SM). Mismo cuerpo que 20260930074916 + k.equipo_id. Cambia el tipo devuelto → drop + create (sin datos).
drop function if exists public.ventas_por_su_cuenta_equipo();
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
     and (lower(coalesce(k.manager_email, '')) = lower(auth.email())
          or (public.es_admin() and public.puede('comisiones_reparto')))
   order by k.modo_declarado_en desc nulls last
$$;
revoke all on function public.ventas_por_su_cuenta_equipo() from public, anon;
grant execute on function public.ventas_por_su_cuenta_equipo() to authenticated;
grant execute on function public.venta_objecion_crear(uuid, text) to authenticated;
grant execute on function public.venta_objecion_resolver(uuid, text, text) to authenticated;
grant execute on function public.venta_modo_admin(uuid, text, text) to authenticated;
