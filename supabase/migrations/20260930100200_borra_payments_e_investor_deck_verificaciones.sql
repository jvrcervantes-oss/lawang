-- destructivo-ok: owner 30-sep-2026 («si, aplica»): 2 tablas con 0 filas y sin dependencias; backup datos hecho 09:51
-- 30-sep-2026 · Limpieza de superficie (orden del owner). Tablas verificadas: 0 filas y sin dependencias
-- (sin vistas, sin funciones, sin triggers, sin cron; `payments` solo tiene FK SALIENTE hacia `reservations`, que NO se toca).
-- Inversa: contracts/sql/inversa_limpieza_superficie_20260930.sql
drop table public.payments;
drop table public.investor_deck_verificaciones;
