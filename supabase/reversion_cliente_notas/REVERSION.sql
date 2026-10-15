-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015170000_cliente_notas.sql (15-oct-2026, sesion notas-cliente).
-- ORDEN: 1) front de la ficha a su version anterior (git revert del commit de las notas: vuelve el campo «Notas» al editor),
-- 2) ESTE fichero, en una transaccion. Al reves, la pantalla llamaria a funciones que ya no existen.
-- Antes de borrar las tablas, cada ficha recupera en clients.notes sus notas (todas las que tenga, la mas reciente arriba,
-- separadas por una linea en blanco): ninguna nota escrita entre medias se pierde. La traza de retiradas se pierde con su
-- tabla (no tiene texto). _kyc_retencion_candidato vuelve LITERAL a la viva del 15-oct (md5(prosrc) 206cb44b7784b6142164499c62b9696d).
-- destructivo-ok: borra las tablas y funciones que creo la migracion despues de devolver su texto a clients.notes
set local lock_timeout = '5s';

do $pre$
begin
  if to_regclass('public.cliente_notas') is null then
    raise exception 'cliente_notas no existe: no hay nada que revertir';
  end if;
end $pre$;

drop trigger if exists trg_clients_notas_a_historial on public.clients;
drop trigger if exists trg_clients_notas_al_borrar on public.clients;

update public.clients c
   set notes = s.texto
  from (select n.client_id, string_agg(n.texto, E'\n\n' order by n.creado_en desc, n.id desc) as texto
          from public.cliente_notas n group by n.client_id) s
 where s.client_id = c.id;

drop function if exists public._clients_notas_a_historial();
drop function if exists public._clients_notas_al_borrar();
drop function if exists public.cliente_notas_datos(uuid);
drop function if exists public.cliente_nota_agrega(uuid, text);
drop function if exists public.cliente_nota_retira(bigint, text);
drop function if exists public._cliente_ficha_ve(uuid);
drop table if exists public.cliente_notas_retiradas;
drop table if exists public.cliente_notas;
drop function if exists public._cliente_notas_inmutable();
drop function if exists public._cliente_notas_retiradas_solo_anade();

CREATE OR REPLACE FUNCTION public._kyc_retencion_candidato(p_id uuid, p_corte timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ult timestamptz;
begin
  if not exists (select 1 from public.documents d where d.client_id = p_id and d.retirado_el is null
                   and d.doc_type in ('passport', 'npwp', 'visa', 'proof_of_funds', 'proof_of_address', 'other')) then
    return false;
  end if;
  if exists (select 1 from public.documents d where d.client_id = p_id
               and (d.doc_type = 'signed_contract' or d.contrato_id is not null or d.reservation_id is not null)) then
    return false;
  end if;
  select greatest(c.created_at, c.kyc_verificado_el,
                  (select max(d.uploaded_at) from public.documents d where d.client_id = c.id),
                  (select max(cd.corregido_en) from public.correcciones_datos cd where cd.tabla = 'clients' and cd.fila_id = c.id))
    into v_ult from public.clients c where c.id = p_id;
  if v_ult is null or v_ult >= p_corte then return false; end if;
  return (public._sc_referencias_cliente(p_id) - 'public.documents') = '{}'::jsonb;
end $function$;
