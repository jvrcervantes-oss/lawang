-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Fase 2 · bloque 3 · 7b (7-oct-2026): la condicion de 20261008306000_f2_b3_7_cliente_guarda_exclusivo se limito a los roles de empresa (es_admin_en_alguna_empresa()).
--   Se aplico en vivo como un segundo parche (nombre f2_b3_7b_cliente_guarda_solo_roles_empresa), pero el fichero 20261008306000 ya contiene el RESULTADO FINAL de los dos pasos:
--   repetir aqui el parche (un reemplazo de texto sobre la funcion viva) fallaria en una base reconstruida, porque el fragmento ya no existe. Este fichero no hace nada a proposito:
--   existe para que el nombre aplicado tenga su fichero y quede dicho donde esta el texto (LAW-496).
-- destructivo-ok: no hace nada
-- REVERTIR: no procede
select 1;
