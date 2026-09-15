-- Investor Deck multi-proyecto (15-sep-2026) -- pieza 1/4.
-- Revision previa hecha (Seguridad+Datos+Diseno, CEO/flujos/revision_previa.md)
-- + 3 rondas de confirmacion del owner en la misma sesion. Ver el resto de la
-- tanda en las migraciones siguientes (deck_config_proyecto, investor_deck_activar,
-- deck_config_publico).
--
-- Datos senalo en la revision que hace falta un identificador de URL estable
-- para cada proyecto, distinto de `proyectos.nombre` (que es el nombre
-- operativo interno, el mismo que usa `unidades.proyecto` -- verificado con un
-- JOIN antes de escribir esto: las 29 filas de `proyectos` casan con
-- `unidades.proyecto` sin huerfanos, no hay dos grafias hoy). Aun asi el nombre
-- interno no es apto para URL (espacios, comas, "S3 - S4 Karana") y cambiarlo
-- de forma automatica derivandolo del nombre repetiria el bug ya visto en este
-- repo con el mapeo manual de parcela_master (20260817112306): un slug se
-- escribe a mano, una vez, por quien prepara el deck de ese proyecto -- nunca
-- se infiere solo.
alter table public.proyectos
  add column if not exists slug text unique;

comment on column public.proyectos.slug is
  'Identificador de URL del Investor Deck (investor-deck/<slug>/). Se rellena A MANO por proyecto cuando se prepara su deck -- nunca derivado automaticamente del nombre (evita el bug de mapeo ya visto con parcela_master). NULL = ese proyecto no tiene URL de deck todavia.';

-- Palm Field ya tiene su propia carpeta fisica (investor-deck/palmfield/, fuera
-- de este sistema generico) con esa misma palabra en la URL desde el 10-sep.
-- Se le fija el slug aqui por coherencia de dato, aunque el router nuevo nunca
-- lo sirva a el (el .htaccess deja la carpeta fisica fuera del router a proposito).
update public.proyectos set slug = 'palmfield' where nombre = 'Palm Field W5' and slug is null;
