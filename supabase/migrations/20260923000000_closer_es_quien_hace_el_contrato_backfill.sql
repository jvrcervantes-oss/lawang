-- El closer de una venta es quien hace el contrato — 22-sep-2026, owner
-- ----------------------------------------------------------------------------
-- Regla dicha por el owner al explicar Comisiones: «'Closer atribuido a cada
-- venta' es quien hace el contrato». Para los contratos NUEVOS ya la aplica el
-- trigger trg_contrato_closer_semilla (siembra contrato_closer con creado_por
-- al insertar una raíz, autor 'sistema:alta'). Pero 121 raíces anteriores a
-- ese trigger seguían sin closer, y sin closer el motor de comisiones no
-- devenga nada (comisiones_evaluar_contrato: «sin closer atribuido: nada que
-- devengar todavía»). Este backfill aplica a lo antiguo la misma regla y con
-- el mismo criterio que el trigger: solo autores que siguen activos en la
-- intranet, y solo donde no había atribución (la manual, si la hubo, manda).
-- Deja rastro en contrato_closer_log con autor 'sistema:backfill', para que
-- en el historial se distinga de una atribución hecha a mano.
with sembrados as (
  insert into public.contrato_closer (contrato_id, closer_email, asignado_por, asignado_en)
  select c.id, c.creado_por, 'sistema:backfill', now()
    from public.contratos c
   where c.contrato_padre_id is null
     and c.creado_por is not null
     and public.crm_usuario_activo(c.creado_por)
     and not exists (select 1 from public.contrato_closer k where k.contrato_id = c.id)
  returning contrato_id, closer_email
)
insert into public.contrato_closer_log (contrato_id, de, a, autor)
select contrato_id, null, closer_email, 'sistema:backfill' from sembrados;
