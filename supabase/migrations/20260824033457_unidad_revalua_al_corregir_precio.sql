-- destructivo-ok: el único `drop` es `drop trigger if exists` sobre un trigger
-- que este mismo fichero recrea a continuación (idempotencia estándar, Postgres
-- no tiene `CREATE OR REPLACE TRIGGER` en esta versión); no borra datos ni
-- ningún objeto ajeno.

create or replace function public.trg_revalua_unidad_por_precio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.precio is distinct from old.precio and new.contrato_id is not null then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  return new;
end;
$$;

revoke all on function public.trg_revalua_unidad_por_precio() from public, anon;

drop trigger if exists trg_revalua_unidad_por_precio on public.unidades;
create trigger trg_revalua_unidad_por_precio
  after update of precio on public.unidades
  for each row execute function public.trg_revalua_unidad_por_precio();
;
