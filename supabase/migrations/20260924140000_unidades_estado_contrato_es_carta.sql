-- unidades_estado: `contrato_es_carta` (24-sep-2026).
--
-- Owner: «S1-H9 de Horizon (Daniel Santos Español): solo la barra de suelo
-- levantada — ¿suma la CR o la obra está en borrador? Píntala de un color propio».
-- Ni una cosa ni otra: 0 € cobrados y sin contrato de Construcción. La barra de
-- suelo salía llena porque su tramo «firmado» se enciende con `contrato_firmado`
-- (contrato bloqueado), y el contrato de la parcela es la Carta de Reserva
-- CR00049 firmada — una retención, no la compraventa del suelo.
--
-- La vista dice ahora si el contrato de la parcela es una Carta. El catálogo es
-- `contrato_tipo_etapa` (etapa 'reserva' menos 'reserva_parcela', el MISMO
-- criterio que `libera_reserva()`), nunca una lista a mano en el cliente. La
-- columna va al final: CREATE OR REPLACE VIEW solo admite añadir columnas.
-- Se repite `security_invoker = true` (seguridad_2026.md: recrear la vista lo pierde).

create or replace view public.unidades_estado as
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
    cp.cobrado_suelo + cp.cobrado_obra AS facturado,
        CASE
            WHEN cp.cobrado_suelo IS NULL THEN NULL::numeric
            WHEN COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) > 0::numeric THEN round((cp.cobrado_suelo + cp.cobrado_obra) / COALESCE(u.precio, NULLIF(COALESCE(u.precio_suelo, 0::numeric) + COALESCE(u.precio_construccion, 0::numeric), 0::numeric)) * 100::numeric, 1)
            ELSE NULL::numeric
        END AS pct_cobrado,
    u.fase_masterplan,
    u.zona_masterplan,
    u.precio AS precio_guardado,
    c.creado_por AS contrato_creado_por,
    cp.cobrado_suelo,
    cp.cobrado_obra,
    cp.obra_firmada,
    u.codigo_orden,
    (c.id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.contrato_tipo_etapa e
         WHERE e.tipo = c.tipo AND e.etapa = 'reserva' AND e.tipo <> 'reserva_parcela')) AS contrato_es_carta
   FROM unidades u
     LEFT JOIN contratos c ON c.id = u.contrato_id
     LEFT JOIN LATERAL unidad_parte_cobrada_split(u.id) cp(cobrado_suelo, cobrado_obra, obra_firmada) ON true;

alter view public.unidades_estado set (security_invoker = true);
