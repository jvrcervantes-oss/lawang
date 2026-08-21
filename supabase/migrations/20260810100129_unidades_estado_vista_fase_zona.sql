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
          WHERE x.contrato_id = u.contrato_id AND COALESCE(x.anulada, false) = false AND x.tipo <> 'proforma'::text) f ON true;;
