-- destructivo-ok: solo UPDATE de una columna nullable (proyecto_id) de NULL a un
-- valor, sobre 8 filas identificadas por numero exacto. Reversible (volver a
-- NULL). No borra filas ni columnas.
--
-- 8 recibís de agosto de 2026 (antes de que existiera `facturas.proyecto_id`,
-- añadida el 22-ago) que nunca quedaron enlazados a ningún contrato y cuyo
-- `proyecto_nombre` en texto libre decía "Sumba Hills SH - NN" — el mismo
-- patrón que dejaba el "Total Cobrado" de un proyecto por debajo de lo real
-- (ver 18-sep-2026, agrupación por proyecto_id en intranet/v4/assets/datos.js).
-- Sin proyecto_id, estos 8 (146.610 €) quedaban fuera del total de Sumba Hills
-- aun después de ese fix. Se identifican por el texto porque no hay
-- contrato_id que los ligue; un noveno recibí de la misma fecha (REC00012, sin
-- texto de proyecto) se deja tal cual — encargo del owner, 18-sep-2026.
update public.facturas
   set proyecto_id = '2f4fb2ad-a6ea-4c0a-862c-e54e34079f56'
 where numero in ('REC00006', 'REC00007', 'REC00008', 'REC00009',
                  'REC00010', 'REC00011', 'REC00013', 'REC00014')
   and proyecto_id is null;
