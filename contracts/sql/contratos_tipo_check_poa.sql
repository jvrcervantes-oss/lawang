-- `poa` entra en la restricción CHECK de contratos.tipo — 14-ago-2026.
--
-- SÍNTOMA: guardar un Poder Notarial devolvía 400 con
--   new row for relation "contratos" violates check constraint "contratos_tipo_check"
-- y, como efecto colateral, el campo "Nº de contrato" nunca se rellenaba: el
-- número lo pone el trigger set_contrato_numero() AL INSERTAR, y el insert no
-- llegaba a ocurrir.
--
-- CAUSA: el tipo 'poa' se dio de alta el 10-ago en la app (CONTRACT_TIPO en
-- contracts/app.html) y en la numeración (contrato_numero_serie_poa.sql, serie
-- PA), pero no en la lista de valores permitidos de la columna. La app lo
-- mandaba y la base de datos lo rechazaba. Mismo agujero que el 28-jul con
-- clients/documents: de una tabla que no creaste hay que leer los CHECK, no
-- solo las columnas.
--
-- POR QUÉ NO VA UNA LISTA ESCRITA A MANO: no sé de memoria los 13 valores que
-- hay hoy en la restricción, y escribir mi propia lista podría dejar fuera un
-- tipo antiguo que sí tenga filas — el ADD fallaría (bien) o, peor, alguien
-- lo "arreglaría" borrando el que sobra. Así que esto LEE la definición
-- vigente y le añade 'poa' delante, sin tocar el resto.
--
-- Es idempotente: si 'poa' ya está, no hace nada. Y va dentro de un bloque DO,
-- o sea una sola transacción: si el ADD fallara, el DROP se deshace y la tabla
-- NO se queda sin restricción.

do $$
declare
  def   text;
  nueva text;
begin
  select pg_get_constraintdef(c.oid) into def
    from pg_constraint c
   where c.conrelid = 'public.contratos'::regclass
     and c.conname  = 'contratos_tipo_check';

  if def is null then
    raise exception 'No existe la restriccion contratos_tipo_check — revisa el nombre antes de seguir';
  end if;

  if position('''poa''' in def) > 0 then
    raise notice 'contratos_tipo_check ya admite poa; no se toca nada';
    return;
  end if;

  nueva := replace(def, 'ARRAY[', 'ARRAY[''poa''::text, ');
  if nueva = def then
    raise exception 'La restriccion no tiene la forma ARRAY[...] esperada: %', def;
  end if;

  execute 'alter table public.contratos drop constraint contratos_tipo_check';
  execute 'alter table public.contratos add constraint contratos_tipo_check ' || nueva;
  raise notice 'contratos_tipo_check actualizada: %', nueva;
end $$;

-- Comprobación: la definición debe incluir ahora 'poa'.
-- select pg_get_constraintdef(oid) from pg_constraint
--  where conrelid = 'public.contratos'::regclass and conname = 'contratos_tipo_check';
