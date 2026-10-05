#!/usr/bin/env python3
"""F9a de The Collection v2 — diff de datos entre la web actual (data.json) y la v2 (RPC coleccion_publica).

Compara, ficha a ficha, las fichas VISIBLES de data.json con lo que sirve coleccion_publica() y separa:
  · diferencias de FORMA (vacio frente a ausente: «", [], null»), que no cambian lo que ve el publico;
  · diferencias REALES, que son las que hay que explicar y aceptar (o corregir) antes del corte F10a.
Solo lectura. Las rutas del bucket `deck` se componen a URL como lo hace coleccion/lib.php, para no
contar como diferencia lo que es solo la forma de la ruta.

Uso:  python coleccion/tests/diff_v1_v2.py [--v1 <data.json|url>] [--v2 <respuesta rpc.json|url>] [--detalle k1 k2 | all]
Por defecto baja los dos de produccion. El diff FINAL (el que vale para F10a) se corre despues de
congelar data.json, no antes: mientras v1 sea editable la foto envejece.
Sale con codigo 1 si hay diferencias reales o fichas que no estan en los dos lados.
"""
import argparse, collections, json, re, sys, urllib.request

SB = 'https://vtulllundrfennhjddhc.supabase.co'
KEY = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg'  # PUBLICABLE, la misma que modelo/catalogo.php
BUCKET = SB + '/storage/v1/object/public/deck/'


def carga(origen, rpc=False):
    if origen and not origen.startswith('http'):
        return json.load(open(origen, encoding='utf-8'))
    if rpc and not origen:
        req = urllib.request.Request(SB + '/rest/v1/rpc/coleccion_publica', data=b'{}',
                                     headers={'apikey': KEY, 'Content-Type': 'application/json'})
    else:
        req = urllib.request.Request(origen or 'https://lawangproperties.com/data.json')
    return json.load(urllib.request.urlopen(req, timeout=30))


def url(u):
    ok = isinstance(u, str) and re.match(r'^[A-Za-z0-9_-]+/[A-Za-z0-9._-]+\.(webp|jpe?g|png|avif|svg)$', u)
    return BUCKET + u if ok else u


def vacio(x):
    # Vacio ESTRICTO: ausente, texto vacio, lista o dict vacios (o con todo vacio). 0 y False NO lo son:
    # un precio 0 frente a ausente o un `false` frente a null son un dato distinto y se cuentan aparte.
    if x is None or x == '' or x == '—' or x == '-' or x == [] or x == {}:
        return True
    return isinstance(x, dict) and all(vacio(v) for v in x.values())


def cero_o_falso(x):
    return x is False or (x == 0 and x is not False and not isinstance(x, bool))


def corto(x):
    s = json.dumps(x, ensure_ascii=False)
    return s if len(s) < 110 else s[:107] + '…'


def compara(a, b):
    v1l = [p for p in a['properties'] if p.get('visible') is True]
    v2l = list(b['properties'])
    for lado, lista in (('v1', v1l), ('v2', v2l)):
        ids = [p['id'] for p in lista]
        dup = sorted({i for i in ids if ids.count(i) > 1})
        if dup:
            raise SystemExit(f'ids duplicados en {lado}: {dup} (el diff colapsaria uno en silencio)')
    v1 = {p['id']: p for p in v1l}
    v2 = {p['id']: p for p in v2l}
    real, forma = collections.defaultdict(list), collections.Counter()
    ceros = collections.defaultdict(list)
    for i in sorted(set(v1) & set(v2)):
        p, q = v1[i], dict(v2[i])
        q['images'] = [url(x) for x in (q.get('images') or [])]
        if 'masterplanImage' in q:
            q['masterplanImage'] = url(q['masterplanImage'])
        for k in sorted(set(p) | set(q)):
            if k == 'visible' or p.get(k) == q.get(k):
                continue
            if vacio(p.get(k)) and vacio(q.get(k)):
                forma[k] += 1
            elif (cero_o_falso(p.get(k)) and vacio(q.get(k))) or (vacio(p.get(k)) and cero_o_falso(q.get(k))):
                ceros[k].append((i, p.get(k), q.get(k)))  # 0/false frente a ausente: se enseña, no se esconde
            else:
                real[k].append((i, p.get(k), q.get(k)))
    return v1, v2, real, forma, ceros


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--v1'); ap.add_argument('--v2'); ap.add_argument('--detalle', nargs='*', default=[])
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')
    v1, v2, real, forma, ceros = compara(carga(a.v1), carga(a.v2, rpc=True))
    print(f'v1 visibles: {len(v1)} · v2: {len(v2)}')
    print('solo en v1:', sorted(set(v1) - set(v2)) or '—')
    print('solo en v2:', sorted(set(v2) - set(v1)) or '—')
    print(f'diferencias de forma (sin efecto): {sum(forma.values())}')
    print('0/false frente a ausente (revisar, no es forma pura):', {k: len(v) for k, v in ceros.items()} or 'ninguna')
    print('diferencias REALES por clave:', {k: len(v) for k, v in real.items()} or 'ninguna')
    for k, v in list(real.items()) + [('(0/false) ' + k, v) for k, v in ceros.items()]:
        if 'all' in a.detalle or k in a.detalle:
            print('\n##', k)
            for i, x, y in v:
                print(f'  {i}\n     v1: {corto(x)}\n     v2: {corto(y)}')
    return 1 if real or set(v1) ^ set(v2) else 0


if __name__ == '__main__':
    sys.exit(main())
