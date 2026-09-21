-- LAW v4 paridad lanzamiento, S14 (encargo 20260919, revision previa #34 con Legal+Seguridad+Administracion).
-- Decision del owner 21-sep-2026: una factura/recibi/proforma YA ENVIADA a un comprador real
-- (facturas.enviada = true) no se puede borrar NUNCA desde el panel, ni por super_admin.
-- Unico camino que queda para un documento enviado: Anular. Solo sigue siendo borrable un
-- borrador interno que nunca salio del sistema (enviada = false).
--
-- Toca la policy "borrar facturas" de public.facturas (creada en
-- 20260819044926_law71_editar_firmado_y_borrar_facturas.sql). Anade "AND NOT enviada" a las DOS
-- ramas (super_admin y admin) sin tocar ninguna otra condicion (anulada / recibi_aplicaciones
-- para la rama admin se quedan exactamente igual).

-- destructivo-ok: drop+create de policy es el patron estandar del estudio para reemplazar una
-- policy (departamentos/datos/prompt.md permite crear/drop policy sin preguntar); no borra datos.
drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete using (
    coalesce(enviada, false) = false
    and (
      public.es_super_admin()
      or (public.es_admin()
          and coalesce(anulada, false) = false
          and not exists (select 1 from public.recibi_aplicaciones ra
                           where ra.factura_id = facturas.id or ra.recibi_id = facturas.id))
    )
  );
