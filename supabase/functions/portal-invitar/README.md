# portal-invitar — aquí NO está el código

El código de esta edge vive en `contracts/edge/portal-invitar/index.ts` (única copia).
`supabase/config.toml` → `[functions.portal-invitar]` lo señala con `entrypoint` y fija `verify_jwt = false`
(la autorización se hace dentro con el JWT del admin, para devolver errores legibles; con `true` el gateway respondería 401 al preflight).

Esta carpeta existe solo para que `python tools/aterriza.py <id> --edge portal-invitar` la encuentre
(exige `supabase/functions/<slug>/`). El CLI empaqueta lo que importa el `entrypoint`; este README no se publica.

- Hasta el 11-oct-2026 aquí había un symlink de 47 bytes hacia el `index.ts`; en Windows (`core.symlinks=false`) se materializa como un
  fichero de texto con la ruta, y un despliegue desde esa máquina habría publicado ESE texto. Por eso se cambió por `entrypoint`, como portal-acceso.
- Verificación tras cada despliegue: `get_edge_function portal-invitar` debe devolver el mismo sha256 que
  `contracts/edge/portal-invitar/index.ts`.

Origen: LAW-1 S2 (11-oct-2026), `encargos/20261011_lawang_portal_enlace_por_correo.md` en la agencia.
