-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261016090000_law338_l5_compradores_datos.sql (16-oct-2026, sesión lecturas-servidor-2, LAW-338 L5).
-- ORDEN: 1) si ya se aplicó el revoke (law338_l5_revoke), primero devolver el SELECT de authenticated a las 7 tablas y a la vista
--    (lo trae su propia vuelta atrás); 2) front de L5 a su versión anterior (git revert del commit del front y las 3 edges, con
--    `aterriza.py --edge ficheros-kyc,portal-invitar,asistente-peticiones`); 3) ESTE fichero, en una transacción. Al revés, la
--    pantalla llamaría a funciones que ya no existen.
-- Nada de datos: solo funciones y permisos. clientes_busca vuelve LITERAL a su cuerpo del 15-oct (language sql, INVOKER);
-- contratos_busca y bot_pendientes, a INVOKER de postgres con su ACL de antes (postgres, authenticated, service_role).
-- destructivo-ok: borra solo las 8 funciones que creó la migración; ninguna tabla ni fila
set local lock_timeout = '5s';

drop function if exists public.clientes_lista_datos(uuid[]);
drop function if exists public.comprador_ficha_datos(uuid, text[]);
drop function if exists public.operacion_compradores_datos(uuid, uuid[]);
drop function if exists public.operaciones_compradores_datos();
drop function if exists public.soporte_datos();
drop function if exists public.notificaciones_datos(int);
drop function if exists public.correos_registro_datos(uuid[], uuid);
drop function if exists public.documentos_desactualizados_datos(text, uuid, uuid);

-- primero INVOKER y después dueño postgres (Seguridad, 16-oct): nunca una DEFINER de postgres, ni un instante
alter function public.clientes_busca(text) security invoker;
alter function public.contratos_busca(text) security invoker;
alter function public.bot_pendientes(uuid) security invoker;
alter function public.clientes_busca(text) owner to postgres;
alter function public.contratos_busca(text) owner to postgres;
alter function public.bot_pendientes(uuid) owner to postgres;
create or replace function public.clientes_busca(p_q text)
 returns table(id uuid, full_name text, email text, phone text)
 language sql
 stable
 security invoker
 set search_path to ''
as $function$
  with q as (select public.normaliza_busqueda(left(p_q, 200)) as v)   -- tope en el servidor (la edge corta a 120)
  select c.id, c.full_name, c.email, c.phone
    from public.clients c
    cross join q
   where public.es_agente()
     and char_length(q.v) >= 2
     and (strpos(public.normaliza_busqueda(c.full_name), q.v) > 0
          or lower(c.passport_number) = lower(btrim(p_q)))
   limit 6
$function$;
revoke all on function public.clientes_busca(text) from public, anon;
revoke all on function public.contratos_busca(text) from public, anon;
revoke all on function public.bot_pendientes(uuid) from public, anon;
grant execute on function public.clientes_busca(text) to authenticated, service_role;
grant execute on function public.contratos_busca(text) to authenticated, service_role;
grant execute on function public.bot_pendientes(uuid) to authenticated, service_role;
revoke execute on function public.normaliza_busqueda(text) from lw_lector;
revoke select (clave, razon) on public.sociedades from lw_lector;
