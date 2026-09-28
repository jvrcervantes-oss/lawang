-- destructivo-ok: retira contrato_envio_sin_anexo (drop function); no borra ni cambia ninguna fila.
-- LAW-406, paso 3 de 3 (28-sep-2026). APLICAR SOLO DESPUÉS de redesplegar la edge ficheros-contrato con la
-- constancia dentro de contrato_envia_firma (migración 20260928120000). Reducir la exposición: su único
-- llamador era la segunda llamada de la edge vieja; con la edge nueva no la llama nadie. Aplicada antes que la
-- edge, los envíos «sin anexo» de ese hueco saldrían sin constancia.
-- VIVE EN supabase/migrations_diferidas/ (no en migrations/) para que no se aplique en lote por accidente. Cuando
-- se aplique, `tools/supabase_fetch_seguro.py` baja la versión real a migrations/ y este fichero se borra de aquí.
drop function if exists public.contrato_envio_sin_anexo(uuid, text, jsonb);
