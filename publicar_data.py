#!/usr/bin/env python3
"""publicar_data.py — sube el data.json LOCAL a produccion via api/save.php.

Existe porque data.json esta en .gitignore (lo gestiona el servidor), asi que un cambio
hecho a mano en el fichero local NO viaja con el push. El panel admin.html no sirve para
esto: lee el data.json del servidor, no el local.

La contrasena se pide por teclado y no se guarda en ninguna parte. Uso:

    python publicar_data.py            # publica data.json
    python publicar_data.py --verificar # solo compara local vs produccion

Requiere `pip install requests`.
"""
import argparse
import getpass
import hashlib
import json
import pathlib
import sys

import requests

HOST = 'https://lawangproperties.com'
AQUI = pathlib.Path(__file__).parent
LOCAL = AQUI / 'data.json'


def baja_produccion():
    # ?cb=..&x=1: el CDN de Hostinger sirve un data.json TRUNCADO para el patron ?_=..
    # (ver reference_hostinger_cdn_datajson_truncated). Dos parametros y otro nombre lo esquivan.
    r = requests.get(f'{HOST}/data.json', params={'cb': '1', 'x': '1'},
                     headers={'Cache-Control': 'no-store'}, timeout=30)
    r.raise_for_status()
    d = r.json()
    if not isinstance(d.get('properties'), list):
        sys.exit('produccion devolvio un data.json invalido o truncado — no sigo')
    return r.content, d


def resumen(rotulo, crudo, d):
    print(f'{rotulo:12} {len(crudo):>7} bytes · {len(d["properties"]):>3} propiedades · '
          f'md5 {hashlib.md5(crudo).hexdigest()[:8]}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verificar', action='store_true',
                    help='solo comparar, no publicar')
    args = ap.parse_args()

    crudo_local = LOCAL.read_bytes()
    d_local = json.loads(crudo_local)
    crudo_prod, d_prod = baja_produccion()

    resumen('local', crudo_local, d_local)
    resumen('produccion', crudo_prod, d_prod)

    if d_local == d_prod:
        print('\nIdenticos: no hay nada que publicar.')
        return 0
    if args.verificar:
        print('\nDIFIEREN (esperado antes de publicar).')
        return 1

    print(f'\nSe va a sobrescribir el data.json de {HOST}.')
    if input('Escribe "publicar" para continuar: ').strip() != 'publicar':
        print('Cancelado.')
        return 1

    s = requests.Session()
    s.headers['Origin'] = HOST  # api/ exige mismo origen (lawang_require_same_origin)

    r = s.post(f'{HOST}/api/auth.php', json={'password': getpass.getpass('Password admin: ')},
               timeout=30)
    if not r.json().get('ok'):
        sys.exit(f'login rechazado: {r.status_code} {r.text[:200]}')
    print('sesion abierta')

    r = s.post(f'{HOST}/api/save.php', data=crudo_local,
               headers={'Content-Type': 'application/json'}, timeout=60)
    if not (r.ok and r.json().get('ok')):
        sys.exit(f'save.php fallo: {r.status_code} {r.text[:200]}')

    # Verificar releyendo: que save.php diga ok no prueba que el fichero servido sea el nuevo.
    _, d_despues = baja_produccion()
    print('\nOK publicado.' if d_despues == d_local
          else '\nAVISO: save.php dijo ok pero produccion no coincide todavia (CDN?). Reintenta --verificar en un minuto.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
