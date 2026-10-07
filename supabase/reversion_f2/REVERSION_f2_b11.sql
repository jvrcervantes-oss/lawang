-- REVERSION del BLOQUE 11 (migracion 20261008960000): devuelve la lista, los numeros y el buscador de clientes al texto de antes (7-oct-2026).
-- destructivo-ok: solo reemplaza 3 funciones de lectura por su texto anterior
create or replace function public.compradores_lista()
 returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, kyc_status text, propietario text, created_at timestamp with time zone, passport_hint text)
 language sql stable security definer set search_path to ''
as $function$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.kyc_status, c.propietario, c.created_at,
         case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end
    from public.clients c
   where public.es_agente()
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id)) $function$;

create or replace function public.compradores_numeros()
 returns table(id uuid, numero_cliente text)
 language sql stable security definer set search_path to ''
as $function$
  select c.id, c.numero_cliente from public.clients c
   where public.es_agente()
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id)) $function$;

create or replace function public.comprador_buscar(p_q text)
 returns table(id uuid, full_name text, email text, passport_hint text, tipo text, propietario text)
 language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not public.es_agente() then return; end if;
  if length(btrim(coalesce(p_q,''))) < 3 then return; end if;
  return query
    select c.id, c.full_name, c.email, case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end,
           c.tipo, c.propietario
      from public.clients c
     where (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))
       and (c.full_name ilike '%'||btrim(p_q)||'%' or c.email ilike '%'||btrim(p_q)||'%' or lower(c.passport_number) = lower(btrim(p_q)))
     limit 8;
end $function$;
