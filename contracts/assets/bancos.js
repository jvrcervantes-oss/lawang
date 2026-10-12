/* ═══════════════════════════════════════════════════════════════════════════
   BANCOS — lectura de extractos y sugerencias de conciliación (24-sep-2026)
   ═══════════════════════════════════════════════════════════════════════════
   Módulo `bancos` del AxisWorks ERP. Funciones PURAS (sin DOM ni red): entra el
   texto del extracto y un perfil de lectura; salen movimientos normalizados. Lo
   pinta y lo guarda `intranet/v4/assets/panel-bancos.js`; lo prueba
   `contracts/bancos.test.js`.

   Por qué importación y no conexión: Statrys y los bancos de Hong Kong y
   Singapur que usa el cliente no ofrecen una API que la intranet pueda usar.
   Cada banco exporta su CSV a su manera, así que el formato NO se adivina en
   código: se guarda un PERFIL por cuenta (qué columna es qué), que se propone
   solo a partir de las cabeceras y la persona confirma la primera vez.

   Reglas:
   · Un importe de un extracto es TEXTO tecleado por un banco: se lee con
     lwParseImporte (acepta 1,234.56 y 1.234,56), más los dos formatos de negativo
     de los bancos: «(1,234.56)» y «1,234.56-».
   · Signo único: + entra, − sale. Si el banco da dos columnas (cargo / abono),
     se combinan aquí y en ningún otro sitio.
   · La huella que evita duplicar al reimportar = cuenta + fecha + importe +
     moneda + concepto normalizado + referencia + «#k», donde k es la ocurrencia
     entre filas IDÉNTICAS de ese fichero (revisión previa #67, Datos). Así dos
     transferencias iguales el mismo día son #1 y #2, y reimportar un extracto
     que se solapa choca exactamente. NO lleva el orden dentro del día (un
     extracto cortado a media jornada lo desplazaría) ni el saldo (un export lo
     trae y otro no).
   ═══════════════════════════════════════════════════════════════════════════ */

/* ── CSV ───────────────────────────────────────────────────────────────────
   RFC 4180 con comillas, y separador detectado (coma, punto y coma o tabulador)
   contando en las primeras líneas cuál aparece de forma constante. */
function bancosSeparador(texto){
  const lineas = String(texto || '').split(/\r?\n/).filter(l => l.trim()).slice(0, 12);
  let mejor = ',', puntos = -1;
  for (const sep of [',', ';', '\t']){
    const cuentas = lineas.map(l => l.split(sep).length - 1).filter(n => n > 0);
    if (!cuentas.length) continue;
    const moda = cuentas.sort((a, b) => cuentas.filter(x => x === b).length - cuentas.filter(x => x === a).length)[0];
    const p = cuentas.filter(n => n === moda).length * moda;
    if (p > puntos){ puntos = p; mejor = sep; }
  }
  return mejor;
}
function bancosCSV(texto, sep){
  const s = String(texto || '').replace(/^﻿/, '');
  sep = sep || bancosSeparador(s);
  const filas = []; let fila = [], campo = '', comillas = false;
  for (let i = 0; i < s.length; i++){
    const c = s[i];
    if (comillas){
      if (c === '"'){ if (s[i + 1] === '"'){ campo += '"'; i++; } else comillas = false; }
      else campo += c;
    } else if (c === '"') comillas = true;
    else if (c === sep){ fila.push(campo); campo = ''; }
    else if (c === '\n' || c === '\r'){
      if (c === '\r' && s[i + 1] === '\n') i++;
      fila.push(campo); campo = '';
      if (fila.some(x => x.trim() !== '')) filas.push(fila);
      fila = [];
    } else campo += c;
  }
  fila.push(campo);
  if (fila.some(x => x.trim() !== '')) filas.push(fila);
  return filas.map(f => f.map(x => x.trim()));
}

/* ── Fechas ────────────────────────────────────────────────────────────────
   Formatos que usan estos bancos. 'auto' mira TODAS las fechas de la columna:
   si alguna trae un primer número > 12 es DD/MM; si alguna trae el segundo > 12,
   MM/DD; si ninguna lo resuelve, se asume DD/MM (Hong Kong, Singapur e Indonesia
   escriben el día primero) y el perfil lo deja guardado para confirmarlo. */
const BANCOS_MESES = { jan:1, feb:2, mar:3, apr:4, may:5, jun:6, jul:7, aug:8, sep:9, sept:9, oct:10, nov:11, dec:12,
  ene:1, abr:4, ago:8, dic:12, agu:8, des:12, mei:5, okt:10 };
function _iso(y, m, d){
  y = Number(y); m = Number(m); d = Number(d);
  if (y < 100) y += 2000;
  if (!(y > 1990 && m >= 1 && m <= 12 && d >= 1 && d <= 31)) return null;
  const f = new Date(Date.UTC(y, m - 1, d));
  if (f.getUTCMonth() !== m - 1) return null;                 // 31/02 no existe
  return y + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
}
function bancosFecha(txt, formato){
  const t = String(txt || '').trim();
  if (!t) return null;
  let m = t.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/);           // 2026-09-24
  if (m) return _iso(m[1], m[2], m[3]);
  m = t.match(/^(\d{1,2})[\s\-/.]([A-Za-z]{3,4})[a-z]*[\s\-/.,]+(\d{2,4})/);   // 24 Sep 2026 · 24-Sep-26
  if (m && BANCOS_MESES[m[2].toLowerCase()]) return _iso(m[3], BANCOS_MESES[m[2].toLowerCase()], m[1]);
  m = t.match(/^([A-Za-z]{3,4})[a-z]*[\s\-/.]+(\d{1,2}),?[\s\-/.]+(\d{2,4})/);   // Sep 24, 2026
  if (m && BANCOS_MESES[m[1].toLowerCase()]) return _iso(m[3], BANCOS_MESES[m[1].toLowerCase()], m[2]);
  m = t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})/);             // 24/09/2026 o 09/24/2026
  if (m) return formato === 'mdy' ? _iso(m[3], m[1], m[2]) : _iso(m[3], m[2], m[1]);
  return null;
}
function bancosFormatoFecha(valores){
  let dmy = false, mdy = false;
  for (const v of valores || []){
    const m = String(v || '').trim().match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})/);
    if (!m) continue;
    if (Number(m[1]) > 12) dmy = true;
    if (Number(m[2]) > 12) mdy = true;
  }
  return mdy && !dmy ? 'mdy' : 'dmy';
}

/* ── Importes ──────────────────────────────────────────────────────────── */
function bancosImporte(txt){
  let t = String(txt == null ? '' : txt).trim();
  if (!t || t === '-') return null;
  let neg = false;
  if (/^\(.*\)$/.test(t)){ neg = true; t = t.slice(1, -1); }          // (1,234.56)
  if (/-\s*$/.test(t) && !/^-/.test(t)){ neg = true; t = t.replace(/-\s*$/, ''); }   // 1,234.56-
  if (/^\s*-/.test(t)){ neg = true; t = t.replace(/^\s*-/, ''); }
  t = t.replace(/[A-Za-z$€£¥]/g, '').trim();                       // «HKD 1,000.00», «$1,000»
  const n = typeof lwParseImporte === 'function' ? lwParseImporte(t) : Number(t.replace(/,/g, ''));
  if (n == null || !isFinite(n)) return null;
  return Math.round((neg ? -n : n) * 100) / 100;
}

/* ── Perfil propuesto a partir de las cabeceras ────────────────────────────
   Solo PROPONE: la pantalla lo enseña con una vista previa y la persona lo
   confirma o lo corrige. Devuelve índices de columna (o null). */
const BANCOS_PISTAS = {
  fecha:      /^(transaction\s*date|txn\s*date|date|fecha|posting\s*date|booking\s*date|tanggal)$/i,
  fechaValor: /^(value\s*date|fecha\s*valor)$/i,
  concepto:   /(description|details|narrative|particulars|concepto|transaction\s*details|remarks|keterangan)/i,
  referencia: /(reference|ref\.?\s*no|referencia|cheque|transaction\s*id|txn\s*id)/i,
  importe:    /^(amount|importe|transaction\s*amount|jumlah)$/i,
  cargo:      /(debit|withdrawal|withdrawals|money\s*out|cargo|salida|paid\s*out)/i,
  abono:      /(credit|deposit|deposits|money\s*in|abono|entrada|paid\s*in)/i,
  saldo:      /(balance|saldo|running\s*balance)/i,
  moneda:     /^(currency|ccy|moneda|mata\s*uang)$/i,
};
function bancosProponerPerfil(filas){
  // la fila de cabeceras es la primera con 3+ celdas de texto y alguna pista de fecha
  let cab = 0;
  for (let i = 0; i < Math.min(filas.length, 15); i++){
    if (filas[i].some(c => BANCOS_PISTAS.fecha.test(c) || BANCOS_PISTAS.fechaValor.test(c))){ cab = i; break; }
  }
  const h = (filas[cab] || []).map(x => x.trim());
  const col = re => { const i = h.findIndex(x => re.test(x)); return i === -1 ? null : i; };
  const p = { cabecera: cab, fecha: col(BANCOS_PISTAS.fecha), fechaValor: col(BANCOS_PISTAS.fechaValor), concepto: col(BANCOS_PISTAS.concepto),
    referencia: col(BANCOS_PISTAS.referencia), importe: col(BANCOS_PISTAS.importe), cargo: col(BANCOS_PISTAS.cargo), abono: col(BANCOS_PISTAS.abono),
    saldo: col(BANCOS_PISTAS.saldo), moneda: col(BANCOS_PISTAS.moneda), formatoFecha: 'auto', monedaFija: null };
  if (p.fecha == null) p.fecha = p.fechaValor;
  // «balance» también casa en «Credit balance»: nunca la misma columna para dos papeles
  if (p.saldo != null && (p.saldo === p.abono || p.saldo === p.cargo)) p.saldo = null;
  if (p.importe != null){ p.cargo = null; p.abono = null; }
  return p;
}

/* ── Hash corto y estable (cyrb53) para la huella ─────────────────────── */
function bancosHash(str){
  let h1 = 0xdeadbeef, h2 = 0x41c6ce57;
  for (let i = 0; i < str.length; i++){
    const ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761); h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(36);
}

/* ── Aplicar un perfil: filas del extracto → movimientos ───────────────────
   Devuelve { movimientos, errores } — una fila que no se puede leer NO se
   descarta en silencio: va a `errores` con su nº de línea y el motivo, y la
   pantalla lo enseña antes de guardar. */
function bancosLeer(filas, perfil, cuenta, monedaCuenta){
  const p = perfil || {};
  const datos = filas.slice((p.cabecera || 0) + 1);
  const fmt = p.formatoFecha && p.formatoFecha !== 'auto' ? p.formatoFecha
            : bancosFormatoFecha(datos.map(f => f[p.fecha]));
  const movs = [], errores = [], vistos = {};
  datos.forEach((f, i) => {
    const linea = (p.cabecera || 0) + i + 2;
    const celda = k => (p[k] == null ? '' : (f[p[k]] || '').trim());
    const fecha = bancosFecha(celda('fecha'), fmt);
    if (!fecha){
      // pies de extracto («Closing balance», totales): sin fecha y sin importe, fuera sin ruido
      if (!f.some(x => /\d/.test(x))) return;
      if (/total|balance|saldo|closing|opening/i.test(f.join(' ')) && !bancosFecha(f[0], fmt)) return;
      errores.push({ linea, motivo: 'fecha que no se entiende: «' + celda('fecha') + '»' }); return;
    }
    let importe;
    if (p.importe != null) importe = bancosImporte(celda('importe'));
    else {
      const c = bancosImporte(celda('cargo')), a = bancosImporte(celda('abono'));
      if (c == null && a == null) importe = null;
      else importe = Math.round(((a || 0) - Math.abs(c || 0)) * 100) / 100;
    }
    if (importe == null){ errores.push({ linea, motivo: 'importe vacío o ilegible' }); return; }
    if (importe === 0) return;                                    // líneas informativas del banco
    const moneda = (p.moneda != null ? celda('moneda').toUpperCase() : '') || p.monedaFija || monedaCuenta || 'EUR';
    if (!/^[A-Z]{3}$/.test(moneda)){ errores.push({ linea, motivo: 'moneda «' + moneda + '»' }); return; }
    const saldo = p.saldo != null ? bancosImporte(celda('saldo')) : null;
    const concepto = celda('concepto'), referencia = celda('referencia');
    const base = [cuenta, fecha, importe.toFixed(2), moneda, concepto.toUpperCase().replace(/\s+/g, ' ').trim(), referencia.toUpperCase().replace(/\s+/g, '')].join('|');
    vistos[base] = (vistos[base] || 0) + 1;
    movs.push({ cuenta_clave: cuenta, fecha, fecha_valor: bancosFecha(celda('fechaValor'), fmt), concepto: concepto || null, referencia: referencia || null,
      importe, moneda, saldo, huella: bancosHash(base + '|' + vistos[base]), linea });
  });
  return { movimientos: movs, errores, formatoFecha: fmt };
}

/* ── Sugerencias de conciliación ───────────────────────────────────────────
   Para un movimiento, los documentos que lo explican con más probabilidad:
   mismo SIGNO (entrada ↔ recibí; salida ↔ gasto, PPh o comisión), misma moneda,
   mismo importe (± tolerancia) y fecha a ±ventana días. Puntúa más la fecha
   cercana y que el número del documento aparezca en el concepto o la referencia.
   `candidatos`: [{ tipo, id, importe (positivo), moneda, fecha, numero, texto }],
   ya sin los que estén conciliados del todo. Devuelve los `max` mejores. */
/* Tolerancia SOLO para sugerir (Administración, #67): una transferencia SWIFT
   llega recortada por la comisión del banco (50.000 € → 49.985 €). Se sugiere
   hasta el 0,1 % del importe con un mínimo de 1 y un máximo de 50 unidades; la
   diferencia NUNCA cierra sola: se concilia con su línea de comisión bancaria. */
function bancosTolerancia(abs){ return Math.max(1, Math.min(50, Math.abs(abs) * 0.001)); }
function bancosSugerencias(mov, candidatos, opts){
  const o = Object.assign({ tolerancia: null, ventana: 15, max: 5 }, opts || {});
  const entra = mov.importe > 0, abs = Math.abs(mov.importe);
  const tol = o.tolerancia == null ? bancosTolerancia(abs) : o.tolerancia;
  const dia = s => Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10)) / 86400000;
  const texto = ((mov.concepto || '') + ' ' + (mov.referencia || '')).toLowerCase();
  return (candidatos || [])
    // un traspaso entre cuentas propias casa en los dos sentidos (el candidato ya es de signo contrario)
    .filter(c => (c.tipo === 'traspaso' || (entra ? c.tipo === 'recibi' : c.tipo !== 'recibi')) && c.moneda === mov.moneda && c.fecha
              && Math.abs(Math.abs(c.pendiente != null ? c.pendiente : c.importe) - abs) <= tol && Math.abs(dia(c.fecha) - dia(mov.fecha)) <= o.ventana)
    .map(c => {
      const dias = Math.abs(dia(c.fecha) - dia(mov.fecha));
      const nombra = !!(c.numero && texto.indexOf(String(c.numero).toLowerCase()) !== -1);
      const objetivo = Math.abs(c.pendiente != null ? c.pendiente : c.importe);
      const diferencia = Math.round((abs - objetivo) * 100) / 100;      // + = llegó MENOS de lo esperado… o más
      return Object.assign({}, c, { dias, nombra, diferencia, puntos: (nombra ? 100 : 0) + (o.ventana - dias) + (diferencia === 0 ? 5 : 0) });
    })
    .sort((a, b) => b.puntos - a.puntos)
    .slice(0, o.max);
}

/* Celda segura para exportar a CSV (Seguridad, #67): el concepto lo escribe
   quien transfiere, y una celda que empieza por = + - @ tab o CR se ejecuta
   como fórmula al abrirla en Excel. Se antepone un apóstrofo. */
function bancosCeldaSegura(v){
  const s = v == null ? '' : String(v);
  return /^[=+\-@\t\r]/.test(s) ? "'" + s : s;
}

/* Saldo por cuenta: el ÚLTIMO saldo que da el propio banco (fecha más reciente;
   a igualdad, la última línea leída). Si el banco no da saldo, `null`: no se
   inventa sumando movimientos, porque falta el saldo de partida. */
function bancosSaldos(movimientos){
  const porCuenta = {};
  for (const m of movimientos || []){
    if (m.saldo == null) continue;
    const k = m.cuenta_clave + '|' + m.moneda, a = porCuenta[k];
    if (!a || m.fecha > a.fecha || (m.fecha === a.fecha && (m.orden || 0) >= (a.orden || 0)))
      porCuenta[k] = { cuenta_clave: m.cuenta_clave, moneda: m.moneda, saldo: m.saldo, fecha: m.fecha, orden: m.orden || 0 };
  }
  return Object.values(porCuenta);
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { bancosSeparador, bancosCSV, bancosFecha, bancosFormatoFecha, bancosImporte, bancosProponerPerfil, bancosHash, bancosLeer, bancosTolerancia, bancosSugerencias, bancosCeldaSegura, bancosSaldos };
