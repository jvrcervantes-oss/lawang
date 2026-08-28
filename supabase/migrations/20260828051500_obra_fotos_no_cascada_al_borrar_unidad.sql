-- destructivo-ok: ALTER TABLE que cambia la clausula ON DELETE de una FK
-- (definicion, no datos) -- ningun DELETE real la ha disparado nunca: hasta
-- el commit de hoy (borrar_unidad_rpc) `unidades` no tenia NINGUN borrado
-- desde la app, asi que este CASCADE llevaba sin usarse desde que se creo.
--
-- Hallazgo Seguridad (28-ago-2026, revision de despliegue de borrar_unidad):
-- el chequeo de fotos en borrar_unidad() ("select count(*) from obra_fotos")
-- y el DELETE de la unidad corren en sentencias separadas, sin lock -- una
-- foto insertada justo entre las dos (READ COMMITTED) no la ve el chequeo, y
-- el DELETE la arrastra en cascada en silencio en vez de frenar como el
-- dialogo de la UI promete ("Solo se puede si no tiene... fotos de obra").
--
-- La FK a contratos.unidad_id ya es NO ACTION (bloquea el DELETE si queda
-- algo colgando) -- se alinea obra_fotos al mismo criterio: el borrado en si
-- es la unica garantia que no tiene ventana de carrera, un chequeo de
-- aplicacion antes siempre puede perder la carrera con un insert concurrente.
alter table public.obra_fotos
  drop constraint obra_fotos_unidad_id_fkey,
  add constraint obra_fotos_unidad_id_fkey
    foreign key (unidad_id) references public.unidades(id);
