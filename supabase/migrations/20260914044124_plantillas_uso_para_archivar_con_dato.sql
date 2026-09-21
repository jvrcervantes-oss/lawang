-- CUÁNTOS CONTRATOS TIENE CADA TIPO — para archivar mirando el uso, no a ojo.
--
-- Owner: «así puedo quitar morralla que no usemos». «Que no usemos» es un dato, y
-- sin él archivar es adivinar: de los 18 tipos que la app puede emitir, 11 se han
-- usado alguna vez y hay varios con cero. El panel enseña la cifra al lado del
-- interruptor para que la decisión se tome con eso delante.
--
-- Clon de `cuentas_uso()`: solo RECUENTOS, ni un dato de comprador. SECURITY
-- DEFINER porque el agregado tiene que ver los 223 contratos aunque la RLS del
-- lector no llegue a todos —si contara solo los suyos, un tipo en uso podría
-- parecer muerto y se archivaría— y gateada a super admin, que es el único que
-- puede archivar. `search_path` fijado, como toda función DEFINER de aquí.
--
-- Devuelve por `contratos.tipo`; el panel traduce a slug de plantilla con
-- `TIPO_SLUG` (assets/vocabulario.js), que es la fuente única de ese mapeo.
create or replace function public.plantillas_uso()
returns table (tipo text, contratos bigint, firmados bigint, ultimo date)
language sql
security definer
set search_path = ''
as $$
  select ct.tipo,
         count(*)                                as contratos,
         count(*) filter (where ct.bloqueado)    as firmados,
         max(ct.fecha_firma)                     as ultimo
  from public.contratos ct
  where public.es_super_admin()
  group by ct.tipo;
$$;

revoke all on function public.plantillas_uso() from public;
revoke all on function public.plantillas_uso() from anon;
grant execute on function public.plantillas_uso() to authenticated;;
