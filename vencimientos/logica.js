/* Lógica del dashboard de vencimientos — 18-ago-2026.
   Fuera del HTML para poder pasarle un test de verdad (logica.test.js), el mismo
   molde que facturas/totales.js. Aquí no hay DOM ni red: entran filas y sale un
   modelo; todo lo que decide dinero está en este fichero y probado en node.

   LAS REGLAS DE DINERO NO SE INVENTAN AQUÍ — se importan las que la suite ya
   pagó por aprender:
   · Un importe se LEE con lwParseImporte y se ESCRIBE con lwFormatoImporte
     (assets/dinero.js). Nada de parseos propios: ya hubo cuatro y divergían.
   · Una Carta de Reserva no suma precio (lwEsPreliminar, assets/vocabulario.js):
     su importe es el mismo que luego reparten Bloqueo y Construcción, y sumarla
     cuenta la villa dos veces. Lo que SÍ aporta la Carta es su COBRADO, que se
     descuenta al pasar al Bloqueo — por eso cobradoEfectivo() se lo suma al
     contrato del que cuelga.
   · Monedas NUNCA mezcladas en una suma: cada agregado va por moneda, y quien
     pinta elige cuál enseña. 100 M€ no se vigilan sumando rupias con euros. */

/* ── el importe de un vencimiento ──────────────────────────────────────────
   Manda el monto escrito; sin monto, el pct sobre el precio del contrato; sin
   ninguno, null — un vencimiento sin importe conocido NO es un vencimiento de
   0 €, y meterlo como 0 en las sumas es mentir a la baja (la misma regla que
   hizo a lwParseImporte devolver null y no 0). */
function importeVencimiento(v, contrato){
  const monto = lwParseImporte(v.monto);
  if(monto != null && monto !== 0) return monto;
  const pct = lwParseImporte(v.pct);
  const precio = contrato ? Number(contrato.precio_total) || 0 : 0;
  if(pct != null && pct !== 0 && precio) return Math.round(precio * pct / 100 * 100) / 100;
  return null;
}

/* ── el cobrado que de verdad tiene un contrato ────────────────────────────
   cobradoPorId viene de contratos_cobrado_equipo() (solo el recibí prueba
   dinero). A eso se le suma el cobrado de sus hijos PRELIMINARES: la Carta
   cuelga de su Bloqueo (LAW-50) y lo que el cliente pagó con la Carta es
   dinero YA entregado a cuenta de esa misma operación. Los hijos NO
   preliminares (la Construcción cuelga de la Reserva) no se suman: son otro
   contrato con su propio precio y su propio calendario. */
function cobradoEfectivo(contrato, contratos, cobradoPorId){
  let total = Number(cobradoPorId[contrato.id]) || 0;
  for(const c of contratos){
    if(c.contrato_padre_id === contrato.id && lwEsPreliminar(c.tipo))
      total += Number(cobradoPorId[c.id]) || 0;
  }
  return total;
}

/* ── la cascada: qué vencimiento está cubierto por lo ya cobrado ───────────
   El recibí se aplica a facturas, no a hitos, así que el reparto por hito es
   una LECTURA, no un asiento: el dinero cobrado del contrato va cubriendo sus
   vencimientos en orden de fecha (sin fecha, al final, por orden). Es la
   lectura natural de un calendario de pagos — lo primero que vence es lo
   primero que se paga — y está escrita aquí una sola vez para que todas las
   pantallas la cuenten igual.
   Devuelve los vencimientos ANOTADOS: importe, cubierto, pendiente y estado:
     cobrado   → cubierto del todo
     parcial   → cubierto a medias
     vencido   → fecha pasada y pendiente > 0
     pendiente → fecha futura (o sin importe conocido, con importe null)
     sin_fecha → sin fecha puesta: no se puede vigilar, y eso ES el aviso */
function cascada(vencs, contrato, cobrado, hoyISO){
  const orden = vencs.slice().sort((a,b)=>{
    if(a.fecha && b.fecha) return a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : (a.orden - b.orden);
    if(a.fecha) return -1;
    if(b.fecha) return 1;
    return a.orden - b.orden;
  });
  let resto = cobrado;
  return orden.map(v=>{
    const importe = importeVencimiento(v, contrato);
    let cubierto = 0, pendiente = null, estado;
    if(importe != null){
      cubierto = Math.min(resto, importe);
      resto = Math.round((resto - cubierto) * 100) / 100;
      pendiente = Math.round((importe - cubierto) * 100) / 100;
    }
    if(!v.fecha && !(importe != null && pendiente === 0)) estado = 'sin_fecha';
    else if(importe == null) estado = 'pendiente';
    else if(pendiente === 0) estado = 'cobrado';
    else if(v.fecha && v.fecha < hoyISO) estado = 'vencido';
    else if(cubierto > 0) estado = 'parcial';
    else estado = 'pendiente';
    return { ...v, importe, cubierto, pendiente, estado };
  });
}

/* ── el modelo entero, por moneda ──────────────────────────────────────────
   Entra todo lo que las cuatro consultas traen; sale un mapa moneda → modelo.
   Los PRELIMINARES no aportan vencimientos ni precio (su dinero ya está en el
   cobradoEfectivo de su Bloqueo); un contrato sin calendario sigue contando en
   cartera y pendiente — que no tenga hitos no hace que no se le deba dinero. */
function modeloFinanciero(o){
  const hoy = o.hoyISO;
  const porMoneda = {};
  const de = m => porMoneda[m] || (porMoneda[m] = {
    moneda: m, cartera: 0, cobrado: 0, pendiente: 0, vencido: 0,
    proximos30: 0, proximos90: 0, sinFecha: 0, nSinFecha: 0,
    /* LO QUE ESTE PANEL NO CUENTA, contado. Ver la nota de `fuera` más abajo. */
    fuera: { sinFirmar: 0, preliminares: 0, importe: 0, proyectos: {} },
    filas: [], porProyecto: {}, porMes: {}, avisos: [],
  });
  const vencsDe = {};
  for(const v of o.vencimientos) (vencsDe[v.contrato_id] = vencsDe[v.contrato_id] || []).push(v);

  for(const c of o.contratos){
    /* ── LO QUE SE QUEDA FUERA, CONTADO ─────────────────────────────────────
       Las dos exclusiones de abajo tienen su motivo y no se tocan. El efecto
       secundario sí: un proyecto entero puede no aparecer y nadie sabe por qué.
       Caso real (26-ago-2026, owner: «no veo Sumba Hills»): 46 contratos, solo
       2 firmados y los dos Cartas de Reserva → cero filas y ni una palabra. Un
       panel financiero que enseña un hueco donde hay 46 contratos se lee como
       «aquí no hay dinero», que es la lectura peligrosa.
       No se cambia QUÉ se cuenta: se cuenta lo que NO, para poder decirlo. */
    const anotaFuera = (m, clave) => {
      m.fuera[clave]++;
      const pr = (c.proyecto_nombre || '').trim();
      if(pr) m.fuera.proyectos[pr] = (m.fuera.proyectos[pr] || 0) + 1;
      const p = Number(c.precio_total) || 0;
      if(p) m.fuera.importe += p;
    };
    if(lwEsPreliminar(c.tipo)){
      /* Una Carta que CUELGA de su Bloqueo ya está contada: su cobrado entra
         por cobradoEfectivo() del padre. Pero una Carta SUELTA —la reserva
         está viva y el Bloqueo aún no existe— tiene señales cobradas que son
         dinero real en caja: sin esto, el KPI de cobrado mentía a la baja
         exactamente en la fase en que más entra la señal. Su PRECIO sigue sin
         sumar (no es de fiar, regla del 14-ago) y sus vencimientos tampoco:
         el calendario llega con el contrato de verdad. */
      const m = de(c.moneda || 'EUR');
      if(!c.contrato_padre_id) m.cobrado += Number(o.cobradoPorId[c.id]) || 0;
      anotaFuera(m, 'preliminares');
      continue;
    }
    /* SOLO CONTRATOS FIRMADOS — 18-ago-2026, decisión del cliente («debemos
       esperar al menos a que el contrato esté firmado»). Un borrador no es un
       compromiso: crear el contrato NO puede marcar dinero como esperado, y
       hasta hoy lo hacía. Se filtra AQUÍ, en la lectura, y no en el trigger de
       la base, por un motivo que no es de gusto: al firmar, la edge marca
       `bloqueado=true` SIN tocar `datos`, así que un trigger que solo creara
       las filas "al firmar" no se dispararía nunca — el espejo se sincroniza
       desde el borrador precisamente para que al firmar ya esté todo puesto.
       El COBRADO del borrador sí cuenta (rama de abajo): un recibí es dinero
       real en caja, esté el contrato en el estado que esté. */
    if(!c.bloqueado){
      const m = de(c.moneda || 'EUR');
      m.cobrado += cobradoEfectivo(c, o.contratos, o.cobradoPorId);
      anotaFuera(m, 'sinFirmar');
      continue;
    }
    const m = de(c.moneda || 'EUR');
    const precio = Number(c.precio_total) || 0;
    const cobrado = cobradoEfectivo(c, o.contratos, o.cobradoPorId);
    m.cartera += precio;
    m.cobrado += cobrado;
    m.pendiente += Math.max(0, precio - cobrado);

    const anotados = cascada(vencsDe[c.id] || [], c, cobrado, hoy);
    for(const v of anotados){
      m.filas.push({ ...v, contrato: c });
      const proy = c.proyecto_nombre || 'Sin proyecto';
      const p = m.porProyecto[proy] || (m.porProyecto[proy] = { cartera:0, cobrado:0, vencido:0, proximos90:0 });
      if(v.estado === 'vencido'){ m.vencido += v.pendiente; p.vencido += v.pendiente; }
      if(v.estado === 'sin_fecha'){ m.nSinFecha++; if(v.importe != null) m.sinFecha += v.pendiente ?? v.importe; }
      if(v.fecha && v.pendiente > 0 && v.fecha >= hoy){
        if(diasEntre(hoy, v.fecha) <= 30) m.proximos30 += v.pendiente;
        if(diasEntre(hoy, v.fecha) <= 90){ m.proximos90 += v.pendiente; p.proximos90 += v.pendiente; }
      }
      if(v.fecha){
        const mes = v.fecha.slice(0,7);
        const fila = m.porMes[mes] || (m.porMes[mes] = { previsto:0, cobrado:0, vencido:0 });
        if(v.importe != null){
          fila.previsto += v.importe;
          fila.cobrado += v.cubierto;
          if(v.estado === 'vencido') fila.vencido += v.pendiente;
        }
      }
    }
    // cartera/cobrado por proyecto van por CONTRATO, no por vencimiento: un
    // contrato sin calendario también es cartera de su proyecto.
    const proy = c.proyecto_nombre || 'Sin proyecto';
    const p = m.porProyecto[proy] || (m.porProyecto[proy] = { cartera:0, cobrado:0, vencido:0, proximos90:0 });
    p.cartera += precio; p.cobrado += cobrado;

    // ── avisos de calidad de dato: lo que impide vigilar de verdad ──
    if(!(vencsDe[c.id] || []).length && precio > 0 && !esConsultivo(c.tipo))
      m.avisos.push({ tipo:'sin_calendario', contrato: c });
    const sumaPct = (vencsDe[c.id] || []).reduce((t,v)=>t+(lwParseImporte(v.pct)||0),0);
    if((vencsDe[c.id] || []).length && sumaPct && Math.round(sumaPct) !== 100)
      m.avisos.push({ tipo:'pct_no_100', contrato: c, suma: Math.round(sumaPct*100)/100 });
  }
  for(const m of Object.values(porMoneda)){
    m.filas.sort((a,b)=>{
      if(a.fecha && b.fecha) return a.fecha < b.fecha ? -1 : 1;
      if(a.fecha) return -1; if(b.fecha) return 1;
      return 0;
    });
  }
  return porMoneda;
}

/* Tipos que no son una venta con calendario propio: no se les reprocha no
   tenerlo. Los poderes y acuerdos comerciales no cobran por hitos. */
const TIPOS_SIN_CALENDARIO = ['poa', 'acuerdo_comercial', 'protocolo_operativo', 'commercial_offer', 'contrato_general'];
function esConsultivo(tipo){ return TIPOS_SIN_CALENDARIO.includes(tipo); }

function diasEntre(aISO, bISO){
  return Math.round((new Date(bISO + 'T00:00:00Z') - new Date(aISO + 'T00:00:00Z')) / 86400000);
}

/* Los meses del gráfico de caja: desde 3 atrás hasta 11 adelante, SIEMPRE los
   15 aunque estén a cero — un mes que falta en un gráfico de caja se lee como
   "no hay nada que cobrar", que es distinto de "0 este mes". */
function mesesVentana(hoyISO){
  const [y, mm] = hoyISO.split('-').map(Number);
  const out = [];
  for(let i = -3; i <= 11; i++){
    const d = new Date(Date.UTC(y, mm - 1 + i, 1));
    out.push(d.getUTCFullYear() + '-' + String(d.getUTCMonth() + 1).padStart(2, '0'));
  }
  return out;
}

/* ── deuda por antigüedad: cuánto lleva vencido cada euro ──────────────────
   Los cuatro tramos clásicos de un aging (1-30 / 31-60 / 61-90 / +90 días de
   retraso), sobre las filas YA anotadas por la cascada: solo lo `vencido`, y por
   su PENDIENTE — lo cubierto no es deuda. Un tramo vacío se devuelve igual, a
   cero: en un informe de deuda, un tramo que falta se lee como "no hay deuda
   vieja", que es distinto de "0 € en ese tramo". */
function agingVencido(filas, hoyISO){
  const tramos = [
    { etiqueta:'1–30 días',  desde:1,  hasta:30,  importe:0, n:0 },
    { etiqueta:'31–60 días', desde:31, hasta:60,  importe:0, n:0 },
    { etiqueta:'61–90 días', desde:61, hasta:90,  importe:0, n:0 },
    { etiqueta:'+90 días',   desde:91, hasta:Infinity, importe:0, n:0 },
  ];
  for(const f of filas){
    if(f.estado !== 'vencido' || !(f.pendiente > 0)) continue;
    const retraso = diasEntre(f.fecha, hoyISO);
    const t = tramos.find(x => retraso >= x.desde && retraso <= x.hasta);
    if(t){ t.importe = Math.round((t.importe + f.pendiente) * 100) / 100; t.n++; }
  }
  return tramos;
}

/* ── el dinero por trimestre: la pregunta del cliente ──────────────────────
   «Sabe el dinero que debe entrar cada trimestre»: lo PENDIENTE con fecha
   dentro de cada uno de los próximos `n` trimestres naturales, empezando por
   el corriente. Trimestres naturales (T1=ene-mar…) y no ventanas móviles:
   así la cifra coincide con cómo se cierra la contabilidad. */
function porTrimestre(filas, hoyISO, n){
  const [y0, m0] = hoyISO.split('-').map(Number);
  const q0 = Math.floor((m0 - 1) / 3);          // 0..3 del trimestre corriente
  const out = [];
  for(let i = 0; i < (n || 4); i++){
    const total = q0 + i;
    const y = y0 + Math.floor(total / 4), q = total % 4;
    const desde = `${y}-${String(q*3+1).padStart(2,'0')}-01`;
    const finMes = new Date(Date.UTC(y, q*3+3, 0));
    const hasta = finMes.toISOString().slice(0,10);
    let importe = 0, cuenta = 0;
    for(const f of filas){
      if(!f.fecha || !(f.pendiente > 0)) continue;
      if(f.fecha >= desde && f.fecha <= hasta){ importe += f.pendiente; cuenta++; }
    }
    out.push({ trimestre:`T${q+1} ${y}`, desde, hasta,
               importe: Math.round(importe*100)/100, n: cuenta });
  }
  return out;
}

if(typeof module !== 'undefined' && module.exports)
  module.exports = { importeVencimiento, cobradoEfectivo, cascada, modeloFinanciero, mesesVentana, diasEntre, agingVencido, porTrimestre, TIPOS_SIN_CALENDARIO };
