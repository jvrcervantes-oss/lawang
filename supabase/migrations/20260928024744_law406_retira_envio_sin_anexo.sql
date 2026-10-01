-- destructivo-ok: retira contrato_envio_sin_anexo (drop function); no borra ni cambia ninguna fila.
-- LAW-406, paso 3 de 3 (28-sep-2026). APLICAR SOLO DESPUÉS de redesplegar la edge ficheros-contrato con la
-- constancia dentro de contrato_envia_firma (migración 20260928120000). Reducir la exposición: su único
-- llamador era la segunda llamada de la edge vieja; con la edge nueva no la llama nadie. Aplicada antes que la
-- edge, los envíos «sin anexo» de ese hueco saldrían sin constancia.
-- Estuvo en supabase/migrations_diferidas/ hasta aplicarla (28-sep-2026, tras ficheros-contrato v6), para que no
-- entrara en lote antes de la edge; ahora lleva el nombre con el que la registró la base.
drop function if exists public.contrato_envio_sin_anexo(uuid, text, jsonb);
