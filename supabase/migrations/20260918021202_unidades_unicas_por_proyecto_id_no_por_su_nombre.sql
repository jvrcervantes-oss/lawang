-- La unicidad de una parcela pasa a medirse por `proyecto_id`, no por el TEXTO
-- del nombre del proyecto. Hallazgo de Datos en la revision previa del 18-sep-2026
-- (encargos/20260918_lawang_multiempresa_karana.md): `unidades_proyecto_codigo_key`
-- es `unique (proyecto, codigo)` sobre un espejo de texto; el dia que dos
-- organizaciones puedan tener proyectos con el mismo nombre, dos parcelas distintas
-- colisionan o dejan de colisionar segun como este escrito el espejo.
--
-- Comprobado antes de crearlo: 0 duplicados de (proyecto_id, codigo) en las 461
-- unidades, y 0 unidades sin proyecto_id.
--
-- NO se retira la constraint vieja, a proposito: hoy `proyectos.nombre` sigue
-- siendo UNIQUE global, asi que la de texto no estorba y ademas cubre el unico
-- hueco de la nueva (varias filas con proyecto_id nulo). Se retira el dia que se
-- decida que dos organizaciones pueden repetir nombre de proyecto -- decision
-- abierta del encargo, no de esta migracion.
create unique index if not exists unidades_proyecto_id_codigo_key
  on public.unidades (proyecto_id, codigo);

comment on index public.unidades_proyecto_id_codigo_key is
  'Unicidad real de la parcela: por id de proyecto. La de (proyecto, codigo) es el espejo de texto y se retira cuando los nombres dejen de ser unicos globales.';
