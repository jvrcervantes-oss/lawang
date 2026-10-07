-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- BLOQUE 10 · 1/2 (Fase 2, prueba final de aislamiento, 7-oct-2026). La prueba (supabase/pruebas/f2_aislamiento_s1_rls.sql) cazo SEIS lecturas con la policy «es_agente()» a secas:
--   un admin_empresa / super_admin_empresa de UNA empresa veia filas de la OTRA. Se acotan igual que el resto del bloque 1-9: quien tiene el alcance acotado (alcance_restringido()) solo ve lo de sus empresas;
--   para los 34 usuarios de hoy (alcance_restringido() = false) la condicion es identica a la de antes (misma foto de ids, ver f2_aislamiento.sql).
--     contrato_compradores  (que comprador esta en que contrato, de las dos empresas)       -> por la empresa del contrato (proyecto_en_alcance)
--     hilo_soporte / mensajes_comprador (tickets y mensajes de compradores)                  -> solo de compradores que el rol ve (clients ya filtra por empresa)
--     proyecto_cuentas / proyecto_eventos / proyecto_plazo_pago (cuentas, eventos y plazos)  -> por la empresa del proyecto
--     deck_publicaciones    (historial antes/despues de fotos, previsiones y config del deck) -> por el proyecto que lleva dentro el registro; sin proyecto, solo no acotados
-- destructivo-ok: cambia policies de SELECT (sin tocar filas ni permisos de tabla); nadie real tiene rol de empresa
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b10.sql
drop policy if exists "agentes leen contrato_compradores" on public.contrato_compradores;
create policy "agentes leen contrato_compradores" on public.contrato_compradores for select to authenticated, lw_lector
  using (public.es_agente() and (not (select public.alcance_restringido())
         or public.proyecto_en_alcance((select c.proyecto_id from public.contratos c where c.id = contrato_compradores.contrato_id))));

drop policy if exists "equipo lee los tickets" on public.hilo_soporte;
create policy "equipo lee los tickets" on public.hilo_soporte for select to authenticated, lw_lector
  using (public.es_agente() and (not (select public.alcance_restringido())
         or exists (select 1 from public.clients k where k.id = hilo_soporte.client_id)));

drop policy if exists "equipo ve hilos de mensajes" on public.mensajes_comprador;
create policy "equipo ve hilos de mensajes" on public.mensajes_comprador for select to authenticated, lw_lector
  using (public.es_agente() and (not (select public.alcance_restringido())
         or exists (select 1 from public.clients k where k.id = mensajes_comprador.client_id)));

drop policy if exists "cuentas por proyecto: agentes" on public.proyecto_cuentas;
create policy "cuentas por proyecto: agentes" on public.proyecto_cuentas for select to authenticated, lw_lector
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_cuentas.proyecto_id)));

drop policy if exists proyecto_eventos_select on public.proyecto_eventos;
create policy proyecto_eventos_select on public.proyecto_eventos for select to public
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_eventos.proyecto_id)));

drop policy if exists proyecto_plazo_pago_select on public.proyecto_plazo_pago;
create policy proyecto_plazo_pago_select on public.proyecto_plazo_pago for select to public
  using (public.es_agente() and (not (select public.alcance_restringido()) or public.proyecto_en_alcance(proyecto_plazo_pago.proyecto_id)));

drop policy if exists "deck_publicaciones: leer" on public.deck_publicaciones;
create policy "deck_publicaciones: leer" on public.deck_publicaciones for select to public
  using (public.es_agente() and (not (select public.alcance_restringido())
         or public.proyecto_en_alcance(nullif(coalesce(deck_publicaciones.despues ->> 'proyecto_id', deck_publicaciones.antes ->> 'proyecto_id'), '')::uuid)));
