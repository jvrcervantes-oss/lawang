-- destructivo-ok: CREATE OR REPLACE VIEW sobre una vista existente, mismo texto que ya corre en produccion (solo se estaba fijando en el repo) -- el intento anterior fallo por cambiar el orden de columnas (u.* en vez de listarlas), se corrige aqui manteniendo el orden exacto de la vista viva.
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
    COALESCE(contrato_cobrado(u.contrato_id), 0::numeric) AS facturado,
        CASE
            WHEN u.precio > 0::numeric THEN round(COALESCE(contrato_cobrado(u.contrato_id), 0::numeric) / u.precio * 100::numeric, 1)
            ELSE NULL::numeric
        END AS pct_cobrado,
    u.fase_masterplan,
    u.zona_masterplan
   FROM unidades u
     LEFT JOIN contratos c ON c.id = u.contrato_id;

alter view public.unidades_estado set (security_invoker = true);
grant select on public.unidades_estado to authenticated;
;
