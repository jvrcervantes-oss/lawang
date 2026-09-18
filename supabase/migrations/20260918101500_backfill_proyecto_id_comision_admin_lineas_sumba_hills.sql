-- destructivo-ok: solo UPDATE de una columna nullable (proyecto_id) de NULL a un
-- valor, sobre 8 filas identificadas por recibi_numero exacto. Reversible.
-- No borra filas ni cambia importe/pct/estado.
--
-- Continuación de 20260918100000_backfill_proyecto_id_recibis_sumba_hills_agosto.sql:
-- esa migración enlazó los 8 recibís en `facturas`, pero `comision_admin_lineas`
-- guarda su PROPIO proyecto_id (snapshot al devengar, no una referencia en vivo
-- a facturas), así que seguían apareciendo sin proyecto en el libro de comisión
-- de administración aunque ya lo tuvieran en Facturas. Las 8 líneas están en
-- estado 'pendiente', sin factura de comisión emitida todavía sobre ninguna
-- (hallazgo de Administración en la consulta de deploy, 18-sep-2026).
update public.comision_admin_lineas
   set proyecto_id = '2f4fb2ad-a6ea-4c0a-862c-e54e34079f56'
 where recibi_numero in ('REC00006', 'REC00007', 'REC00008', 'REC00009',
                         'REC00010', 'REC00011', 'REC00013', 'REC00014')
   and proyecto_id is null;
