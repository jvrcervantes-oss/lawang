-- Editar los tramos de una condición de comisión — 22-sep-2026, owner
-- ----------------------------------------------------------------------------
-- «Déjame editar condiciones de comisión una vez ya creadas». Los tramos se
-- sustituyen enteros (borrar + insertar), pero el trigger de la tabla,
-- condicion_tramos_suma_100, es CONSTRAINT … INITIALLY DEFERRED: comprueba
-- que sumen 100 al CERRAR la transacción. Por REST cada petición es su propia
-- transacción, así que un DELETE de todos los tramos moriría solo (suman 0)
-- antes de que llegara el INSERT. Esta función hace las dos cosas en una
-- transacción; el trigger sigue siendo el guardián de la suma.
--
-- SECURITY INVOKER a propósito: la RLS de condicion_tramos («escribir»,
-- es_admin) es el gate, y así no hay un segundo gate que mantener. Solo con
-- una condición SIN devengos: comisiones_devengadas cita cada tramo por id
-- (FK NO ACTION) con su importe congelado — con devengos, el DELETE fallaría
-- por la FK, y aquí se dice en claro antes.
create or replace function public.condicion_tramos_reemplaza(p_condicion uuid, p_tramos jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_n integer;
begin
  if exists (select 1 from public.comisiones_devengadas d where d.condicion_id = p_condicion) then
    raise exception 'Esta condición ya ha devengado comisiones: sus tramos no se cambian. Desactívala y crea otra.'
      using errcode = '23514';
  end if;
  if jsonb_typeof(p_tramos) <> 'array' or jsonb_array_length(p_tramos) = 0 then
    raise exception 'Hacen falta tramos' using errcode = '23514';
  end if;

  delete from public.condicion_tramos where condicion_id = p_condicion;

  insert into public.condicion_tramos (condicion_id, orden, disparador_tipo, umbral, pct_tramo)
  select p_condicion, ord,
         t->>'disparador_tipo',
         case when (t->>'disparador_tipo') like 'pct_cobrado_%' then (t->>'umbral')::numeric end,
         (t->>'pct_tramo')::numeric
    from jsonb_array_elements(p_tramos) with ordinality as x(t, ord);

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.condicion_tramos_reemplaza(uuid, jsonb) from public, anon;
grant execute on function public.condicion_tramos_reemplaza(uuid, jsonb) to authenticated, service_role;
