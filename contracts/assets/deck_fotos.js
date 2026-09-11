/* ═══════════════════════════════════════════════════════════════════════════
   FOTOS PÚBLICAS DEL INVESTOR DECK — pieza compartida de la suite
   11-sep-2026 · encargo del owner
   ═══════════════════════════════════════════════════════════════════════════

   POR QUÉ VIVE AQUÍ Y NO DENTRO DE UNA PANTALLA. La usan DOS herramientas —
   Proyectos (fotos del sitio) y Modelos (fotos de una tipología de villa)— y la
   Regla 0 de `contexto/suite_lawang.md` es explícita: una pieza que van a usar
   dos herramientas o más nace ya en `contracts/assets/`, no dentro de una con
   idea de moverla luego. Esa mudanza no ocurre nunca, y lo que queda son dos
   copias que divergen — que en esta suite ha sido el fallo, no la causa del
   fallo, cinco veces seguidas.

   ⚠️ AQUÍ SUBIR ES PUBLICAR, Y NO ES UN DESCUIDO. El bucket `deck` es el único
   público de los seis de Lawang (decisión del owner, 11-sep-2026): el fichero es
   alcanzable por URL desde el segundo en que se sube, salga o no listado en el
   deck. Por eso `deck_fotos` NO tiene columna «publicado» —sería decorativa y
   mentiría— y por eso esta pantalla lo dice con esas palabras en vez de esconderlo
   detrás de una casilla. La foto está o no está.

   ⚠️ TODA IMAGEN SE RECODIFICA EN EL NAVEGADOR ANTES DE SUBIR. No es una
   optimización: hace tres trabajos que no se pueden dar por hechos de otra forma.
   1. Mata el EXIF. Una foto de obra lleva coordenadas GPS, y en un proyecto
      inmobiliario eso es la casa de un comprador real, publicada.
   2. Valida que los bytes SON una imagen. `allowed_mime_types` del bucket valida
      el content-type que DECLARA el cliente, no el contenido: un fichero .html
      etiquetado `image/webp` se colaría y quedaría servido bajo nuestra
      infraestructura. Lo que no decodifica no se puede recodificar.
   3. Deja WebP, que es obligatorio en toda web del estudio.

   Depende de la cáscara ya montada (`suite.css`, `suite-comun.js`, `dialogo.js`,
   `idioma.js`): `suiAbrirCajon`, `toast`, `esc`, `lwConfirmar`, `lwT`. No trae
   ni una línea de CSS propia.
   ═══════════════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var BUCKET = 'deck';
  var LADO_MAX = 2000;       // px del lado mayor
  var CALIDAD = 0.86;
  var IDIOMAS = [['en', 'Inglés'], ['es', 'Español'], ['id', 'Bahasa']];

  function T(s) { return window.lwT ? lwT(s) : s; }
  function E(s) { return window.esc ? esc(s) : String(s == null ? '' : s); }
  function aviso(s) { if (window.toast) toast(s); }

  /* Recodificado. `createImageBitmap` es el que de verdad decide si esto era una
     imagen: con cualquier otra cosa lanza, y ahí se acaba el camino. */
  function aWebp(file) {
    return createImageBitmap(file).then(function (bmp) {
      var escala = Math.min(1, LADO_MAX / Math.max(bmp.width, bmp.height));
      var w = Math.round(bmp.width * escala);
      var h = Math.round(bmp.height * escala);
      var c = document.createElement('canvas');
      c.width = w; c.height = h;
      c.getContext('2d').drawImage(bmp, 0, 0, w, h);
      if (bmp.close) bmp.close();
      return new Promise(function (res, rej) {
        c.toBlob(function (b) {
          // Safari viejo no sabe WebP en toBlob y devuelve PNG o null. Se para
          // aquí: subir un PNG etiquetado .webp rompería el bucket, que solo
          // admite image/webp, y el error saldría lejos de su causa.
          if (!b || b.type !== 'image/webp') {
            rej(new Error(T('Este navegador no sabe guardar en WebP. Usa Chrome, Edge o Firefox.')));
            return;
          }
          res(b);
        }, 'image/webp', CALIDAD);
      });
    });
  }

  /* ── la pantalla ──────────────────────────────────────────────────────────
     `opts`: { SB, ambito:'proyecto'|'modelo', proyectoId, modeloId, titulo,
               sub, esAdmin } */
  function abrir(opts) {
    var SB = opts.SB;
    var esModelo = opts.ambito === 'modelo';
    var FOTOS = [];

    function url(path) {
      return SB.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
    }

    function filtro(q) {
      return esModelo ? q.eq('modelo_id', opts.modeloId) : q.eq('proyecto_id', opts.proyectoId);
    }

    function cargar() {
      return filtro(SB.from('deck_fotos').select('*')).order('uso').order('orden')
        .then(function (r) {
          if (r.error) throw r.error;
          FOTOS = r.data || [];
        });
    }

    function pie(f, lang) {
      return (f.pie && f.pie[lang]) || '';
    }

    function cuerpo() {
      var filas = FOTOS.map(function (f, i) {
        return '' +
          '<div class="sui-bloque" style="display:flex;gap:12px;align-items:flex-start;padding:10px 0;border-bottom:1px solid var(--linea)">' +
            '<img src="' + E(url(f.path)) + '" alt="" loading="lazy" ' +
                 'style="width:104px;height:78px;object-fit:cover;border-radius:var(--r-p);border:1px solid var(--linea);flex:none">' +
            '<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px">' +
              '<div style="display:flex;gap:8px;flex-wrap:wrap">' +
                (esModelo ? '' :
                  '<select class="sui-sel" data-campo="uso" data-id="' + E(f.id) + '" style="max-width:150px" aria-label="' + T('Dónde sale') + '">' +
                    '<option value="hero"' + (f.uso === 'hero' ? ' selected' : '') + '>' + T('Portada') + '</option>' +
                    '<option value="galeria"' + (f.uso === 'galeria' ? ' selected' : '') + '>' + T('Galería') + '</option>' +
                  '</select>') +
                '<select class="sui-sel" data-campo="tipo" data-id="' + E(f.id) + '" style="max-width:190px" aria-label="' + T('Qué es') + '">' +
                  '<option value="foto"' + (f.tipo === 'foto' ? ' selected' : '') + '>' + T('Fotografía real') + '</option>' +
                  '<option value="render"' + (f.tipo === 'render' ? ' selected' : '') + '>' + T('Render') + '</option>' +
                  '<option value="ia"' + (f.tipo === 'ia' ? ' selected' : '') + '>' + T('Imagen generada por IA') + '</option>' +
                '</select>' +
                '<button type="button" class="sui-btn" data-sube="' + E(f.id) + '"' + (i === 0 ? ' disabled' : '') + ' aria-label="' + T('Subir') + '">↑</button>' +
                '<button type="button" class="sui-btn" data-baja="' + E(f.id) + '"' + (i === FOTOS.length - 1 ? ' disabled' : '') + ' aria-label="' + T('Bajar') + '">↓</button>' +
                '<button type="button" class="sui-btn" data-borra="' + E(f.id) + '">' + T('Quitar') + '</button>' +
              '</div>' +
              IDIOMAS.map(function (l) {
                return '<div class="campo" style="margin:0">' +
                  '<label for="pie-' + E(f.id) + '-' + l[0] + '" class="mini">' + T('Pie') + ' · ' + l[1] + '</label>' +
                  '<input id="pie-' + E(f.id) + '-' + l[0] + '" data-pie="' + E(f.id) + '" data-lang="' + l[0] + '" ' +
                    'value="' + E(pie(f, l[0])) + '"' + (l[0] === 'en' ? ' placeholder="' + T('Obligatorio') + '"' : '') + '></div>';
              }).join('') +
            '</div>' +
          '</div>';
      }).join('');

      return '' +
        '<div class="sui-aviso" role="status">' +
          '<b>' + T('Al subir, la foto es pública al instante.') + '</b> ' +
          T('Queda accesible por su dirección web aunque todavía no salga en el deck, igual que una foto colgada en la web. No subas aquí nada que no pueda ver cualquiera.') +
        '</div>' +
        '<p class="sui-nota">' +
          T('Se convierten solas a WebP y se les quitan los datos ocultos de la cámara (incluida la ubicación GPS) antes de salir de este navegador. Se redimensionan a 2000 px de lado mayor.') +
          (esModelo
            ? ' ' + T('Estas fotos son del MODELO, así que salen en el deck de todos los proyectos donde se construya.')
            : ' ' + T('«Portada» son las del carrusel de arriba del deck; «Galería», las de la sección de fotos.')) +
        '</p>' +
        '<p class="sui-nota">' +
          T('El pie en inglés es obligatorio: es el que ve quien abre el deck en un idioma que no tenemos. Si falta, la foto no se guarda. «Render» e «Imagen generada por IA» salen escritos junto al pie — un render de algo aún no construido no puede pasar por fotografía.') +
        '</p>' +
        '<div style="margin:14px 0;display:flex;gap:8px;align-items:center;flex-wrap:wrap">' +
          '<input type="file" id="df-file" accept="image/*" multiple hidden>' +
          '<button type="button" class="sui-btn primario" id="df-anadir"' + (opts.esAdmin ? '' : ' disabled') + '>' +
            T('Añadir fotos…') + '</button>' +
          '<span class="mini" id="df-estado"></span>' +
        '</div>' +
        (opts.esAdmin ? '' : '<p class="sui-nota">' + T('Solo un administrador puede cambiar estas fotos.') + '</p>') +
        '<div id="df-lista">' + (filas || '<p class="sui-nota">' + T('Todavía no hay ninguna foto. El deck sigue enseñando las que trae el repositorio hasta que subas la primera.') + '</p>') + '</div>';
    }

    function repinta() {
      var cont = document.getElementById('df-cajon-cuerpo');
      if (!cont) return;
      cont.innerHTML = cuerpo();
      ata();
    }

    function guarda(id, fila) {
      return SB.from('deck_fotos').update(fila).eq('id', id).select('id').then(function (r) {
        if (r.error) throw r.error;
        // Sin fila devuelta no es "guardado": es que la policy no dejó. La suite
        // ya se comió una vez un "Guardado" que no había guardado nada.
        if (!r.data || !r.data.length) throw new Error(T('No tienes permiso (solo administrador).'));
      });
    }

    function ata() {
      var $$ = function (s) { return Array.prototype.slice.call(document.querySelectorAll(s)); };

      $$('#df-lista [data-campo]').forEach(function (sel) {
        sel.onchange = function () {
          var fila = {}; fila[sel.getAttribute('data-campo')] = sel.value;
          guarda(sel.getAttribute('data-id'), fila)
            .then(function () { aviso(T('Guardado')); return cargar(); }).then(repinta)
            .catch(function (e) { aviso(T('No se ha guardado: ') + (e.message || e)); });
        };
      });

      // El pie se guarda al SALIR del campo, no en cada tecla: son tres idiomas
      // por foto y escribir una frase serían cuarenta escrituras.
      $$('#df-lista [data-pie]').forEach(function (inp) {
        inp.onchange = function () {
          var id = inp.getAttribute('data-pie');
          var f = FOTOS.filter(function (x) { return x.id === id; })[0];
          if (!f) return;
          var p = Object.assign({}, f.pie || {});
          var v = inp.value.trim();
          if (v) p[inp.getAttribute('data-lang')] = v; else delete p[inp.getAttribute('data-lang')];
          if (!p.en) {
            aviso(T('El pie en inglés no puede quedarse vacío.'));
            inp.value = (f.pie && f.pie.en) || '';
            return;
          }
          guarda(id, { pie: p })
            .then(function () { aviso(T('Guardado')); return cargar(); })
            .catch(function (e) { aviso(T('No se ha guardado: ') + (e.message || e)); });
        };
      });

      // Reordenar intercambiando el `orden` con el vecino DENTRO de su mismo uso:
      // portada y galería son dos listas, y moverse entre ellas se hace con el
      // desplegable, no con las flechas.
      function mueve(id, delta) {
        var f = FOTOS.filter(function (x) { return x.id === id; })[0];
        if (!f) return;
        var hermanas = FOTOS.filter(function (x) { return x.uso === f.uso; });
        var i = hermanas.indexOf(f);
        var otra = hermanas[i + delta];
        if (!otra) return;
        Promise.all([guarda(f.id, { orden: otra.orden }), guarda(otra.id, { orden: f.orden })])
          .then(cargar).then(repinta)
          .catch(function (e) { aviso(T('No se ha podido mover: ') + (e.message || e)); });
      }
      $$('#df-lista [data-sube]').forEach(function (b) { b.onclick = function () { mueve(b.getAttribute('data-sube'), -1); }; });
      $$('#df-lista [data-baja]').forEach(function (b) { b.onclick = function () { mueve(b.getAttribute('data-baja'), 1); }; });

      $$('#df-lista [data-borra]').forEach(function (b) {
        b.onclick = function () {
          var id = b.getAttribute('data-borra');
          var f = FOTOS.filter(function (x) { return x.id === id; })[0];
          if (!f) return;
          var seguir = window.lwConfirmar
            ? lwConfirmar({ titulo: T('Quitar esta foto'),
                            cuerpo: '<p>' + T('Desaparece del deck y se borra del almacenamiento. No se puede deshacer.') + '</p>',
                            confirmar: T('Quitar') })
            : Promise.resolve(true);
          Promise.resolve(seguir).then(function (ok) {
            if (!ok) return;
            /* PRIMERO EL FICHERO Y DESPUÉS LA FILA, y aquí importa más que en el
               resto de la suite: al revés, un fallo al borrar el objeto dejaría
               una imagen que el deck ya no lista pero que sigue siendo PÚBLICA
               en su dirección, y sin ninguna fila que diga que está ahí. */
            return SB.storage.from(BUCKET).remove([f.path]).then(function (r) {
              if (r.error) throw r.error;
              return SB.from('deck_fotos').delete().eq('id', id);
            }).then(function (r) {
              if (r && r.error) throw r.error;
              aviso(T('Foto quitada'));
              return cargar();
            }).then(repinta);
          }).catch(function (e) { aviso(T('No se ha podido quitar: ') + (e.message || e)); });
        };
      });

      var btn = document.getElementById('df-anadir');
      var file = document.getElementById('df-file');
      if (btn && file) {
        btn.onclick = function () { file.click(); };
        file.onchange = function () { sube(Array.prototype.slice.call(file.files)); file.value = ''; };
      }
    }

    function sube(files) {
      if (!files.length) return;
      var estado = document.getElementById('df-estado');
      var hechas = 0, fallos = [];
      var base = FOTOS.reduce(function (a, f) { return Math.max(a, f.orden); }, -1) + 1;

      function siguiente(i) {
        if (i >= files.length) {
          if (estado) estado.textContent = '';
          if (fallos.length) aviso(T('No han entrado: ') + fallos.join(', '));
          if (hechas) aviso(hechas + ' ' + T('foto(s) añadida(s) y ya públicas'));
          return cargar().then(repinta);
        }
        if (estado) estado.textContent = T('Preparando ') + (i + 1) + '/' + files.length + '…';
        return aWebp(files[i]).then(function (blob) {
          var path = opts.ambito + '/' + crypto.randomUUID() + '.webp';
          return SB.storage.from(BUCKET).upload(path, blob, { contentType: 'image/webp' })
            .then(function (up) {
              if (up.error) throw up.error;
              var fila = {
                ambito: opts.ambito, uso: esModelo ? 'galeria' : 'galeria',
                tipo: 'foto', path: path, orden: base + i,
                // Nace con el nombre del fichero como pie en inglés: el CHECK de
                // la tabla exige `en`, y dejar que la subida falle por un campo
                // que el usuario aún no ha podido escribir sería absurdo. Es un
                // punto de partida para corregir, no un placeholder inventado:
                // sale del nombre que la persona le puso a su propio fichero.
                pie: { en: files[i].name.replace(/\.[a-z0-9]+$/i, '').replace(/[_-]+/g, ' ').trim() || 'Photo' }
              };
              if (esModelo) fila.modelo_id = opts.modeloId; else fila.proyecto_id = opts.proyectoId;
              return SB.from('deck_fotos').insert(fila).select('id');
            })
            .then(function (r) {
              if (r.error) {
                /* Si la fila no entra, el fichero que acaba de subirse se queda
                   huérfano EN UN BUCKET PÚBLICO. Se retira sin preguntar. */
                return SB.storage.from(BUCKET).remove([path]).then(function () { throw r.error; });
              }
              hechas++;
            });
        }).catch(function (e) {
          fallos.push(files[i].name + ' (' + (e.message || e) + ')');
        }).then(function () { return siguiente(i + 1); });
      }
      siguiente(0);
    }

    cargar().then(function () {
      suiAbrirCajon({
        titulo: opts.titulo || T('Fotos públicas del deck'),
        sub: opts.sub || '',
        cuerpo: '<div id="df-cajon-cuerpo">' + cuerpo() + '</div>',
        pie: '<button class="sui-btn" id="df-cerrar">' + T('Cerrar') + '</button>',
      });
      var c = document.getElementById('df-cerrar');
      if (c) c.onclick = suiCerrarCajon;
      ata();
    }).catch(function (e) {
      aviso(T('No se han podido cargar las fotos: ') + (e.message || e));
    });
  }

  window.lwDeckFotos = { abrir: abrir };
})();
