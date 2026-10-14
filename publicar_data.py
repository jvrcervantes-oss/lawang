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
    ese guardado: hace falta ADEMAS `--restaurar-antiguo`. Y si la antiguedad NO se puede medir
    (produccion no manda Last-Modified) se trata igual: no poder probar que el local es posterior no es
    lo mismo que serlo. La fecha sola no protege (copiar o editar un fichero viejo le pone la fecha de
    hoy): por eso el freno que manda es el numero, y este va encima;
  · justo antes de guardar se vuelve a bajar lo publicado: si cambio mientras se confirmaba, no se guarda.

QUE ES «LO QUE SE VE» (14-oct-2026, revisor). Hoy el mismo catalogo lo pintan DOS reglas, y el freno cuenta
con la mas amplia: una ficha cuenta como visible salvo que su `visible` sea exactamente `false`.
  · coleccion/lib.php (cabecera, JSON-LD, sitemap, /property/<id>, la home por api/coleccion.php): `=== true`
    y un id que case con ^[A-Za-z0-9-]+$;
  · la rejilla de /thecollection (assets/portfolio-app.js, que con la fuente `datajson` baja data.json en
    crudo): `!== false`, sin mirar el id. Pinta tambien una ficha sin la clave, con `null`, `"false"` o `0`.
Con lo publicado hoy las dos dan lo mismo (44 fichas, 12 visibles, todo booleanos, ids unicos: medido el
14-oct). Solo se separan con un catalogo mal formado, y un catalogo mal formado NO se cuenta: se frena.
Se frena, sin opcion que lo salte (se arregla el fichero), si:
  · en el local o en lo publicado hay una entrada que no es una ficha, una ficha sin id de texto o un id
    repetido (no se puede decir que ficha es cual: el numero seria mentira);
  · en el LOCAL una ficha no trae `visible` como true/false, o su id no casa con ^[A-Za-z0-9-]+$ (saldria
    en la rejilla y su pagina daria 404). En lo publicado esto no frena, para poder arreglarlo desde aqui:
    se cuenta con la regla amplia.
Prueba sin red: coleccion/tests/test_publicar_data.py.

CODIGOS DE SALIDA
  0  identicos (nada que publicar), o publicado Y comprobado releyendo produccion
  1  difieren con --verificar, o cancelado en el teclado. No se escribio nada y nada fallo
  2  argumentos mal puestos (lo da argparse)
  3  FRENADO: falta o no coincide --cambian, antiguedad sin --restaurar-antiguo, catalogo que no se puede
     contar, o lo publicado cambio mientras se confirmaba. No se escribio nada
  4  FALLO antes de escribir: red, respuesta invalida o truncada, data.json local ilegible, login
     rechazado, o cualquier excepcion. No se escribio nada
  5  FALLO al guardar o al comprobar lo guardado: NO se sabe que hay publicado. Mirarlo con --verificar
Requiere `pip install requests`.
"""
import argparse
import email.utils
import getpass
import hashlib
import json
import pathlib
import re
import sys
import time
import traceback

import requests
from requests import RequestException   # ligada al importar: la prueba sustituye `requests` entero

HOST = 'https://lawangproperties.com'
AQUI = pathlib.Path(__file__).parent
LOCAL = AQUI / 'data.json'
DIFIEREN = 1
CANCELADO = 1                             # mismo codigo a proposito: en los dos no se escribio nada y nada fallo
FRENADO = 3
FALLO = 4
FALLO_GUARDANDO = 5
ID_VALIDO = re.compile(r'[A-Za-z0-9-]+')  # la misma que coleccion/lib.php, thecollection.php y /property/<id>
ULTIMA_BAJADA = {'last_modified': None}   # cabecera Last-Modified de la ultima bajada de produccion
ESTADO = {'guardando': False}             # True desde justo antes del POST a save.php: separa el 4 del 5
_FALTA = object()                         # distingue «la clave no esta» de «la clave vale null»


class Fallo(Exception):
    """Algo que el script comprueba y no cuadra (respuesta invalida, login rechazado, save.php dice que no)."""


# Lo que acaba en FALLO / FALLO_GUARDANDO con su mensaje. A proposito NO es `Exception`: la prueba avisa con
# AssertionError cuando se toca la red o el teclado sin deber, y eso no se puede tragar aqui.
ERRORES = (Fallo, RequestException, ValueError, OSError)


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
        raise Fallo('produccion devolvio un data.json invalido o truncado')
    ULTIMA_BAJADA['last_modified'] = r.headers.get('Last-Modified')
    return r.content, d


def resumen(rotulo, crudo, d):
    print(f'{rotulo:12} {len(crudo):>7} bytes · {len(d["properties"]):>3} propiedades · '
          f'md5 {hashlib.md5(crudo).hexdigest()[:8]}')


def _nombre(p, n):
    i = p.get('id') if isinstance(p, dict) else None
    return f'«{i}»' if isinstance(i, str) and i else f'n.º {n + 1} de la lista'


def anomalias(d, es_local):
    """Por que NO se puede contar lo que se ve con el catalogo `d`. Lista de frases; vacia = se puede. Pura.

    Siempre: entrada que no es una ficha, ficha sin id de texto, id repetido (sin eso no hay forma de decir
    que ficha es cual). Solo si `es_local` (lo que se va a publicar): `visible` que no es true/false e id que
    el servidor no acepta. Ver «QUE ES LO QUE SE VE» en la cabecera.
    """
    out, vistos = [], {}
    for n, p in enumerate(d.get('properties') or []):
        if not isinstance(p, dict):
            out.append(f'la entrada n.º {n + 1} de la lista no es una ficha ({type(p).__name__})')
            continue
        i = p.get('id')
        if not isinstance(i, str) or not i:
            out.append(f'la ficha n.º {n + 1} de la lista no tiene id de texto ({i!r})')
        elif i in vistos:
            out.append(f'id repetido «{i}» (fichas n.º {vistos[i] + 1} y n.º {n + 1} de la lista)')
        else:
            vistos[i] = n
            if es_local and not ID_VALIDO.fullmatch(i):
                out.append(f'el id «{i}» no casa con ^[A-Za-z0-9-]+$: saldria en la rejilla y su pagina daria 404')
        if es_local and not isinstance(p.get('visible', _FALTA), bool):
            v = p.get('visible', _FALTA)
            out.append(f'la ficha {_nombre(p, n)} no dice `visible` como true/false '
                       f'({"falta la clave" if v is _FALTA else repr(v)}): la rejilla la pintaria y el resto de la web no')
    return out


def _fichas(d):
    return [p for p in d.get('properties') or [] if isinstance(p, dict)]


def _visibles(d):
    # La regla MAS AMPLIA de las dos que pintan el catalogo: todo lo que no sea exactamente `false` (el
    # `!== false` de assets/portfolio-app.js). `is not False` y no `!= False`: en Python 0 == False, y la
    # rejilla SI pinta un `visible: 0`. Lo que pinta coleccion/lib.php (`=== true`) queda dentro.
    return {p.get('id'): p for p in _fichas(d) if p.get('visible') is not False}


def cambios_publicados(d_local, d_prod):
    """Que cambiaria EN LA WEB si `d_local` sustituyera a `d_prod`. Pura: ni red ni disco.

    retiradas  ids visibles hoy que en el local no lo son o no existen
    cambiadas  {id: [campos]} visibles en los dos y distintas
    nuevas     ids que pasarian a verse
    bloques    claves de raiz distintas de `properties` (settings, downloads…): tambien salen en la web
    orden      las visibles comunes cambian de orden (es el orden de la pagina)
    ocultas    fichas no visibles en ninguno de los dos que difieren: se informa, no cuenta
    total      retiradas + cambiadas + nuevas + bloques + (1 si cambia el orden) — el N de `--cambian`

    «Visible» es la regla amplia de `_visibles`. Lanza ValueError si en alguno de los dos no se puede decir
    que ficha es cual (entrada que no es ficha, id ausente o repetido): con eso el total seria mentira.
    """
    for rotulo, d in (('local', d_local), ('lo publicado', d_prod)):
        malas = anomalias(d, es_local=False)
        if malas:
            raise ValueError(f'{rotulo} no se puede contar: ' + '; '.join(malas))
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


def _pregunta(f, texto):
    """Lo tecleado, o None si no hay teclado (EOF: lanzado sin terminal) o se corta con Ctrl-C: es cancelar."""
    try:
        return f(texto)
    except (EOFError, KeyboardInterrupt):
        return None


def _corre(args):
    crudo_local = LOCAL.read_bytes()
    d_local = json.loads(crudo_local)
    if not isinstance(d_local, dict) or not isinstance(d_local.get('properties'), list):
        raise Fallo('el data.json local no es un catalogo valido')
    crudo_prod, d_prod = baja_produccion()

    resumen('local', crudo_local, d_local)
    resumen('produccion', crudo_prod, d_prod)

    if d_local == d_prod:
        print('\nIdenticos: no hay nada que publicar.')
        return 0

    # El freno va AQUI: antes de «publicar», de la contrasena y de cualquier peticion que escriba.
    # Primero, si se puede contar. Tambien con --verificar: un numero sobre un catalogo mal formado seria mentira.
    malas = ([f'LOCAL: {m}' for m in anomalias(d_local, es_local=True)]
             + [f'PUBLICADO: {m}' for m in anomalias(d_prod, es_local=False)])
    if malas:
        print('\nFRENADO, no se publica nada: el catalogo esta mal formado y no se puede contar lo que se ve.')
        for m in malas:
            print(f'  · {m}')
        print('No hay opcion que lo salte: se arregla el fichero (lo de PUBLICADO, desde el panel de admin) y se repite.')
        return FRENADO

    c = cambios_publicados(d_local, d_prod)
    pinta_cambios(c)
    antiguo = local_mas_antiguo(LOCAL.stat().st_mtime, ULTIMA_BAJADA['last_modified'])
    if antiguo is None:
        print('ANTIGUEDAD: no se ha podido medir (produccion no dio una fecha Last-Modified legible). '
              'No se puede probar que el local sea posterior a lo publicado.')
    elif antiguo:
        print(f'ANTIGUEDAD: el data.json local se escribio ANTES de la ultima vez que se guardo lo publicado '
              f'({ULTIMA_BAJADA["last_modified"]}). Subirlo DESHACE lo que se guardo despues.')

    if args.verificar:
        print('\nDIFIEREN (esperado antes de publicar).')
        return DIFIEREN

    motivos = []
    if args.cambian is None:
        motivos.append('falta --cambian N: el TOTAL de arriba, y solo si esa lista es exactamente lo que quieres publicar')
    elif args.cambian != c['total']:
        motivos.append(f'--cambian {args.cambian} no es el numero de cambios que se ven ({c["total"]})')
    if antiguo is None and not args.restaurar_antiguo:
        motivos.append('no se ha podido medir si el local es anterior a lo publicado: se trata como si lo fuera. Repite '
                       'mas tarde; o, si sabes que partiste de lo publicado hoy, anade --restaurar-antiguo')
    elif antiguo and not args.restaurar_antiguo:
        motivos.append('el local es mas antiguo que lo publicado: lo normal es partir de lo publicado hoy y rehacer el cambio '
                       'encima; solo si es una restauracion decidida, anade --restaurar-antiguo')
    if motivos:
        print('\nFRENADO, no se publica nada:')
        for m in motivos:
            print(f'  · {m}')
        return FRENADO

    print(f'\nSe va a sobrescribir el data.json de {HOST}.')
    if (_pregunta(input, 'Escribe "publicar" para continuar: ') or '').strip() != 'publicar':
        print('Cancelado.')
        return CANCELADO
    clave = _pregunta(getpass.getpass, 'Password admin: ')
    if clave is None:
        print('Cancelado.')
        return CANCELADO

    s = requests.Session()
    s.headers['Origin'] = HOST  # api/ exige mismo origen (lawang_require_same_origin)

    r = s.post(f'{HOST}/api/auth.php', json={'password': clave}, timeout=30)
    if not r.json().get('ok'):
        raise Fallo(f'login rechazado: {r.status_code} {r.text[:200]}')
    print('sesion abierta')

    # Lo confirmado es la lista de arriba, calculada contra `crudo_prod`. Si alguien guardo desde el
    # panel mientras tanto, esa lista ya no es verdad y guardar pisaria su cambio sin haberlo ensenado.
    crudo_ahora, _ = baja_produccion()
    if crudo_ahora != crudo_prod:
        print('\nFRENADO, no se publica nada: lo publicado ha cambiado mientras confirmabas (alguien guardo '
              'desde el panel). Vuelve a empezar.')
        return FRENADO

    ESTADO['guardando'] = True   # desde aqui, cualquier fallo es «no se sabe que hay publicado»
    r = s.post(f'{HOST}/api/save.php', data=crudo_local,
               headers={'Content-Type': 'application/json'}, timeout=60)
    if not (r.ok and r.json().get('ok')):
        raise Fallo(f'save.php fallo: {r.status_code} {r.text[:200]}')

    # Verificar releyendo: que save.php diga ok no prueba que el fichero servido sea el nuevo.
    _, d_despues = baja_produccion()
    if d_despues != d_local:
        print('\nAVISO: save.php dijo ok pero lo que sirve produccion NO es el local (CDN?). No se da por publicado: '
              'repite --verificar en un minuto.')
        return FALLO_GUARDANDO
    print('\nOK publicado.')
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--verificar', action='store_true',
                    help='solo comparar, no publicar')
    ap.add_argument('--cambian', type=int, metavar='N',
                    help='el TOTAL de cambios que se ven en la web (lo ensena --verificar); sin el numero exacto no se publica')
    ap.add_argument('--restaurar-antiguo', action='store_true',
                    help='ademas de --cambian: el local es anterior a lo publicado (o no se ha podido medir) y se sube a sabiendas')
    args = ap.parse_args()
    ESTADO['guardando'] = False
    try:
        return _corre(args)
    except ERRORES as e:
        return _fallo(e)


def _fallo(e):
    guardando = ESTADO['guardando']
    print(f'\nFALLO ({type(e).__name__}): {e}', file=sys.stderr)
    print('NO se sabe que hay publicado: el fallo llego al guardar o al comprobarlo. Miralo con --verificar.' if guardando
          else 'No se ha escrito nada en produccion.', file=sys.stderr)
    return FALLO_GUARDANDO if guardando else FALLO


def cli():
    """main() con red para lo imprevisto: una excepcion sin nombre no puede salir con el 1 de «difieren»."""
    try:
        return main()
    except (Exception, KeyboardInterrupt) as e:   # noqa: BLE001 — solo aqui, fuera de lo que llama la prueba (ver ERRORES)
        traceback.print_exc()
        return _fallo(e)


if __name__ == '__main__':
    sys.exit(cli())
