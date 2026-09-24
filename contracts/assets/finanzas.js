/* ═══════════════════════════════════════════════════════════════════════════
   FINANZAS — el cálculo del dashboard financiero (24-sep-2026)
   ═══════════════════════════════════════════════════════════════════════════
   Primer módulo escrito ya con la forma del AxisWorks ERP
   (encargos/20260924_estudio_erp_modular.md): aquí NO hay DOM, ni red, ni
   nada de Lawang. Entran filas normalizadas y sale un modelo, por moneda.
   Quien pinta es `intranet/v4/assets/panel-finanzas.js`; quien trae los datos
   es su `cargar()`. Así el día del registro de módulos (F2) el módulo
   «finanzas» es este fichero + esa pantalla, y se prueba en node sin sesión.

   NO INVENTA ARITMÉTICA DEL DINERO. Lo que ya está pagado por aprender se
   importa, no se copia (Regla 0 de contexto/suite_lawang.md):
   · Cartera, cobrado por contrato, cascada de hitos, vencido, trimestres y
     antigüedad de hitos → `modeloFinanciero()` y compañía, de
     `intranet/vencimientos/logica.js`. Es el mismo modelo que enseña
     Vencimientos: si las dos pantallas dijeran cifras distintas de la misma
     cartera, ninguna sería de fiar.
   · Leer un importe tecleado → `lwParseImporte` (dinero.js); uno que ya es
     número, tal cual (`finImporte`, abajo). Carta de Reserva que no
     suma precio → `lwEsPreliminar` (vocabulario.js), vía logica.js.

   REGLAS que este fichero sí pone, cada una con su porqué:
   · NUNCA se suman monedas. Todo sale en `porMoneda[m]`; quien pinta elige.
   · Un importe desconocido es null, no 0 (misma regla que lwParseImporte).
   · Los bloques «pendiente de cobro», «facturado sin cobrar» y «previsión»
     son VISTAS DE LA MISMA CARTERA, no importes que se suman (revisión previa
     #62, Administración). Por eso `desglose` reparte el pendiente en tramos
     que SÍ suman, y dice si cuadra; lo facturado se enseña como «de ello».
   · Lo que no se cuenta, se cuenta: contratos liberados, sin firmar, hitos
     sin fecha o sin importe salen con su cifra, no desaparecen.
   ═══════════════════════════════════════════════════════════════════════════ */

/* Puente a logica.js: en el navegador son globales (se carga antes), en node
   el test las pone en `global`. Defensivo a propósito: un fichero de cálculo
   que revienta al importarse tumba el guardrail que lo prueba. */
function _finLogica(){
  if (typeof modeloFinanciero !== 'function') throw new Error('finanzas.js necesita intranet/vencimientos/logica.js cargado antes');
  return { modeloFinanciero, porTrimestre, diasEntre };
}

const FIN_R = n => Math.round((Number(n) || 0) * 100) / 100;
/* Un importe que viene de la BASE ya es un número: se usa tal cual.
   lwParseImporte es para lo que teclea una persona, y lee «8176.625» como
   8.176.625 (tres cifras tras el punto = separador de miles). Cazado en el
   arnés del 24-sep: una comisión de 8.176,625 € salía como 8,2 millones.
   Solo un texto pasa por lwParseImporte. */
const finImporte = v => (typeof v === 'number') ? (isFinite(v) ? v : null) : lwParseImporte(v);
const finEsISO = s => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}/.test(s);

/* Los `n` meses que acaban en el de `hoyISO` (incluido), del más viejo al
   más nuevo. SIEMPRE los n aunque estén a cero: un mes que falta en un
   gráfico de caja se lee como «no hubo nada», distinto de «0 ese mes». */
function finMeses(hoyISO, desde, hasta){
  const [y, m] = hoyISO.split('-').map(Number);
  const out = [];
  for (let i = desde; i <= hasta; i++){
    const d = new Date(Date.UTC(y, m - 1 + i, 1));
    out.push(d.getUTCFullYear() + '-' + String(d.getUTCMonth() + 1).padStart(2, '0'));
  }
  return out;
}

function _porMoneda(obj, m, nuevo){ return obj[m] || (obj[m] = nuevo()); }

/* ── COBRADO: el dinero que ha entrado ─────────────────────────────────────
   Solo el recibí prueba dinero recibido (reforma del 11-ago: la factura es lo
   que se DEBE). Se cuenta por la fecha del recibí, que es la fecha de caja.
   Entrada: [{ total, moneda, fecha:'YYYY-MM-DD', anulada, sociedad }].
   «Año anterior» compara el MISMO tramo del año (1-ene → mismo día): comparar
   nueve meses contra doce da siempre una caída falsa. */
function finCobros(recibis, hoyISO){
  const mesHoy = hoyISO.slice(0, 7);
  const [y] = hoyISO.split('-').map(Number);
  const mesAnt = finMeses(hoyISO, -1, -1)[0];
  const diaDelAnio = hoyISO.slice(5);
  const porMoneda = {};
  for (const r of recibis || []){
    if (r.anulada || !finEsISO(r.fecha)) continue;
    const imp = finImporte(r.total);
    if (imp == null) continue;
    const m = _porMoneda(porMoneda, r.moneda || 'EUR', () => ({ mes:0, mesAnterior:0, anio:0, anioAnteriorMismoTramo:0, n:0, porMes:{}, porSociedadAnio:{} }));
    const mes = r.fecha.slice(0, 7), anio = Number(r.fecha.slice(0, 4));
    m.n++;
    m.porMes[mes] = FIN_R((m.porMes[mes] || 0) + imp);
    if (mes === mesHoy) m.mes += imp;
    if (mes === mesAnt) m.mesAnterior += imp;
    if (anio === y && r.fecha <= hoyISO){
      m.anio += imp;
      const s = r.sociedad || '';
      m.porSociedadAnio[s] = FIN_R((m.porSociedadAnio[s] || 0) + imp);
    }
    if (anio === y - 1 && r.fecha.slice(5) <= diaDelAnio) m.anioAnteriorMismoTramo += imp;
  }
  for (const m of Object.values(porMoneda)){
    m.mes = FIN_R(m.mes); m.mesAnterior = FIN_R(m.mesAnterior);
    m.anio = FIN_R(m.anio); m.anioAnteriorMismoTramo = FIN_R(m.anioAnteriorMismoTramo);
  }
  return porMoneda;
}

/* ── FACTURADO SIN COBRAR ──────────────────────────────────────────────────
   Solo `tipo = 'factura'`: la proforma no es exigible y el recibí es cobro.
   El pendiente de cada factura viene YA calculado de
   facturas_pendiente_equipo() — no se resta aquí a mano (una segunda resta es
   una segunda verdad). La antigüedad se mide desde el vencimiento de la
   factura y, si no lo tiene, desde su emisión — y se CUENTA cuántas van por
   cada criterio, porque el 24-sep eran 22 de 137 con vencimiento propio y un
   reparto por tramos que no lo dijera parecería más exacto de lo que es
   (revisión previa #62, Datos).
   Y se separa lo facturado sobre contratos SIN FIRMAR (`contrato_firmado`
   false): el 24-sep era la mayor parte, por el alta de histórico, y sin
   decirlo «facturado sin cobrar» salía mayor que «firmado por cobrar», que
   se leía como una contradicción del panel.
   Entrada: [{ tipo, moneda, anulada, pendiente, venc, fecha_emision, contrato_firmado }]. */
function finFacturadoSinCobrar(facturas, hoyISO){
  const { diasEntre } = _finLogica();
  const porMoneda = {};
  const tramosVacios = () => [
    { clave:'al_dia', etiqueta:'Al día',      desde:-Infinity, hasta:0,        importe:0, n:0 },
    { clave:'d30',    etiqueta:'1–30 días',   desde:1,         hasta:30,       importe:0, n:0 },
    { clave:'d60',    etiqueta:'31–60 días',  desde:31,        hasta:60,       importe:0, n:0 },
    { clave:'d90',    etiqueta:'61–90 días',  desde:61,        hasta:90,       importe:0, n:0 },
    { clave:'d90m',   etiqueta:'Más de 90',   desde:91,        hasta:Infinity, importe:0, n:0 },
  ];
  for (const f of facturas || []){
    if (f.tipo !== 'factura' || f.anulada) continue;
    const pend = finImporte(f.pendiente);
    if (!(pend > 0)) continue;
    const m = _porMoneda(porMoneda, f.moneda || 'EUR', () => ({ total:0, n:0, porVencimiento:0, porEmision:0, sinFecha:0, deSinFirmar:0, nSinFirmar:0, tramos:tramosVacios() }));
    m.total += pend; m.n++;
    if (f.contrato_firmado === false){ m.deSinFirmar += pend; m.nSinFirmar++; }
    let ref = null;
    if (finEsISO(f.venc)){ ref = f.venc.slice(0, 10); m.porVencimiento++; }
    else if (finEsISO(f.fecha_emision)){ ref = f.fecha_emision.slice(0, 10); m.porEmision++; }
    if (!ref){ m.sinFecha++; continue; }
    const dias = diasEntre(ref, hoyISO);
    const t = m.tramos.find(x => dias >= x.desde && dias <= x.hasta);
    t.importe = FIN_R(t.importe + pend); t.n++;
  }
  for (const m of Object.values(porMoneda)){ m.total = FIN_R(m.total); m.deSinFirmar = FIN_R(m.deSinFirmar); }
  return porMoneda;
}

/* ── STOCK: lo que queda por vender ────────────────────────────────────────
   Valor a precio de lista de `unidades`, por estado. No es dinero que vaya a
   entrar: es el techo de lo que falta por vender, y se enseña aparte de la
   cartera para que nadie lo sume con ella.
   Entrada: [{ proyecto, estado, precio, moneda }]. */
function finStock(unidades){
  const porMoneda = {};
  for (const u of unidades || []){
    const m = _porMoneda(porMoneda, u.moneda || 'EUR', () => ({ estados:{}, porProyecto:{}, sinPrecio:0 }));
    const est = u.estado || 'sin_estado';
    const e = m.estados[est] || (m.estados[est] = { n:0, valor:0 });
    const precio = finImporte(u.precio);
    e.n++;
    if (precio == null) m.sinPrecio++; else e.valor = FIN_R(e.valor + precio);
    if (est === 'disponible'){
      const p = (u.proyecto || '').trim() || 'Sin proyecto';
      const pp = m.porProyecto[p] || (m.porProyecto[p] = { n:0, valor:0 });
      pp.n++; if (precio != null) pp.valor = FIN_R(pp.valor + precio);
    }
  }
  return porMoneda;
}

/* ── SALIDAS COMPROMETIDAS ─────────────────────────────────────────────────
   Lo que la empresa ya debe pagar: solicitudes de pago vivas y comisiones
   devengadas. Una comisión que ya tiene su solicitud (`solicitud_id`) NO se
   suma otra vez: es la misma deuda, contada ya en la solicitud (revisión
   previa #62: el 24-sep las 4 solicitudes pendientes eran exactamente 4
   comisiones con solicitud — sin este corte, 51.992 € salían dos veces).
   Entrada: solicitudes [{ estado, importe, moneda }],
            comisiones  [{ estado, importe, importe_ajustado, moneda, solicitud_id }]. */
const FIN_VIVAS = ['pendiente', 'aprobada'];
function finSalidas(solicitudes, comisiones){
  const porMoneda = {};
  const de = m => _porMoneda(porMoneda, m || 'EUR', () => ({ solicitudes:{ n:0, importe:0 }, comisiones:{ n:0, importe:0 }, total:0 }));
  for (const s of solicitudes || []){
    if (!FIN_VIVAS.includes(s.estado)) continue;
    const imp = finImporte(s.importe); if (imp == null) continue;
    const m = de(s.moneda); m.solicitudes.n++; m.solicitudes.importe = FIN_R(m.solicitudes.importe + imp);
  }
  for (const c of comisiones || []){
    if (!FIN_VIVAS.includes(c.estado) || c.solicitud_id) continue;
    const imp = finImporte(c.importe_ajustado != null ? c.importe_ajustado : c.importe); if (imp == null) continue;
    const m = de(c.moneda); m.comisiones.n++; m.comisiones.importe = FIN_R(m.comisiones.importe + imp);
  }
  for (const m of Object.values(porMoneda)) m.total = FIN_R(m.solicitudes.importe + m.comisiones.importe);
  return porMoneda;
}

/* ── CARTERA: lo firmado que falta por cobrar ──────────────────────────────
   `modeloFinanciero()` tal cual (solo contratos firmados, Carta fuera del
   precio, cobrado de la Carta al Bloqueo, cascada por fecha). Lo único que se
   hace ANTES es apartar los contratos LIBERADOS: una venta que se cayó no le
   debe nada a nadie, y el modelo de Vencimientos no lo mira (el 24-sep eran 3
   firmados y 364.510 € que salían como cartera — pendiente anotado aparte
   para Vencimientos, que no se toca desde aquí). Se cuentan, no se esconden.

   Y DESPUÉS se reparte el pendiente en tramos que suman:
     vencido + próximos 30 + 31-90 + más de 90 + sin fecha + resto = pendiente
   «resto» es lo que ningún hito explica: contratos sin calendario o
   calendarios que no llegan al 100 %. Si sale NEGATIVO, los hitos prometen
   más de lo que se debe (p. ej. un hito que no se descontó) y se avisa: el
   desglose no cuadra y la previsión está inflada. */
function finCartera(e){
  const { modeloFinanciero, porTrimestre, diasEntre } = _finLogica();
  const hoy = e.hoyISO;
  const liberadas = {};
  const vivos = [];
  for (const c of e.contratos || []){
    if (c.liberado_en){
      if (c.bloqueado && !lwEsPreliminar(c.tipo)){
        const l = _porMoneda(liberadas, c.moneda || 'EUR', () => ({ n:0, precio:0 }));
        l.n++; l.precio = FIN_R(l.precio + (Number(c.precio_total) || 0));
      }
      continue;
    }
    vivos.push(c);
  }
  const modelo = modeloFinanciero({ hoyISO: hoy, contratos: vivos, cobradoPorId: e.cobradoPorId || {}, vencimientos: e.vencimientos || [] });
  const mesHoy = hoy.slice(0, 7);
  const porMoneda = {};
  for (const [mon, m] of Object.entries(modelo)){
    let futuro = 0, d30 = 0, d90 = 0, sinImporte = 0, nVencido = 0;
    const previstoPorMes = {};
    for (const f of m.filas){
      if (f.importe == null){ sinImporte++; continue; }
      if (f.estado === 'vencido') nVencido++;
      if (!(f.pendiente > 0) || !f.fecha || f.fecha < hoy) continue;
      futuro += f.pendiente;
      const dias = diasEntre(hoy, f.fecha);
      if (dias <= 30) d30 += f.pendiente; else if (dias <= 90) d90 += f.pendiente;
      const mes = f.fecha.slice(0, 7);
      previstoPorMes[mes] = FIN_R((previstoPorMes[mes] || 0) + f.pendiente);
    }
    const pendiente = FIN_R(m.pendiente);
    const explicado = FIN_R(m.vencido + futuro + m.sinFecha);
    const resto = FIN_R(pendiente - explicado);
    porMoneda[mon] = {
      moneda: mon,
      /* `cobrado` del modelo incluye lo cobrado de contratos SIN firmar y de
         Cartas sueltas (es caja real); para «% cobrado de lo firmado» vale
         solo lo cobrado de lo firmado, que es lo que suma porProyecto.
         Sin esta distinción el 24-sep salía «122,9 % cobrado». */
      cartera: FIN_R(m.cartera), cobrado: FIN_R(m.cobrado), pendiente,
      cobradoFirmado: FIN_R(Object.values(m.porProyecto).reduce((a, p) => a + (p.cobrado || 0), 0)),
      desglose: {
        vencido: FIN_R(m.vencido), nVencido, d30: FIN_R(d30), d31a90: FIN_R(d90), mas90: FIN_R(futuro - d30 - d90),
        sinFecha: FIN_R(m.sinFecha), nSinFecha: m.nSinFecha, nSinImporte: sinImporte,
        resto: resto > 0 ? resto : 0,
        cuadra: resto >= -1,          // 1 unidad de holgura: redondeos de pct
        exceso: resto < -1 ? -resto : 0,
      },
      previstoPorMes,
      mesHoy,
      trimestres: porTrimestre(m.filas, hoy, 4),
      porProyecto: m.porProyecto,
      fuera: m.fuera,                  // sin firmar y Cartas, con su importe
      avisos: m.avisos,
      liberadas: liberadas[mon] || { n:0, precio:0 },
    };
  }
  // una moneda que solo tiene liberadas también se dice
  for (const [mon, l] of Object.entries(liberadas)) if (!porMoneda[mon]) porMoneda[mon] = { moneda: mon, cartera:0, cobrado:0, pendiente:0, desglose:null, previstoPorMes:{}, mesHoy, trimestres:[], porProyecto:{}, fuera:null, avisos:[], liberadas:l };
  return porMoneda;
}

/* ── POR PROYECTO ──────────────────────────────────────────────────────────
   La cartera por proyecto (de modeloFinanciero, por contrato) junto al stock
   disponible (de unidades). Se siembra de LOS DOS: un proyecto sin ventas
   firmadas pero con stock tiene que salir — es justo el que falta por vender
   («una vista derivada solo enseña lo que hay en aquello de lo que deriva»,
   suite_lawang.md, Regla 0 bis). */
function finPorProyecto(carteraM, stockM){
  const nombres = new Set([
    ...Object.keys((carteraM && carteraM.porProyecto) || {}),
    ...Object.keys((stockM && stockM.porProyecto) || {}),
  ]);
  const filas = [];
  for (const p of nombres){
    const c = (carteraM && carteraM.porProyecto[p]) || null;
    const s = (stockM && stockM.porProyecto[p]) || null;
    const cartera = c ? FIN_R(c.cartera) : 0, cobrado = c ? FIN_R(c.cobrado) : 0;
    filas.push({
      proyecto: p, cartera, cobrado,
      pendiente: FIN_R(Math.max(0, cartera - cobrado)),
      pctCobrado: cartera > 0 ? Math.round(cobrado / cartera * 1000) / 10 : null,
      vencido: c ? FIN_R(c.vencido) : 0,
      proximos90: c ? FIN_R(c.proximos90) : 0,
      stockN: s ? s.n : 0, stockValor: s ? s.valor : 0,
    });
  }
  return filas.sort((a, b) => (b.cartera - a.cartera) || (b.stockValor - a.stockValor) || a.proyecto.localeCompare(b.proyecto));
}

/* ── EL MODELO ENTERO ──────────────────────────────────────────────────────
   Entrada normalizada (el contrato del módulo — cualquier instancia del ERP
   que traiga estas filas obtiene el mismo dashboard):
     { hoyISO, contratos, cobradoPorId, vencimientos, recibis, facturas,
       unidades, solicitudes|null, comisiones|null }
   `solicitudes`/`comisiones` a null = «sin permiso para verlas»: se devuelve
   `salidas: null` y quien pinta dice «sin permiso», nunca 0 (revisión previa
   #62, Datos: ninguno de los 4 admin tenía la casilla, y la RLS les devolvía
   0 filas sin error). */
function finModelo(e){
  const hoy = e.hoyISO;
  const cobros = finCobros(e.recibis, hoy);
  const facturado = finFacturadoSinCobrar(e.facturas, hoy);
  const stock = finStock(e.unidades);
  const cartera = finCartera(e);
  const salidas = (e.solicitudes == null && e.comisiones == null) ? null : finSalidas(e.solicitudes, e.comisiones);
  const monedas = new Set([...Object.keys(cobros), ...Object.keys(facturado), ...Object.keys(stock), ...Object.keys(cartera), ...Object.keys(salidas || {})]);
  const porMoneda = {};
  for (const m of monedas){
    const car = cartera[m] || null, sto = stock[m] || null;
    porMoneda[m] = {
      moneda: m,
      cobros: cobros[m] || null,
      facturado: facturado[m] || null,
      stock: sto,
      cartera: car,
      salidas: salidas ? (salidas[m] || { solicitudes:{ n:0, importe:0 }, comisiones:{ n:0, importe:0 }, total:0 }) : null,
      porProyecto: finPorProyecto(car, sto),
    };
  }
  /* Orden de monedas: la de más cartera primero (mezcla monedas SOLO para
     ordenar, nunca para enseñar una cifra). */
  const peso = m => ((cartera[m] && cartera[m].cartera) || 0) + ((cobros[m] && cobros[m].anio) || 0);
  const orden = [...monedas].sort((a, b) => (a === 'EUR' ? -1 : b === 'EUR' ? 1 : peso(b) - peso(a)));
  return { hoyISO: hoy, monedas: orden, porMoneda };
}

/* La serie del gráfico de caja: 12 meses cobrados + el mes en curso partido
   (cobrado y lo que falta de él) + 6 meses previstos. Lo previsto es
   PENDIENTE de hitos firmados con fecha, ya descontado lo cobrado por la
   cascada — no el importe bruto del hito. */
function finSerieCaja(pm, hoyISO, atras, adelante){
  const meses = finMeses(hoyISO, -(atras || 12), adelante == null ? 6 : adelante);
  const mesHoy = hoyISO.slice(0, 7);
  const cob = (pm && pm.cobros && pm.cobros.porMes) || {};
  const prev = (pm && pm.cartera && pm.cartera.previstoPorMes) || {};
  return meses.map(mes => ({
    mes,
    cobrado: mes <= mesHoy ? FIN_R(cob[mes] || 0) : null,
    previsto: mes >= mesHoy ? FIN_R(prev[mes] || 0) : null,
    esHoy: mes === mesHoy,
  }));
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { finMeses, finCobros, finFacturadoSinCobrar, finStock, finSalidas, finCartera, finPorProyecto, finModelo, finSerieCaja };
