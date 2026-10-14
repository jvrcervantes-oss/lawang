#!/usr/bin/env python3
"""El freno de publicar_data.py:  python coleccion/tests/test_publicar_data.py   (sale con 1 si algo falla)

SIN RED y sin datos reales: la bajada de produccion, el teclado, la contrasena y `requests` se sustituyen, y
el teclado y la red REVIENTAN si alguien los toca cuando no debe. Los documentos son sinteticos.

POR QUE EXISTE (14-oct-2026). El `data.json` del clon principal era una copia vieja (escrita el 7-ago a las
05:32 UTC; lo publicado se guardo ese dia a las 07:08 UTC) que reaparecio el 10-oct tras vaciarse la carpeta.
`publicar_data.py` la habria subido tal cual: 6 de las 12 fichas visibles de la web habrian cambiado, y entre el
aviso «DIFIEREN» y el servidor solo habia que teclear «publicar» y la contrasena. Lo que se afirma aqui:

  · sin `--cambian N` con el numero EXACTO de cambios que se ven en la web, no se llega ni a preguntar;
  · el resumen nombra cada ficha visible que se retira, cambia o aparece (y los bloques comunes);
  · un local escrito ANTES de lo publicado no se sube sin decir ademas que es una restauracion;
  · si lo publicado cambia mientras se confirma, no se guarda.

No lo corre el control todavia: `tools/test.py` solo descubre en Lawang `*.test.js` y `tests/*_test.php`
(PY_DE_PROYECTO no tiene a Lawang). Se lanza a mano tras tocar publicar_data.py.
"""
import contextlib
import copy
import io
import json
import os
import pathlib
import sys
import tempfile

RAIZ = pathlib.Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True   # sin esto deja un __pycache__/ sin versionar en la raiz de la web
sys.path.insert(0, str(RAIZ))
import publicar_data as pd  # noqa: E402

FALLOS = []


def ok(cond, msg):
    if not cond:
        FALLOS.append(msg)
        print('FALLO: ' + msg)


def ficha(i, visible=True, **extra):
    f = {'id': i, 'visible': visible, 'title': {'en': 'Villa ' + i}, 'priceEUR': 250000,
         'images': ['/assets/img/%s.webp' % i]}
    f.update(extra)
    return f


def doc(props):
    return {'settings': {'whatsapp': '62811'}, 'properties': props, 'downloads': {'signature': []}}


PROD = doc([ficha('uno'), ficha('dos'), ficha('tres'), ficha('oculta', visible=False)])
# Publicado el 7-ago-2026 07:08:08 GMT; el local viejo del incidente se escribio a las 05:32:04 UTC (medido 14-oct).
LM_PROD = 'Fri, 07 Aug 2026 07:08:08 GMT'
T_VIEJO = 1786080724      # 2026-08-07 05:32:04 UTC
T_NUEVO = 1786150000      # 2026-08-08, posterior a lo publicado


class NoToques(AssertionError):
    pass


class Red:
    """Sustituto de `requests`: sin `sesion`, cualquier uso revienta."""

    def __init__(self, sesion=None):
        self._sesion = sesion

    def Session(self):
        if self._sesion is None:
            raise NoToques('se abrio una sesion de red')
        return self._sesion

    def get(self, *a, **k):
        raise NoToques('requests.get directo')

    def post(self, *a, **k):
        raise NoToques('requests.post directo')


class Resp:
    def __init__(self, cuerpo):
        self.ok, self.status_code, self.text, self._c = True, 200, json.dumps(cuerpo), cuerpo

    def json(self):
        return self._c


class Sesion:
    def __init__(self):
        self.headers, self.posts = {}, []

    def post(self, url, **k):
        self.posts.append((url, k.get('data')))
        return Resp({'ok': True})


def corre(local, args, teclado=None, clave=None, prod=PROD, mtime=T_NUEVO, lm=LM_PROD, sesion=None, prod_despues=None):
    """Lanza main() con todo sustituido. Devuelve (rc o excepcion, salida, veces que se pregunto, sesion)."""
    tmp = tempfile.mkdtemp(prefix='lw_publicar_test_')
    ruta = pathlib.Path(tmp) / 'data.json'
    crudo_local = json.dumps(local, indent=2).encode()
    ruta.write_bytes(crudo_local)
    os.utime(ruta, (mtime, mtime))
    bajadas, preguntas = [], []

    def baja():
        d = prod if (not bajadas or prod_despues is None) else prod_despues
        bajadas.append(1)
        if hasattr(pd, 'ULTIMA_BAJADA'):
            pd.ULTIMA_BAJADA['last_modified'] = lm
        return json.dumps(d, indent=2).encode(), copy.deepcopy(d)

    def pregunta(_=''):
        preguntas.append(1)
        if teclado is None:
            raise NoToques('se llego a pedir «publicar» por teclado')
        return teclado

    def pide_clave(_=''):
        if clave is None:
            raise NoToques('se llego a pedir la contrasena')
        return clave

    viejo = (pd.LOCAL, pd.baja_produccion, pd.requests, pd.getpass.getpass, sys.argv, getattr(pd, 'input', None))
    pd.LOCAL, pd.baja_produccion, pd.requests = ruta, baja, Red(sesion)
    pd.getpass.getpass, pd.input, sys.argv = pide_clave, pregunta, ['publicar_data.py'] + list(args)
    sal = io.StringIO()
    try:
        with contextlib.redirect_stdout(sal), contextlib.redirect_stderr(sal):
            try:
                rc = pd.main()
            except SystemExit as e:      # sys.exit('texto') o argparse
                rc = e.code
            except NoToques as e:
                rc = e
    finally:
        pd.LOCAL, pd.baja_produccion, pd.requests, pd.getpass.getpass, sys.argv = viejo[:5]
        if viejo[5] is None:
            del pd.input
        else:
            pd.input = viejo[5]
        ruta.unlink()
        os.rmdir(tmp)
    return rc, sal.getvalue(), len(preguntas), sesion, crudo_local


def caso(nombre, f):
    try:
        f()
    except Exception as e:  # un caso que revienta es un fallo con nombre, no un test que no corrio
        ok(False, '%s: revento con %s: %s' % (nombre, type(e).__name__, e))


# El local del incidente en pequeno: 1 ficha visible cambiada, 1 retirada (deja de ser visible), 1 nueva.
VIEJO = doc([ficha('uno', principles=[], territory=None), ficha('dos', visible=False), ficha('tres'),
             ficha('oculta', visible=False), ficha('cuatro')])


def t_main_sin_confirmar():
    rc, sal, n, _, _ = corre(VIEJO, [])
    ok(not isinstance(rc, NoToques), 'sin --cambian NO se llega a preguntar ni a la red: ' + str(rc))
    ok(rc not in (0, None), 'sin --cambian sale con codigo de freno, no 0: %r' % (rc,))
    ok(n == 0, 'sin --cambian no se pide «publicar»')
    for i in ('uno', 'dos', 'cuatro'):
        ok(i in sal, 'el resumen nombra la ficha visible afectada «%s»' % i)
    ok('principles' in sal and 'territory' in sal, 'el resumen nombra los campos que cambian')
    ok('--cambian' in sal, 'el resumen dice como confirmar')


def t_main_numero_equivocado():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '1'])
    ok(not isinstance(rc, NoToques) and rc not in (0, None) and n == 0, 'con un numero que no es el exacto no se pregunta: %r' % (rc,))
    ok('uno' in sal and 'dos' in sal and 'cuatro' in sal, 'con el numero equivocado se vuelve a ensenar el resumen')


def t_main_numero_exacto():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='no')
    ok(n == 1 and rc == 1 and 'Cancelado' in sal, 'con el numero exacto se llega a la pregunta (y «no» cancela sin pedir contrasena): %r' % (rc,))


def t_main_identicos():   # caso de control: verde antes y despues
    rc, sal, n, _, _ = corre(copy.deepcopy(PROD), [])
    ok(rc == 0 and n == 0, 'identicos: 0 y sin preguntar: %r' % (rc,))


def t_main_verificar():
    rc, sal, n, _, _ = corre(VIEJO, ['--verificar'])
    ok(rc == 1 and n == 0, '--verificar con diferencias devuelve 1 sin preguntar: %r' % (rc,))
    ok('uno' in sal and 'dos' in sal and 'cuatro' in sal, '--verificar ensena el mismo resumen por ficha')


def t_main_local_mas_antiguo():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], mtime=T_VIEJO)
    ok(not isinstance(rc, NoToques) and rc not in (0, None) and n == 0,
       'local escrito ANTES de lo publicado: no se pregunta aunque el numero sea exacto: %r' % (rc,))
    ok('--restaurar-antiguo' in sal, 'el aviso de antiguedad dice como se confirma una restauracion')
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3', '--restaurar-antiguo'], mtime=T_VIEJO, teclado='no')
    ok(n == 1 and rc == 1, 'con --restaurar-antiguo y el numero exacto si se llega a la pregunta: %r' % (rc,))
    rc, sal, n, _, _ = corre(VIEJO, ['--restaurar-antiguo'], mtime=T_VIEJO)
    ok(not isinstance(rc, NoToques) and rc not in (0, None) and n == 0, '--restaurar-antiguo solo no sustituye al numero: %r' % (rc,))
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], lm=None, teclado='no')
    ok(n == 1 and 'no se ha podido medir' in sal, 'sin Last-Modified se dice que la antiguedad NO se pudo medir (y manda el numero)')


def t_main_publica():
    s = Sesion()
    rc, sal, n, _, crudo = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s)
    guardados = [d for u, d in s.posts if u.endswith('/api/save.php')]
    ok(rc == 0 and guardados == [crudo], 'camino completo: un solo guardado, con los bytes del local: %r' % (rc,))


def t_main_cambia_mientras():
    s = Sesion()
    otro = doc([ficha('uno', priceEUR=1), ficha('dos'), ficha('tres'), ficha('oculta', visible=False)])
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s, prod_despues=otro)
    ok(not any(u.endswith('/api/save.php') for u, _ in s.posts) and rc not in (0, None),
       'si lo publicado cambia entre la comparacion y el guardado, NO se guarda: %r' % (rc,))


def t_funcion_pura():
    c = pd.cambios_publicados(VIEJO, PROD)
    ok(c['retiradas'] == ['dos'] and c['nuevas'] == ['cuatro'], 'retiradas y nuevas por id: %r %r' % (c['retiradas'], c['nuevas']))
    ok(c['cambiadas'] == {'uno': ['principles', 'territory']}, 'cambiadas con sus campos: %r' % (c['cambiadas'],))
    ok(c['total'] == 3 and c['bloques'] == [] and c['orden'] is False, 'total 3, sin bloques ni cambio de orden')
    ok(pd.cambios_publicados(PROD, PROD)['total'] == 0, 'identicos: 0 cambios')
    # visible es `is True`, la misma regla que el `=== true` de coleccion/lib.php: "true" no es visible
    c = pd.cambios_publicados(doc([ficha('uno', visible='true'), ficha('dos'), ficha('tres')]), PROD)
    ok(c['retiradas'] == ['uno'], 'visible "true" (texto) cuenta como retirada: %r' % (c['retiradas'],))
    # una ficha que desaparece del todo
    c = pd.cambios_publicados(doc([ficha('uno'), ficha('tres'), ficha('oculta', visible=False)]), PROD)
    ok(c['retiradas'] == ['dos'] and c['total'] == 1, 'ficha visible que falta = retirada')
    # las no visibles no cuentan, pero se dicen
    c = pd.cambios_publicados(doc([ficha('uno'), ficha('dos'), ficha('tres'), ficha('oculta', visible=False, x=1)]), PROD)
    ok(c['total'] == 0 and c['ocultas'] == 1, 'una ficha no visible distinta no cuenta y se informa: %r' % (c,))
    # los bloques comunes salen en la web: cuentan
    l = copy.deepcopy(PROD)
    l['settings']['whatsapp'] = '000'
    del l['downloads']
    c = pd.cambios_publicados(l, PROD)
    ok(c['bloques'] == ['downloads', 'settings'] and c['total'] == 2, 'settings y downloads cuentan: %r' % (c['bloques'],))
    # el orden de las visibles es el orden de la pagina
    c = pd.cambios_publicados(doc([ficha('dos'), ficha('uno'), ficha('tres'), ficha('oculta', visible=False)]), PROD)
    ok(c['orden'] is True and c['total'] == 1 and c['cambiadas'] == {}, 'reordenar las visibles cuenta como 1 cambio')
    # antiguedad, con los valores medidos el 14-oct
    ok(pd.local_mas_antiguo(T_VIEJO, LM_PROD) is True, 'local 05:32 UTC frente a publicado 07:08 GMT = mas antiguo')
    ok(pd.local_mas_antiguo(T_NUEVO, LM_PROD) is False, 'local posterior = no es mas antiguo')
    ok(pd.local_mas_antiguo(T_NUEVO, None) is None and pd.local_mas_antiguo(T_NUEVO, 'ayer') is None, 'sin cabecera o ilegible = None (no medido)')


for nombre, f in [(k, v) for k, v in sorted(globals().items()) if k.startswith('t_') and callable(v)]:
    caso(nombre, f)

if FALLOS:
    print('\n%d FALLO(S)' % len(FALLOS))
    sys.exit(1)
print('OK: freno de publicar_data.py (numero exacto, resumen por ficha, antiguedad, cambio entre medias).')
