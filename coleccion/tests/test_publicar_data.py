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
  · «lo que se ve» se cuenta con la regla MAS AMPLIA de las dos que pintan el catalogo (todo lo que no sea
    `visible: false`, que es lo que pinta la rejilla de /thecollection), y un catalogo mal formado —ficha sin
    `visible`, `visible` que no es true/false, id repetido, ausente o que el servidor no acepta— NO se cuenta:
    frena con 3 (revisor, 14-oct: con la regla estrecha esos casos daban «0 cambios» y la web cambiaba);
  · un local escrito ANTES de lo publicado, o cuya antiguedad no se puede medir, no se sube sin decirlo;
  · si lo publicado cambia mientras se confirma, no se guarda;
  · cada salida tiene su codigo (0 a 5, cabecera de publicar_data.py): un fallo de red no se lee como «difieren».

Lo corre el control de subidas en cada push a Lawang (desde el 14-oct-2026: `coleccion/tests` esta en PY_DE_PROYECTO de
`tools/test.py`). En una maquina sin `requests` sale «saltado», no en rojo (PY_MODULOS del mismo fichero).
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
    def __init__(self, entra=True, guarda=True):
        self.headers, self.posts, self._entra, self._guarda = {}, [], entra, guarda

    def post(self, url, **k):
        self.posts.append((url, k.get('data')))
        return Resp({'ok': self._guarda if url.endswith('/api/save.php') else self._entra})

    def guardados(self):
        return [d for u, d in self.posts if u.endswith('/api/save.php')]


def corre(local, args, teclado=None, clave=None, prod=PROD, mtime=T_NUEVO, lm=LM_PROD, sesion=None, prod_despues=None,
          baja_falla=None, guardado_se_ve=True):
    """Lanza main() con todo sustituido. Devuelve (rc o excepcion, salida, veces que se pregunto, sesion, bytes del local).

    `baja_falla=(n, excepcion)`: la bajada numero n (desde 0) lanza esa excepcion. Tras un guardado en `sesion`,
    produccion sirve el local (como el servidor de verdad) salvo `guardado_se_ve=False`. `teclado` puede ser una
    clase de excepcion (EOFError: lanzado sin terminal)."""
    tmp = tempfile.mkdtemp(prefix='lw_publicar_test_')
    ruta = pathlib.Path(tmp) / 'data.json'
    crudo_local = json.dumps(local, indent=2).encode()
    ruta.write_bytes(crudo_local)
    os.utime(ruta, (mtime, mtime))
    bajadas, preguntas = [], []

    def baja():
        n = len(bajadas)
        bajadas.append(1)
        if baja_falla is not None and baja_falla[0] == n:
            raise baja_falla[1]
        if sesion is not None and sesion.guardados() and guardado_se_ve:
            d = local
        else:
            d = prod if (n == 0 or prod_despues is None) else prod_despues
        if hasattr(pd, 'ULTIMA_BAJADA'):
            pd.ULTIMA_BAJADA['last_modified'] = lm
        return json.dumps(d, indent=2).encode(), copy.deepcopy(d)

    def pregunta(_=''):
        preguntas.append(1)
        if teclado is None:
            raise NoToques('se llego a pedir «publicar» por teclado')
        if isinstance(teclado, type):
            raise teclado()
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
    ok(rc == 3, 'sin --cambian sale con el codigo de freno (3): %r' % (rc,))
    ok(n == 0, 'sin --cambian no se pide «publicar»')
    for i in ('uno', 'dos', 'cuatro'):
        ok(i in sal, 'el resumen nombra la ficha visible afectada «%s»' % i)
    ok('principles' in sal and 'territory' in sal, 'el resumen nombra los campos que cambian')
    ok('--cambian' in sal, 'el resumen dice como confirmar')


def t_main_numero_equivocado():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '1'])
    ok(rc == 3 and n == 0, 'con un numero que no es el exacto no se pregunta y sale con 3: %r' % (rc,))
    ok('uno' in sal and 'dos' in sal and 'cuatro' in sal, 'con el numero equivocado se vuelve a ensenar el resumen')


def t_main_numero_exacto():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='no')
    ok(n == 1 and rc == 1 and 'Cancelado' in sal, 'con el numero exacto se llega a la pregunta (y «no» cancela sin pedir contrasena): %r' % (rc,))


def t_main_identicos():   # caso de control: verde antes y despues
    rc, sal, n, _, _ = corre(copy.deepcopy(PROD), [])
    ok(rc == 0 and n == 0, 'identicos: 0 y sin preguntar: %r' % (rc,))


def t_main_solo_no_visibles():
    # La regla es una sola: si el fichero difiere, hace falta el numero, aunque sea 0.
    l = doc([ficha('uno'), ficha('dos'), ficha('tres'), ficha('oculta', visible=False, nota=1)])
    rc, sal, n, _, _ = corre(l, [])
    ok(rc == 3 and n == 0, 'solo cambian fichas no visibles: tampoco se pregunta sin numero (3): %r' % (rc,))
    rc, sal, n, _, _ = corre(l, ['--cambian', '0'], teclado='no')
    ok(n == 1 and rc == 1, 'con --cambian 0 (nada visible cambia) si se llega a la pregunta: %r' % (rc,))


def t_main_verificar():
    rc, sal, n, _, _ = corre(VIEJO, ['--verificar'])
    ok(rc == 1 and n == 0, '--verificar con diferencias devuelve 1 sin preguntar: %r' % (rc,))
    ok('uno' in sal and 'dos' in sal and 'cuatro' in sal, '--verificar ensena el mismo resumen por ficha')


def t_main_local_mas_antiguo():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], mtime=T_VIEJO)
    ok(rc == 3 and n == 0, 'local escrito ANTES de lo publicado: no se pregunta aunque el numero sea exacto (3): %r' % (rc,))
    ok('--restaurar-antiguo' in sal, 'el aviso de antiguedad dice como se confirma una restauracion')
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3', '--restaurar-antiguo'], mtime=T_VIEJO, teclado='no')
    ok(n == 1 and rc == 1, 'con --restaurar-antiguo y el numero exacto si se llega a la pregunta: %r' % (rc,))
    rc, sal, n, _, _ = corre(VIEJO, ['--restaurar-antiguo'], mtime=T_VIEJO)
    ok(rc == 3 and n == 0, '--restaurar-antiguo solo no sustituye al numero (3): %r' % (rc,))


def t_main_antiguedad_sin_medir():
    # Falla cerrado: no poder probar que el local es posterior no es lo mismo que serlo.
    for rotulo, lm in (('sin Last-Modified', None), ('con un Last-Modified ilegible', 'ayer')):
        rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], lm=lm)
        ok(rc == 3 and n == 0, 'antiguedad sin medir (%s): frena con 3 aunque el numero sea exacto, sin preguntar: %r' % (rotulo, rc))
        ok('no se ha podido medir' in sal and '--restaurar-antiguo' in sal, 'antiguedad sin medir (%s): lo dice y dice como se pasa' % rotulo)
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3', '--restaurar-antiguo'], lm=None, teclado='no')
    ok(n == 1 and rc == 1, 'antiguedad sin medir, con --restaurar-antiguo y el numero exacto: se llega a la pregunta: %r' % (rc,))
    rc, sal, n, _, _ = corre(VIEJO, ['--verificar'], lm=None)
    ok(rc == 1 and 'no se ha podido medir' in sal, '--verificar sin Last-Modified: 1 y lo dice: %r' % (rc,))


def t_main_publica():
    s = Sesion()
    rc, sal, n, _, crudo = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s)
    ok(rc == 0 and s.guardados() == [crudo] and 'OK publicado' in sal, 'camino completo: un solo guardado, con los bytes del local, y 0: %r' % (rc,))


def t_main_cambia_mientras():
    s = Sesion()
    otro = doc([ficha('uno', priceEUR=1), ficha('dos'), ficha('tres'), ficha('oculta', visible=False)])
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s, prod_despues=otro)
    ok(not s.guardados() and rc == 3, 'si lo publicado cambia entre la comparacion y el guardado, NO se guarda y sale con 3: %r' % (rc,))


def t_funcion_pura():
    c = pd.cambios_publicados(VIEJO, PROD)
    ok(c['retiradas'] == ['dos'] and c['nuevas'] == ['cuatro'], 'retiradas y nuevas por id: %r %r' % (c['retiradas'], c['nuevas']))
    ok(c['cambiadas'] == {'uno': ['principles', 'territory']}, 'cambiadas con sus campos: %r' % (c['cambiadas'],))
    ok(c['total'] == 3 and c['bloques'] == [] and c['orden'] is False, 'total 3, sin bloques ni cambio de orden')
    ok(pd.cambios_publicados(PROD, PROD)['total'] == 0, 'identicos: 0 cambios')
    # visible "true" (texto): coleccion/lib.php la retira, la rejilla la sigue pintando. Es UN cambio que se ve, y la
    # ficha NO sale de la cuenta (con la regla estrecha se contaba como retirada sin mas: ver t_regla_amplia).
    c = pd.cambios_publicados(doc([ficha('uno', visible='true'), ficha('dos'), ficha('tres'), ficha('oculta', visible=False)]), PROD)
    ok(c['retiradas'] == [] and c['cambiadas'] == {'uno': ['visible']} and c['total'] == 1,
       'visible "true" (texto): la rejilla la sigue pintando, cuenta como cambiada en `visible`: %r' % (c,))
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


# ── Catalogo mal formado (revisor, 14-oct-2026) ─────────────────────────────────────────────────────────────────
# Con la regla estrecha (`visible is True`, id como clave de un dict) estos cinco locales daban el total de la tercera
# columna —lo que habia que teclear en `--cambian` para llegar a la pregunta— y la web cambiaba: la rejilla de
# /thecollection pinta todo lo que no sea `visible: false` y no agrupa por id.
def sin(f, clave):
    f = dict(f)
    del f[clave]
    return f


BASE = [ficha('uno'), ficha('dos'), ficha('tres')]
OCULTA = ficha('oculta', visible=False)
MAL_FORMADOS = [
    ('ficha nueva sin la clave `visible`', doc(BASE + [OCULTA, sin(ficha('cinco'), 'visible')]), '0', '«cinco»'),
    ('`visible` pasa de false a null', doc(BASE + [ficha('oculta', visible=None)]), '0', '«oculta»'),
    ('id repetido con otro precio', doc([ficha('uno', priceEUR=1), ficha('dos'), ficha('tres'), OCULTA, ficha('uno')]), '0', 'id repetido «uno»'),
    ('dos fichas sin id', doc(BASE + [OCULTA, sin(ficha('a'), 'id'), sin(ficha('b'), 'id')]), '1', 'no tiene id'),
    ('`visible` no booleano (1) en una oculta', doc(BASE + [ficha('oculta', visible=1)]), '0', '«oculta»'),
]


def t_main_catalogo_mal_formado():
    for nombre, local, total_viejo, marca in MAL_FORMADOS:
        rc, sal, n, _, _ = corre(local, ['--cambian', total_viejo])
        ok(rc == 3 and n == 0, 'catalogo mal formado (%s): con --cambian %s NO se llega a preguntar, sale con 3: %r' % (nombre, total_viejo, rc))
        ok(marca in sal and 'LOCAL' in sal, 'catalogo mal formado (%s): el aviso nombra la ficha y dice que es el local' % nombre)
        rc, sal, n, _, _ = corre(local, ['--verificar'])
        ok(rc == 3 and n == 0 and marca in sal, 'catalogo mal formado (%s): --verificar tambien sale con 3 y lo nombra: %r' % (nombre, rc))
    # No hay opcion que lo salte: ni el numero que daria la regla amplia, ni --restaurar-antiguo.
    rc, sal, n, _, _ = corre(MAL_FORMADOS[0][1], ['--cambian', '1', '--restaurar-antiguo'])
    ok(rc == 3 and n == 0, 'catalogo mal formado: tampoco pasa con el numero de la regla amplia y --restaurar-antiguo: %r' % (rc,))
    # Un id que el servidor no acepta saldria en la rejilla y su pagina daria 404.
    rc, sal, n, _, _ = corre(doc(BASE + [OCULTA, ficha('villa nueva')]), ['--cambian', '1'])
    ok(rc == 3 and n == 0 and '«villa nueva»' in sal, 'id que el servidor no acepta (con espacio): frena con 3: %r' % (rc,))
    rc, sal, n, _, _ = corre(doc(BASE + [OCULTA, 'no soy una ficha']), ['--cambian', '0'])
    ok(rc == 3 and n == 0 and 'no es una ficha' in sal, 'entrada de la lista que no es una ficha: frena con 3: %r' % (rc,))


def t_main_publicado_mal_formado():
    # Lo PUBLICADO con ids repetidos tampoco se puede contar: frena y dice que se arregla desde el panel.
    prod = doc(BASE + [OCULTA, ficha('uno', priceEUR=1)])
    rc, sal, n, _, _ = corre(doc(BASE + [OCULTA]), ['--cambian', '0'], prod=prod)
    ok(rc == 3 and n == 0 and 'PUBLICADO' in sal and 'id repetido «uno»' in sal, 'lo publicado con un id repetido: frena con 3 y lo dice: %r' % (rc,))
    # En cambio un `visible` raro en lo PUBLICADO no frena (si frenara no se podria arreglar desde aqui): se cuenta con
    # la regla amplia. La rejilla pintaba «oculta» (null); el local la deja en false: es UNA retirada.
    prod = doc(BASE + [ficha('oculta', visible=None)])
    rc, sal, n, _, _ = corre(doc(BASE + [OCULTA]), ['--cambian', '0'], prod=prod)
    ok(rc == 3 and n == 0 and 'RETIRADA  oculta' in sal, '`visible: null` publicado que el local pone a false: es una retirada, --cambian 0 frena: %r' % (rc,))
    rc, sal, n, _, _ = corre(doc(BASE + [OCULTA]), ['--cambian', '1'], prod=prod, teclado='no')
    ok(rc == 1 and n == 1, '`visible: null` publicado que el local arregla: con --cambian 1 se llega a la pregunta: %r' % (rc,))


def t_regla_amplia():
    # Sobre `cambios_publicados` a solas: cuenta todo lo que ALGUNA de las dos reglas pinta.
    c = pd.cambios_publicados(MAL_FORMADOS[0][1], PROD)
    ok(c['nuevas'] == ['cinco'] and c['total'] == 1, 'regla amplia: una ficha sin la clave `visible` se ve (nueva): %r' % (c,))
    c = pd.cambios_publicados(MAL_FORMADOS[1][1], PROD)
    ok(c['nuevas'] == ['oculta'] and c['total'] == 1, 'regla amplia: `visible` de false a null pasa a verse (nueva): %r' % (c,))
    c = pd.cambios_publicados(MAL_FORMADOS[4][1], PROD)
    ok(c['nuevas'] == ['oculta'] and c['total'] == 1, 'regla amplia: `visible: 1` pasa a verse (nueva; en Python 1 no es False): %r' % (c,))
    c = pd.cambios_publicados(doc(BASE + [ficha('oculta', visible=0)]), PROD)
    ok(c['nuevas'] == ['oculta'], 'regla amplia: `visible: 0` tambien se ve (la rejilla usa !== false; en Python 0 == False): %r' % (c,))
    c = pd.cambios_publicados(doc([ficha('uno', visible=None), ficha('dos'), ficha('tres'), OCULTA]), PROD)
    ok(c['cambiadas'] == {'uno': ['visible']} and c['retiradas'] == [] and c['total'] == 1, 'regla amplia: `visible` de true a null es UN cambio: %r' % (c,))
    for nombre, local in ((MAL_FORMADOS[2][0], MAL_FORMADOS[2][1]), (MAL_FORMADOS[3][0], MAL_FORMADOS[3][1])):
        try:
            c = pd.cambios_publicados(local, PROD)
            ok(False, 'regla amplia (%s): `cambios_publicados` no puede devolver un total, tiene que negarse; dio %r' % (nombre, c['total']))
        except ValueError:
            pass
        try:
            pd.cambios_publicados(PROD, local)
            ok(False, 'regla amplia (%s) en lo publicado: `cambios_publicados` tiene que negarse' % nombre)
        except ValueError:
            pass


def t_anomalias():
    ok(pd.anomalias(PROD, es_local=True) == [] and pd.anomalias(VIEJO, es_local=True) == [], 'un catalogo bien formado no tiene anomalias')
    for nombre, local, _, marca in MAL_FORMADOS:
        a = pd.anomalias(local, es_local=True)
        ok(len(a) >= 1 and any(marca in x for x in a), 'anomalias (%s): la nombra: %r' % (nombre, a))
    solo_visible = [m for m in MAL_FORMADOS if 'visible' in m[0]]
    ok(len(solo_visible) == 3 and all(pd.anomalias(m[1], es_local=False) == [] for m in solo_visible),
       'anomalias en lo publicado: un `visible` raro no cuenta (se arregla desde aqui); solo los ids')
    ok(len(pd.anomalias(MAL_FORMADOS[3][1], es_local=False)) == 2, 'anomalias: cada ficha sin id se dice por separado')
    ok(len(pd.anomalias(doc([ficha('uno', id=7), ficha('dos', id=['x']), ficha('tres', id='')]), es_local=False)) == 3,
       'anomalias: un id que no es texto (numero, lista, vacio) es un id ausente, y no revienta')


# ── Codigos de salida (revisor, 14-oct-2026): el 1 significaba a la vez «difieren», «cancelado» y «se cayo la red» ──
def t_codigos_fallo_antes_de_escribir():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], baja_falla=(0, pd.RequestException('sin red')))
    ok(rc == 4 and n == 0 and 'No se ha escrito nada' in sal, 'la bajada falla por red: 4 (no un traceback ni el 1 de «difieren») y dice que no se escribio: %r' % (rc,))
    rc, sal, n, _, _ = corre({'properties': 'no es una lista'}, ['--verificar'])
    ok(rc == 4, 'el data.json local no es un catalogo: 4: %r' % (rc,))
    s = Sesion(entra=False)
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s)
    ok(rc == 4 and not s.guardados(), 'login rechazado: 4 y no se guarda: %r' % (rc,))
    s = Sesion()
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s, baja_falla=(1, pd.RequestException('sin red')))
    ok(rc == 4 and not s.guardados(), 'la bajada de antes de guardar falla: 4 y no se guarda: %r' % (rc,))


def t_codigos_fallo_guardando():
    s = Sesion(guarda=False)
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s)
    ok(rc == 5 and 'NO se sabe que hay publicado' in sal, 'save.php dice que no: 5 y dice que no se sabe que hay publicado: %r' % (rc,))
    s = Sesion()
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s, guardado_se_ve=False)
    ok(rc == 5 and len(s.guardados()) == 1 and 'OK publicado' not in sal, 'save.php dice ok pero produccion no sirve el local: 5, nunca «OK publicado»: %r' % (rc,))
    s = Sesion()
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado='publicar', clave='x', sesion=s, baja_falla=(2, pd.RequestException('sin red')))
    ok(rc == 5 and len(s.guardados()) == 1, 'la red cae al comprobar lo guardado: 5: %r' % (rc,))


def t_codigos_cancelar():
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', '3'], teclado=EOFError)
    ok(rc == 1 and n == 1 and 'Cancelado' in sal, 'sin teclado (EOF) al pedir «publicar»: cancela con 1, no revienta: %r' % (rc,))
    rc, sal, n, _, _ = corre(VIEJO, ['--cambian', 'tres'])
    ok(rc == 2, 'argumento mal puesto: 2 (argparse): %r' % (rc,))


def t_codigos_imprevisto():
    # cli() es lo que corre de verdad: una excepcion sin nombre no puede salir con el 1 de «difieren».
    def revienta():
        raise RuntimeError('algo que nadie previo')
    viejo, pd.main = pd.main, revienta
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            pd.ESTADO['guardando'] = False
            antes = pd.cli()
            pd.ESTADO['guardando'] = True
            despues = pd.cli()
    finally:
        pd.main = viejo
        pd.ESTADO['guardando'] = False
    ok(antes == 4 and despues == 5, 'excepcion imprevista: 4 antes de guardar y 5 despues, nunca 1: %r %r' % (antes, despues))


for nombre, f in [(k, v) for k, v in sorted(globals().items()) if k.startswith('t_') and callable(v)]:
    caso(nombre, f)

if FALLOS:
    print('\n%d FALLO(S)' % len(FALLOS))
    sys.exit(1)
print('OK: freno de publicar_data.py (numero exacto, resumen por ficha, regla amplia y catalogo mal formado, antiguedad, cambio entre medias, codigos de salida).')
