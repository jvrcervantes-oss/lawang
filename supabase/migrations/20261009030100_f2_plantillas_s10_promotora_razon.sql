-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Encargo «plantillas de contrato por empresa» · S10 · cierre (8-oct-2026) · DATO DEL OWNER (8-oct-2026): la razon social juridica de la promotora fundadora que nombra
-- `estatutos_sw` es «PT Tepi Sun Gai». Dueno del dato: el owner (no se deduce de la tabla `sociedades`); aqui se guarda como valor de ficha, por empresa, que es lo que lee
-- _plantilla_motivo_bloqueo() (sin esta fila, estatutos_sw no se puede activar en esa empresa). Se da a las dos empresas: la plantilla es la misma y el bloqueo se mira por empresa.
-- Esto SOLO quita el motivo «falta promotora_razon»: no activa nada ni toca semillas ni versiones; el resto de bloqueos de estatutos_sw (otra sociedad, solo-global, nunca-activable) sigue igual.
-- NO se inserta nada en plantilla_sociedad_cruce (decision del owner: ningun cruce empresa-sociedad).
-- destructivo-ok: inserta 2 filas de ficha (on conflict do nothing); no toca versiones, cuerpos ni contratos
-- REVERTIR:
--   delete from public.plantilla_ficha where clave = 'promotora_razon' and valor = 'PT Tepi Sun Gai' and empresa in ('lawang', 'sandal_woods');
insert into public.plantilla_ficha (empresa, clave, valor)
values ('lawang', 'promotora_razon', 'PT Tepi Sun Gai'), ('sandal_woods', 'promotora_razon', 'PT Tepi Sun Gai')
on conflict (empresa, clave) do nothing;
