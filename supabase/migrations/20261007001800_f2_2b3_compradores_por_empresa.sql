-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · paso 2B · migracion 3 (7-oct-2026): DIRECTORIO DE COMPRADORES POR EMPRESA. compradores_lista y compradores_numeros devolvian TODOS los clientes a cualquier agente;
--   ahora, quien tiene el alcance restringido (rol de empresa, o empresas marcadas) solo ve los clientes que cliente_visible deja ver (los de contratos de su empresa; los 13 sin contratos quedan cerrados).
--   comprador_contratos_resumen: un restringido no ve ni la fila (proyecto, autor, tipo) de un contrato de la otra empresa. Quien no esta restringido (los 34 de hoy): identico a antes.
-- destructivo-ok: create or replace de tres funciones; sin borrar datos
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_2b.sql
create or replace function public.compradores_lista()
 returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, kyc_status text, propietario text, created_at timestamp with time zone, passport_hint text)
 language sql stable security definer set search_path = '' as $$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.kyc_status, c.propietario, c.created_at,
         case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end
    from public.clients c
   where public.es_agente()
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id)) $$;

create or replace function public.compradores_numeros()
 returns table(id uuid, numero_cliente text)
 language sql stable security definer set search_path = '' as $$
  select c.id, c.numero_cliente from public.clients c
   where public.es_agente()
     and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id)) $$;

create or replace function public.comprador_contratos_resumen(p_client_id uuid)
 returns table(contrato_id uuid, rol text, tipo text, proyecto_nombre text, autor text, bloqueado boolean, visible boolean)
 language sql stable security definer set search_path = '' as $$
  select case when v.visible then c.id end,
         cc.rol, c.tipo, c.proyecto_nombre, c.creado_por,
         coalesce(c.bloqueado, false), v.visible
    from public.contrato_compradores cc
    join public.contratos c on c.id = cc.contrato_id
    cross join lateral (
      select public.puede_ver_contrato(c.id) as visible) v
   where public.es_agente() and cc.client_id = p_client_id
     and (v.visible or not (select public.alcance_restringido()))
   order by c.created_at $$;
