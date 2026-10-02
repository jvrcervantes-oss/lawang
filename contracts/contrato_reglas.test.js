/* ═══════════════════════════════════════════════════════════════════════════
   REGLAS DE LA PANTALLA DE CONTRATOS — 19-ago-2026
   `node contrato_reglas.test.js`. Lo corre `tools/test.py`, y con él el gate de
   push. (Nació como `ficha_solo_compradores.test.js`; se renombró al sumar los
   frenos de permisos, que son la misma clase de fallo.)
   ═══════════════════════════════════════════════════════════════════════════
   POR QUÉ EXISTE ESTE TEST. El 18-ago se construyó «el comprador sale de su
   ficha» y, de paso, se le dio al contrato la capacidad de CREAR el cliente
   («Crear ficha de cliente nuevo») y de CORREGIRLO («Corregir ficha», que
   escribía en `clients`). Parecía una comodidad. El owner lo tumbó al día
   siguiente: si dos pantallas pueden crear a la misma persona, la identidad
   vuelve a tener dos dueños — que es exactamente el problema que el cambio del
   18 venía a resolver.

   La norma está escrita en `contexto/suite_lawang.md` («Una persona se da de
   alta en UN solo sitio: Compradores»). Esto es su peldaño mecánico: una regla
   escrita se olvida, y este fallo no da error al cometerlo — el botón funciona
   perfectamente, solo que crea clientes desde donde no debe.

   Lo que afirma, sobre `app.html`:
     1. No hay ninguna escritura a `clients` (insert/update/upsert/delete).
     2. No vuelven los identificadores de los botones que se quitaron.
     3. El buscador sigue existiendo: quitar el alta no puede llevarse por
        delante la forma de ELEGIR a alguien, o el contrato queda sin comprador.
   ═══════════════════════════════════════════════════════════════════════════ */
const fs = require('fs');
const path = require('path');

/* app.html Y los assets que carga: desde el 21-ago-2026 parte del codigo vive
   fuera del .html, y este test se puso en rojo por seguir mirando solo alli.
   Ver codigo_app.js — mover una funcion de fichero no cambia lo que la app hace. */
const app = require('./codigo_app').todo();
const leerAsset = n => fs.readFileSync(path.join(__dirname, 'assets', n), 'utf8');
let fallos = 0;

function afirma(titulo, ok, detalle) {
  if (ok) { console.log('  ok   ' + titulo); return; }
  fallos++;
  console.log('  FALLA ' + titulo + (detalle ? '\n         ' + detalle : ''));
}

/* 1) ninguna escritura a `clients` desde el contrato ------------------------
   Se busca la tabla y el verbo por separado y luego se comprueba que no van
   juntos: `.from('clients')` seguido de un método que escribe, en la misma
   cadena. Un `select` sí puede (y debe) seguir existiendo. */
const escrituras = [];
const re = /from\(\s*['"]clients['"]\s*\)\s*\n?\s*\.?\s*(\w+)/g;
let m;
while ((m = re.exec(app)) !== null) {
  if (/^(insert|update|upsert|delete)$/.test(m[1])) {
    const linea = app.slice(0, m.index).split('\n').length;
    escrituras.push(m[1] + '() en la línea ' + linea);
  }
}
afirma('app.html no escribe en `clients`', escrituras.length === 0, escrituras.join(' · '));

/* 2) los botones que se quitaron no vuelven -------------------------------- */
// `cliNuevo` NO está en la lista a propósito: ese id sobrevive como el ENLACE a
// Compradores. Lo que no puede volver es la función que escribía.
const prohibidos = ['crearFichaComprador', 'guardarCorreccionFicha', 'cliCorregir', 'CORRIGIENDO_FICHA'];
const vueltos = prohibidos.filter(p => app.includes(p));
afirma('no vuelven «Crear ficha» ni «Corregir ficha»', vueltos.length === 0, vueltos.join(' · '));
afirma('el enlace de alta apunta a Compradores',
  app.includes('/intranet/v4/compradores/?nuevo=1'),   // v4 desde el corte de la clasica (27-sep-2026)
  'sin ese enlace, el aviso de «este comprador no tiene ficha» no dice dónde se da de alta');

/* 3) elegir cliente sigue siendo posible ----------------------------------- */
afirma('el buscador de clientes sigue en pie',
  app.includes('wireClienteBuscador(') && app.includes('enlazarFicha('));
afirma('los adquirientes II+ tienen su propio buscador',
  app.includes('data-cli-buscar'));

/* 4) una sola definición de «esta plantilla exige ficha» -------------------- */
const usos = (app.match(/plantillaExigeFicha\(\)/g) || []).length;
afirma('`plantillaExigeFicha()` es la única definición y se reutiliza', usos >= 2,
  'aparece ' + usos + ' vez/veces: el candado y el freno del guardado tienen que compartirla');

/* 5) el bloque de elegir comprador es UNO, no dos ---------------------------
   El 19-ago el owner preguntó por qué el buscador del Adquiriente I y el de los
   adicionales eran distintos. Lo eran porque había dos marcados para la misma
   acción. Ahora los pinta `bloqueElegirComprador()`; esto afirma que no vuelve
   a haber un segundo marcado suelto que pueda derivar del primero. */
const llamadas = (app.match(/bloqueElegirComprador\(/g) || []).length;
afirma('el bloque de elegir comprador se pinta desde una sola función',
  llamadas >= 3, 'aparece ' + llamadas + ' vez/veces (1 definición + 2 usos como mínimo)');
const literales = (app.match(/class="cli-pedir"/g) || []).length;
afirma('no hay un segundo marcado `cli-pedir` a mano', literales === 1,
  'aparece ' + literales + ' veces: si son dos, ya pueden separarse otra vez');

/* 6) «Diseño / Marca» es de admin, y detrás de un botón ---------------------
   19-ago, encargo del owner: mismo criterio que «Editar texto». El panel
   cambia el color de portada, el logo y la marca de agua, y su botón de
   guardar los deja fijados para TODOS los agentes. Que se cuele a un agente
   no da error: simplemente puede cambiar la marca de los contratos. */
afirma('el panel de Diseño solo se construye para admin',
  /if\(!CAN_EDIT_TEXT\) return '';/.test(app),
  'buildDesignPanel() tiene que salirse antes de pintar nada si no es admin');
// Desde el 23-sep la visibilidad vive en la tabla de pintaAcciones(): por ROL
// se oculta (CAN_EDIT_TEXT), por ESTADO se apaga. Las dos filas, misma llave.
afirma('el botón de Diseño se enseña con la misma llave que «Editar texto»',
  /\['btnEdit',\s*CAN_EDIT_TEXT,/.test(app) && /\['btnDesign',\s*CAN_EDIT_TEXT,/.test(app));
afirma('el panel nace escondido y lo abre el botón',
  app.includes('id="designPanel" hidden') && app.includes("$('#btnDesign').addEventListener"));

/* ── LAW-73: la parcela SALE DEL INVENTARIO, nunca se teclea ───────────────
   21-ago-2026, decisión del owner. El campo era texto libre siempre que el
   proyecto no tuviera unidades cargadas, y de ahí salieron 21 parcelas que el
   inventario no reconoce («the fifth bali», «Bungalow Villas Suite num. 6»):
   el contrato decía una parcela, el mapa de unidades no la ataba a nada, y ni
   contaba como vendida ni se bloqueaba. Sin dar ningún error.

   Se comprueba lo que de verdad falla, no que exista una función: que en NINGÚN
   camino se pinte un input de texto para ese campo. Había tres caminos y solo
   se tapó uno la primera vez — sin elegir proyecto, el campo se quedaba como lo
   dejaba fieldHTML y volvía a ser texto libre. */
{
  const parcela = leerAsset('parcela_inventario.js');

  afirma('el campo de parcela no se pinta nunca como texto libre',
    !/<input\s+name="parcela_codigo"\s+type="text"/.test(parcela)
    && !/type="text"[^>]*name="parcela_codigo"/.test(parcela),
    'un input de texto aquí es exactamente lo que produjo las 21 parcelas sueltas');

  afirma('sin proyecto elegido el campo también se repinta (y por tanto se bloquea)',
    /else if\(proy\)\{[\s\S]{0,320}?pintarSelectorParcela\(\)/.test(app),
    'si no se llama a nadie, el campo se queda como lo dejó fieldHTML: un input de texto');

  afirma('una parcela fuera del inventario no se puede quitar',
    /if\(!u\)\{[\s\S]{0,400}?histórica · fuera del inventario/.test(parcela)
    && !/if\(!u\)\{[\s\S]{0,400}?data-quitar-parcela/.test(parcela),
    'sin texto libre, quitarla sería un borrado IRREVERSIBLE detrás de un botón pequeño');

  afirma('los tres motivos por los que no hay lista se dicen distintos',
    /No se ha podido leer el inventario/.test(parcela)
    && /no tiene parcelas en el inventario/.test(parcela)
    && /Elige antes el <b>proyecto<\/b>/.test(parcela),
    'no poder mirar, no haber nada y no haber elegido son tres cosas y piden tres acciones');
}

/* ── Cuánto se comprime un anexo, y qué NUNCA se comprime ──────────────────
   23-ago-2026. La calidad de los anexos la eligió el owner comparando dos
   imágenes de una página REAL (ver el comentario en assets/documento_anexos.js).
   Es un numero con una decision detras, no un valor por defecto: si alguien lo
   cambia, que sea a sabiendas y con otra pagina delante.

   Y la segunda mitad importa mas que la primera. El 21-ago estuve a punto de
   dejar la firma de LAWANG «optimizada»: la revirti al medir que le cambiaba
   hasta 28/255 en el 44% de sus pixeles. Una firma va en PNG, que no pierde
   nada. El dia que alguien la pase a JPEG para ahorrar unos kB, esto lo para. */
{
  const anexos = leerAsset('documento_anexos.js');

  const m = /const CALIDAD_ANEXO = ([\d.]+);/.exec(anexos);
  afirma('la calidad del anexo está declarada en UN solo sitio', !!m,
    'con la cifra repetida en cada llamada, cambiar una y olvidar la otra no da error');
  afirma('sigue siendo la que el owner aprobó mirando una página real (0.55)',
    m && Number(m[1]) === 0.55,
    m ? 'ahora vale ' + m[1] + ': si es a propósito, actualiza también este test y el porqué' : '');

  const sueltas = [...anexos.matchAll(/toDataURL\(\s*'image\/jpeg'\s*,\s*([^)]+)\)/g)]
    .map(x => x[1].trim()).filter(v => v !== 'CALIDAD_ANEXO');
  afirma('ninguna página de anexo se codifica con una calidad escrita a mano',
    sueltas.length === 0, sueltas.join(' · '));

  /* 25-sep-2026: los planos suben a 2.000 px porque las cotas no se leían. Las
     fotos se quedan en la escala de siempre: son las que más pesan, y a ellas
     no les hacía falta. Ver el comentario en documento_anexos.js. */
  const ancho = /const ANCHO_PLANO = (\d+);/.exec(anexos);
  const corte = /const CLARO_PLANO = ([\d.]+);/.exec(anexos);
  afirma('el ancho y el corte de los planos están declarados en UN solo sitio',
    !!ancho && !!corte && (anexos.match(/ANCHO_PLANO\s*=/g) || []).length === 1
      && (anexos.match(/CLARO_PLANO\s*=/g) || []).length === 1);
  afirma('el corte deja margen por debajo del plano más pálido medido (0.67)',
    corte && Number(corte[1]) <= 0.62,
    corte ? 'ahora vale ' + corte[1] + ': por encima de 0.67 hay planos (Dune Sirap p6) que vuelven a 1.190 px' : '');
  afirma('las páginas de foto siguen con la escala de siempre (tope 2×)',
    /pintarPagina\(page, Math\.min\(1400\/base\.width, 2\)\)/.test(anexos),
    'cambiar esto engorda todos los contratos, no solo los que llevan planos');
  afirma('los planos se pintan con la misma CALIDAD_ANEXO: lo que sube es la resolución',
    /fraccionClara\(cv\) >= CLARO_PLANO\) cv = await pintarPagina\(page, Math\.min\(ANCHO_PLANO\/base\.width, 4\)\)/.test(anexos)
    && (anexos.match(/toDataURL\('image\/jpeg'/g) || []).length === 2);

  /* El Anexo Maestro sale de Modelos, nunca del PDF viejo del repo (25-sep-2026). */
  afirma('el anexo automático ya no cae al PDF del repo (assets/anexos/)',
    !/fetch\(\s*'assets\/anexos\//.test(anexos),
    'Dali.pdf y Tropical.pdf son fichas comerciales de julio: volverían a entrar en contratos de Construcción');
  /* 27-sep-2026, el owner revierte la regla del anexo único de Construcción: «debo poder
     subir el PDF que quiera, como antes». La subida se ofrece en todas las plantillas y
     nada retira los anexos subidos a mano. */
  afirma('se pueden subir anexos a mano en cualquier contrato, también en Construcción',
    // LAW-78 (27-sep-2026): la subida pide el contrato GUARDADO (las páginas van al archivo
    // con su id) y no se ofrece con él bloqueado o en firma; sigue en todas las plantillas.
    /<div class="dz"[^>]*><label class="up" id="anxUpLabel">/.test(anexos)
    && !/tipologia_construccion[^\n]*anxUpLabel|anxUpLabel[^\n]*tipologia_construccion/.test(anexos)
    && /if\(inp\) inp\.addEventListener\('change'/.test(anexos)
    && !/retiraAnexosManuales|ANEXO_MANUAL_RETIRADO/.test(anexos + app),
    'el owner quiere adjuntar el PDF que quiera; quitarlo otra vez es una decisión suya, no un refactor');
  /* 30-sep-2026, owner: «que te deje seleccionar desde los archivos que hay en la intranet ya
     subidos». Junto a la subida del ordenador, y por el MISMO camino (anadeAnexosDeFicheros). */
  afirma('se puede elegir como anexo un documento ya subido a la intranet, junto a la subida desde el ordenador',
    /<button type="button" class="up" data-accion="anexo-intranet">/.test(anexos)
    && /anadeAnexosDeFicheros\(\[\{ file, titulo/.test(anexos)
    && /files\.map\(f => \(\{ file:f/.test(anexos),
    'el owner lo pidió: quitarlo es una decisión suya, y las dos vías tienen que compartir la subida');
  /* 27-sep-2026, el owner revierte el bloqueo: «si no hay anexo, que deje mandar
     igual». Sin anexo del modelo se avisa y se decide; no se bloquea. Desde el 27-sep
     (varios documentos marcados) también avisa si uno marcado no se pudo adjuntar. */
  afirma('sin anexo del modelo (o con uno marcado que falla) el envío a firma avisa y deja seguir («Enviar igualmente»), no bloquea',
    /if\(tipSel && \(autoMal \|\| sinApendiceA\)\)\{\s*const seguir = await lwConfirmar\([\s\S]{0,600}?confirmar: lwT\('Enviar igualmente'\)[\s\S]{0,80}?if\(!seguir\) return;[\s\S]{0,240}?\}/.test(app)
    // y deja constancia (owner, 28-sep): lo que confirmó viaja a la edge y la base lo apunta con el envío (LAW-406)
    && /sin_anexo: sinAnexo/.test(app),
    'el owner quiere poder enviar sin anexo; el aviso es para que sea una decisión, no un descuido');
  /* LAW-406 (28-sep-2026): la constancia de «sin anexo» va en la MISMA transacción que el envío. Eran dos
     llamadas (envío y luego constancia) y un fallo de la segunda dejaba un envío sin constancia. Lo que no
     puede volver: la segunda llamada, su aviso de «no apuntada», o una constancia fuera de contrato_envia_firma. */
  const edgeFich = require('fs').readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'ficheros-contrato', 'index.ts'), 'utf8');
  const migEnvio = require('fs').readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260928120000_law406_envia_firma_con_constancia.sql'), 'utf8');
  const cuerpoEnvia = (migEnvio.split('create or replace function public.contrato_envia_firma(')[1] || '').split('end $$;')[0];
  afirma('la constancia de «sin anexo» se apunta dentro de contrato_envia_firma, en la misma transacción que el envío',
    /usuario\.rpc\('contrato_envia_firma', \{[\s\S]{0,400}?p_sin_anexo: body\.sin_anexo/.test(edgeFich)
    && !/contrato_envio_sin_anexo|constancia_sin_anexo_no_apuntada/.test(edgeFich)
    && !/no_se_pudo_apuntar_el_envio_sin_anexo/.test(app)
    && /insert into public\.contrato_firmas[\s\S]*insert into public\.contrato_eventos[\s\S]*'envio_sin_anexo_confirmado'/.test(cuerpoEnvia)
    && !/drop function if exists public\.contrato_envio_sin_anexo\(/.test(migEnvio)   // se retira en el paso 3, tras la edge
    && /drop function if exists public\.contrato_envio_sin_anexo\(/.test(require('fs').readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260928024744_law406_retira_envio_sin_anexo.sql'), 'utf8')),
    'dos llamadas sueltas vuelven a permitir un envío a firma sin su constancia');

  const firmas = require('fs').readFileSync(path.join(__dirname, 'firmar.html'), 'utf8');
  afirma('la firma del comprador se guarda en PNG, nunca en JPEG',
    /toDataURL\('image\/png'\)/.test(firmas) && !/toDataURL\('image\/jpeg'/.test(firmas),
    'JPEG pierde informacion: en una firma manuscrita eso es alterar la prueba');
  afirma('la firma del formulario también va en PNG',
    /pad\.cv\.toDataURL\('image\/png'\)/.test(app));
}

/* UNA SOLA CARA: la v4 (27-sep-2026, owner: «Archivar lo muerto + v4 en todo
   lo vivo»). El generador tuvo dos caras y piel.js decidía cuál; la clásica se
   retiró. Lo que no puede volver sin que nadie lo decida: la salida `?v4=0`, la
   piel que depende de por dónde se llegó (referrer / sessionStorage), el
   listado clásico alcanzable, y la capa v3 apilada encima de la v4. */
{
  const piel = fs.readFileSync(path.join(__dirname, 'assets', 'piel.js'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  const html = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8');
  afirma('piel.js enciende la v4 sin condición',
    /window\.LW_PIEL = 'v4';/.test(piel) && /classList\.add\('v4'\)/.test(piel)
    && !/v4=0|get\('v4'\)|document\.referrer|sessionStorage/.test(piel),
    'la cara v4 volvió a depender de un parámetro, del referrer o de la pestaña');
  afirma('sin puerta de editor, piel.js manda al listado de la v4',
    /location\.replace\('\/intranet\/v4\/contratos\/'\)/.test(piel));
  /* El listado clásico era el panel #cpOverlay a pantalla completa (openContractsPanel, body.modo-listado).
     Se retiró el 27-sep; lo que no puede volver es un listado PROPIO de app.html, se llame como se llame
     su función de entrada (28-sep-2026: la regla anterior vigilaba `pantallaC('listado'`, que ya no existía). */
  afirma('app.html no tiene listado propio de contratos',
    !/id="cpOverlay"|openContractsPanel|modo-listado/.test(html) && !/LW_PIEL/.test(html),
    'el listado de contratos es /intranet/v4/contratos/: dos listados es la duplicación prohibida');
  afirma('app.html no carga la capa v3 encima de la v4',
    !/(src|href)=\"[^\"]*(movimiento-v3\.js|saldos-v3\.js|suite-v3(-herramientas)?\.css)/.test(html));
}

/* EL PANEL DE ANEXOS SE PINTA CON EL CONTRATO YA PUESTO — 2-oct-2026 (owner: «no me deja anexar
   documentos»). buildAnnexPanel() decide en el momento de pintarse si ofrece «+ Subir…» (hay
   SAVED_CONTRACT y no está bloqueado ni a firma). Desde LAW-78 (27-sep) se pintaba al abrir ANTES
   de poner SAVED_CONTRACT y LOCKED, y al guardar uno nuevo no se repintaba: el panel se quedaba en
   «Guarda el contrato para poder añadirle anexos» con el contrato ya guardado. Lo que se afirma:
   después de poner SAVED_CONTRACT (y LOCKED al abrir) hay un rebuildAnnex(); el cambio de estado de
   firma también repinta; y repintar no pliega el panel que el usuario tiene abierto. */
{
  const html = fs.readFileSync(path.join(__dirname, 'app.html'), 'utf8');
  const cuerpo = nombre => {
    const i = html.search(new RegExp('\\n(async )?function ' + nombre + '\\('));
    if (i < 0) return '';
    const j = html.slice(i + 1).search(/\n(async )?function \w+\(/);
    return j < 0 ? html.slice(i) : html.slice(i, i + 1 + j);
  };
  const repintaTras = (c, marca) => c.indexOf(marca) >= 0 && c.lastIndexOf('rebuildAnnex()') > c.indexOf(marca);
  const abrir = cuerpo('openSavedContract'), guardar = cuerpo('guardarContrato'), firma = cuerpo('aplicarEstadoFirma');
  afirma('al abrir un contrato, el panel de anexos se repinta con SAVED_CONTRACT y LOCKED ya puestos',
    repintaTras(abrir, 'SAVED_CONTRACT = {') && repintaTras(abrir, 'LOCKED = !!data.bloqueado'),
    'sin esto el panel dice «Guarda el contrato…» en un contrato guardado y no ofrece subir anexos');
  afirma('al guardar, el panel de anexos se repinta con el contrato ya guardado',
    repintaTras(guardar, 'SAVED_CONTRACT = {'),
    'un contrato recién creado seguía sin botón de subir anexos hasta recargar');
  // aplicarEstadoFirma corre con CADA tecla (updateSaveButton): repintar ahí sin guarda cambia el panel
  // bajo los dedos. Tiene que ir por la guarda, nunca por rebuildAnnex() a pelo (revisor, 2-oct-2026).
  afirma('el estado de firma repinta el panel de anexos solo si cambia lo que decide la subida',
    /repintaAnexosSiCambia\(\)/.test(firma) && !/rebuildAnnex\(\)/.test(firma),
    'rebuildAnnex() a pelo en aplicarEstadoFirma repinta con cada tecla: se pierde el título del anexo y el «Incluir»');
  // El comportamiento (la guarda no repinta si nada cambió; repintar conserva el panel abierto) lo
  // ejecuta documento_anexos.test.js sobre el código real.
}

console.log(fallos ? '\n' + fallos + ' fallo(s)' : '\nLas reglas de la pantalla de contratos se sostienen.');
process.exit(fallos ? 1 : 0);
