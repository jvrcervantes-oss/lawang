-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68); pareja IDÉNTICA de erp/migraciones/20260929101000
-- LAW-428 fase 1 — la vista unidades_estado expone proyecto_id (29-sep-2026).
-- Pareja: Lawang supabase/migrations/<versión>_unidades_estado_proyecto_id.sql. Cuerpos IDÉNTICOS (hash de la vista
-- 12b334b3fac6b82e0ce1eff7b3983cbb en las dos bases antes de esto).
-- El front filtraba esta vista por el NOMBRE del proyecto (`.eq('proyecto', nombre)`, datos.js y editores.js) porque
-- no tenía el id. Norma del 29-sep (contexto/patrones_tecnicos.md → «Enganche por identificador estable»): se filtra
-- por proyecto_id. La columna va AL FINAL: `create or replace view` solo deja añadir detrás, y así conserva los
-- permisos y el security_invoker que ya tiene.
create or replace view public.unidades_estado with (security_invoker = true) as
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
    c.id IS NOT NULL AND (EXISTS ( SELECT 1
           FROM public.contrato_tipo_etapa e
          WHERE e.tipo = c.tipo AND e.etapa = 'reserva'::text AND e.tipo <> 'reserva_parcela'::text)) AS contrato_es_carta,
    u.proyecto_id
   FROM public.unidades u
     LEFT JOIN public.contratos c ON c.id = u.contrato_id
     LEFT JOIN LATERAL public.unidad_parte_cobrada_split(u.id) cp(cobrado_suelo, cobrado_obra, obra_firmada) ON true;
