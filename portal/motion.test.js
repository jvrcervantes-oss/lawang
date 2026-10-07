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

// el FLIP solo con la misma forma (±5 %): si no, un fundido normal
ok(M.mismaForma(300, 225, 520, 390) === true, '4:3 con 4:3 es la misma forma');
ok(M.mismaForma(108, 197, 358, 269) === false, 'la miniatura vertical del móvil no casa con 4:3');
ok(M.mismaForma(300, 225, 520, 300) === false, '4:3 con 16:9.2 no casa');
ok(M.mismaForma(0, 100, 100, 100) === false, 'ancho 0 no casa');
ok(M.mismaForma(NaN, 100, 100, 100) === false, 'NaN no casa');

// sin navegador no hace nada ni falla
ok(M.puede() === false, 'en node no hay animate: puede() es false');
M.pantalla(null, 'inicio'); M.menu(null); M.campana(null, 3); M.abrePanel(null);
let llamado = false; M.cajon(null, null, true, () => { llamado = true; });
ok(llamado, 'cajon sin animación llama igualmente a fin');

if (fallos) { console.error(fallos + ' fallo(s)'); process.exit(1); }
console.log('motion.test.js — OK');
