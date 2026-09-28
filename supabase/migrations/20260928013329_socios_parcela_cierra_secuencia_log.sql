-- Secuencia de identidad de unidad_socio_log nacida con authenticated=rwU por los default privileges (Seguridad #140-1;
-- la migración socios_parcela revocó la secuencia con nombre pero no la implícita del `generated always as identity`).
-- erp-ok: dato interno propio de Lawang, misma pieza que socios_parcela
revoke all on sequence public.unidad_socio_log_id_seq from public, anon, authenticated;
