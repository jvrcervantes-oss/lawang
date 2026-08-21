-- El libro real es la fila 1. Hasta ahora el CHECK obligaba a que solo existiese esa,
-- asi que probar el servidor en local escribia SOBRE la contabilidad de verdad: la unica
-- proteccion era que quien probara se acordase. Se abre el rango para que exista una fila
-- de pruebas (CUENTAS_ROW=9) y el guardrail deje de depender de la memoria de nadie.
alter table public.axisworks_cuentas drop constraint if exists axisworks_cuentas_id_check;
alter table public.axisworks_cuentas add constraint axisworks_cuentas_id_check
  check (id between 1 and 9);;
