-- LAW-474 (f), cierre del hueco (30-sep-2026): el trigger de 20260930120030 solo miraba UPDATE OF closer_email. Un
-- super admin podía llamar crm_contrato_closer_set(raíz, NULL, actual) —que BORRA la fila de contrato_closer— y luego
-- asignar otro closer: eso es un INSERT, el trigger no saltaba y el motor devengaba para el nuevo lo ya devengado al
-- anterior. Ahora quitar el closer de una venta con devengos vivos también se bloquea (BEFORE DELETE, mismo chequeo).
-- La función devuelve OLD en el borrado (NEW es NULL ahí: devolverlo cancelaría en silencio cualquier desasignación).
-- Único escritor que borra filas de contrato_closer (grep de cuerpos vivos, 30-sep): crm_contrato_closer_set.
-- De paso: el comentario de anulado_por_modo ya no promete una reposición que aún no está aplicada.

create or replace function public._trg_contrato_closer_devengos_vivos()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if exists (select 1 from public.comisiones_devengadas d
              where d.contrato_raiz_id = old.contrato_id and d.estado <> 'anulada') then
    raise exception 'Esta venta ya tiene comisiones vivas: para cambiar el closer, un administrador las anula antes con motivo (así el nuevo closer no cobra lo que ya devengó el anterior)'
      using errcode = '22023';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $function$;

revoke all on function public._trg_contrato_closer_devengos_vivos() from public, anon, authenticated;

create trigger trg_contrato_closer_a_devengos_vivos_borrado
  before delete on public.contrato_closer
  for each row
  execute function public._trg_contrato_closer_devengos_vivos();

comment on column public.comisiones_devengadas.anulado_por_modo is
  'LAW-474 (a): true si la anuló _venta_modo_aplica al cambiar el modo de la venta (una anulación de un administrador '
  'queda en false). La reposición automática que la usa está pendiente de aplicar (supabase/pendientes/'
  'PENDIENTE_law474_a_b_reposicion_y_roles.sql, espera OK del owner).';
