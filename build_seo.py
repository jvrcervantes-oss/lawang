#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_seo.py — Inyector de fallback SEO estático para Lawang (portfolio.html)

PROBLEMA: portfolio.html es una SPA React (Babel en navegador). Las fichas de
propiedad se cargan desde data.json y se pintan en cliente. Los crawlers que NO
ejecutan JS (GPTBot, PerplexityBot, ClaudeBot y Google en su peor caso) ven la
pagina VACIA -> no indexan ni precios ni descripciones.

SOLUCION (Option A): generar, DESDE data.json, un bloque HTML semantico con todas
las propiedades e inyectarlo en un <noscript> justo despues del root de React.
- Usuarios con JS: noscript oculto -> sin flash, React manda.
- Crawlers sin JS: leen el contenido real (titulos, region, precio, specs, desc).

Es IDEMPOTENTE: re-ejecutarlo reemplaza el bloque entre marcadores.
Lanzar tras cada cambio en data.json:

    python build_seo.py
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "data.json"
HTML = HERE / "portfolio.html"

START = "<!-- SEO_FALLBACK_START (auto-generado por build_seo.py — NO editar a mano) -->"
END = "<!-- SEO_FALLBACK_END -->"

import html as _html
esc = _html.escape


def load_dict_labels(html_text):
    """Extrae las etiquetas EN de tenure.* y status.* del DICT incrustado."""
    labels = {}
    for m in re.finditer(r'"((?:tenure|status)\.[a-z]+)"\s*:\s*\{[^}]*?"en"\s*:\s*"([^"]*)"', html_text):
        labels[m.group(1)] = m.group(2)
    return labels


def fmt_price(eur):
    try:
        return "€" + f"{int(eur):,}"
    except (TypeError, ValueError):
        return ""


def specs(p):
    out = []
    if p.get("beds"):
        out.append(f"{p['beds']} bed")
    if p.get("baths"):
        out.append(f"{p['baths']} bath")
    if p.get("built"):
        out.append(f"{p['built']} m² built")
    if p.get("land"):
        out.append(f"{p['land']} m² land")
    return " · ".join(out)


def build_block(data, labels):
    props = data.get("properties", [])
    cards = []
    for p in props:
        pid = p.get("id", "")
        title = (p.get("title") or {}).get("en", pid)
        region = p.get("region", "")
        price = fmt_price(p.get("priceEUR"))
        sub = (p.get("sub") or {}).get("en", "")
        desc = (p.get("desc") or {}).get("en", "")
        status = labels.get(p.get("status", ""), "")
        tenure = labels.get(p.get("tenure", ""), "")
        handover = (p.get("handover", "") or "").strip()
        # Guiones sueltos (—, –, -, N/A) significan "no aplica" -> no mostrar "Handover X"
        if handover in {"—", "–", "-", "", "N/A", "n/a"}:
            handover = ""
        imgs = p.get("images") or []
        img = imgs[0] if imgs else ""

        meta_bits = [b for b in (status, tenure, (f"Handover {handover}" if handover else "")) if b]
        meta = " · ".join(meta_bits)
        sp = specs(p)

        img_tag = f'<img src="{esc(img)}" alt="{esc(title)} — {esc(region)}" loading="lazy" width="800" height="600">' if img else ""

        cards.append(f"""    <article class="seo-prop">
      {img_tag}
      <h3><a href="#property/{esc(pid)}">{esc(title)}</a></h3>
      <p class="seo-region">{esc(region)}</p>
      {f'<p class="seo-price">From {esc(price)}</p>' if price else ''}
      {f'<p class="seo-specs">{esc(sp)}</p>' if sp else ''}
      {f'<p class="seo-meta">{esc(meta)}</p>' if meta else ''}
      {f'<p class="seo-sub">{esc(sub)}</p>' if sub else ''}
      {f'<p class="seo-desc">{esc(desc)}</p>' if desc else ''}
    </article>""")

    inner = "\n".join(cards)
    return (
        f"{START}\n"
        f'<noscript>\n'
        f'  <section class="seo-fallback" aria-label="Lawang property portfolio">\n'
        f"    <h1>Lawang — Property Portfolio in Bali & Sumba</h1>\n"
        f"    <p>Signature homes, land parcels, villas and resort units across Bali and Sumba, Indonesia. "
        f"Freehold and leasehold opportunities with managed rental income.</p>\n"
        f"{inner}\n"
        f"  </section>\n"
        f"</noscript>\n"
        f"{END}"
    )


def main():
    if not DATA.exists() or not HTML.exists():
        sys.exit(f"[build_seo] No encuentro data.json o portfolio.html en {HERE}")

    data = json.loads(DATA.read_text(encoding="utf-8"))
    html_text = HTML.read_text(encoding="utf-8")
    labels = load_dict_labels(html_text)

    block = build_block(data, labels)

    # ¿Ya existe el bloque? -> reemplazar (idempotente)
    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.DOTALL)
    if pattern.search(html_text):
        new_text = pattern.sub(lambda _: block, html_text)
        action = "actualizado"
    else:
        anchor = '<div id="portfolio-root"></div>'
        if anchor not in html_text:
            sys.exit("[build_seo] No encuentro el div #portfolio-root para anclar el fallback.")
        new_text = html_text.replace(anchor, anchor + "\n\n" + block, 1)
        action = "inyectado"

    if new_text == html_text:
        print("[build_seo] Sin cambios.")
        return

    HTML.write_text(new_text, encoding="utf-8")
    n = len(data.get("properties", []))
    print(f"[build_seo] Fallback SEO {action}: {n} propiedades en <noscript> de portfolio.html")


if __name__ == "__main__":
    main()
