-- Fase y zona del masterplan de Sumba Hills (10-ago-2026, CSV "SUMBA PLOTS" del
-- cliente: 228 unidades con columnas FASE/ZONE). Nombres deliberadamente
-- distintos de `obra_fase` (que ya existe y es la fase de OBRA/construcción de
-- una unidad concreta, ver obra/index.html): esto es la fase del DESARROLLO del
-- masterplan (I, II...) y la zona/cluster dentro de esa fase (1-7) — dos
-- conceptos distintos que por casualidad ambos se llaman "fase" en el lenguaje
-- del negocio. Columnas nullable y genéricas en la tabla (no hay tablas por
-- proyecto), pero solo se rellenan cuando el CSV las trae — hoy solo Sumba
-- Hills. Texto, no numérico: "I"/"II" no son números y una zona podría no
-- serlo siempre.
alter table public.unidades
  add column if not exists fase_masterplan text,
  add column if not exists zona_masterplan text;;
