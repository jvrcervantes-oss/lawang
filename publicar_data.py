#!/usr/bin/env python3
"""publicar_data.py — sube el data.json LOCAL a produccion via api/save.php.

Existe porque data.json esta en .gitignore (lo gestiona el servidor), asi que un cambio
hecho a mano en el fichero local NO viaja con el push. El panel admin.html no sirve para
esto: lee el data.json del servidor, no el local.

La contrasena se pide por teclado y no se guarda en ninguna parte. Uso:

    python publicar_data.py --verificar   # solo compara local vs produccion y ensena que cambiaria
    python publicar_data.py --cambian N   # publica, si N es el TOTAL de cambios que se ven en la web

EL FRENO (14-oct-2026). Subir el local SUSTITUYE el catalogo entero de la web. El 14-oct el local del
clon principal era una copia vieja (escrita el 7-ago 05:32 UTC; lo publicado se guardo ese dia a las
07:08 UTC) que reaparecio el 10-oct tras vaciarse la carpeta: publicarla habria cambiado 6 de las 12
fichas visibles, y entre el aviso «DIFIEREN» y el servidor solo habia que teclear «publicar» y la
contrasena. Desde hoy, ANTES de preguntar nada:
  · se ensena, ficha a ficha, lo que cambiaria en la web (retiradas, cambiadas con sus campos, nuevas,
    bloques comunes y orden) y no se sigue sin `--cambian N` con el numero EXACTO. No hay valor por
    defecto ni forma de decir «todas»: quien publica tiene que haber leido la lista;
  · si el fichero local se escribio antes de la ultima vez que se guardo lo publicado, subirlo deshace
    ese guardado: hace falta ADEMAS `--restaurar-antiguo`. La fecha sola no protege (copiar o editar un
    fichero viejo le pone la fecha de hoy): por eso el freno que manda es el numero, y este va encima;
  · justo antes de guardar se vuelve a bajar lo publicado: si cambio mientras se confirmaba, no se guarda.
Prueba sin red: coleccion/tests/test_publicar_data.py.

Sale con 0 (identicos o publicado), 1 (difieren con --verificar, o cancelado) o 3 (frenado).
Requiere `pip install requests`.
"""
import argparse
import email.utils
import getpass
import hashlib
import json
import pathlib
import sys
import time

import requests

HOST = 'https://lawangproperties.com'
AQUI = pathlib.Path(__file__).parent
LOCAL = AQUI / 'data.json'
FRENADO = 3
ULTIMA_BAJADA = {'last_modified': None}   # cabecera Last-Modified de la ultima bajada de produccion
_FALTA = object()                         # distingue «la clave no esta» de «la clave vale null»


def baja_produccion():
    # ?cb=..&x=1: el CDN de Hostinger sirve un data.json TRUNCADO para el patron ?_=..
    # (ver reference_hostinger_cdn_datajson_truncated). Dos parametros y otro nombre lo esquivan.
    # cb cambia en cada bajada (medido 14-oct con 10 y con 19 cifras: devuelve el fichero entero): la
    # comparacion de antes de guardar no puede ser el eco de la bajada anterior.
    r = requests.get(f'{HOST}/data.json', params={'cb': str(time.time_ns()), 'x': '1'},
                     headers={'Cache-Control': 'no-store'}, timeout=30)
    r.raise_for_status()
    d = r.json()
    if not isinstance(d, dict) or not isinstance(d.get('properties'), list):
        sys.exit('produccion devolvio un data.json invalido o truncado — no sigo')
    ULTIMA_BAJADA['last_modified'] = r.headers.get('Last-Modified')
    return r.content, d


def resumen(rotulo, crudo, d):
    print(f'{rotulo:12} {len(crudo):>7} bytes · {len(d["properties"]):>3} propiedades · '
          f'md5 {hashlib.md5(crudo).hexdigest()[:8]}')


def _fichas(d):
    return [p for p in d.get('properties') or [] if isinstance(p, dict)]


def _visibles(d):
    # `visible is True`: la misma regla que el `=== true` de coleccion/lib.php ("true" en texto no es visible).
    return {p.get('id'): p for p in _fichas(d) if p.get('visible') is True}


def cambios_publicados(d_local, d_prod):
    """Que cambiaria EN LA WEB si `d_local` sustituyera a `d_prod`. Pura: ni red ni disco.

    retiradas  ids visibles hoy que en el local no lo son o no existen
    cambiadas  {id: [campos]} visibles en los dos y distintas
    nuevas     ids que pasarian a verse
    bloques    claves de raiz distintas de `properties` (settings, downloads…): tambien salen en la web
    orden      las visibles comunes cambian de orden (es el orden de la pagina)
    ocultas    fichas no visibles en ninguno de los dos que difieren: se informa, no cuenta
    total      retiradas + cambiadas + nuevas + bloques + (1 si cambia el orden) — el N de `--cambian`
    """
    vl, vp = _visibles(d_local), _visibles(d_prod)
    retiradas = [i for i in vp if i not in vl]
    nuevas = [i for i in vl if i not in vp]
    cambiadas = {}
    for i in vp:
        if i in vl and vl[i] != vp[i]:
            cambiadas[i] = sorted(k for k in set(vl[i]) | set(vp[i])
                                  if vl[i].get(k, _FALTA) != vp[i].get(k, _FALTA))
    bloques = sorted(k for k in (set(d_local) | set(d_prod)) - {'properties'}
                     if d_local.get(k, _FALTA) != d_prod.get(k, _FALTA))
    orden = [i for i in vp if i in vl] != [i for i in vl if i in vp]
    tl = {p.get('id'): p for p in _fichas(d_local)}
    tp = {p.get('id'): p for p in _fichas(d_prod)}
    ocultas = sum(1 for i in set(tl) | set(tp)
                  if i not in vl and i not in vp and tl.get(i, _FALTA) != tp.get(i, _FALTA))
    return {'retiradas': retiradas, 'cambiadas': cambiadas, 'nuevas': nuevas, 'bloques': bloques,
            'orden': orden, 'ocultas': ocultas,
            'total': len(retiradas) + len(cambiadas) + len(nuevas) + len(bloques) + (1 if orden else 0)}


def local_mas_antiguo(mtime_local, last_modified):
    """True si el local se escribio ANTES de la ultima vez que se guardo lo publicado; None si no se puede medir."""
    try:
        return mtime_local < email.utils.parsedate_to_datetime(last_modified).timestamp()
    except (TypeError, ValueError):
        return None


def pinta_cambios(c):
    print('\nLo que cambiaria EN LA WEB al subir el local (fichas visibles y bloques comunes):')
    for i in c['retiradas']:
        print(f'  RETIRADA  {i}  (hoy se ve; en el local no es visible o no existe)')
    for i, campos in c['cambiadas'].items():
        print(f'  CAMBIA    {i}: {", ".join(campos)}')
    for i in c['nuevas']:
        print(f'  NUEVA     {i}  (pasaria a verse)')
    for b in c['bloques']:
        print(f'  BLOQUE    {b}')
    if c['orden']:
        print('  ORDEN     las fichas visibles cambian de orden')
    if c['ocultas']:
        print(f'  (ademas difieren {c["ocultas"]} ficha(s) no visibles: no se ven en la web y no cuentan)')
    print(f'TOTAL: {c["total"]} cambio(s) que se ven.')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verificar', action='store_true',
                    help='solo comparar, no publicar')
    ap.add_argument('--cambian', type=int, metavar='N',
                    help='el TOTAL de cambios que se ven en la web (lo ensena --verificar); sin el numero exacto no se publica')
    ap.add_argument('--restaurar-antiguo', action='store_true',
                    help='ademas de --cambian: el local es anterior a lo publicado y se sube a sabiendas (restauracion)')
    args = ap.parse_args()

    crudo_local = LOCAL.read_bytes()
    d_local = json.loads(crudo_local)
    if not isinstance(d_local, dict) or not isinstance(d_local.get('properties'), list):
        sys.exit('el data.json local no es un catalogo valido — no sigo')
    crudo_prod, d_prod = baja_produccion()

    resumen('local', crudo_local, d_local)
    resumen('produccion', crudo_prod, d_prod)

    if d_local == d_prod:
        print('\nIdenticos: no hay nada que publicar.')
        return 0

    # El freno va AQUI: antes de «publicar», de la contrasena y de cualquier peticion que escriba.
    c = cambios_publicados(d_local, d_prod)
    pinta_cambios(c)
    antiguo = local_mas_antiguo(LOCAL.stat().st_mtime, ULTIMA_BAJADA['last_modified'])
    if antiguo is None:
        print('Antiguedad: no se ha podido medir (produccion no dio Last-Modified). Manda el numero de cambios.')
    elif antiguo:
        print(f'ANTIGUEDAD: el data.json local se escribio ANTES de la ultima vez que se guardo lo publicado '
              f'({ULTIMA_BAJADA["last_modified"]}). Subirlo DESHACE lo que se guardo despues.')

    if args.verificar:
        print('\nDIFIEREN (esperado antes de publicar).')
        return 1

    motivos = []
    if args.cambian is None:
        motivos.append('falta --cambian N: el TOTAL de arriba, y solo si esa lista es exactamente lo que quieres publicar')
    elif args.cambian != c['total']:
        motivos.append(f'--cambian {args.cambian} no es el numero de cambios que se ven ({c["total"]})')
    if antiguo and not args.restaurar_antiguo:
        motivos.append('el local es mas antiguo que lo publicado: lo normal es partir de lo publicado hoy y rehacer el cambio '
                       'encima; solo si es una restauracion decidida, anade --restaurar-antiguo')
    if motivos:
        print('\nFRENADO, no se publica nada:')
        for m in motivos:
            print(f'  · {m}')
        return FRENADO

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

    # Lo confirmado es la lista de arriba, calculada contra `crudo_prod`. Si alguien guardo desde el
    # panel mientras tanto, esa lista ya no es verdad y guardar pisaria su cambio sin haberlo ensenado.
    crudo_ahora, _ = baja_produccion()
    if crudo_ahora != crudo_prod:
        sys.exit('lo publicado ha cambiado mientras confirmabas (alguien guardo desde el panel): NO guardo. Vuelve a empezar.')

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
