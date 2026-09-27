# -*- coding: utf-8 -*-
"""Cliente mínimo de Supabase con service_role para los scripts de LAW-78 (anexos_a_storage.py,
anexos_barrido.py). Solo biblioteca estándar. La clave sale del entorno y NUNCA se imprime:

    SUPABASE_URL=https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=<clave de servicio>   (nunca en el repo, que es público)

Los errores se devuelven con el código HTTP y un trozo del cuerpo de la respuesta, nunca con la URL
completa ni con cabeceras: una URL firmada o una clave no pueden acabar en un log.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

BUCKET = 'contratos-anexos'


class ErrorSupabase(Exception):
    pass


def _entorno():
    url = os.environ.get('SUPABASE_URL', '').rstrip('/')
    clave = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')
    if not url.startswith('https://') or not clave:
        sys.exit('Faltan SUPABASE_URL (https://...) y SUPABASE_SERVICE_ROLE_KEY en el entorno.')
    return url, clave


URL, CLAVE = (None, None)


def _pide(metodo, ruta, cuerpo=None, cabeceras=None, crudo=False, tiempo=300):
    global URL, CLAVE
    if URL is None:
        URL, CLAVE = _entorno()
    h = {'Authorization': 'Bearer ' + CLAVE, 'apikey': CLAVE}
    h.update(cabeceras or {})
    datos = None
    if cuerpo is not None:
        if isinstance(cuerpo, (bytes, bytearray)):
            datos = bytes(cuerpo)
        else:
            datos = json.dumps(cuerpo).encode('utf-8')
            h.setdefault('Content-Type', 'application/json')
    req = urllib.request.Request(URL + ruta, data=datos, headers=h, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=tiempo) as r:
            b = r.read()
            if crudo:
                return b
            return json.loads(b.decode('utf-8')) if b else None
    except urllib.error.HTTPError as e:
        cuerpo_err = e.read()[:300].decode('utf-8', 'replace')
        raise ErrorSupabase('HTTP %s en %s %s: %s' % (e.code, metodo, ruta.split('?')[0][:60], cuerpo_err))


def rest(metodo, tabla_y_query, cuerpo=None, prefer=None):
    cab = {'Prefer': prefer} if prefer else None
    return _pide(metodo, '/rest/v1/' + tabla_y_query, cuerpo, cab)


def rpc(funcion, args):
    return _pide('POST', '/rest/v1/rpc/' + funcion, args)


def sube(path, datos, tipo='image/jpeg'):
    """Sube SIN sobrescribir (x-upsert false): una ruta nueva por página, como la edge."""
    return _pide('POST', '/storage/v1/object/%s/%s' % (BUCKET, urllib.parse.quote(path)), datos,
                 {'Content-Type': tipo, 'x-upsert': 'false'})


def baja(path):
    """El objeto entero, sin caché (la CDN de Storage puede servir una versión vieja ~60 s)."""
    return _pide('GET', '/storage/v1/object/authenticated/%s/%s?v=%s'
                 % (BUCKET, urllib.parse.quote(path), uuid.uuid4().hex), crudo=True,
                 cabeceras={'Cache-Control': 'no-cache'})


def borra_objetos(paths):
    """Borra por la API de Storage (SQL no puede: el fichero se quedaría en el disco). Lotes de 100."""
    hechos = 0
    for i in range(0, len(paths), 100):
        lote = paths[i:i + 100]
        _pide('DELETE', '/storage/v1/object/' + BUCKET, {'prefixes': lote})
        hechos += len(lote)
    return hechos
