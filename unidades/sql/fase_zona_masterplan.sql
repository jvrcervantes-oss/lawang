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
--
-- Aplicado en Supabase con apply_migration (dos pasos: primero la columna,
-- luego la vista — un CREATE OR REPLACE VIEW no puede insertar una columna en
-- medio de las que ya existen, así que las dos nuevas van al final del
-- SELECT). Este fichero es el espejo en el repo; unidades/ no tenía carpeta
-- sql/ propia hasta ahora (a diferencia de contracts/, operaciones/, facturas/).
alter table public.unidades
  add column if not exists fase_masterplan text,
  add column if not exists zona_masterplan text;

create or replace view public.unidades_estado as
 SELECT u.id,
    u.codigo,
    u.proyecto,
    u.tipo,
    u.superficie_m2,
    u.precio,
    u.moneda,
    u.estado,
    u.contrato_id,
    u.notas,
    u.created_at,
    u.precio_suelo,
    u.precio_construccion,
    u.modelo,
    u.obra_fase,
    u.obra_fecha_entrega,
    u.obra_actualizado,
    c.numero AS contrato_numero,
    c.comprador_nombre,
    c.bloqueado AS contrato_firmado,
    COALESCE(f.facturado, 0::numeric) AS facturado,
        CASE
            WHEN u.precio > 0::numeric THEN round(COALESCE(f.facturado, 0::numeric) / u.precio * 100::numeric, 1)
            ELSE NULL::numeric
        END AS pct_cobrado,
    u.fase_masterplan,
    u.zona_masterplan
   FROM unidades u
     LEFT JOIN contratos c ON c.id = u.contrato_id
     LEFT JOIN LATERAL ( SELECT sum(x.total) AS facturado
           FROM facturas x
          WHERE x.contrato_id = u.contrato_id AND COALESCE(x.anulada, false) = false AND x.tipo <> 'proforma'::text) f ON true;
