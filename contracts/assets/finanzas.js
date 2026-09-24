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
   Entrada: [{ total, moneda, fecha:'YYYY-MM-DD', anulada, sociedad, destino }].

   DESTINO (24-sep-2026, LAW-305): a qué cuenta fue el dinero. `propia` (de la
   sociedad), `tercero` (contratista, vendedor de suelo), `escrow` (notario) o
   `sin_clasificar` (cuenta sin marcar o recibí sin cuenta; también si no viene
   el dato). «Cobrado» es TODO lo que pagó el comprador; «caja» es solo lo que
   entró en la sociedad: propia + sin clasificar. Lo sin clasificar va dentro
   de la caja y se DICE, porque sacarlo daría una caja casi vacía hasta que se
   marquen las cuentas, y eso tampoco sería verdad.
   «Año anterior» compara el MISMO tramo del año (1-ene → mismo día): comparar
   nueve meses contra doce da siempre una caída falsa. */
const FIN_DESTINOS = ['propia', 'tercero', 'escrow', 'sin_clasificar'];
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
    const m = _porMoneda(porMoneda, r.moneda || 'EUR', () => ({ mes:0, mesAnterior:0, anio:0, anioAnteriorMismoTramo:0, n:0, porMes:{}, porSociedadAnio:{}, porProyecto:{},
      porMesCaja:{}, porMesTerceros:{}, porProyectoCaja:{}, anioCaja:0, porDestinoAnio:{ propia:0, tercero:0, escrow:0, sin_clasificar:0 } }));
    const destino = FIN_DESTINOS.includes(r.destino) ? r.destino : 'sin_clasificar';
    const esCaja = destino === 'propia' || destino === 'sin_clasificar';
    const mes = r.fecha.slice(0, 7), anio = Number(r.fecha.slice(0, 4));
    m.n++;
    m.porMes[mes] = FIN_R((m.porMes[mes] || 0) + imp);
    const pr = (r.proyecto_nombre || '').trim();
    if (pr) m.porProyecto[pr] = FIN_R((m.porProyecto[pr] || 0) + imp);
    if (esCaja){
      m.porMesCaja[mes] = FIN_R((m.porMesCaja[mes] || 0) + imp);
      if (pr) m.porProyectoCaja[pr] = FIN_R((m.porProyectoCaja[pr] || 0) + imp);
    } else m.porMesTerceros[mes] = FIN_R((m.porMesTerceros[mes] || 0) + imp);
    if (mes === mesHoy) m.mes += imp;
    if (mes === mesAnt) m.mesAnterior += imp;
    if (anio === y && r.fecha <= hoyISO){
      m.anio += imp;
      m.porDestinoAnio[destino] = FIN_R(m.porDestinoAnio[destino] + imp);
      if (esCaja) m.anioCaja += imp;
      const s = r.sociedad || '';
      m.porSociedadAnio[s] = FIN_R((m.porSociedadAnio[s] || 0) + imp);
    }
    if (anio === y - 1 && r.fecha.slice(5) <= diaDelAnio) m.anioAnteriorMismoTramo += imp;
  }
  for (const m of Object.values(porMoneda)){
    m.mes = FIN_R(m.mes); m.mesAnterior = FIN_R(m.mesAnterior);
    m.anio = FIN_R(m.anio); m.anioAnteriorMismoTramo = FIN_R(m.anioAnteriorMismoTramo); m.anioCaja = FIN_R(m.anioCaja);
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

/* ── GASTOS: el dinero que SALE (módulo `gastos`, 24-sep-2026) ─────────────
   Revisión previa #64 (Administración), cada regla con su porqué:
   · Lo que se paga AL PROVEEDOR es total − PPh retenido; la retención se paga
     aparte a la DJP cuando se ingresa (`pph_ingresado_el`). Por eso la caja
     sale en DOS momentos, y lo pendiente también son dos cosas.
   · Anulado no cuenta en nada.
   · El suelo es INVERSIÓN (existencias), no gasto de explotación: sale de caja
     igual, pero se agrupa aparte (`grupo === 'suelo'`) para no leerlo como coste.
   · La base (sin impuesto) va aparte del total: el PPN soportado se compensa y
     no es coste; en caja sí sale.
   Entrada: [{ estado, moneda, total, base, pph_retenido, pph_ingresado_el,
               fecha, vence_el, pagado_el, proyecto_nombre, grupo }]. */
// Una moneda sin gastos pero CON el módulo visible: ceros de verdad, no null.
function finGastosVacio(){
  return { pendientePagar: 0, nPendientes: 0, vencidoPagar: 0, nVencidos: 0, pphPorIngresar: 0,
           pagadoMes: 0, pagadoAnio: 0, pagadoPorMes: {}, aPagarPorMes: {},
           porProyecto: {}, baseAnioPorGrupo: {}, n: 0 };
}
function finGastos(gastos, hoyISO){
  const mesHoy = hoyISO.slice(0, 7), anio = hoyISO.slice(0, 4);
  const porMoneda = {};
  const de = m => _porMoneda(porMoneda, m || 'EUR', finGastosVacio);
  const suma = (obj, k, v) => { obj[k] = FIN_R((obj[k] || 0) + v); };
  for (const g of gastos || []){
    if (!g || g.estado === 'anulado') continue;
    const total = finImporte(g.total), pph = finImporte(g.pph_retenido) || 0, base = finImporte(g.base);
    if (total == null) continue;
    const m = de(g.moneda); m.n++;
    const alProveedor = FIN_R(total - pph);
    const proy = (g.proyecto_nombre || '').trim() || 'General (sin proyecto)';
    const pp = m.porProyecto[proy] || (m.porProyecto[proy] = { pagado: 0, pendiente: 0, base: 0 });
    if (base != null) pp.base = FIN_R(pp.base + base);
    if (base != null && finEsISO(g.fecha) && g.fecha.slice(0, 4) === anio) suma(m.baseAnioPorGrupo, g.grupo || 'general', base);
    if (g.estado === 'pagado' && finEsISO(g.pagado_el)){
      const mes = g.pagado_el.slice(0, 7);
      suma(m.pagadoPorMes, mes, alProveedor);
      if (mes === mesHoy) m.pagadoMes += alProveedor;
      if (g.pagado_el.slice(0, 4) === anio) m.pagadoAnio += alProveedor;
      pp.pagado = FIN_R(pp.pagado + alProveedor);
    } else if (g.estado === 'pendiente'){
      m.pendientePagar += alProveedor; m.nPendientes++;
      pp.pendiente = FIN_R(pp.pendiente + alProveedor);
      const cuando = finEsISO(g.vence_el) ? g.vence_el.slice(0, 10) : null;
      if (cuando && cuando < hoyISO){ m.vencidoPagar += alProveedor; m.nVencidos++; }
      // lo que vence este mes o después va al gráfico como «a pagar»; lo ya
      // vencido no (está en su cifra), igual que en los cobros
      if (cuando && cuando >= hoyISO) suma(m.aPagarPorMes, cuando.slice(0, 7), alProveedor);
    }
    // La retención: pendiente hasta que se ingresa; al ingresarse es caja de ese mes
    if (pph > 0){
      if (finEsISO(g.pph_ingresado_el)){
        const mes = g.pph_ingresado_el.slice(0, 7);
        suma(m.pagadoPorMes, mes, pph);
        if (mes === mesHoy) m.pagadoMes += pph;
        if (g.pph_ingresado_el.slice(0, 4) === anio) m.pagadoAnio += pph;
        pp.pagado = FIN_R(pp.pagado + pph);
      } else {
        m.pphPorIngresar += pph;
        pp.pendiente = FIN_R(pp.pendiente + pph);
      }
    }
  }
  for (const m of Object.values(porMoneda)){
    ['pendientePagar', 'vencidoPagar', 'pphPorIngresar', 'pagadoMes', 'pagadoAnio'].forEach(k => { m[k] = FIN_R(m[k]); });
  }
  return porMoneda;
}

/* ── COMISIONES YA PAGADAS: también es caja que sale ───────────────────────
   Se leen de `comisiones_devengadas` y NUNCA se apuntan en `gastos` (#64):
   pagadas (`pagado_en`), no anuladas, por el importe ajustado si lo hay. No
   llevan sociedad ni proyecto: el proyecto sale de su contrato raíz; sin él,
   van a su propia fila, nunca repartidas a ojo.
   Entrada: comisiones [{ pagado_en, anulado_en, importe, importe_ajustado,
   moneda, contrato_raiz_id }], proyectoDe {contrato_id: nombre}. */
function finComisionesPagadas(comisiones, proyectoDe, hoyISO){
  const mesHoy = hoyISO.slice(0, 7), anio = hoyISO.slice(0, 4);
  const porMoneda = {};
  for (const c of comisiones || []){
    if (!c || !c.pagado_en || c.anulado_en) continue;
    const imp = finImporte(c.importe_ajustado != null ? c.importe_ajustado : c.importe);
    if (imp == null) continue;
    const m = _porMoneda(porMoneda, c.moneda || 'EUR', () => ({ porMes: {}, porProyecto: {}, mes: 0, anio: 0 }));
    const f = String(c.pagado_en).slice(0, 10), mes = f.slice(0, 7);
    m.porMes[mes] = FIN_R((m.porMes[mes] || 0) + imp);
    if (mes === mesHoy) m.mes = FIN_R(m.mes + imp);
    if (f.slice(0, 4) === anio) m.anio = FIN_R(m.anio + imp);
    const proy = (proyectoDe && proyectoDe[c.contrato_raiz_id]) || 'Comisiones sin proyecto';
    m.porProyecto[proy] = FIN_R((m.porProyecto[proy] || 0) + imp);
  }
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
  /* `incluirSinFirmar`: el MISMO interruptor que Vencimientos (apagado por
     defecto). Existe por el alta de histórico: mientras dure, «sin firmar»
     significa a menudo «aún no marcado», y el owner puede querer verlo. */
  const modelo = modeloFinanciero({ hoyISO: hoy, contratos: vivos, cobradoPorId: e.cobradoPorId || {}, vencimientos: e.vencimientos || [], incluirSinFirmar: !!e.incluirSinFirmar });
  const mesHoy = hoy.slice(0, 7);
  const porMoneda = {};
  for (const [mon, m] of Object.entries(modelo)){
    let futuro = 0, d30 = 0, d90 = 0, sinImporte = 0, nVencido = 0;
    const previstoPorMes = {};
    /* Lo vencido de CADA comprador dentro de su proyecto, para «quién debe».
       El modelo ya da lo pendiente por persona; lo vencido sale de las filas
       de la cascada con las mismas claves que usa él (proyecto y nombre tal
       como vienen en el contrato), para que casen sin segunda regla. */
    const vencidoPorPersona = {};
    for (const f of m.filas){
      if (f.importe == null){ sinImporte++; continue; }
      if (f.estado === 'vencido'){
        nVencido++;
        const proy = (f.contrato && f.contrato.proyecto_nombre) || 'Sin proyecto';
        const quien = ((f.contrato && f.contrato.comprador_nombre) || '').trim() || 'Sin comprador';
        const vp = vencidoPorPersona[proy] || (vencidoPorPersona[proy] = {});
        vp[quien] = FIN_R((vp[quien] || 0) + (f.pendiente || 0));
      }
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
      vencidoPorPersona,
      fuera: m.fuera,                  // sin firmar y Cartas, con su importe
      avisos: m.avisos,
      liberadas: liberadas[mon] || { n:0, precio:0 },
    };
  }
  // una moneda que solo tiene liberadas también se dice
  for (const [mon, l] of Object.entries(liberadas)) if (!porMoneda[mon]) porMoneda[mon] = { moneda: mon, cartera:0, cobrado:0, pendiente:0, desglose:null, previstoPorMes:{}, mesHoy, trimestres:[], porProyecto:{}, fuera:null, avisos:[], liberadas:l };
  return porMoneda;
}

/* ── QUIÉN DEBE, dentro de un proyecto ─────────────────────────────────────
   Owner (26-ago, en Vencimientos): «que le salgan las personas ahí con lo que
   deben». Solo quien debe algo, ordenado por lo VENCIDO primero (es a quien
   hay que llamar) y luego por lo pendiente. Un mismo comprador con dos
   contratos en el proyecto sale una vez, sumado (así lo agrupa el modelo). */
function finPersonas(c, vencidos){
  if (!c || !c.personas) return [];
  return Object.entries(c.personas)
    .map(([nombre, x]) => ({ nombre, precio: FIN_R(x.precio), cobrado: FIN_R(x.cobrado), pendiente: FIN_R(x.pendiente),
                            vencido: FIN_R(vencidos[nombre] || 0), firmados: x.firmados, sinFirmar: x.sinFirmar }))
    .filter(x => x.pendiente > 0)
    .sort((a, b) => (b.vencido - a.vencido) || (b.pendiente - a.pendiente) || a.nombre.localeCompare(b.nombre));
}

/* ── POR PROYECTO ──────────────────────────────────────────────────────────
   La cartera por proyecto (de modeloFinanciero, por contrato) junto al stock
   disponible (de unidades). Se siembra de LOS DOS: un proyecto sin ventas
   firmadas pero con stock tiene que salir — es justo el que falta por vender
   («una vista derivada solo enseña lo que hay en aquello de lo que deriva»,
   suite_lawang.md, Regla 0 bis). */
function finPorProyecto(carteraM, stockM, gastosM, comM, cobrosM){
  const nombres = new Set([
    ...Object.keys((carteraM && carteraM.porProyecto) || {}),
    ...Object.keys((stockM && stockM.porProyecto) || {}),
    ...Object.keys((gastosM && gastosM.porProyecto) || {}),
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
      personas: finPersonas(c, (carteraM && carteraM.vencidoPorPersona && carteraM.vencidoPorPersona[p]) || {}),
      /* Gastos y caja neta (módulo `gastos`). `null` = no se sabe (sin permiso o
         sin el módulo), que no es lo mismo que 0. La caja neta es lo que ha
         ENTRADO por recibís de ese proyecto (todo el histórico, firmado o no)
         menos lo PAGADO: gastos + comisiones. No es margen: los costes
         registrados pueden estar incompletos. */
      gastosBase: gastosM ? ((gastosM.porProyecto[p] && gastosM.porProyecto[p].base) || 0) : null,
      cajaNeta: (gastosM && cobrosM)
        ? FIN_R(((cobrosM.porProyectoCaja || cobrosM.porProyecto || {})[p] || 0) - ((gastosM.porProyecto[p] && gastosM.porProyecto[p].pagado) || 0) - ((comM && comM.porProyecto[p]) || 0))
        : null,
    });
  }
  return filas.sort((a, b) => (b.cartera - a.cartera) || (b.stockValor - a.stockValor) || a.proyecto.localeCompare(b.proyecto));
}

/* ── UNA SOCIEDAD SOLA ─────────────────────────────────────────────────────
   Cada sociedad es una empresa con su propia caja. El recorte se hace sobre
   la ENTRADA y no sobre el modelo, igual que Vencimientos: los contratos con
   `filtraEmpresa()` de logica.js (la Carta hereda la sociedad de su Bloqueo;
   regla escrita allí una vez), y recibís y facturas por su propia columna
   `sociedad` con el mismo resolver (`lwSociedadContrato`). Así la suma de las
   sociedades ES «Todas» por construcción.
   Lo que no es de ninguna sociedad no se reparte a ojo: el stock (una unidad
   no tiene sociedad hasta que se vende) y las comisiones salen como
   `null` + `noSeReparte`, y quien pinta lo dice. Los contratos necesitan el
   campo `soc` (sociedad firmante del documento). */
function finFiltraEmpresa(e, empresa){
  if (!empresa || empresa === 'todas') return e;
  const deEmpresa = x => lwSociedadContrato(x.sociedad, x.tipo) === empresa;
  return {
    ...e,
    contratos: filtraEmpresa({ contratos: e.contratos || [] }, empresa).contratos,
    recibis: (e.recibis || []).filter(deEmpresa),
    facturas: (e.facturas || []).filter(deEmpresa),
    gastos: e.gastos == null ? null : e.gastos.filter(g => g.sociedad === empresa),
    unidades: null,
    solicitudes: null,
    comisiones: null,
    noSeReparte: true,
  };
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
  const stock = e.unidades == null ? {} : finStock(e.unidades);
  const cartera = finCartera(e);
  const salidas = (e.solicitudes == null && e.comisiones == null) ? null : finSalidas(e.solicitudes, e.comisiones);
  // null = sin permiso / sin el módulo: se dice, nunca se pinta 0
  const gastos = e.gastos == null ? null : finGastos(e.gastos, hoy);
  const proyectoDe = {}; (e.contratos || []).forEach(c => { proyectoDe[c.id] = c.proyecto_nombre; });
  const comPagadas = e.comisiones == null ? null : finComisionesPagadas(e.comisiones, proyectoDe, hoy);
  const monedas = new Set([...Object.keys(cobros), ...Object.keys(facturado), ...Object.keys(stock), ...Object.keys(cartera), ...Object.keys(salidas || {}), ...Object.keys(gastos || {})]);
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
      gastos: gastos ? (gastos[m] || finGastosVacio()) : null,
      comPagadas: comPagadas ? (comPagadas[m] || { porMes: {}, porProyecto: {}, mes: 0, anio: 0 }) : null,
      porProyecto: finPorProyecto(car, sto, gastos ? (gastos[m] || { porProyecto: {} }) : null,
                                  comPagadas ? (comPagadas[m] || null) : null, cobros[m] || { porProyecto: {} }),
    };
  }
  /* Orden de monedas: la de más cartera primero (mezcla monedas SOLO para
     ordenar, nunca para enseñar una cifra). */
  const peso = m => ((cartera[m] && cartera[m].cartera) || 0) + ((cobros[m] && cobros[m].anio) || 0);
  const orden = [...monedas].sort((a, b) => (a === 'EUR' ? -1 : b === 'EUR' ? 1 : peso(b) - peso(a)));
  return { hoyISO: hoy, monedas: orden, porMoneda, noSeReparte: !!e.noSeReparte, incluirSinFirmar: !!e.incluirSinFirmar, conGastos: gastos != null };
}

/* La serie del gráfico de caja: 12 meses cobrados + el mes en curso partido
   (cobrado y lo que falta de él) + 6 meses previstos. Lo previsto es
   PENDIENTE de hitos firmados con fecha, ya descontado lo cobrado por la
   cascada — no el importe bruto del hito. */
function finSerieCaja(pm, hoyISO, atras, adelante){
  const meses = finMeses(hoyISO, -(atras || 12), adelante == null ? 6 : adelante);
  const mesHoy = hoyISO.slice(0, 7);
  // Lo que entró en la SOCIEDAD (propias + sin clasificar); lo pagado a terceros va aparte
  const cob = (pm && pm.cobros && (pm.cobros.porMesCaja || pm.cobros.porMes)) || {};
  const ter = (pm && pm.cobros && pm.cobros.porMesTerceros) || {};
  const prev = (pm && pm.cartera && pm.cartera.previstoPorMes) || {};
  /* Salidas (módulo `gastos`): lo pagado a proveedores y a la DJP, más las
     comisiones pagadas; y lo que vence por pagar. `null` si no hay datos de
     salidas (sin permiso): el gráfico entonces enseña solo entradas y lo dice. */
  const g = pm && pm.gastos, cp = pm && pm.comPagadas;
  const conSalidas = !!g;
  const pag = mes => FIN_R(((g && g.pagadoPorMes[mes]) || 0) + ((cp && cp.porMes[mes]) || 0));
  return meses.map(mes => {
    const cobrado = mes <= mesHoy ? FIN_R(cob[mes] || 0) : null;
    const pagado = conSalidas && mes <= mesHoy ? pag(mes) : null;
    return {
      mes, cobrado,
      aTerceros: mes <= mesHoy ? FIN_R(ter[mes] || 0) : null,
      previsto: mes >= mesHoy ? FIN_R(prev[mes] || 0) : null,
      pagado,
      aPagar: conSalidas && mes >= mesHoy ? FIN_R((g.aPagarPorMes[mes]) || 0) : null,
      neto: cobrado != null && pagado != null ? FIN_R(cobrado - pagado) : null,
      esHoy: mes === mesHoy,
    };
  });
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { finMeses, finCobros, finFacturadoSinCobrar, finStock, finSalidas, finGastos, finComisionesPagadas, finCartera, finPersonas, finPorProyecto, finFiltraEmpresa, finModelo, finSerieCaja };
