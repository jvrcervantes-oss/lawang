-- CUÁNTOS CONTRATOS USAN CADA CUENTA — para que el panel avise con un número.
--
-- Hallazgo de la consulta de deploy del 14-sep (Legal + Administración): al hacer
-- `es_escrow` editable desde un panel, la casilla que decide si el contrato
-- imprime la cláusula «Naturaleza de la cuenta — depósito en garantía» pasó a
-- estar a un clic. Y hay 45 contratos FIRMADOS apuntando a cuentas afectadas
-- (`notario_nyoman_wiryasa`: 3 firmados de 29). Cambiar esa casilla cambia lo que
-- imprimen si alguien los reabre.
--
-- NO se bloquea el cambio: el owner tiene que poder corregir un dato mal puesto,
-- y prohibirlo obligaría a crear una cuenta duplicada para arreglar una errata.
-- Lo que faltaba es que la pantalla lo DIGA con una cifra delante en el momento
-- de decidir, en vez de un aviso genérico que se lee una vez y se ignora.
--
-- SECURITY DEFINER y gateada a super admin: lo que devuelve son RECUENTOS, sin
-- ningún dato de comprador ni de contrato, y el agregado tiene que ver los 223
-- contratos aunque la RLS del lector no llegue a todos — si contara solo los
-- suyos diría «0 firmados» y el aviso mentiría justo en el sentido peligroso.
-- `search_path` fijado: es DEFINER (advisor `function_search_path_mutable`).
create or replace function public.cuentas_uso()
returns table (clave text, contratos bigint, firmados bigint)
language sql
security definer
set search_path = ''
as $$
  select c.clave,
         count(ct.id)                                as contratos,
         count(ct.id) filter (where ct.bloqueado)    as firmados
  from public.cuentas_bancarias c
  left join public.contratos ct
         on ct.datos->'fields'->>'cuenta_bancaria' = c.clave
  where public.es_super_admin()
  group by c.clave;
$$;

revoke all on function public.cuentas_uso() from public;
revoke all on function public.cuentas_uso() from anon;
grant execute on function public.cuentas_uso() to authenticated;;
