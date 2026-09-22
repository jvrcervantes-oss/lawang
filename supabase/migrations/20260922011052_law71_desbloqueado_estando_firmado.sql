-- ════════════════════════════════════════════════════════════════════════════
-- FIX URGENTE — colisión del evento 'desbloqueado' — 22-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Dos triggers AFTER UPDATE en contratos insertaban el MISMO string en
-- contrato_eventos por motivos distintos: contrato_evento_log() (evento normal
-- de ciclo de vida — cualquier admin desbloquea un contrato editable) y
-- trg_registra_edicion_privilegiada() (LAW-71 — un super_admin salta el freno
-- y desbloquea un contrato YA FIRMADO, que nadie más puede tocar). La policy
-- del 21-sep (20260921143154_law_contrato_eventos_solo_dueno_no_privilegios)
-- excluye 'desbloqueado' de la vista del agente raso para tapar el SEGUNDO
-- caso — y de paso tapa también el primero, que es justo el evento normal que
-- el dueño del contrato SÍ debe poder ver en su propio historial.
--
-- Fix: el salto de privilegio pasa a llamarse 'desbloqueado_estando_firmado',
-- mismo patrón que 'editado_estando_firmado' (la otra rama del mismo trigger,
-- ya con nombre propio desde el 19-ago). 'desbloqueado' sigue vivo para el
-- caso normal. 0 filas existen hoy con evento='desbloqueado' (verificado antes
-- de aplicar) — no hace falta backfill.
--
-- Verificado en transacción ROLLBACK contra CR00007 (bloqueado real, creado_por
-- = un agente raso real): el agente ve 'desbloqueado' de su propio contrato,
-- no ve 'desbloqueado_estando_firmado' de ningún contrato; super_admin ve
-- ambos. privilegios_ejercidos: agente 0 filas, super_admin 1.

-- destructivo-ok: DROP CONSTRAINT + ADD CONSTRAINT (se sustituye por una lista
-- más amplia, ningún valor existente se quita) y DROP POLICY + CREATE POLICY
-- de SELECT (mismo patrón que la migración que se está corrigiendo). No borra
-- filas, no toca RLS ni el esquema auth.
alter table public.contrato_eventos drop constraint contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array[
    'creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta','firma_recogida',
    'firma_anulada','firmado_del_todo','desbloqueado','traspaso',
    'editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear','cobro_a_factura_huerfana',
    'cobro_a_otro_comprador','comprador_sin_ficha','factura_borrada','contrato_borrado','reserva_liberada'
  ]));

comment on constraint contrato_eventos_evento_check on public.contrato_eventos is
  'Lista cerrada de eventos. Al anadir uno nuevo en codigo hay que anadirlo AQUI: si no, la escritura falla y el sintoma aparece lejos de la causa. Lo vigila tools/test.py via contracts/eventos.test.js (que lee sql/super_admin_poderes.sql, no esta migracion).';

-- 2) el trigger de LAW-71: solo cambia el nombre del evento en la rama else
create or replace function public.trg_registra_edicion_privilegiada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(old.bloqueado, false) then
    perform public.registra_privilegio(new.id,
      case when coalesce(new.bloqueado, false) then 'editado_estando_firmado' else 'desbloqueado_estando_firmado' end,
      jsonb_build_object('numero', old.numero, 'bloqueado_antes', old.bloqueado,
                         'bloqueado_despues', new.bloqueado));
  end if;
  return new;
end $$;

-- LAW-71 ya documentó que esto se olvida dos veces si no se repite explícito
-- tras cada CREATE OR REPLACE de esta función.
revoke all on function public.trg_registra_edicion_privilegiada() from public, anon, authenticated;

-- 3) la policy del 21-sep: 'desbloqueado' sale de la lista de exclusión,
-- 'desbloqueado_estando_firmado' entra en su lugar
drop policy "super_admin ve todo, el resto solo eventos normales de sus contratos" on public.contrato_eventos;
create policy "super_admin ve todo, el resto solo eventos normales de sus contratos"
  on public.contrato_eventos
  for select to authenticated
  using (
    public.es_super_admin()
    or (
      public.es_agente()
      and evento not in (
        'editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear',
        'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha'
      )
      and exists (
        select 1 from public.contratos c
         where c.id = contrato_eventos.contrato_id
           and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))
      )
    )
  );

-- 4) la vista de auditoría: mismo cambio de literal
create or replace view public.privilegios_ejercidos as
select e.creado_en as cuando, e.quien, e.evento, c.numero as contrato, e.detalle
  from public.contrato_eventos e
  left join public.contratos c on c.id = e.contrato_id
 where e.evento in ('editado_estando_firmado','desbloqueado_estando_firmado','factura_sin_bloquear',
                    'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha')
union all
select b.borrado_en, b.quien, 'borrado_' || b.tabla, b.numero,
       jsonb_build_object('fila_id', b.fila_id)
  from public.borrados b;

-- CREATE OR REPLACE VIEW resetea security_invoker (gotcha ya reincidente en
-- este repo, p.ej. unidades_estado) -- se re-fija explícito, siempre.
alter view public.privilegios_ejercidos set (security_invoker = true);
grant select on public.privilegios_ejercidos to authenticated;
