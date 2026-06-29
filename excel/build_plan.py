#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_plan.py — Generador de planes financieros por fases (Lawang / Lamborghini Wild Coast Sumba).

Inyecta un JSON de inputs en la hoja 'Assumptions' de la plantilla y guarda un .xlsx nuevo.
Las hojas 'Calculations' y 'Dashboard' son fórmulas: se recalculan solas al abrir en Excel.

Uso:
    python build_plan.py datos.json
    python build_plan.py datos.json salida/MiPlan.xlsx     # ruta de salida opcional

El JSON de datos admite:
    {
      "_salida": "Lamborghini_Sumba_Phase_I.xlsx",   (opcional, nombre de archivo)
      "num_villas": 10,
      "precio_villa": 1000000,
      ... (resto de campos del schema.json; los %% en decimal: 3% -> 0.03)
    }
Campos ausentes -> se conserva el valor que ya tuviera la plantilla (no se borra nada).
"""
import json
import sys
from pathlib import Path

try:
    import openpyxl
except ImportError:
    sys.exit("Falta openpyxl. Instala con:  pip install openpyxl")

BASE = Path(__file__).resolve().parent
SCHEMA_PATH = BASE / "schema.json"


def cargar_schema():
    with open(SCHEMA_PATH, encoding="utf-8") as f:
        return json.load(f)


def coerce(valor, tipo):
    """Normaliza el valor según el tipo del campo."""
    if isinstance(valor, str):
        v = valor.strip().replace("€", "").replace("%", "").replace(" ", "")
        # admite "1.000.000" o "1,000,000" o "0,03"
        if v.count(",") == 1 and v.count(".") == 0:
            v = v.replace(",", ".")
        else:
            v = v.replace(".", "").replace(",", "") if tipo in ("int", "eur", "num") else v
        valor = float(v) if v not in ("", "-") else None
    if valor is None:
        return None
    if tipo == "int":
        return int(round(float(valor)))
    if tipo == "pct":
        f = float(valor)
        return f / 100.0 if f > 1 else f  # admite 3 o 0.03
    return float(valor)


def build(datos_path, salida_path=None):
    schema = cargar_schema()
    plantilla = BASE / schema["plantilla"]
    if not plantilla.exists():
        sys.exit(f"No encuentro la plantilla: {plantilla}")

    with open(datos_path, encoding="utf-8") as f:
        datos = json.load(f)

    wb = openpyxl.load_workbook(plantilla)  # conserva fórmulas y formato
    ws = wb[schema["hoja_inputs"]]

    aplicados, faltan = [], []
    for campo in schema["campos"]:
        key, cell, tipo = campo["key"], campo["cell"], campo["tipo"]
        if key in datos and datos[key] is not None and datos[key] != "":
            valor = coerce(datos[key], tipo)
            ws[cell] = valor
            aplicados.append((campo["label"], cell, valor))
        else:
            faltan.append(campo["label"])

    # Nombre de salida
    if salida_path is None:
        nombre = datos.get("_salida") or (Path(datos_path).stem + ".xlsx")
        if not nombre.endswith(".xlsx"):
            nombre += ".xlsx"
        salida_path = BASE / "salida" / nombre
    salida_path = Path(salida_path)
    salida_path.parent.mkdir(parents=True, exist_ok=True)

    wb.save(salida_path)

    print(f"OK  Generado: {salida_path}")
    print(f"    Inputs aplicados: {len(aplicados)}/{len(schema['campos'])}")
    for label, cell, valor in aplicados:
        print(f"      [{cell}] {label} = {valor}")
    if faltan:
        print(f"    Sin dato (se conserva el de la plantilla): {len(faltan)}")
        for label in faltan:
            print(f"      - {label}")
    return salida_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Uso: python build_plan.py datos.json [salida/Plan.xlsx]")
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
