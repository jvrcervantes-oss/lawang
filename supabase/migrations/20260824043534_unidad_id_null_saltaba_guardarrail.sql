-- destructivo-ok: `create or replace function`, no borra filas ni objetos. El
-- "UPDATE sin WHERE" que marca el guardarraíl es un falso positivo de su
-- heurística de texto sobre `tg_op = 'UPDATE'` (comparación dentro del cuerpo
-- del trigger) — no hay ningún `update ... set` en este fichero.

create or replace function public.trg_valida_unidad_id_contrato()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_raiz uuid;
  v_unidad_contrato uuid;
begin
  if tg_op = 'UPDATE' and new.unidad_id is distinct from old.unidad_id
     and not public.es_admin() then
    raise exception 'solo un admin puede cambiar la parcela de un contrato ya guardado' using errcode = '42501';
  end if;

  if new.unidad_id is null then return new; end if;

  v_raiz := coalesce(new.contrato_padre_id, new.id);
  select contrato_id into v_unidad_contrato from public.unidades where id = new.unidad_id;
  if v_unidad_contrato is distinct from v_raiz then
    raise exception 'unidad_id debe pertenecer a la misma reserva raíz del contrato' using errcode = '23514';
  end if;
  return new;
end;
$$;
;
