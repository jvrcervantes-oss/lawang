/* Afinador de grosor de titulares sobre la página real (owner 7-oct-2026).
   Solo se carga con ?afinar en la dirección (lo engancha el cargador del final de cada index.html).
   Todo pasa en el navegador de quien lo abre: no escribe en ningún sitio salvo su localStorage.
   Retirar este fichero y su cargador cuando el owner cierre los pesos. */
(function () {
  var GRUPOS = [
    { id: 'h1', nombre: 'Titular de portada', sel: 'html body h1' },
    { id: 'h2', nombre: 'Títulos de sección', sel: 'html body h2' },
    { id: 'h3', nombre: 'Títulos de bloque', sel: 'html body h3' },
    { id: 'pr', nombre: 'Nombres de proyecto', sel: 'html body .proys .villa .b h3' }
  ];
  var KABEL = [[300, 'Light'], [350, 'Book'], [400, 'Regular'], [500, 'Medium'], [700, 'Bold']];
  var SEASONS = [[400, 'Regular'], [700, 'Bold']];
  var INICIAL = { h1: 700, h2: 700, h3: 700, pr: 700 };
  var estado;
  try { estado = JSON.parse(localStorage.getItem('lw-afinar-pesos')) || null; } catch (e) { estado = null; }
  estado = Object.assign({}, INICIAL, estado || {});

  var hoja = document.createElement('style');
  hoja.textContent = "@font-face{font-family:'Neue Kabel';src:url('/assets/fonts/neue-kabel/NeueKabel-Book.woff2') format('woff2');font-weight:350;font-style:normal;font-display:swap}";
  document.head.appendChild(hoja);
  var reglas = document.createElement('style');
  document.head.appendChild(reglas);

  function aplica() {
    reglas.textContent = GRUPOS.map(function (g) {
      return g.sel + ',' + g.sel + ' em,' + g.sel + ' .nk{font-weight:' + estado[g.id] + '!important}';
    }).join('\n');
    try { localStorage.setItem('lw-afinar-pesos', JSON.stringify(estado)); } catch (e) {}
    resumen.textContent = GRUPOS.map(function (g) {
      var tabla = g.id === 'pr' ? SEASONS : KABEL;
      var n = tabla.filter(function (p) { return p[0] === estado[g.id]; })[0];
      return g.nombre + ': ' + (n ? n[1] : estado[g.id]);
    }).join(' · ');
  }

  var panel = document.createElement('div');
  panel.setAttribute('style', 'position:fixed;left:12px;bottom:100px;z-index:99999;width:min(340px,calc(100vw - 24px));background:#fffdf8;color:#1b1c19;border:1px solid #beb3a5;border-radius:14px;padding:12px 14px;font:13px/1.4 Jost,system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.18)');
  panel.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px"><b style="font-size:13px">Grosor de titulares</b><button type="button" data-af="plegar" style="border:0;background:none;cursor:pointer;font:inherit;color:#485b37">Ocultar</button></div><div data-af="cuerpo"></div><div data-af="resumen" style="margin-top:8px;padding-top:8px;border-top:1px solid #e4e2dd;color:#44483f;font-size:12px"></div>';
  var cuerpo = panel.querySelector('[data-af="cuerpo"]'), resumen = panel.querySelector('[data-af="resumen"]');

  GRUPOS.forEach(function (g) {
    var fila = document.createElement('div');
    fila.setAttribute('style', 'margin:6px 0');
    fila.innerHTML = '<div style="font-size:12px;color:#44483f;margin-bottom:3px"></div><div data-af="opciones" style="display:flex;flex-wrap:wrap;gap:4px"></div>';
    fila.firstChild.textContent = g.nombre + (g.id === 'pr' ? ' (The Seasons)' : ' (Neue Kabel)');
    var ops = fila.querySelector('[data-af="opciones"]');
    (g.id === 'pr' ? SEASONS : KABEL).forEach(function (p) {
      var b = document.createElement('button');
      b.type = 'button'; b.textContent = p[1]; b.setAttribute('data-peso', p[0]);
      b.setAttribute('style', 'border:1px solid #beb3a5;border-radius:999px;padding:3px 10px;cursor:pointer;font:inherit;font-size:12px');
      b.onclick = function () { estado[g.id] = p[0]; pinta(); aplica(); };
      ops.appendChild(b);
    });
    fila.pinta = function () {
      ops.querySelectorAll('button').forEach(function (b) {
        var on = +b.getAttribute('data-peso') === estado[g.id];
        b.style.background = on ? '#104c4f' : '#fff'; b.style.color = on ? '#fffdf8' : '#1b1c19';
      });
    };
    cuerpo.appendChild(fila);
  });
  function pinta() { Array.prototype.forEach.call(cuerpo.children, function (f) { f.pinta(); }); }
  panel.querySelector('[data-af="plegar"]').onclick = function () {
    var oculto = cuerpo.style.display === 'none';
    cuerpo.style.display = oculto ? '' : 'none'; this.textContent = oculto ? 'Ocultar' : 'Mostrar';
  };
  document.body.appendChild(panel);
  pinta(); aplica();
})();
