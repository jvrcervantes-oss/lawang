-- MCP de Lawang · F1 · abre la entrada del puente: la edge `mcp` (anon) y la página de conexión (authenticated) (16-oct-2026,
-- sesión mcp-lawang). Va DESPUÉS de 20261016130000 (P4): ia_peticion_datos nace allí.
-- PARADA DEL OWNER: abre una función a `anon` (CLAUDE.md, Política de autonomía; departamentos/backend/prompt.md → Supabase).
-- No se aplica en la viva sin su OK escrito; hasta entonces vive en supabase/propuestas/ (fuera de migrations/: revisor, 16-oct) y
-- con el OK pasa a migrations/. Sale JUNTO con el despliegue de la edge `mcp` y la página intranet/v4/ia/conectar/: sin ellos
-- estas tres funciones no tendrían llamador (Seguridad, 16-oct; contexto/seguridad_2026.md §1.ter). La página (index.html,
-- ia-conectar.js e ia-conectar.css) espera en supabase/propuestas/web/ con sus rutas de destino: con el OK vuelve a su sitio,
-- se resella (tools/sella_assets.py) y sale en el mismo aterrizaje que esta migración y el despliegue de la edge.
-- Condiciones para el OK (contexto/pendientes.md): aviso por correo a la persona en cada conexión nueva, tope de peticiones `pide`
-- sin conexión (riesgo residual de abuso) y que el OK nombre la lectura de unidades_log (herramienta de cambios de estado).
--
-- Por qué a anon. La edge `mcp` no tiene llaves (ni service_role ni secretos): llega a la base solo con la clave publicable, es
-- decir, como anon. public.ia_puente solo hace algo si le llega un token, un código o una petición válidos (256 bits aleatorios,
-- comprobados por su hash dentro de la base); con cualquier otra cosa devuelve error sin escribir (prueba J3 de
-- supabase/pruebas/mcp_f1_p1_base.sql). Pública con motivo escrito: contexto/seguridad_2026.md §1.ter. Llamador: la edge `mcp`.
-- Cualquiera con la clave publicable puede llamarla también sin la edge; por eso PKCE, recurso, tope y registro viven dentro
-- de la base, no en la edge (#394/#395).
-- Por qué a authenticated. ia_peticion_datos (qué asistente pide entrar) e ia_conexion_autoriza (la persona acepta, con la
-- contraseña puesta hace ≤120 s) las llama la página de conexión con la sesión de la persona; cada una lo comprueba todo por dentro.
--
-- VUELTA ATRÁS (no destruye nada):
--   revoke execute on function public.ia_puente(text, jsonb) from anon;
--   revoke execute on function public.ia_conexion_autoriza(text) from authenticated;
--   revoke execute on function public.ia_peticion_datos(text) from authenticated;
grant execute on function public.ia_puente(text, jsonb) to anon;
grant execute on function public.ia_conexion_autoriza(text) to authenticated;
grant execute on function public.ia_peticion_datos(text) to authenticated;
