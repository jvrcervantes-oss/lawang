-- LAW-338 L3 (10-oct-2026, revisor): operacion_comisiones_datos cortaba en 2000 filas SIN decirlo (sin `recortado`). Es el
-- recuento que el diálogo de «borrar operación» enseña antes de borrar: un corte mudo prometería menos comisiones de las
-- que se van a purgar. Se quita el tope de filas: la entrada ya está acotada a 200 contratos (falla en voz alta, 22023)
-- y cada contrato devenga unas pocas comisiones (una por nivel), así que la lista cabe entera.
-- Mismo cuerpo que 20261010062215 salvo el `limit 2000`. CREATE OR REPLACE conserva dueño (lw_lector) y permisos; se
-- comprueba abajo. Firma y forma del jsonb iguales: la pareja del maestro (20261008139650, B10 aparcado hasta el 1-nov)
-- conserva el tope hasta que se retome; anotado en el encargo B10.
-- Vuelta atrás: volver a crear la función con el cuerpo de 20261010062215 (sección 5).

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
    from public.comisiones_devengadas d
   where d.contrato_raiz_id = any(coalesce(p_contratos, '{}'::uuid[]));
  return jsonb_build_object('comisiones', v_lista);
end $$;

do $$
declare v_dueno text; v_secdef boolean;
begin
  select pg_get_userbyid(p.proowner), p.prosecdef into v_dueno, v_secdef
    from pg_proc p where p.oid = 'public.operacion_comisiones_datos(uuid[])'::regprocedure;
  if v_dueno <> 'lw_lector' or not v_secdef then
    raise exception 'operacion_comisiones_datos: dueño % / definer % (se esperaba lw_lector, definer)', v_dueno, v_secdef;
  end if;
  if not has_function_privilege('authenticated', 'public.operacion_comisiones_datos(uuid[])', 'execute')
     or has_function_privilege('anon', 'public.operacion_comisiones_datos(uuid[])', 'execute')
     or has_function_privilege('service_role', 'public.operacion_comisiones_datos(uuid[])', 'execute') then
    raise exception 'operacion_comisiones_datos: permisos cambiados';
  end if;
end $$;
