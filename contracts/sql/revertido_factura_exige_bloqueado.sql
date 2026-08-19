-- ════════════════════════════════════════════════════════════════════════════
-- REVERTIDO: facturar NO exige contrato bloqueado — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Por la mañana se pidió que una factura solo se pudiera emitir sobre un
-- contrato bloqueado, y por la tarde el owner lo revirtió: **hay que poder
-- facturar contratos no bloqueados**. Esto deshace aquello en la base.
--
-- El fichero que lo creaba (`factura_exige_contrato_bloqueado.sql`) se BORRA
-- del repo, no se deja con una nota: un `.sql` que sigue ahí es un `.sql` que
-- alguien puede volver a aplicar, y reinstalaría una regla que el owner ya
-- tumbó. Lo que queda es este fichero, que documenta el estado real.
--
-- Lo que la medición dejó claro y explica la vuelta atrás: de 29 facturas, 22
-- estaban emitidas sobre contratos sin firmar. No era una excepción, era el
-- procedimiento normal de la casa.

drop trigger if exists trg_factura_exige_contrato_bloqueado on public.facturas;
drop function if exists public.trg_factura_exige_contrato_bloqueado();

-- ⚠️ `factura_sin_bloquear` se queda en el CHECK de `contrato_eventos` (ver
-- super_admin_poderes.sql) aunque ya no lo escriba nadie: quitarlo obliga a
-- otra migración y la lista tolera entradas históricas. Si algún día vuelve la
-- regla, el evento ya está permitido.
