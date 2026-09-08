#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sella `?v=` de los assets de idioma de la web PUBLICA con el hash de su contenido.

Mismo criterio que `tools/sella_assets.py` (que solo cubre `contracts/assets/`, o sea
la suite interna): el sello es el HASH DEL CONTENIDO, no una fecha. Si el fichero
cambia, el CDN se entera solo; si no cambia, no se tira la cache de nadie.

Existe porque el CDN de Hostinger cachea 7 dias y un `?v=` escrito a mano ya costo
dos despliegues seguidos en este mismo proyecto (4-ago-2026, seis sellos distintos
conviviendo). Y porque durante el desarrollo de esto mismo el navegador sirvio una
version vieja de `idioma-web.js` y el sintoma fue que la pagina parecia no traducir.

    python assets/sella_i18n.py            # sella
    python assets/sella_i18n.py --check    # sale 1 si falta sellar (para el gate)
"""
import hashlib
import io
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# asset -> paginas que lo cargan
ASSETS = {
    'assets/idioma-web.js':  ['index.html', 'thecollection.php', 'modelo/index.php',
                              'dali/index.php', 'palmfield/index.php'],
    'assets/i18n-home.js':   ['index.html'],
    'assets/i18n-landing.js': ['modelo/index.php', 'dali/index.php', 'palmfield/index.php'],
    'assets/consent.js':     ['index.html', 'thecollection.php', 'legal.html', 'legal-es.html',
                              'modelo/index.php', 'dali/index.php', 'palmfield/index.php'],
}


def sello(ruta):
    with open(ruta, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()[:12]


def main():
    check = '--check' in sys.argv
    pendientes, tocados = [], 0

    for asset, paginas in ASSETS.items():
        abs_asset = os.path.join(RAIZ, asset)
        if not os.path.exists(abs_asset):
            continue
        v = sello(abs_asset)
        base = os.path.basename(asset)
        # casa el fichero con o sin sello previo, en cualquier ruta (/assets/… o assets/…)
        patron = re.compile(r'(["\'][^"\']*' + re.escape(base) + r')(\?v=[A-Za-z0-9_.-]+)?(["\'])')

        for pag in paginas:
            abs_pag = os.path.join(RAIZ, pag)
            if not os.path.exists(abs_pag):
                continue
            s = io.open(abs_pag, encoding='utf-8').read()
            nuevo = patron.sub(lambda m: m.group(1) + '?v=' + v + m.group(3), s)
            if nuevo != s:
                if check:
                    pendientes.append('%s -> %s' % (pag, base))
                else:
                    io.open(abs_pag, 'w', encoding='utf-8').write(nuevo)
                    tocados += 1

    if check:
        if pendientes:
            print('SIN SELLAR (%d):' % len(pendientes))
            for p in pendientes:
                print('  ·', p)
            return 1
        print('Sellos al dia.')
        return 0

    print('Sellado: %d referencia(s) actualizada(s).' % tocados)
    return 0


if __name__ == '__main__':
    sys.exit(main())
