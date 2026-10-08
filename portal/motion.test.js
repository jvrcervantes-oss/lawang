// motion.test.js — lo puro de motion.js: qué perfil entra en cada pantalla, cómo recorre una cifra y cuándo
// cambia la clave que decide si se anima. Lo visual lo cubre el arnés de capturas.
const M = require('./motion.js');
let fallos = 0;
function ok(c, m) { if (!c) { fallos++; console.error('FALLO:', m); } }

// perfiles de la intranet: B la primera vez de Inicio, D en dinero, A el resto
ok(M.perfil('inicio', []) === 'B', 'Inicio la primera vez entra con B');
ok(M.perfil('inicio', ['inicio']) === 'A', 'Inicio después entra con A');
ok(M.perfil('facturas', []) === 'D', 'Facturas es siempre D, también la primera vez');
ok(M.perfil('facturas', ['inicio']) === 'D', 'Facturas sigue siendo D');
['contratos', 'obra', 'documentos', 'soporte', 'perfil'].forEach(s => ok(M.perfil(s, []) === 'A', s + ' entra con A'));

// la cifra: empieza en 0, acaba EXACTA y nunca pasa del final ni baja
ok(M.valorCuenta(19000, 0) === 0, 'k=0 → 0');
ok(M.valorCuenta(19000, 1) === 19000, 'k=1 → el valor exacto, sin decimales de más');
ok(M.valorCuenta(19000, 1.5) === 19000, 'k>1 → el valor exacto');
ok(M.valorCuenta(19000, -1) === 0, 'k<0 → 0');
let prev = -1;
for (let k = 0; k <= 1.0001; k += 0.05) { const v = M.valorCuenta(123456.78, Math.min(1, k)); ok(v >= prev && v <= 123456.78, 'monótona y acotada en k=' + k); prev = v; }
ok(M.valorCuenta(0, 0.5) === 0, 'un importe 0 sigue en 0');

// la clave: solo cambia al cambiar de sección o de carpeta; un repintado por idioma o datos no la cambia
ok(M.claveVista('inicio', null) === 'inicio|', 'inicio no depende de la carpeta');
ok(M.claveVista('inicio', 'abc') === 'inicio|', 'una carpeta en otra sección se ignora');
ok(M.claveVista('documentos', null) === 'documentos|', 'documentos sin carpeta');
ok(M.claveVista('documentos', 'pf') !== M.claveVista('documentos', null), 'abrir una carpeta cambia la clave');
ok(M.claveVista('documentos', 'pf') !== M.claveVista('documentos', 'sh'), 'cambiar de carpeta cambia la clave');
ok(M.claveVista('documentos', 'pf') === M.claveVista('documentos', 'pf'), 'repintar la misma carpeta NO cambia la clave');

// sin navegador no hace nada ni falla
ok(M.puede() === false, 'en node no hay animate: puede() es false');
M.pantalla(null, 'inicio'); M.menu(null); M.campana(null, 3); M.abrePanel(null);
let llamado = false; M.cajon(null, null, true, () => { llamado = true; });
ok(llamado, 'cajon sin animación llama igualmente a fin');
// las piezas nuevas, sin navegador, tampoco hacen nada ni fallan; el aviso dice que no ha animado
M.selectores(null); M.recuerdaPortada(null);
let pintado = false; M.reordena(null, () => { pintado = true; }, 'data-doc');
ok(pintado, 'reordena sin movimiento pinta igualmente');
ok(M.aviso(null, true) === false, 'aviso sin movimiento devuelve false (el portal sigue con su fundido)');

// el recorte de la foto de la tarjeta dentro de la portada: la ventana exacta, nunca negativa
const dest = { top: 100, right: 500, bottom: 400, left: 50 };
ok(M.recorte({ top: 110, right: 300, bottom: 200, left: 100 }, dest, 12) === 'inset(10px 200px 200px 50px round 12px)', 'recorte de una tarjeta dentro de la portada');
ok(M.recorte(dest, dest) === 'inset(0px 0px 0px 0px round 0px)', 'la misma caja: sin recorte');
ok(M.recorte({ top: 20, right: 600, bottom: 450, left: 0 }, dest, 8) === 'inset(0px 0px 0px 0px round 8px)', 'una tarjeta más grande que la portada no da recortes negativos');

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('motion.test.js — OK');
