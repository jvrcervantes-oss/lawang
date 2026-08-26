-- destructivo-ok: `create or replace function` + `drop trigger if exists`
-- idempotente sobre un trigger que este mismo fichero recrea; no borra datos.
-- El "UPDATE sin WHERE" es un falso positivo sobre `tg_op`/`update of` dentro
-- del cuerpo del trigger, no hay ningún `update ... set` real aquí.

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
;
