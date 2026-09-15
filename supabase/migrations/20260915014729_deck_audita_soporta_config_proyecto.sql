-- Bug real cazado en pruebas (15-sep-2026): deck_audita() daba por hecho que
-- toda tabla auditada tiene columna `id`, con un caso especial ya escrito solo
-- para `deck_forecast_proyecto` (que usa `proyecto_id` como PK). La tabla
-- nueva `deck_config_proyecto` tiene la MISMA forma (proyecto_id como PK, sin
-- columna id) y el primer INSERT de prueba fallo con
-- "record new has no field id". Se generaliza el caso especial a las DOS
-- tablas con PK=proyecto_id en vez de duplicar la rama.
create or replace function public.deck_audita()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if TG_TABLE_NAME in ('deck_forecast_proyecto', 'deck_config_proyecto') then
    v_id := coalesce(new.proyecto_id, old.proyecto_id);
  else
    v_id := coalesce(new.id, old.id);
  end if;

  insert into public.deck_publicaciones (tabla, fila_id, accion, antes, despues)
  values (
    TG_TABLE_NAME,
    v_id,
    case TG_OP when 'INSERT' then 'alta' when 'UPDATE' then 'cambio' else 'baja' end,
    case when TG_OP = 'INSERT' then null else to_jsonb(old) end,
    case when TG_OP = 'DELETE' then null else to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;
