# asistente-peticiones — aquí NO está el código

El código de esta edge vive en `contracts/edge/asistente-peticiones/index.ts` (única copia).
`supabase/config.toml` → `[functions.asistente-peticiones]` lo señala con `entrypoint` y fija `verify_jwt = true`.

Esta carpeta existe solo para que `python tools/aterriza.py <id> --edge asistente-peticiones` la encuentre
(exige `supabase/functions/<slug>/`). El CLI empaqueta lo que importa el `entrypoint`; este README no se publica.

- Hasta el 15-oct-2026 aquí había una segunda copia idéntica del `index.ts`: dos copias del mismo código acaban
  diferenciándose (el guardarraíl de búsquedas contaba las mismas 6 dos veces). Se unificó como portal-invitar.
- Verificación tras cada despliegue: `get_edge_function asistente-peticiones` debe devolver el mismo sha256 que
  `contracts/edge/asistente-peticiones/index.ts`.

Origen: búsqueda sin tildes (15-oct-2026), regla en `contexto/patrones_tecnicos.md` de la agencia → «Búsqueda sin tildes».
