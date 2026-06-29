# Generador de planes financieros — Lawang / Lamborghini Wild Coast Sumba

Herramienta local para pasar a Excel un plan financiero por fases **pegando texto o una imagen**.
Genera un **informe corporativo de marca Lawang desde cero** (NO usa la plantilla del cliente):
portada de marca, paleta Lawang, tablas editoriales legibles. El JSON es la fuente de verdad;
el `.xlsx` es el documento renderizado.

## Estructura

```
excel/
├── inbox/      ← arrastra aquí la imagen o el texto, o un datos.json
├── salida/     ← aquí aparece el .xlsx generado
├── schema.json ← diccionario de los 22 campos (referencia; no se carga)
├── build_plan.py
└── README.md
```

> El Excel es **solo texto y números** (sin imágenes), por preferencia del cliente (29-jun).

## Cómo se usa (flujo normal)

1. **Arrastra** la imagen o pega el texto en `inbox/` (o pégalo directamente en el chat).
2. Dile al estudio: **"pásalo a Excel"**.
3. Claude **lee la imagen/el texto y extrae los datos** a un `datos.json`.
4. Se ejecuta el generador y aparece el `.xlsx` de marca en `salida/`.

> La extracción de imagen/texto la hace Claude (Depto. Documentación). No hace falta clave de API.

## Generar a mano

```bash
python build_plan.py inbox/datos.json
python build_plan.py inbox/datos.json salida/MiPlan.xlsx   # ruta opcional
```

## Formato del datos.json

22 inputs + opcionales. Porcentajes en **decimal** (3 % → `0.03`). Ver `schema.json` para la lista.

```json
{
  "_salida": "Lamborghini_Sumba_Phase_II.xlsx",
  "fase": "Phase II",
  "num_villas": 20,
  "precio_villa": 1000000,
  "coste_construccion_villa": 300000,
  "pct_tonino": 0.03,
  "cash_flow": [
    { "hito": "Preventas (30%)", "mes": "2 – 4", "entrada": 6000000, "salida": 0 }
  ]
}
```

El modelo calcula solo: GDV, costes directos, honorarios, comercial & admin, margen operativo,
reparto (Tonino/introductor), beneficio neto, márgenes, ROI, valor y plusvalía del suelo, y el
cash flow acumulado a partir del array `cash_flow`.

## Fórmulas vivas (hoja Supuestos)

El `.xlsx` tiene **dos hojas**:
- **Supuestos** — los inputs editables (C5..C26). Cambia un valor aquí…
- **Plan Financiero** — el informe; cada importe es una **fórmula de Excel** que referencia
  `Supuestos!Cx` (p. ej. `=-$D$16*Supuestos!C18` para comisiones, `=D30+D33+D34` para el neto).

…y todo el plan se **recalcula solo al abrir** en Excel/OpenOffice. El generador también escribe
los valores correctos de partida, así que abre listo. El cash flow usa columnas ocultas H/I
(entrada/salida) y `FLUJO`/`ACUMULADO` son fórmulas.

> Verificación: como las celdas son fórmulas, el preview PNG no sirve (mostraría `=...`). Se valida
> con un mini-evaluador que resuelve las fórmulas reales del fichero (carpeta scratchpad). pycel
> NO funciona en Python 3.14 (usa `ast.Str`, retirado).

## Diseño (directrices del Depto. Diseño)

Paleta Lawang: Raw Linen `F5F0E6` (fondo) · Territorial Green `485B37` (cabeceras) ·
Deep Lagoon `104C4F` (totales/KPI) · Volcanic Ash `2E3437` (texto) · Soft Canopy `8F9B7A` (acento)
· Stone Sand `BEB3A5` (reglas). Tipografía: **Georgia** (títulos, sustituto de The Seasons) +
**Segoe UI** (cuerpo, sustituto de Neue Kabel). Sin cuadrícula, reglas horizontales finas, mucho aire.

## Verificación visual (sin Office)

Para ver el resultado sin abrir Excel se usa `render_preview.py` (scratchpad): rasteriza el `.xlsx`
a PNG leyendo celdas, fills, fuentes reales del sistema y la imagen incrustada (tamaño real vía
`anchor.ext.cx/cy`). OpenOffice headless `-convert-to pdf` resultó poco fiable en este equipo.

## Notas

- Sirve para **Fase I/II/III** y cualquier plan con la misma estructura: solo cambian los inputs.
- **Coherencia (29-jun):** la imagen `1.jpeg` muestra ROI **154 % / 330 %** en sus notas al pie,
  pero el modelo da ROI **≈45 % (coste) / ≈51 % (inversión)**. El resto de cifras coincide exacto.
  Esas dos cifras parecen del render de marketing. Confirmar con el cliente cuál es la buena.
- La plantilla original del cliente queda en la raíz como referencia; el generador **no la usa**.
