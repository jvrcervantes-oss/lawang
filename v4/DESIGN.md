# DESIGN — Intranet Lawang v4 (tokens reales de las pantallas)

> Extraído el 3-sep-2026 del `tailwind.config` que comparten las 18 pantallas
> generadas por Stitch (verificado: mismo tema en todas). **Ojo:** el tema
> guardado en los ajustes del proyecto de Stitch («Architectural Prestige»,
> oscuro, Bodoni Moda + Manrope) es una dirección ANTERIOR descartada — la
> pantalla oscura «Consola de Control Territorial» estaba oculta en el lienzo.
> El sistema vigente es este: claro, lino y verde territorial.

## Tipografía

| uso | familia |
|---|---|
| Display / titulares | Cormorant Garamond (500-700, itálica 600) |
| Interfaz / etiquetas | Instrument Sans (500-700) |
| Cuerpo | Jost (400-700) — la misma familia de marca de la suite viva |
| Iconos | Material Symbols Outlined |

## Paleta — tokens con nombre propio

| token | hex |
|---|---|
| `background` | `#fbf9f4` |
| `burnt-earth` | `#42210B` |
| `control-border` | `#8A8474` |
| `deep-lagoon` | `#104C4F` |
| `error` | `#ba1a1a` |
| `on-surface` | `#1b1c19` |
| `outline` | `#75786e` |
| `outline-variant` | `#c5c8bc` |
| `primary` | `#314322` |
| `raw-linen` | `#F5F0E6` |
| `secondary` | `#316669` |
| `stone-sand` | `#BEB3A5` |
| `surface` | `#fbf9f4` |
| `surface-alt` | `#F1EBDD` |
| `territorial-green` | `#485B37` |
| `volcanic-ash` | `#2E3437` |

## Config completa

La fuente de verdad de la maqueta es el bloque `<script id="tailwind-config">` de
cada pantalla (idéntico en las 18). Al compilar CSS para producción (condición 4
del README) ese bloque se convierte en la config del build y muere el Play CDN.

Colores completos (56 tokens):

```json
{
  "background": "#fbf9f4",
  "burnt-earth": "#42210B",
  "control-border": "#8A8474",
  "deep-lagoon": "#104C4F",
  "error": "#ba1a1a",
  "error-container": "#ffdad6",
  "inverse-on-surface": "#f2f1eb",
  "inverse-primary": "#b8cea1",
  "inverse-surface": "#30312d",
  "on-background": "#1b1c19",
  "on-error": "#ffffff",
  "on-error-container": "#93000a",
  "on-primary": "#ffffff",
  "on-primary-container": "#bcd2a5",
  "on-primary-fixed": "#0f2003",
  "on-primary-fixed-variant": "#3a4c2a",
  "on-secondary": "#ffffff",
  "on-secondary-container": "#356b6e",
  "on-secondary-fixed": "#002021",
  "on-secondary-fixed-variant": "#144e51",
  "on-surface": "#1b1c19",
  "on-surface-variant": "#44483f",
  "on-tertiary": "#ffffff",
  "on-tertiary-container": "#edbdd8",
  "on-tertiary-fixed": "#2e1125",
  "on-tertiary-fixed-variant": "#5f3c52",
  "outline": "#75786e",
  "outline-variant": "#c5c8bc",
  "primary": "#314322",
  "primary-container": "#485b37",
  "primary-fixed": "#d3eabb",
  "primary-fixed-dim": "#b8cea1",
  "raw-linen": "#F5F0E6",
  "secondary": "#316669",
  "secondary-container": "#b3e9ed",
  "secondary-fixed": "#b6ecef",
  "secondary-fixed-dim": "#9ad0d3",
  "soft-canopy": "#8F9B7A",
  "stone-sand": "#BEB3A5",
  "surface": "#fbf9f4",
  "surface-alt": "#F1EBDD",
  "surface-bright": "#fbf9f4",
  "surface-container": "#efeee8",
  "surface-container-high": "#e9e8e3",
  "surface-container-highest": "#e4e2dd",
  "surface-container-low": "#f5f4ee",
  "surface-container-lowest": "#ffffff",
  "surface-dim": "#dbdad5",
  "surface-tint": "#51643f",
  "surface-variant": "#e4e2dd",
  "territorial-green": "#485B37",
  "tertiary": "#563349",
  "tertiary-container": "#6f4a61",
  "tertiary-fixed": "#ffd8ed",
  "tertiary-fixed-dim": "#e9b9d4",
  "volcanic-ash": "#2E3437"
}
```
