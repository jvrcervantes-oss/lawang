-- destructivo-ok: solo UPDATE de una columna nullable (proyecto_id) de NULL a un
-- valor, sobre 8 filas identificadas por numero exacto. Reversible (volver a NULL).
-- No borra filas ni columnas. 8 recibís de 4-ago-2026 (antes de que existiera
-- proyecto_id en facturas, 22-ago) cuyo texto "Sumba Hills SH - NN" identifica
-- el proyecto sin ambigüedad; no tocan REC00012 (sin texto de proyecto, se deja
-- sin adivinar). Encargo del owner, 18-sep-2026.
update public.facturas
   set proyecto_id = '2f4fb2ad-a6ea-4c0a-862c-e54e34079f56'
 where numero in ('REC00006','REC00007','REC00008','REC00009','REC00010','REC00011','REC00013','REC00014')
   and proyecto_id is null;;
