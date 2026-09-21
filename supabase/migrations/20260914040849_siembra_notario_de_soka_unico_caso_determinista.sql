-- Se siembra UNA fila, y es a propósito.
--
-- De los 157 contratos con cuenta, el único caso determinista de verdad es
-- Soka Village W2 → `notario_nyoman_wiryasa` en sus Bloqueos de Parcela: 18 de
-- 18, sin una sola excepción, entre el 18-ago-2025 y el 1-abr-2026.
--
-- Los demás proyectos NO se siembran aunque tengan un favorito claro: Mejan
-- Village S7, Bonian Village y Tamarind Rise tienen TRES cuentas distintas cada
-- uno en ese mismo tipo de contrato. Con la semántica de restringir que pidió el
-- owner, sembrar «la más usada» le quitaría al comercial opciones que estuvo
-- usando este mismo mes, y ninguna de esas elecciones está demostrada
-- equivocada. Esos proyectos heredan el reparto general hasta que el owner diga
-- lo contrario desde el panel, con el mapa de lo que se ha usado delante.
--
-- Nivel `ppjb_parcela` y NO `'*'`: en Soka, los contratos de construcción cobran
-- en `sandalwoods_dbs_sg`, no en el notario. En `'*'` esta fila los habría roto.
insert into public.proyecto_cuentas (proyecto_id, slug, clave, es_default)
select p.id, 'ppjb_parcela', 'notario_nyoman_wiryasa', true
from public.proyectos p
where p.nombre = 'Soka Village W2'
on conflict (proyecto_id, slug, clave) do nothing;;
