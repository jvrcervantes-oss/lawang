-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015062313_busqueda_sin_tildes.sql (15-oct-2026, sesion busqueda-tildes).
-- ORDEN (inverso al de publicar): 1) front de asistente-contrato.js y edge asistente-peticiones a su version anterior
-- (git revert del commit de la tanda 2 + redesplegar la edge), 2) ESTE fichero, en una transaccion.
-- En otro orden, el buscador de ventas y el asistente se rompen entre medias (llamarian a funciones que ya no existen).
-- comprador_buscar vuelve LITERAL a la viva del 15-oct (pg_get_functiondef, md5 bd0230e91ad793e198ab687f18552c8f); el
-- CREATE OR REPLACE conserva sus grants. Precondicion: que la viva sea la que dejo la migracion (su comentario propio,
-- normaliza_busqueda y sin ilike), para no pisar un cambio posterior.
-- destructivo-ok: borra solo las 3 funciones nuevas de la migracion (sin CASCADE) y repone comprador_buscar; no toca datos
set local lock_timeout = '5s';

do $pre$
declare d text := pg_get_functiondef('public.comprador_buscar(text)'::regprocedure);
begin
  if position('el servidor normaliza lo que llega' in d) = 0 or position('normaliza_busqueda' in d) = 0 or d ~* 'ilike' then
    raise exception 'comprador_buscar viva no es la que dejo 20261015062313: alguien la cambio despues; revertir a mano';
  end if;
end $pre$;

CREATE OR REPLACE FUNCTION public.comprador_buscar(p_q text)
 RETURNS TABLE(id uuid, full_name text, email text, passport_hint text, tipo text, propietario text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.es_agente() then return; end if;
  if length(btrim(coalesce(p_q,''))) < 3 then return; end if;
  return query
    select c.id, c.full_name, c.email, case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end,
           c.tipo, c.propietario
      from public.clients c
     where (c.full_name ilike '%'||btrim(p_q)||'%' or c.email ilike '%'||btrim(p_q)||'%'
            or (lower(c.passport_number) = lower(btrim(p_q))
                and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))))
     limit 8;
end $function$;

drop function public.contratos_busca(text);
drop function public.clientes_busca(text);
drop function public.normaliza_busqueda(text);
