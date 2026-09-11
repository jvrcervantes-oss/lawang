-- destructivo-ok: CREATE OR REPLACE VIEW sustituye la misma vista con una
-- columna mas al final -- ninguna columna existente se quita ni se reordena
-- (Postgres no deja insertar en medio en un CREATE OR REPLACE: 42P16 la
-- primera vez que se probo insertandola antes de `facturado`).
-- ════════════════════════════════════════════════════════════════════════════
-- unidades_estado: añade qué agente creó el contrato — 11-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del owner: en Proyectos, ver de un vistazo qué agente hizo el
-- contrato de cada unidad, sin abrir el contrato. `contratos.creado_por` ya
-- existe (email del autor); esta vista solo lo expone como
-- `contrato_creado_por`. El JS resuelve el email a nombre con un mapa
-- `usuarios.email → nombre` cargado aparte (RLS "el equipo se ve entre sí"
-- ya deja leerlo a cualquiera del equipo, no hace falta ser admin).
--
-- ⚠️ CREATE OR REPLACE VIEW resetea `security_invoker` a su default SIN avisar
-- (ya mordió dos veces en este proyecto: unidades_estado_vista_fase_zona
-- 10-ago, unidades_estado_precio_efectivo 26-ago). La vista real tenía
-- `security_invoker=true` — se re-declara aquí EN LA MISMA sentencia.
create or replace view public.unidades_estado
with (security_invoker = true) as
 SELECT u.id,
    u.codigo,
    u.proyecto,
    u.tipo,
    u.superficie_m2,
    COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) AS precio,
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
    COALESCE(unidad_parte_cobrada(u.id), 0::numeric) AS facturado,
        CASE
            WHEN COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) > 0::numeric THEN round(COALESCE(unidad_parte_cobrada(u.id), 0::numeric) / COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) * 100::numeric, 1)
            ELSE NULL::numeric
        END AS pct_cobrado,
    u.fase_masterplan,
    u.zona_masterplan,
    u.precio AS precio_guardado,
    c.creado_por AS contrato_creado_por
   FROM unidades u
     LEFT JOIN contratos c ON c.id = u.contrato_id;

-- Comprobación:
--   select column_name from information_schema.columns where table_name='unidades_estado' and column_name='contrato_creado_por'; -- 1 fila
--   select reloptions from pg_class where relname='unidades_estado'; -- {security_invoker=true}
