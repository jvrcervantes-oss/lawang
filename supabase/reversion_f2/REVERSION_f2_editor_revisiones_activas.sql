-- Reversion de la migracion 20261010000500 (E10 · selector de revision para agentes, 8-oct-2026): quita la RPC de lectura. No hay datos que perder.
-- destructivo-ok: elimina una funcion de solo lectura sin filas propias
drop function if exists public.plantilla_contrato_revisiones_activas(text, text);
