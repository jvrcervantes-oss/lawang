#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_plan.py — Generador de planes financieros LAWANG (Lamborghini Wild Coast Sumba).

Construye un Excel corporativo de marca DESDE CERO (no usa la plantilla del cliente):
informe editorial legible, paleta Lawang, portada de marca incrustada.

El JSON de datos es la única fuente de verdad. Para actualizar cifras -> editar el JSON
y regenerar. El Excel es el documento renderizado.

Uso:
    python build_plan.py inbox/datos.json
    python build_plan.py inbox/datos.json salida/Plan.xlsx
"""
import json
import sys
from pathlib import Path

try:
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.drawing.image import Image as XLImage
    from openpyxl.utils import get_column_letter
except ImportError:
    sys.exit("Falta openpyxl. Instala con:  pip install openpyxl")

BASE = Path(__file__).resolve().parent

# ----------------------------------------------------------------------------- PALETA LAWANG
LINEN    = "FFF5F0E6"   # Raw Linen  · fondo 60%
LINEN_LT = "FFFBF8F2"   # banding claro
GREEN    = "FF485B37"   # Territorial Green · cabeceras
LAGOON   = "FF104C4F"   # Deep Lagoon · totales / KPI
ASH      = "FF2E3437"   # Volcanic Ash · texto
CANOPY   = "FF8F9B7A"   # Soft Canopy · acento
SAND     = "FFBEB3A5"   # Stone Sand · reglas / neutro

EUR = '"€"#,##0;[Red]("€"#,##0)'
PCT = '0.0%'

rule       = Side(style="thin",   color=SAND)
rule_med   = Side(style="medium", color=SAND)
B_BOTTOM   = Border(bottom=rule)
B_TOP_MED  = Border(top=rule_med)

def F(size, bold=False, color=ASH, name="Segoe UI", italic=False):
    return Font(name=name, size=size, bold=bold, color=color, italic=italic)

FILL = lambda c: PatternFill("solid", fgColor=c)
RIGHT  = Alignment(horizontal="right",  vertical="center")
LEFT   = Alignment(horizontal="left",   vertical="center", indent=1)
LEFT0  = Alignment(horizontal="left",   vertical="center")
CENTER = Alignment(horizontal="center", vertical="center", wrap_text=True)


# ----------------------------------------------------------------------------- MODELO
def compute(d):
    g = lambda k, default=0: d.get(k) if d.get(k) is not None else default
    villas   = g("num_villas")
    precio   = g("precio_villa")
    cconstr  = g("coste_construccion_villa")
    gross    = villas * precio
    construc = villas * cconstr
    suelo    = g("coste_adquisicion_suelo")
    urb      = g("urbanizacion")
    lic      = g("licencias")
    direct   = construc + suelo + urb + lic
    nick     = construc * g("pct_nick_maltese")
    arq      = g("arquitecto_local"); otros = g("otros_tecnicos")
    prof     = nick + arq + otros
    mkt      = g("marketing")
    comis    = gross * g("pct_comisiones")
    legal    = g("legal_notaria"); adm = g("gastos_admin")
    seg      = gross * g("pct_seguros")
    comadm   = mkt + comis + legal + adm + seg
    total    = direct + prof + comadm
    op       = gross - total
    tonino   = op * g("pct_tonino"); intro = op * g("pct_introductor")
    net      = op - tonino - intro
    inv      = gross * g("pct_aportacion_socios") + gross * g("pct_deuda")
    land_pot = g("suelo_total") * g("precio_suelo_m2")
    return dict(
        villas=villas, precio=precio, gross=gross, construc=construc, suelo=suelo,
        urb=urb, lic=lic, direct=direct, nick=nick, arq=arq, otros=otros, prof=prof,
        mkt=mkt, comis=comis, legal=legal, adm=adm, seg=seg, comadm=comadm,
        total=total, op=op, tonino=tonino, intro=intro, net=net,
        net_margin=(net / gross if gross else 0),
        roi_cost=(net / total if total else 0),
        roi_inv=(net / inv if inv else 0),
        land_pot=land_pot, land_upside=land_pot - suelo,
        pct=lambda k: d.get(k, 0),
    )


# ----------------------------------------------------------------------------- RENDER
def render(d, m, out):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Plan Financiero"
    ws.sheet_view.showGridLines = False
    ws.sheet_properties.tabColor = GREEN.replace("FF", "", 1)

    widths = {"A": 3, "B": 46, "C": 22, "D": 18, "E": 15}
    for col, w in widths.items():
        ws.column_dimensions[col].width = w

    fase = d.get("fase", "Phase I")

    # --- Banda de título (SIEMPRE arriba, antes de la imagen) --------------------
    def band(r, text, font, fill=GREEN, h=None, align=LEFT):
        ws.merge_cells(f"B{r}:E{r}")
        c = ws[f"B{r}"]; c.value = text; c.font = font; c.alignment = align
        for col in "BCDE":
            ws[f"{col}{r}"].fill = FILL(fill)
        if h: ws.row_dimensions[r].height = h

    r = 1
    band(r, "L A W A N G", F(26, True, LINEN, "Georgia"), h=46); r += 1
    band(r, f"Lamborghini Wild Coast Sumba  ·  Development Financial Plan  ·  {fase}",
         F(11, False, LINEN, "Georgia", italic=True), h=24); r += 1
    band(r, "OWN · THE · ETERNITY", F(9, True, CANOPY), fill=LAGOON, h=20,
         align=Alignment(horizontal="right", vertical="center", indent=1)); r += 1

    # --- Portada (imagen banner DEBAJO del título) ------------------------------
    img_path = BASE / "assets" / "portada_sumba.png"
    ws.row_dimensions[r].height = 6; r += 1               # aire bajo banda
    if img_path.exists():
        img = XLImage(str(img_path))
        img.width, img.height = 686, 384                  # 16:9, ancho B:E aprox
        ws.add_image(img, f"B{r}")
        for rr in range(r, r + 12):
            ws.row_dimensions[rr].height = 24             # 12×24pt = 288pt = 384px
        r += 12
    r += 1                                                # aire bajo imagen

    # --- Helpers de sección ------------------------------------------------------
    def section(title):
        nonlocal r
        ws.row_dimensions[r].height = 8; r += 1            # aire
        ws.merge_cells(f"B{r}:E{r}")
        c = ws[f"B{r}"]; c.value = title.upper()
        c.font = F(13, True, LINEN, "Georgia"); c.alignment = LEFT
        for col in "BCDE": ws[f"{col}{r}"].fill = FILL(GREEN)
        ws.row_dimensions[r].height = 26; r += 1

    def colhead(cols):
        nonlocal r
        for col, (txt, al) in cols.items():
            c = ws[f"{col}{r}"]; c.value = txt
            c.font = F(9, True, ASH); c.alignment = al
            c.border = B_BOTTOM
        ws.row_dimensions[r].height = 18; r += 1

    def row_kv(label, value, fmt=None, bold=False, band_i=0, calc=None,
               total=False, indent=True, color=None):
        nonlocal r
        bg = LAGOON if total else (LINEN_LT if band_i % 2 else LINEN)
        txt = LINEN if total else (color or ASH)
        for col in "BCDE":
            cell = ws[f"{col}{r}"]; cell.fill = FILL(bg)
            cell.border = B_TOP_MED if total else B_BOTTOM
        b = ws[f"B{r}"]; b.value = label
        b.font = F(11, bold or total, txt); b.alignment = LEFT if indent else LEFT0
        if calc is not None:
            cc = ws[f"C{r}"]; cc.value = calc
            cc.font = F(9, False, txt if total else SAND); cc.alignment = LEFT0
        v = ws[f"D{r}"]; v.value = value
        v.font = F(11, bold or total, txt); v.alignment = RIGHT
        if fmt: v.number_format = fmt
        ws.row_dimensions[r].height = 20; r += 1

    def pct_cell(value):
        e = ws[f"E{r-1}"]; e.value = value
        e.font = F(10, False, SAND); e.alignment = RIGHT; e.number_format = PCT

    def kpi(label, value, fmt):
        # tarjeta de 2 filas: label (lagoon) + valor grande (lagoon)
        nonlocal r
        ws.merge_cells(f"B{r}:E{r}")
        c = ws[f"B{r}"]; c.value = label.upper()
        c.font = F(9, True, CANOPY); c.alignment = LEFT
        for col in "BCDE": ws[f"{col}{r}"].fill = FILL(LAGOON)
        ws.row_dimensions[r].height = 18; r += 1
        ws.merge_cells(f"B{r}:E{r}")
        v = ws[f"B{r}"]; v.value = value
        v.font = F(22, True, LINEN, "Georgia"); v.alignment = LEFT
        if fmt: v.number_format = fmt
        for col in "BCDE": ws[f"{col}{r}"].fill = FILL(LAGOON)
        ws.row_dimensions[r].height = 36; r += 1
        ws.row_dimensions[r].height = 6; r += 1            # separación

    # --- PROJECT SNAPSHOT --------------------------------------------------------
    section(f"Project Snapshot — {fase}")
    snap = [
        ("Nº villas",                m["villas"],  None),
        ("Precio de venta por villa", m["precio"], EUR),
        ("Superficie por villa",     f'{d.get("superficie_villa","")} m²', None),
        ("Ventas totales (GDV)",     m["gross"],   EUR),
        ("Inicio comercialización",  d.get("inicio_comercializacion", "Mes 2 – 4"), None),
        ("Entrega estimada",         d.get("entrega_estimada", "Mes 12 – 14"), None),
    ]
    for i, (lbl, val, fmt) in enumerate(snap):
        row_kv(lbl, val, fmt, band_i=i)

    # --- ESTADO DE RESULTADOS ----------------------------------------------------
    section(f"Estado de Resultados — {fase}")
    colhead({"B": ("CONCEPTO", LEFT), "C": ("CÁLCULO", LEFT0),
             "D": ("IMPORTE", RIGHT), "E": ("% S/ VENTAS", RIGHT)})
    g = m["gross"]
    def pl(lbl, val, calc="", i=0, neg=False, total=False):
        v = -abs(val) if neg else val
        row_kv(lbl, v, EUR, band_i=i, calc=calc, total=total)
        if g: pct_cell((v / g))
    pl("Ventas de villas", m["gross"], f'{m["villas"]} × {m["precio"]:,.0f} €'.replace(",", "."), 0)
    pl("TOTAL INGRESOS", m["gross"], "", total=True)
    pl("Construcción", m["construc"], "", 0, neg=True)
    pl("Suelo (adquisición)", m["suelo"], "", 1, neg=True)
    pl("Urbanización & infraestructura", m["urb"], "", 0, neg=True)
    pl("Licencias & permisos", m["lic"], "", 1, neg=True)
    pl("Nick Maltese Studio (diseño & arq.)", m["nick"], "8% s/ construcción", 0, neg=True)
    pl("Arquitecto local & ingeniería", m["arq"], "", 1, neg=True)
    pl("Otros profesionales técnicos", m["otros"], "", 0, neg=True)
    pl("Marketing & branding", m["mkt"], "", 1, neg=True)
    pl("Comisiones comerciales", m["comis"], "% de ventas", 0, neg=True)
    pl("Gastos legales & notaría", m["legal"], "", 1, neg=True)
    pl("Gastos administrativos", m["adm"], "", 0, neg=True)
    pl("Seguros & contingencias", m["seg"], "% de ventas", 1, neg=True)
    pl("MARGEN OPERATIVO ANTES DE REPARTOS", m["op"], "", total=True)

    # --- REPARTO DEL BENEFICIO ---------------------------------------------------
    section("Reparto del Beneficio")
    row_kv("Tonino Lamborghini", -m["tonino"], EUR, band_i=0, calc="3% del beneficio")
    row_kv("Introducción de marca", -m["intro"], EUR, band_i=1, calc="1% del beneficio")
    row_kv("BENEFICIO NETO PARA LAWANG (Fran & Pablo)", m["net"], EUR, total=True)

    # --- MÉTRICAS CLAVE ----------------------------------------------------------
    section(f"Métricas Clave — {fase}")
    kpi("Ventas (GDV)", m["gross"], EUR)
    kpi("Beneficio neto Lawang", m["net"], EUR)
    kpi("Margen neto sobre ventas", m["net_margin"], PCT)
    kpi("ROI sobre coste total", m["roi_cost"], PCT)
    kpi("ROI sobre inversión total", m["roi_inv"], PCT)

    # --- CASH FLOW (si viene en datos) ------------------------------------------
    cf = d.get("cash_flow")
    if cf:
        section(f"Cash Flow Estimado — {fase}")
        colhead({"B": ("HITO", LEFT), "C": ("MES", LEFT0),
                 "D": ("FLUJO", RIGHT), "E": ("ACUMULADO", RIGHT)})
        acc = 0
        for i, h in enumerate(cf):
            flujo = (h.get("entrada", 0) or 0) - (h.get("salida", 0) or 0)
            acc += flujo
            for col in "BCDE":
                cell = ws[f"{col}{r}"]; cell.fill = FILL(LINEN_LT if i % 2 else LINEN)
                cell.border = B_BOTTOM
            ws[f"B{r}"].value = h.get("hito", ""); ws[f"B{r}"].font = F(11); ws[f"B{r}"].alignment = LEFT
            ws[f"C{r}"].value = str(h.get("mes", "")); ws[f"C{r}"].font = F(10, False, SAND); ws[f"C{r}"].alignment = LEFT0
            ws[f"D{r}"].value = flujo; ws[f"D{r}"].number_format = EUR; ws[f"D{r}"].font = F(11); ws[f"D{r}"].alignment = RIGHT
            ws[f"E{r}"].value = acc; ws[f"E{r}"].number_format = EUR; ws[f"E{r}"].font = F(11, True, ASH); ws[f"E{r}"].alignment = RIGHT
            ws.row_dimensions[r].height = 20; r += 1

    # --- VALOR DEL SUELO ---------------------------------------------------------
    section("Valor del Suelo")
    row_kv("Coste de adquisición", m["suelo"], EUR, band_i=0,
           calc=f'{d.get("suelo_total","")} m² · {d.get("coste_adquisicion_suelo",0)/max(d.get("suelo_total",1),1):,.0f} €/m²'.replace(",", "."))
    row_kv("Valor potencial del suelo", m["land_pot"], EUR, band_i=1,
           calc=f'{d.get("suelo_total","")} m² × {d.get("precio_suelo_m2","")} €/m²')
    row_kv("Plusvalía estimada", m["land_upside"], EUR, total=True)

    # pie
    r += 1
    ws.merge_cells(f"B{r}:E{r}")
    foot = ws[f"B{r}"]
    foot.value = "AxisWorks · Documento de inversión confidencial — Lawang Estate"
    foot.font = F(8, False, SAND, italic=True); foot.alignment = LEFT0

    out = Path(out); out.parent.mkdir(parents=True, exist_ok=True)
    wb.save(out)
    return out


def main(datos_path, salida_path=None):
    with open(datos_path, encoding="utf-8") as f:
        d = json.load(f)
    m = compute(d)
    if salida_path is None:
        nombre = d.get("_salida") or (Path(datos_path).stem + ".xlsx")
        if not nombre.endswith(".xlsx"): nombre += ".xlsx"
        salida_path = BASE / "salida" / nombre
    out = render(d, m, salida_path)
    print(f"OK  Generado: {out}")
    print(f"    Beneficio neto Lawang: {m['net']:,.0f} €  ({m['net_margin']*100:.1f}% s/ventas)")
    print(f"    Margen operativo: {m['op']:,.0f} €   ROI coste: {m['roi_cost']*100:.1f}%   ROI inv: {m['roi_inv']*100:.1f}%")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Uso: python build_plan.py datos.json [salida/Plan.xlsx]")
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
