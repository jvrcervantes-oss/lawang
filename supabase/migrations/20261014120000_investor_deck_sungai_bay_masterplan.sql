-- Investor Deck: Sungai Bay W12 — enciende el masterplan interactivo (14-oct-2026).
-- Owner (14-oct, AskUserQuestion tras comparar 4 opciones en un artifact): "General + bloques"
-- -> 4 paginas del manifiesto (Overview, Block A, Block B, Block C) y, al tocar una parcela,
-- salto a su fila del inventario como en Palm Field. Sin codigo nuevo: el deck generico ya
-- pinta pestanas por pagina (precedente: sumbahills.json).
--
-- Manifiesto /investor-deck/masterplan/sungai-bay.json, fichero estatico del repo. Geometria:
-- poligonos del PDF vectorial del CAD (modelos3d/lawang/parcelario_preidea, 12-oct) proyectados
-- a la foto de dron y encajados por bloque sobre la foto con parcelario del owner (residuo
-- mediano < 0,5 px). Cada imagen se rinde desde la foto limpia con trazo y rotulos dibujados a su
-- propia resolucion (owner, 14-oct: al ampliar se perdia calidad del trazo y las letras).
-- 96 de 96 codigos de la intranet con poligono; m2 de la intranet = m2 rotulados en el plano.
-- La parcela de 98,44 m2 sin codigo (LAW-537) se dibuja sin rotulo y sin zona clicable.
--
-- Solo esta fila. Valor anterior: masterplan_activo=false, masterplan_imagen=null.
-- Revertir: update ... set masterplan_activo=false, masterplan_imagen=null (misma fila).
update public.deck_config_proyecto
   set masterplan_activo = true,
       masterplan_imagen = '/investor-deck/masterplan/sungai-bay.json'
 where proyecto_id = (select id from public.proyectos where slug = 'sungai-bay');
