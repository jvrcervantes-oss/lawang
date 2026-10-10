# portal-acceso — aquí NO está el código

El código de esta edge vive en `contracts/edge/portal-acceso/index.ts` (única copia).
`supabase/config.toml` → `[functions.portal-acceso]` lo señala con `entrypoint` y fija `verify_jwt = false`
(formulario anónimo del portal: con `true` el gateway devolvería 401 y el formulario dejaría de enviar enlaces sin error visible).

Esta carpeta existe solo para que `python tools/aterriza.py <id> --edge portal-acceso` la encuentre
(exige `supabase/functions/<slug>/`). El CLI empaqueta lo que importa el `entrypoint`; este README no se publica.

- No poner aquí un symlink ni una copia del `index.ts`: en Windows (`core.symlinks=false`) un symlink se convierte en un
  fichero de texto con la ruta, y una copia diverge sin que nadie la sincronice.
- Verificación tras cada despliegue: `get_edge_function portal-acceso` debe devolver el mismo sha256 que
  `contracts/edge/portal-acceso/index.ts`.

Origen: LAW-1 S0 (11-oct-2026), `encargos/20261011_lawang_portal_enlace_por_correo.md` en la agencia.
