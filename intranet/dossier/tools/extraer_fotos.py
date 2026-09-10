#!/usr/bin/env python3
"""Extrae, dedupe y optimiza las fotos incrustadas en un PDF de dossier.

Uso: python extraer_fotos.py "<pdf>" <carpeta_salida> [--min 500]

- Descarta imagenes decorativas pequenas (< min px de lado).
- Dedupe por hash de contenido (el mismo logo/patron se repite en cada
  pagina de estos dossieres: no tiene sentido guardarlo 20 veces).
- Reescala a maximo 1600px (lado largo), JPEG calidad 82 progresivo -
  misma receta que project_lawang_signature_catalog.
- Nombra por pagina de origen: p<NN>_<i>.jpg - luego se renombra a mano
  lo que se vaya a usar en el dossier.json (mas legible que un hash).
"""
import sys, os, hashlib, argparse
import fitz
from PIL import Image, ImageOps
import io

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("outdir")
    ap.add_argument("--min", type=int, default=500)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    d = fitz.open(args.pdf)
    seen = {}
    saved = 0
    skipped_small = 0
    skipped_dupe = 0

    for pno, page in enumerate(d, start=1):
        for imgi, img in enumerate(page.get_images(full=True), start=1):
            xref = img[0]
            base = d.extract_image(xref)
            raw = base["image"]
            w, h = base.get("width", 0), base.get("height", 0)
            if w < args.min or h < args.min:
                skipped_small += 1
                continue
            h_ = hashlib.sha1(raw).hexdigest()[:16]
            if h_ in seen:
                skipped_dupe += 1
                continue
            seen[h_] = True
            try:
                im = Image.open(io.BytesIO(raw))
                im = ImageOps.exif_transpose(im)
                if im.mode not in ("RGB",):
                    im = im.convert("RGB")
                long_side = max(im.size)
                if long_side > 1600:
                    scale = 1600 / long_side
                    im = im.resize((max(1,int(im.width*scale)), max(1,int(im.height*scale))), Image.LANCZOS)
                fname = f"p{pno:02d}_{imgi}.jpg"
                im.save(os.path.join(args.outdir, fname), "JPEG", quality=82, progressive=True)
                saved += 1
            except Exception as e:
                print("ERR", pno, imgi, e)

    print(f"guardadas={saved} pequenas_descartadas={skipped_small} duplicadas_descartadas={skipped_dupe}")

if __name__ == "__main__":
    main()
