# Intranet Lawang — v4 (MAQUETA de diseño, rama `suite-v4`)

> **Esto es una maqueta navegable. Todos los datos que enseña son ficticios.**
> Origen: proyecto de Stitch «Portal Inmobiliario y Gestión Promotora» (3-sep-2026),
> sistema «Architectural Prestige Portal» — negro volcánico `#070907`, latón `#C89B5C`,
> Bodoni Moda + Manrope. Tokens completos: `DESIGN.md` en esta carpeta.

## Qué hay

- `index.html` — hub de la v4 (construido por el estudio con los tokens del DESIGN.md;
  el diseño de Stitch no traía pantalla de hub: la «Consola de Control Territorial»
  estaba **oculta** en el lienzo = descartada por el owner, y no se ha usado).
- 15 herramientas desktop, una carpeta por herramienta con su `index.html`.
- `movil/` — 3 vistas móviles únicas. En el lienzo de Stitch había 8 instancias
  móviles; 6 eran byte-idénticas entre sí (copias del mismo prototipo). Cuelgan del
  hub, fuera del grafo de navegación desktop, a propósito.
- `assets/nav.js` — la navegación vive en UN fichero: recablea la sidebar que Stitch
  ya pinta en cada página (los enlaces venían todos con `href="#"`), marca la
  herramienta activa e injerta el aviso de maqueta. No hay bloques de nav copiados.
- `assets/img/` — las imágenes que Stitch servía desde `lh3.googleusercontent.com`
  (URLs que caducan), localizadas.

## Censo contra la suite viva (3-sep-2026)

Las **12 herramientas** de `contracts/assets/herramientas.js` tienen pantalla v4.
Además: `generador-contratos` (el editor, hoy `contracts/app.html`),
`proyectos-cuentas` (vista de detalle de un proyecto) y `contratos-inversor`
(equivalente del portal del comprador). Sin pantalla en el diseño: el hub (construido
aquí) y `/entrar/` (login) — pendientes de la fase de cableado.

## Condición de promoción — NO negociable

Esta carpeta **no puede llegar a `main` tal cual**. Promocionar la v4 a cualquier
cosa servida exige, antes del merge:

1. **Regla 0 bis de `contexto/suite_lawang.md`**: cada pantalla hereda TODAS las
   funcionalidades y botones de la herramienta viva — conteo mecánico de `<button id>`
   y de filas, pantalla a pantalla (inventario de paridad de la fase de cableado).
2. `guard.js` y la cáscara compartida de `contracts/assets/` (permisos, dinero.js,
   vocabulario.js…) — la maqueta no protege nada porque no enseña nada real.
3. `python tools/check_seguridad.py` en verde.
4. Sustituir el **Tailwind Play CDN** (`cdn.tailwindcss.com`) por CSS compilado:
   vale para maqueta, no para producción.

## Cómo verla

```
git worktree add ../Lawang-v4 suite-v4   # si no existe ya
cd ../Lawang-v4/v4 && python -m http.server 8090
# → http://localhost:8090/
```
