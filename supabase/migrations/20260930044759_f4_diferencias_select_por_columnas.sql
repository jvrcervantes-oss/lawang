-- F4 seguimiento (30-sep-2026), resuelve LAW-465 (revision de Seguridad del ERP maestro): comisiones_diferencias tenia
-- SELECT de TABLA para authenticated y lw_lector, y un closer podia leer por PostgREST (?select=*) `origen` (correo de
-- quien edito y precios de otros contratos), `provocado_por` y `resuelto_por`, saltandose el recorte de
-- comision_trazabilidad. Pasa a SELECT por COLUMNAS, la misma lista de 14 que el maestro (20260930140000_b3b). El unico
-- lector del navegador (datos.js) pide id,numero,devengo_id,importe,estado,motivo,created_at: todas dentro.
-- Una columna nueva nace SIN permiso hasta que alguien la anada aqui.
revoke select on public.comisiones_diferencias from authenticated, lw_lector;
grant select (id, numero, devengo_id, importe, importe_vigente, importe_nuevo, base_antes, base_despues, motivo, estado,
              solicitud_id, resuelto_en, resolucion_motivo, created_at)
  on public.comisiones_diferencias to authenticated, lw_lector;
