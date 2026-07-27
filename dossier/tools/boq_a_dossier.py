"""Convierte un BOQ / Detail Description del contratista (PDF exportado de Excel)
en un `.dossier.json` del constructor de dossiers, con el tipo de pagina `tabla`.

    python boq_a_dossier.py "ruta\\al\\DESCRIPTION VILLA XXX.pdf" [Titulo del dossier]

Deja el .json junto al builder. Se abre desde `dossier/builder.html` → Cargar.
Requiere PyMuPDF (`pip install pymupdf`).

Verificado contra "DESCRIPTION VILLA CABANA 2BR S2.pdf" (13 pags, 302 filas,
cero lineas perdidas). Los gotchas del formato de origen estan comentados abajo:
son de Excel y se repiten en todos los BOQ de este contratista.
"""
import fitz, json, re, os, sys, collections

BAND = (0.584, 0.702, 0.843)   # barras claras de seccion
YELL = (1.0, 1.0, 0.0)         # resaltado del contratista
PIE_Y = 740                    # por debajo de esto, es pie de pagina
CAFE, BANDA, RESALTE = '#42210B', '#D9C7B6', '#F0DFB4'
# La columna Ref no se puede separar por su x: no esta en la misma posicion en
# todas las paginas (65 en una, 103 en otra) y a veces las dos columnas empatan
# en frecuencia. Se identifica por CONTENIDO: solo lleva numeracion.
ES_REF = re.compile(r'^(?:[IVX]+|[A-Z]|\d+)(?:\.\d+)*$')
near = lambda a, b: all(abs(x - y) < .02 for x, y in zip(a, b))
norm = lambda s: re.sub(r'\s+', ' ', s).strip()


def unir(ss):
    """Une los spans de una fila. Si dos van pegados en pantalla (<1pt) es que
    parten una palabra ('size.120cmx60cm' viene partido en dos) y se concatenan
    sin espacio; si hay hueco, es separacion real. Por eso el texto de cada span
    se conserva EN BRUTO: su ancho incluye el espacio final."""
    out = ''
    for i, s in enumerate(ss):
        if i and not (s['x'] - ss[i - 1]['x1'] < 1):
            out += ' '
        out += s['t']
    return out.strip()


def extraer(ruta):
    """PDF -> [{tipo, cabecera, th, filas, pie_izq, pie_der, sep_final}].
    Regla uniforme, porque las paginas no comparten geometria (alguna no tiene
    cabecera y alguna no tiene barra de cierre):
        texto BLANCO      -> cabecera (va sobre la banda de color)
        texto negro y>740 -> pie
        el resto          -> filas de la tabla"""
    d = fitz.open(ruta)
    pages = []
    for pi, p in enumerate(d):
        fills = [(dr['fill'], dr['rect']) for dr in p.get_drawings() if dr.get('fill')]
        bands = [r for c, r in fills if near(c, BAND)]
        yells = [r for c, r in fills if near(c, YELL)]

        spans = []
        for b in p.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    if s['text'].strip():
                        spans.append({'x': s['bbox'][0], 'x1': s['bbox'][2], 'y': s['bbox'][1],
                                      't': s['text'], 'size': round(s['size'], 1),
                                      'col': s['color'], 'bold': s['font'].endswith(('F1', 'F3'))})
        spans.sort(key=lambda s: (round(s['y'], 1), s['x']))

        if pi == 0:
            pages.append({'tipo': 'portada',
                          'lineas': [{'t': s['t'].strip(), 'x': round(s['x'], 1),
                                      'y': round(s['y'], 1), 'col': s['col']} for s in spans]})
            continue

        blancos = [s for s in spans if s['col'] == 0xffffff]
        th = [s['t'].strip() for s in blancos if s['t'].strip() in ('Ref', 'Description')]
        y_th = min((s['y'] for s in blancos if s['t'].strip() in ('Ref', 'Description')), default=None)
        cab = [s['t'].strip() for s in blancos if y_th is None or s['y'] < y_th - 2]
        pie = [s for s in spans if s['y'] > PIE_Y]
        cuerpo = [s for s in spans if s['y'] <= PIE_Y and s['col'] != 0xffffff]

        # agrupar por CERCANIA, no por y redondeada: el numero de una fila puede
        # estar en y=234.50 y su descripcion en 234.62, y al redondear caian en
        # filas distintas (el numero salia suelto encima de su descripcion)
        grupos = []
        for s in sorted(cuerpo, key=lambda s: (s['y'], s['x'])):
            if grupos and s['y'] - grupos[-1]['y'] < 3:
                grupos[-1]['ss'].append(s)
            else:
                grupos.append({'y': s['y'], 'ss': [s]})

        out = []
        for g in grupos:
            y, ss = g['y'], sorted(g['ss'], key=lambda s: s['x'])
            ref = ''
            if len(ss) > 1 and ES_REF.match(ss[0]['t'].strip()):
                ref = ss[0]['t'].strip()
                ss = ss[1:]
            # contencion ceñida: con margen, el resaltado se comia la fila de abajo
            out.append({'y': round(y, 1), 'ref': ref, 'desc': unir(ss),
                        'banda': False, 'sep': False,
                        'destacado': any(r.y0 - 1 <= y <= r.y1 for r in yells)})

        # Los rectangulos claros son DOS cosas distintas:
        #  · si contienen filas -> fondo del bloque
        #  · si estan vacios    -> fila SEPARADORA; el titulo va debajo, en blanco
        sep_final = False
        for r in bands:
            dentro = [f for f in out if r.y0 - 1 <= f['y'] <= r.y1]
            if dentro:
                for f in dentro:
                    f['banda'] = True
            else:
                sig = next((f for f in out if f['y'] > r.y1), None)
                if sig:
                    sig['sep'] = True
                else:
                    sep_final = True   # ultima barra: no hay fila debajo

        pages.append({'tipo': 'tabla', 'cabecera': cab, 'th': th, 'filas': out,
                      'pie_izq': ' '.join(s['t'] for s in pie if s['x'] < 300).strip(),
                      'pie_der': ' '.join(s['t'] for s in pie if s['x'] >= 300).strip(),
                      'sep_final': sep_final})
    return d, pages


def a_dossier(src, titulo):
    P = []

    def nueva(tipo, d, **extra):
        p = {'id': 'p%d' % len(P), 'type': tipo, 'd': d, 'img': {}, 'free': [], 'rows': []}
        p.update(extra)
        P.append(p)
        return p

    # portada: se agrupa por linea (misma y) porque "LOCATION :" y su valor son
    # dos textos sueltos y, ordenados solo por x, el rotulo iba detras del valor
    def agrupar(lineas):
        out = []
        for l in sorted(lineas, key=lambda l: (l['y'], l['x'])):
            if out and l['y'] - out[-1]['y'] < 3:
                out[-1]['t'] += ' ' + l['t']
            else:
                out.append({'y': l['y'], 't': l['t']})
        return [o['t'].strip() for o in out if o['t'].strip()]

    port = src[0]
    blanco = agrupar([l for l in port['lineas'] if l['col'] == 0xffffff])
    gris = agrupar([l for l in port['lineas'] if l['col'] != 0xffffff])
    # _tag y _no vacios a proposito: el documento es del contratista, no de Lawang
    nueva('statement',
          {'big': blanco[0] if blanco else 'DETAIL DESCRIPTION',
           'note': '<br>'.join([blanco[1] if len(blanco) > 1 else '', ''] +
                               blanco[2:] + ['', ' · '.join(gris)]),
           '_tag': '', '_no': ''},
          bg=CAFE, img={'bg': ''})

    for pg in src[1:]:
        cab = pg['cabecera']
        p = nueva('tabla',
                  {'t1': cab[0] if cab else '',
                   't2': '<br>'.join(cab[1:-1]) if len(cab) > 2 else '',
                   'sec': cab[-1] if len(cab) > 1 else '',
                   'h1': pg['th'][0] if pg['th'] else '',
                   'h2': pg['th'][1] if len(pg['th']) > 1 else '',
                   'fl': pg['pie_izq'], 'fr': pg['pie_der']},
                  bg='#FFFFFF', tc=CAFE, bc=BANDA, hc=RESALTE)
        filas = []
        for f in pg['filas']:
            if f['sep']:
                filas.append({'ref': '', 'desc': '', 'k': 'sep'})
            filas.append({'ref': f['ref'], 'desc': f['desc'],
                          'k': 'hl' if f['destacado'] else ('band' if f['banda'] else '')})
        if pg['sep_final']:
            filas.append({'ref': '', 'desc': '', 'k': 'sep'})
        # la barra de cierre tambien es una fila: asi se puede borrar como el resto
        filas.append({'ref': '', 'desc': '', 'k': 'close'})
        p['rows'] = filas

    return {'title': titulo, 'sizeKey': 'usp', 'size': {'w': 215.9, 'h': 279.4}, 'pages': P}


def control(doc_fitz, src, doc):
    """Ninguna linea del PDF original puede quedarse fuera."""
    sal = set()
    for p in doc['pages']:
        for v in p['d'].values():
            sal.add(norm(v))
            for trozo in re.split(r'<br>| · ', v):
                sal.add(norm(trozo))
        for r in p['rows']:
            sal |= {norm(r['ref']), norm(r['desc'])}
    # los pares "rotulo: valor" se agrupan a proposito, se cotejan como pareja
    pares = {norm(a + ' ' + b) for a in sal for b in sal if a and b}
    orig = {norm(w) for p in doc_fitz for w in p.get_text().split('\n') if w.strip()}
    return sorted(o for o in orig if o and o not in sal and not any(o in s for s in sal)
                  and o not in pares)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ruta = sys.argv[1]
    titulo = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(os.path.basename(ruta))[0]
    doc_fitz, src = extraer(ruta)
    doc = a_dossier(src, titulo)
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                        re.sub(r'\W+', '_', titulo) + '.dossier.json')
    json.dump(doc, open(dest, 'w', encoding='utf-8'), ensure_ascii=False)
    print(len(doc['pages']), 'paginas ·',
          sum(len(p['rows']) for p in doc['pages']), 'filas ->', os.path.normpath(dest))
    falta = control(doc_fitz, src, doc)
    print('LINEAS DEL ORIGINAL SIN REPRESENTAR:', len(falta))
    for f in falta:
        print('   ·', repr(f))
