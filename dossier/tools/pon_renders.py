r"""Coloca renders en el hueco blanco de las paginas `tabla` de un dossier y saca el PDF.

    python pon_renders.py Dali_Sirap.dossier.json ..\renders\dali [-o salida.pdf]

Las paginas del BOQ tienen alto fijo y tablas cortas: media pagina queda en blanco.
Este script mide el hueco REAL en el navegador (no lo estima: la tabla la encoge
`fitTables()` y las alturas de fila no son uniformes) y mete un elemento libre
`kind:'img'` en cada pagina donde quepa una imagen decente.

Requiere PyMuPDF + Pillow y Microsoft Edge. Deja el .dossier.json con las imagenes
puestas junto al builder, para poder seguir editandolo a mano desde `builder.html`.
"""
import json, os, re, shutil, subprocess, sys, tempfile
from PIL import Image

EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
AQUI = os.path.dirname(os.path.abspath(__file__))
BUILDER = os.path.join(AQUI, '..', 'builder.html')

HUECO_MIN = 45.0   # mm de alto libre por debajo del cual no merece la pena la imagen
AIRE = 8.0         # mm de respiro entre la tabla y la imagen, y entre imagen y pie
ANCHO_PX = 1800    # las paginas son de 216 mm; a 300 dpi sobran

MEDIR = """
<script>
state=migrate(__DOC__);uid=maxUid(state);applySize();render();
const out=[];
state.pages.forEach(p=>{
  const page=document.querySelector('.page[data-id="'+p.id+'"]');
  if(!page)return;
  const r=page.getBoundingClientRect(), k=r.width/state.size.w;   // px por mm (el rect ya lleva el CSS zoom)
  const body=page.querySelector('.tbl-body'), foot=page.querySelector('.tbl-foot');
  if(!body||!foot)return;
  const b=body.getBoundingClientRect(), f=foot.getBoundingClientRect();
  out.push({id:p.id, x:(b.left-r.left)/k, w:b.width/k,
            arriba:(b.bottom-r.top)/k, abajo:(f.top-r.top)/k});
});
document.body.insertAdjacentHTML('beforeend','<pre id="MEAS">'+JSON.stringify(out)+'</pre>');
</script>
"""


def pagina(doc, extra):
    """builder.html con el dossier inyectado (el init lee localStorage, aqui no sirve)."""
    html = open(BUILDER, encoding='utf-8').read()
    return html.replace('</body>', extra.replace('__DOC__', json.dumps(doc)) + '</body>')


def edge(*args):
    r = subprocess.run([EDGE, '--headless=new', '--no-sandbox', '--disable-gpu', *args],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.stdout


def medir(doc, tmp):
    f = os.path.join(tmp, 'medir.html')
    open(f, 'w', encoding='utf-8').write(pagina(doc, MEDIR))
    dom = edge('--dump-dom', '--virtual-time-budget=8000', 'file:///' + f.replace('\\', '/'))
    # el ULTIMO: la primera aparicion es el literal dentro del propio <script>
    m = re.findall(r'<pre id="MEAS">(.*?)</pre>', dom, re.S)
    if not m:
        sys.exit('El navegador no devolvio medidas. DOM recibido: %d bytes' % len(dom))
    return {p['id']: p for p in json.loads(m[-1])}


def preparar(carpeta, destino):
    """Reescala los renders (5-11 MB de PNG) a algo que quepa en un PDF."""
    os.makedirs(destino, exist_ok=True)
    out = []
    for n in sorted(os.listdir(carpeta)):
        if not n.lower().endswith(('.png', '.jpg', '.jpeg')):
            continue
        im = Image.open(os.path.join(carpeta, n)).convert('RGB')
        if im.width > ANCHO_PX:
            im = im.resize((ANCHO_PX, round(im.height * ANCHO_PX / im.width)), Image.LANCZOS)
        d = re.sub(r'\W+', '_', os.path.splitext(n)[0]) + '.jpg'
        im.save(os.path.join(destino, d), quality=85, optimize=True)
        out.append((d, im.width / im.height))
    return out


def colocar(doc, med, imgs, ruta_rel):
    """Una imagen por pagina con hueco, en orden y sin repetir hasta agotarlas."""
    uid = 9000
    huecos = []
    for p in doc['pages']:
        m = med.get(p['id'])
        if not m:
            continue
        alto = m['abajo'] - m['arriba'] - 2 * AIRE
        if alto >= HUECO_MIN:
            huecos.append((p, m, alto))
    if not imgs:
        return 0
    for i, (p, m, alto) in enumerate(huecos):
        nombre, ratio = imgs[i % len(imgs)]
        w = m['w']
        h = min(alto, w / ratio)
        w = h * ratio                                  # sin deformar: manda el lado que se agote antes
        uid += 1
        p['free'].append({
            'id': 'f%d' % uid, 'kind': 'img',
            # centrada en el hueco: anclarla al pie dejaba un vacio enorme en las
            # paginas cortas (PRELIMINARIES son 8 filas y media pagina de aire)
            'x': round(m['x'] + (m['w'] - w) / 2, 2),
            'y': round(m['arriba'] + AIRE + (alto - h) / 2, 2),
            'w': round(w, 2), 'h': round(h, 2),
            'src': ruta_rel + '/' + nombre,
            'style': {'rot': 0, 'op': 100, 'fit': 'cover'},
        })
    return len(huecos)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, renders = sys.argv[1], sys.argv[2]
    out_pdf = sys.argv[sys.argv.index('-o') + 1] if '-o' in sys.argv else \
        os.path.splitext(src)[0] + '.pdf'
    doc = json.load(open(src, encoding='utf-8'))

    rel = 'renders/' + re.sub(r'\W+', '_', os.path.basename(os.path.normpath(renders))).lower()
    imgs = preparar(renders, os.path.join(AQUI, '..', rel))
    print(len(imgs), 'renders preparados ->', rel)

    tmp = tempfile.mkdtemp(prefix='dossier_')
    med = medir(doc, tmp)
    print(len(med), 'paginas de tabla medidas')

    n = colocar(doc, med, imgs, rel)
    print(n, 'imagenes colocadas')
    json.dump(doc, open(src, 'w', encoding='utf-8'), ensure_ascii=False)

    # el PDF se imprime desde la carpeta del builder: las rutas de imagen son relativas a el
    f = os.path.join(os.path.dirname(os.path.abspath(BUILDER)), '_print_tmp.html')
    open(f, 'w', encoding='utf-8').write(pagina(doc, '<script>state=migrate(__DOC__);uid=maxUid(state);applySize();render();</script>'))
    try:
        edge('--print-to-pdf=' + os.path.abspath(out_pdf), '--print-to-pdf-no-header',
             '--virtual-time-budget=20000', 'file:///' + f.replace('\\', '/'))
    finally:
        os.remove(f)
    shutil.rmtree(tmp, ignore_errors=True)
    print('->', os.path.abspath(out_pdf))


def autocheck():
    """La geometria es lo unico que puede fallar en silencio: una imagen que se
    sale del hueco pisa el pie o la tabla y el PDF no avisa."""
    doc = {'pages': [{'id': 'p1', 'free': []},                       # hueco ancho
                     {'id': 'p2', 'free': []},                       # hueco estrecho
                     {'id': 'p3', 'free': []}]}                      # sin medida
    med = {'p1': {'x': 10, 'w': 190, 'arriba': 60, 'abajo': 260},
           'p2': {'x': 10, 'w': 190, 'arriba': 200, 'abajo': 250}}   # 50 - 16 = 34 mm < HUECO_MIN
    assert colocar(doc, med, [('a.jpg', 1.87)], 'r') == 1, 'solo p1 tiene hueco suficiente'
    f = doc['pages'][0]['free'][0]
    assert abs(f['w'] / f['h'] - 1.87) < .01, 'la imagen se deforma'
    assert f['y'] >= med['p1']['arriba'] + AIRE - .01, 'se sube sobre la tabla'
    assert f['y'] + f['h'] <= med['p1']['abajo'] - AIRE + .01, 'baja sobre el pie'
    assert f['x'] >= med['p1']['x'] - .01 and f['w'] <= med['p1']['w'] + .01, 'se sale de ancho'
    assert not doc['pages'][1]['free'] and not doc['pages'][2]['free']
    print('autocheck ok')


if __name__ == '__main__':
    if '--check' in sys.argv:
        autocheck()
    else:
        main()
