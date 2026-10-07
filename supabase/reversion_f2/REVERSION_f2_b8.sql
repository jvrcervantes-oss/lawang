-- Reversion del bloque 8 (LAW-496). Los ficheros de migracion renombrados/partidos no tienen reversion (solo cambian de nombre).
grant select on public.sociedades to lw_lector;
