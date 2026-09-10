#!/usr/bin/env python3
"""Verifica un .dossier.json: que parsea y que cada ruta de imagen que declara
existe de verdad en disco (relativa a intranet/dossier/, igual que las lee
el builder). No abre navegador - eso es el paso siguiente, con Playwright.

Uso: python verificar_dossier.py <archivo.dossier.json> [mas...]
"""
import sys, os, json

def check(path):
    base = os.path.dirname(os.path.abspath(path))  # intranet/dossier/
    root = os.path.dirname(os.path.dirname(base))  # repo (Lawang/): dos niveles arriba
    def resolve(v):
        # una ruta absoluta ("/contracts/...") cuelga de la raiz del repo, no del JSON
        return os.path.join(root, v.lstrip("/")) if v.startswith("/") else os.path.join(base, v)
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    missing = []
    refs = 0
    for p in d.get("pages", []):
        img = p.get("img", {})
        for k, v in img.items():
            if not v:
                continue
            refs += 1
            if not os.path.isfile(resolve(v)):
                missing.append((p.get("id"), k, v))
        for fr in p.get("free", []):
            if fr.get("kind") == "img" and fr.get("src"):
                refs += 1
                if not os.path.isfile(resolve(fr["src"])):
                    missing.append((p.get("id"), "free:"+fr.get("id",""), fr["src"]))
    n = len(d.get("pages", []))
    print(f"{os.path.basename(path)}: {n} paginas, {refs} refs de imagen, {len(missing)} rotas")
    for pid, field, v in missing:
        print(f"  ROTA  {pid}.{field} -> {v}")
    return len(missing) == 0

if __name__ == "__main__":
    ok = True
    for p in sys.argv[1:]:
        ok = check(p) and ok
    sys.exit(0 if ok else 1)
