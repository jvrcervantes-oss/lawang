-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- BLOQUE 11 · 1/1 (7-oct-2026, Datos). DIRECTORIO DE CLIENTES GLOBAL. Decision del owner: «los clientes deben ser visibles por todo el mundo en la intranet».
--   FICHA BASICA = lo que ya sale en la lista: id, nº de cliente, nombre, tipo, email, telefono, nacionalidad, KYC, propietario, alta y los 4 ultimos del pasaporte (passport_hint).
--   Sin pasaporte entero, sin fecha de nacimiento, sin direccion, sin notas, sin documentos, sin contratos. NO se abre la tabla `clients` (su policy sigue siendo es_agente() AND cliente_visible),
--   ni `documents`, ni el bucket `kyc`: lo completo sigue la regla de los contratos.
--   - compradores_lista() y compradores_numeros(): TODAS las fichas a cualquier es_agente() (antes, quien tenia alcance restringido veia solo cliente_visible).
--   - comprador_buscar(): por nombre o email, todas; por PASAPORTE ENTERO solo el conjunto de antes (si no, teclear un pasaporte averiguaria a quien pertenece en la otra empresa).
--   - comprador_ficha() (pasaporte, nacimiento, direccion), comprador_contratos_resumen(), cliente_guarda(), traspasos, borrados: NO se tocan.
-- destructivo-ok: solo reemplaza 3 funciones de lectura (mismo tipo de retorno); no toca datos ni tablas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b11.sql
create or replace function public.compradores_lista()
 returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, kyc_status text, propietario text, created_at timestamp with time zone, passport_hint text)
 language sql stable security definer set search_path to ''
as $function$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.kyc_status, c.propietario, c.created_at,
         case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end
    from public.clients c
   where public.es_agente() $function$;

create or replace function public.compradores_numeros()
 returns table(id uuid, numero_cliente text)
 language sql stable security definer set search_path to ''
as $function$
  select c.id, c.numero_cliente from public.clients c
   where public.es_agente() $function$;

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
     where (c.full_name ilike '%'||btrim(p_q)||'%' or c.email ilike '%'||btrim(p_q)||'%'
            or (lower(c.passport_number) = lower(btrim(p_q))
                and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))))
     limit 8;
end $function$;
