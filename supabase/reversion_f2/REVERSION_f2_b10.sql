-- REVERSION del BLOQUE 10 (migraciones 20261008900000 y 20261008900100): devuelve las 8 lecturas a la condicion de antes (7-oct-2026).
-- destructivo-ok: restaura policies de SELECT y la funcion de storage; quita la columna `empresa` de documentos_proyecto (solo guardaba 4 etiquetas)
drop policy if exists "agentes leen contrato_compradores" on public.contrato_compradores;
create policy "agentes leen contrato_compradores" on public.contrato_compradores for select to authenticated, lw_lector using (public.es_agente());
drop policy if exists "equipo lee los tickets" on public.hilo_soporte;
create policy "equipo lee los tickets" on public.hilo_soporte for select to authenticated, lw_lector using (public.es_agente());
drop policy if exists "equipo ve hilos de mensajes" on public.mensajes_comprador;
create policy "equipo ve hilos de mensajes" on public.mensajes_comprador for select to authenticated, lw_lector using (public.es_agente());
drop policy if exists "cuentas por proyecto: agentes" on public.proyecto_cuentas;
create policy "cuentas por proyecto: agentes" on public.proyecto_cuentas for select to authenticated, lw_lector using (public.es_agente());
drop policy if exists proyecto_eventos_select on public.proyecto_eventos;
create policy proyecto_eventos_select on public.proyecto_eventos for select to public using (public.es_agente());
drop policy if exists proyecto_plazo_pago_select on public.proyecto_plazo_pago;
create policy proyecto_plazo_pago_select on public.proyecto_plazo_pago for select to public using (public.es_agente());
drop policy if exists "deck_publicaciones: leer" on public.deck_publicaciones;
create policy "deck_publicaciones: leer" on public.deck_publicaciones for select to public using (public.es_agente());
drop policy if exists "documentacion: leer" on public.documentos_proyecto;
create policy "documentacion: leer" on public.documentos_proyecto for select to authenticated, lw_lector
  using (public.es_agente() and (general or public.puede_proyecto(proyecto, proyecto_id)));
create or replace function public.agente_ve_documento_proyecto(p_name text) returns boolean
 language sql stable security definer set search_path to ''
as $function$
  select public.es_agente() and exists (select 1 from public.documentos_proyecto dp where dp.path = p_name and (dp.general or public.puede_proyecto(dp.proyecto, dp.proyecto_id)))
$function$;
alter table public.documentos_proyecto drop column if exists empresa;
