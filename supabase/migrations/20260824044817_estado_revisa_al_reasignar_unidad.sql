-- destructivo-ok: `create or replace function` + `drop trigger if exists`
-- idempotente sobre un trigger que este mismo fichero recrea; no borra datos.
-- El "UPDATE sin WHERE" es un falso positivo sobre `tg_op`/`update of` dentro
-- del cuerpo del trigger, no hay ningún `update ... set` real aquí.
-- ════════════════════════════════════════════════════════════════════════════
-- EL ESTADO NO SE REVISABA AL REASIGNAR unidad_id — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Hallazgo de Desarrollo (auditoría de hoy), sobre el propio trabajo de hoy:
-- `construccion_por_parcela.sql` hizo que `unidad_parte_cobrada()` (el %)
-- dependa de `contratos.unidad_id`, y dejó que un admin pueda REASIGNARLO
-- después de creado el contrato (`trg_valida_unidad_id_contrato`). Pero
-- `avanza_unidad_por_cobro()` (el ESTADO: disponible/vendida/cobrada) solo lo
-- disparan tres triggers — `trg_avanza_por_recibi` (facturas),
-- `trg_avanza_por_aplicacion` (recibi_aplicaciones) y
-- `trg_revalua_unidad_por_precio` (unidades.precio, el arreglo de hoy para
-- B7) — ninguno sobre `contratos.unidad_id`/`contrato_padre_id`. Si un admin
-- corrige a qué parcela pertenece una Construcción ya pagada, el % de la
-- ficha se recalcula al momento (es una vista), pero el `estado` se queda
-- congelado con el valor de ANTES de la reasignación hasta que entre un pago
-- nuevo — la misma contradicción "ficha dice 100%, estado no se ha movido"
-- que el propio commit de hoy dice haber cerrado.
--
-- Mismo patrón que `unidad_revalua_al_corregir_precio.sql`: un trigger más que
-- llama a la función ya existente, no una segunda versión del cálculo.

create or replace function public.trg_revalua_unidad_por_reasignacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.unidad_id is distinct from old.unidad_id
     or new.contrato_padre_id is distinct from old.contrato_padre_id then
    perform public.avanza_unidad_por_cobro(new.id);
    -- la unidad que PERDIÓ la asignación también hay que revisarla: puede
    -- bajar de 'cobrada' si esa Construcción se llevaba su dinero.
    if old.unidad_id is not null and old.unidad_id is distinct from new.unidad_id then
      perform public.avanza_unidad_por_cobro(
        (select contrato_id from public.unidades where id = old.unidad_id)
      );
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.trg_revalua_unidad_por_reasignacion() from public, anon;

drop trigger if exists trg_revalua_unidad_por_reasignacion on public.contratos;
create trigger trg_revalua_unidad_por_reasignacion
  after update of unidad_id, contrato_padre_id on public.contratos
  for each row execute function public.trg_revalua_unidad_por_reasignacion();
