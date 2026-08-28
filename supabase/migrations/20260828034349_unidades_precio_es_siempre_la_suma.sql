/* El total de una unidad es SIEMPRE suelo + construccion, sin excepcion
   -- decision del owner, 28-ago-2026, tras el hallazgo de 143 parcelas
   descuadradas (141 Sumba Hills + Bonian A4 + Tamarind C1, origen: una
   carga por CSV del 10-ago que traia una columna de Total que no cuadraba
   con Land/Villa de su propia fila). Las 143 ya se corrigieron con rastro
   en correcciones_datos (fuera de esta migracion, no toca datos).

   Antes: un precio "puesto a mano" mandaba sobre sus partes (para permitir
   un descuento pactado). Eso es justo lo que dejaba colarse un Total
   importado sin cruzar. El owner decidio quitar esa via: ya no hay forma
   de guardar un Total que no sea la suma, ni desde el editor de la unidad
   ni desde una importacion CSV ni desde ningun otro camino futuro -- este
   trigger corre en cualquier INSERT/UPDATE sobre `unidades`, sin importar
   por donde entre.

   Si una unidad no tiene NI suelo NI construccion (los proyectos que viven
   solo de la vista unidades_estado -- Riverfront, Palm Field, Horizon,
   Mejan: verificado 28-ago que ninguna fila con precio propio carece de
   los dos a la vez), el trigger no toca precio: no hay nada de lo que
   derivarlo. */
create or replace function public.unidad_precio_es_la_suma()
returns trigger
language plpgsql
as $$
begin
  if new.precio_suelo is not null or new.precio_construccion is not null then
    new.precio := coalesce(new.precio_suelo, 0) + coalesce(new.precio_construccion, 0);
  end if;
  return new;
end;
$$;

-- destructivo-ok: DROP de un TRIGGER (objeto de definicion), no de datos -- patron estandar de
-- "create or replace" para triggers, que no lo soporta directamente. No borra ninguna fila.
drop trigger if exists trg_unidad_precio_suma on public.unidades;
-- destructivo-ok: "BEFORE INSERT OR UPDATE" es la clausula DDL que declara CUANDO dispara el
-- trigger, no una sentencia UPDATE sobre filas -- el escaner de palabra clave la confunde con una.
create trigger trg_unidad_precio_suma
before insert or update on public.unidades
for each row execute function public.unidad_precio_es_la_suma();
