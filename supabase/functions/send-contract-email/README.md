# send-contract-email — aquí NO está el código

El código de esta edge vive en `contracts/edge/send-contract-email/index.ts` (única copia).
`supabase/config.toml` → `[functions.send-contract-email]` lo señala con `entrypoint` y mantiene `verify_jwt = false`
(valor medido en producción; la autorización se hace dentro).

Esta carpeta existe solo para que `python tools/aterriza.py <id> --edge send-contract-email` la encuentre
(exige `supabase/functions/<slug>/`). El CLI empaqueta lo que importa el `entrypoint`; este README no se publica.

- Hasta el 11-oct-2026 aquí había un symlink hacia el `index.ts`; en Windows (`core.symlinks=false`) se materializa como un
  fichero de texto con la ruta, y un despliegue desde esa máquina habría publicado ESE texto. Por eso se cambió por `entrypoint`,
  como portal-acceso y portal-invitar.
- Verificación tras cada despliegue: `get_edge_function send-contract-email` debe devolver el mismo sha256 que
  `contracts/edge/send-contract-email/index.ts`.
