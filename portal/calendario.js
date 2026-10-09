/* calendario.js — las fechas del comprador para la pestaña Calendario del portal (9-oct-2026, owner).

   Devuelve DATOS, nunca HTML: la pantalla escapa cada texto al pintarlo (revisión previa de Seguridad: la CSP del
   portal va en Report-Only, así que `esc()` es la única barrera contra un texto con marcado en un hito o una foto).
   Ninguna regla de dinero vive aquí; se reutilizan las del resto del portal para que el calendario no pueda decir
   otra cosa que Inicio, Contratos o Facturas:
   · qué contratos cuentan → `resumenPortal(...).base` (resumen.js): el calendario de una Carta sustituida son los
     mismos hitos que ya trae su Bloqueo, y pintarlos repetía el mismo pago (revisión previa de Datos);
   · pagado / parcial / pendiente de cada hito → `estadosHitos` (index.html), el reparto de Contratos;
   · «vencida» → `estadoFactura` de su factura (resumen.js), NUNCA solo la fecha: una factura ya cubierta no se
     anuncia vencida aunque el reparto por hitos la siga viendo pendiente (revisor, 8-oct). Un hito sin factura no
     se pinta vencido aunque su fecha haya pasado, igual que en Inicio;
   · caducidad de un documento → `estadoDocumento` (resumen.js), la misma cuenta que Inicio y Mi perfil.

   La fecha de pago es la del CONTRATO (`hitos[].fecha`, congelada al firmar): decisión del owner del 9-oct-2026 entre
   esa y la operativa de `contrato_vencimientos`. Hoy son idénticas (0 filas ajustadas); si el equipo mueve una
   fecha, el comprador sigue viendo la firmada. Solo contratos FIRMADOS: un borrador no es un compromiso.

   Los días van como cadena «AAAA-MM-DD» en hora LOCAL de quien mira (`diaLocal`): `new Date('2026-10-14')` es
   medianoche UTC y al oeste de Greenwich pintaba el día anterior. Los instantes con hora (`expira_en` del enlace de
   firma) se convierten a su día local.

   El enlace de firma lleva un token: aquí no se copia (revisión previa de Seguridad). El evento solo dice de qué
   contrato es; firmar se hace desde Contratos, con el botón que ya existe.

   Lo carga index.html como script normal (globales `eventosCalendario`, `diaCal`, `rejillaMes`, …) y node lo carga
   con require para `calendario.test.js`. */

function _dep(dep){
  const g = typeof globalThis !== 'undefined' ? globalThis : {};
  dep = dep || {};
  const de = n => dep[n] || g[n] || (typeof window !== 'undefined' ? window[n] : undefined);
  return {
    resumenPortal: de('resumenPortal'), precioContrato: de('precioContrato'), facturaDelHito: de('facturaDelHito'),
    estadoFactura: de('estadoFactura'), saldoSinAplicar: de('saldoSinAplicar'), estadoDocumento: de('estadoDocumento'),
    estadosHitos: de('estadosHitos'), obraProyecto: de('obraProyecto'), avisoDias: de('KYC_AVISO_DIAS') || 30,
  };
}

const _2 = n => (n < 10 ? '0' : '') + n;
/* Un Date (o «AAAA-MM-DD», o un instante ISO) → su día local «AAAA-MM-DD». null si no se puede leer.
   No es `diaLocal` (resumen.js) a propósito: aquel, con un instante con hora, cuenta el día ESCRITO (el de UTC);
   aquí un instante —la caducidad del enlace de firma— se pasa al día de quien mira, que es cuando de verdad caduca. */
function diaCal(f){
  if (f == null || f === '') return null;
  let d;
  if (f instanceof Date) d = f;
  else if (/^\d{4}-\d{2}-\d{2}$/.test(String(f))) { const m = String(f).split('-'); d = new Date(+m[0], +m[1] - 1, +m[2]); }
  else d = new Date(f);
  if (isNaN(d)) return null;
  return d.getFullYear() + '-' + _2(d.getMonth() + 1) + '-' + _2(d.getDate());
}
/* «AAAA-MM-DD» → Date local a medianoche. */
function fechaDeDia(s){ const m = String(s || '').split('-'); return new Date(+m[0], +m[1] - 1, +m[2]); }
/* Días de calendario de `a` a `b` (las dos «AAAA-MM-DD»). round: un día con cambio de hora mide 23 o 25 horas. */
function diasEntre(a, b){ return Math.round((fechaDeDia(b) - fechaDeDia(a)) / 86400000); }
function sumaDias(s, n){ const d = fechaDeDia(s); d.setDate(d.getDate() + n); return diaCal(d); }
/* El lunes de la semana de un día. */
function lunesDe(s){ const d = fechaDeDia(s); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return diaCal(d); }
/* Los días que pinta la rejilla de un mes, de lunes a domingo: 5 o 6 semanas. */
function rejillaMes(anio, mes0){
  const ini = lunesDe(diaCal(new Date(anio, mes0, 1)));
  // la sexta semana solo si el mes llega a ella (su lunes sigue siendo del mes)
  const n = fechaDeDia(sumaDias(ini, 35)).getMonth() === mes0 ? 42 : 35;
  const dias = [];
  for (let i = 0; i < n; i++) dias.push(sumaDias(ini, i));
  return dias;
}

/* Las cuatro familias que se filtran y que llevan su punto en la pantalla. */
const CAL_FAMILIAS = ['firma', 'pago', 'obra', 'doc'];

/* ── los eventos ──────────────────────────────────────────────────────────────────────────────────────────────
   Cada evento: { id, familia, clase, dia, estado, pide, ... datos propios }.
   · `pide`: le pide algo al comprador (firmar, pagar, renovar). Es lo que sale en «Pendiente de ti».
   · `id` estable y sin datos sensibles: el contrato, la factura o el documento, nunca el enlace de firma. */
function eventosCalendario(d, hoy, dep){
  const D = _dep(dep);
  d = d || {};
  const hoyDia = diaCal(hoy || new Date());
  const contratos = (d.contratos || []).filter(Boolean);
  const facturas = (d.facturas || []).filter(Boolean);
  const porId = {};
  contratos.forEach(x => { if (x.id) porId[x.id] = x; });
  const ev = [];

  /* Periodo de un evento (owner, 9-oct-2026: el calendario «en color»): además de su día clave, lo que está EN MARCHA
     se pinta como una franja fina que cubre sus días. Solo con datos que el portal ya trae: el enlace de firma desde
     que se envió hasta que caduca; una factura sin pagar desde que se emitió hasta que vence; una vencida desde que
     venció hasta hoy; un documento, los días de aviso antes de caducar (KYC_AVISO_DIAS, el mismo plazo que Inicio). */
  const periodo = (e, desde, hasta) => { if (desde && hasta && desde < hasta){ e.desde = desde; e.hasta = hasta; } return e; };

  // 1 · firma pendiente: el día en que caduca el enlace
  (d.firma_pendiente || []).forEach(fp => {
    const dia = diaCal(fp && fp.expira_en);
    if (!dia) return;
    const x = porId[fp.contrato_id] || {};
    ev.push(periodo({ id: 'firma:' + fp.contrato_id, familia: 'firma', clase: 'firma', dia: dia, estado: 'firmar', pide: true,
              contrato: x.numero || '', proyecto: x.proyecto || '', parcela: x.parcela || '', ir: 'contratos' }, diaCal(fp.enviado_en), dia));
  });

  // 2 · pagos: los hitos con fecha de los contratos que cuentan (la misma base que el «Próximo pago»)
  const res = D.resumenPortal ? D.resumenPortal(contratos) : { base: contratos };
  const extra = D.saldoSinAplicar ? D.saldoSinAplicar(facturas, contratos) : {};
  const facturasDeHito = {};
  res.base.forEach(x => {
    if (!x.firmado) return;
    const precio = D.precioContrato ? D.precioContrato(x) : Number(x.precio);
    const hs = D.estadosHitos ? D.estadosHitos(x.hitos, Number(x.cobrado) || 0, precio) : [];
    hs.forEach((y, i) => {
      const dia = diaCal(y.hito && y.hito.fecha);
      if (!dia) return;
      const fac = D.facturaDelHito ? D.facturaDelHito(facturas, { id: x.id, numero: x.numero }, y.hito, x.moneda) : null;
      if (fac) facturasDeHito[fac.id] = true;
      /* Con factura de estado conocido, la FACTURA manda en el estado y en lo que falta, en todos sus estados: es lo
         que pinta su fila en Facturas (aplicado + resto sin aplicar). El reparto por hitos puede dar por pagado un hito
         cuya factura sigue abierta porque el dinero se aplicó a otra (un extra), y un «vencida» con pago parcial debe
         decir lo que falta, no el total (revisor de código, 9-oct-2026: dos cifras del mismo dinero). Sin factura, o
         con una sin `aplicado`, decide el reparto, como en Contratos. */
      const ef = fac && D.estadoFactura ? D.estadoFactura(fac, extra[fac.id], fechaDeDia(hoyDia).setHours(12)) : { estado: null };
      const monto = isNaN(y.monto) ? null : y.monto;
      let estado, falta;
      if (ef.estado === 'pagada'){ estado = 'pagado'; falta = 0; }
      else if (ef.estado === 'vencida' || ef.estado === 'parcial' || ef.estado === 'pendiente'){
        estado = ef.estado; falta = ef.falta != null ? ef.falta : Number(fac.total);
      } else {
        estado = y.estado === 'pagado' ? 'pagado' : (y.estado === 'parcial' ? 'parcial' : 'pendiente');
        falta = monto == null ? null : (estado === 'pagado' ? 0 : Math.max(0, monto - (y.cubierto || 0)));
      }
      const pendiente = !!fac && ef.estado != null && estado !== 'pagado';
      ev.push(periodo({ id: 'hito:' + x.id + ':' + i, familia: 'pago', clase: estado === 'vencida' ? 'vencida' : 'pago', dia: dia, estado: estado,
                // un pago te lo pedimos cuando hay factura (sale a D-3 del vencimiento): antes es un plazo del plan, no una tarea
                pide: !!fac && ef.estado != null && estado !== 'pagado',
                hito: y.hito, monto: monto, falta: falta, moneda: x.moneda || null,
                contrato: x.numero || '', proyecto: x.proyecto || '', parcela: x.parcela || '',
                factura: fac ? fac.numero : null, ir: fac ? 'factura' : 'contratos' },
                !pendiente ? null : estado === 'vencida' ? dia : diaCal(fac.fecha), !pendiente ? null : estado === 'vencida' ? hoyDia : dia));
    });
  });

  // 3 · facturas que no son de ningún hito con fecha (p. ej. un extra) y siguen por pagar: el día en que vencen
  facturas.forEach(f => {
    if (f.tipo !== 'factura' || facturasDeHito[f.id]) return;
    const ef = D.estadoFactura ? D.estadoFactura(f, extra[f.id], fechaDeDia(hoyDia).setHours(12)) : { estado: null };
    const dia = diaCal(ef.vence);
    if (!dia || !ef.estado || ef.estado === 'pagada') return;
    ev.push(periodo({ id: 'factura:' + f.id, familia: 'pago', clase: ef.estado === 'vencida' ? 'vencida' : 'pago', dia: dia,
              estado: ef.estado === 'vencida' ? 'vencida' : (ef.estado === 'parcial' ? 'parcial' : 'pendiente'),
              pide: true, monto: Number(f.total), falta: ef.falta != null ? ef.falta : Number(f.total), moneda: f.moneda || null,
              contrato: f.contrato_numero || '', proyecto: f.proyecto || '', factura: f.numero, ir: 'factura' },
              ef.estado === 'vencida' ? dia : diaCal(f.fecha), ef.estado === 'vencida' ? hoyDia : dia));
  });

  // 4 · pagos recibidos: el recibo, en su día, como hecho
  facturas.forEach(f => {
    if (f.tipo !== 'recibi') return;
    const dia = diaCal(f.fecha);
    if (!dia) return;
    ev.push({ id: 'recibo:' + f.id, familia: 'pago', clase: 'pago', dia: dia, estado: 'recibido', pide: false,
              monto: Number(f.total), moneda: f.moneda || null, contrato: f.contrato_numero || '', proyecto: f.proyecto || '',
              factura: f.numero, ir: 'factura' });
  });

  // 5 · obra: la entrega de cada unidad y los días con fotos nuevas
  /* Qué proyecto es el de una unidad lo dice `obraProyecto` (index.html: contrato_numero → proyecto_id, y solo si no
     hay id, el nombre), la misma regla que la pantalla Obra: cruzar por nombre aquí era una segunda versión de ella, y
     con nombres que no casan salían dos «Entrega de llaves» (revisor de código, 9-oct-2026). */
  const proyDe = o => { const r = D.obraProyecto ? D.obraProyecto(o) : null; return r && r.proyecto ? r.proyecto.id : null; };
  const conEntrega = {};
  (d.obra || []).forEach(o => {
    if (!o) return;
    const dia = diaCal(o.fecha_entrega);
    // solo la unidad que TRAE fecha tapa la estimada del proyecto: si no, no quedaba ninguna fecha de entrega
    if (dia){ const pid = proyDe(o); if (pid) conEntrega[pid] = true; }
    if (dia) ev.push({ id: 'entrega:' + (o.unidad || o.contrato_numero), familia: 'obra', clase: 'obra', dia: dia,
                       estado: o.fase === 'entregada' ? 'hecho' : 'previsto', pide: false,
                       unidad: o.unidad || '', proyecto: o.proyecto || '', tipoObra: 'entrega', ir: 'obra' });
    const porDia = {};
    (o.fotos || []).forEach(p => { const k = diaCal(p && p.fecha); if (k) (porDia[k] = porDia[k] || []).push(p.titulo || ''); });
    Object.keys(porDia).forEach(k => {
      ev.push({ id: 'fotos:' + (o.unidad || o.contrato_numero) + ':' + k, familia: 'obra', clase: 'obra', dia: k, estado: 'hecho', pide: false,
                unidad: o.unidad || '', proyecto: o.proyecto || '', tipoObra: 'fotos', n: porDia[k].length, titulo: porDia[k][0], ir: 'obra' });
    });
  });
  // la entrega estimada del proyecto solo si ninguna unidad suya trae la suya (si no, saldría dos veces)
  (d.proyectos || []).forEach(p => {
    const dia = diaCal(p && p.entrega);
    if (!dia || conEntrega[p.id]) return;
    ev.push({ id: 'entrega-proy:' + p.id, familia: 'obra', clase: 'obra', dia: dia, estado: 'previsto', pide: false,
              unidad: '', proyecto: p.nombre || '', tipoObra: 'entrega', ir: 'obra' });
  });

  // 6 · documentos: el día en que caduca cada uno
  (d.kyc || []).forEach((k, i) => {
    const dia = diaCal(k && k.caduca);
    if (!dia) return;
    const e = D.estadoDocumento ? D.estadoDocumento(k.caduca, fechaDeDia(hoyDia)) : { estado: 'ok', dias: diasEntre(hoyDia, dia) };
    ev.push(periodo({ id: 'doc:' + (k.tipo || 'otro') + ':' + i, familia: 'doc', clase: e.estado === 'vencido' ? 'vencida' : 'doc', dia: dia,
              estado: e.estado, pide: e.estado === 'pronto' || e.estado === 'vencido', docTipo: k.tipo || '', ir: 'perfil' },
              e.estado === 'vencido' ? null : sumaDias(dia, -D.avisoDias), dia));
  });

  ev.forEach(e => { e.dias = diasEntre(hoyDia, e.dia); });
  // por día; dentro del día, primero lo que pide algo y lo vencido
  const peso = e => (e.clase === 'vencida' ? 0 : e.pide ? 1 : 2);
  return ev.sort((a, b) => a.dia.localeCompare(b.dia) || peso(a) - peso(b) || a.id.localeCompare(b.id));
}

/* «Pendiente de ti»: lo que le pide algo, vencido primero y luego por fecha. */
function pendientesCalendario(eventos){
  return (eventos || []).filter(e => e.pide).slice().sort((a, b) =>
    ((a.clase === 'vencida' ? 0 : 1) - (b.clase === 'vencida' ? 0 : 1)) || a.dia.localeCompare(b.dia));
}

/* Hitos de contratos firmados que cuentan y NO traen fecha: el calendario no los puede colocar y lo dice
   (122 de 212 en producción el 9-oct-2026, revisión previa de Datos) — un calendario vacío no es «no debes nada». */
function hitosSinFecha(d, dep){
  const D = _dep(dep);
  const contratos = ((d && d.contratos) || []).filter(Boolean);
  const facturas = ((d && d.facturas) || []).filter(Boolean);
  const res = D.resumenPortal ? D.resumenPortal(contratos) : { base: contratos };
  let n = 0;
  res.base.forEach(x => {
    if (!x.firmado) return;
    const precio = D.precioContrato ? D.precioContrato(x) : Number(x.precio);
    const hs = D.estadosHitos ? D.estadosHitos(x.hitos, Number(x.cobrado) || 0, precio) : [];
    hs.forEach(y => {
      if (y.estado === 'pagado' || diaCal(y.hito && y.hito.fecha)) return;
      // si ya tiene factura CON estado, el calendario la pinta en su vencimiento (factura suelta): no es «sin fecha».
      // Sin `aplicado` (estado desconocido) o sin vencimiento legible la factura no sale, así que ese hito sigue contando aquí:
      // es la misma condición con la que el bucle de facturas sueltas la descarta.
      const fac = D.facturaDelHito ? D.facturaDelHito(facturas, { id: x.id, numero: x.numero }, y.hito, x.moneda) : null;
      const ef = fac && D.estadoFactura ? D.estadoFactura(fac, 0, Date.now()) : null;
      const sale = !!(ef && ef.estado != null && diaCal(ef.vence));
      if (!sale) n++;
    });
  });
  return n;
}

if (typeof module !== 'undefined' && module.exports)
  module.exports = { eventosCalendario, pendientesCalendario, hitosSinFecha, diaCal, fechaDeDia, diasEntre, sumaDias, lunesDe, rejillaMes, CAL_FAMILIAS };
