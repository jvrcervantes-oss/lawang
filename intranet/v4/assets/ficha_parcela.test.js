// Ficha de la parcela (15-oct-2026): contratos de la parcela, los dos pendientes, documentos y avance de obra
// (ficha-parcela.js). Con un sb falso: no hay obra · obra que no se ve · 3 obras · cobro no visible · una lectura
// que falla · 42501 en el saldo · venta de varias parcelas · precio de catálogo · facturado de más.
// Corre con: node intranet/v4/assets/ficha_parcela.test.js
'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..', '..', '..');
const leer = (...p) => fs.readFileSync(path.join(raiz, ...p), 'utf8').replace(/\r\n/g, '\n');
const FP = require('./ficha-parcela.js');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// precioParte y sueloSinFirmar se sacan de datos.js tal cual: la ficha resta con el MISMO precio que enseña.
const datos = leer('intranet', 'v4', 'assets', 'datos.js');
const trozo = (nombre) => {
  const i = datos.indexOf('function ' + nombre + '(');
  ok(i > 0, 'datos.js tiene ' + nombre);
  let j = datos.indexOf('{', i), d = 0, k = j;
  for (; k < datos.length; k++) { if (datos[k] === '{') d++; else if (datos[k] === '}' && --d === 0) break; }
  return datos.slice(i, k + 1);
};
const H = new Function(trozo('precioParte') + '\n' + trozo('precioTotal') + '\n' + trozo('sueloSinFirmar') +
  '\nreturn { precioParte: precioParte, precioTotal: precioTotal, sueloSinFirmar: sueloSinFirmar };')();
ok(/window\.LW_V4\.precioParte = precioParte;/.test(datos) && /window\.LW_V4\.sueloSinFirmar = sueloSinFirmar;/.test(datos) &&
   /window\.LW_V4\.precioTotal = precioTotal;/.test(datos), 'datos.js publica las tres funciones');

// ── sb falso ────────────────────────────────────────────────────────────────────────────────────────────────────
function sbFalso(t) {
  const llamadas = [];
  const res = (r) => {
    const q = {
      select(c) { llamadas.push(['select', c]); return q; },
      or(f) { llamadas.push(['or', f]); return q; },
      in(c, ids) { llamadas.push(['in', c, ids]); return q; },
      then(a, b) { return (r && r.revienta ? Promise.reject(r.revienta) : Promise.resolve(r || { data: [] })).then(a, b); }
    };
    return q;
  };
  return {
    llamadas,
    rpc(nombre, args) {
      llamadas.push(['rpc', nombre, args]);
      if (nombre === 'contratos_equipo') return res(t.contratos);
      if (nombre === 'facturas_equipo') return res(t.facturas);
      if (nombre === 'contrato_saldo') return res((t.saldo || {})[args.p_contrato] || { data: null, error: { code: 'P0002', message: 'no existe' } });
      throw new Error('rpc inesperada ' + nombre);
    },
    from(tabla) {
      llamadas.push(['from', tabla]);
      if (tabla === 'contrato_tipo_etapa') return res(t.tipos || { data: [{ tipo: 'reserva_parcela', es_obra: false }, { tipo: 'construccion', es_obra: true }, { tipo: 'cc00014_timon', es_obra: true }] });
      if (tabla === 'obra_fases') return res(t.fases || { data: [{ clave: 'cimentacion', es: 'Cimentación', en: 'Foundations' }] });
      throw new Error('tabla inesperada ' + tabla);
    }
  };
}
const U = 'u-1', R = 'c-raiz';
const fila = (x) => Object.assign({ id: U, codigo: 'SH-36', contrato_id: R, contrato_numero: 'RP00101', contrato_firmado: true, moneda: 'EUR',
  precio_suelo: 25000, precio_construccion: 50000, suelo_pactado: 25000, obra_pactada: 44000, cobrado_suelo: 25000, cobrado_obra: 4000,
  obra_firmada: true, suelo_de_contrato: true, obra_de_contrato: true }, x || {});
const raizC = { id: R, numero: 'RP00101', tipo: 'reserva_parcela', bloqueado: true, precio_total: 25000, moneda: 'EUR', fecha_firma: '2026-08-01', contrato_padre_id: null, unidad_id: U };
const obra = (id, num, x) => Object.assign({ id, numero: num, tipo: 'construccion', bloqueado: false, precio_total: 44000, moneda: 'EUR', contrato_padre_id: R, unidad_id: U, created_at: '2026-08-10' }, x || {});
const saldoOk = (x) => ({ data: Object.assign({ cadena: 'RP00101', moneda: 'EUR', precio: 69000, sin_precio: false, facturado: 33000, cobrado: 29000, por_cobrar: 4000, por_facturar: 36000, facturas: [] }, x || {}) });
const pinta = (m) => Object.values(FP.fpHTML).map((f) => f(m)).join('\n');
const corre = async (u, t, h) => { FP._reinicia(); const sb = sbFalso(t); const c = await FP.fpCarga(sb, u); return { m: FP.fpModelo(u, c, Object.assign({ parcelasDeVenta: 1 }, H, h || {})), sb }; };

(async () => {
  // 1 · sin obra: la venta sola, con sus documentos y una factura abierta
  {
    const u = fila({ obra_firmada: false, obra_de_contrato: false, obra_pactada: null, precio_construccion: null, cobrado_obra: 0 });
    const { m, sb } = await corre(u, {
      contratos: { data: [raizC] },
      facturas: { data: [{ id: 'f1', numero: 'INV1', tipo: 'factura', total: 10000, moneda: 'EUR', fecha_emision: '2026-08-02', contrato_id: R },
                         { id: 'r1', numero: 'REC1', tipo: 'recibi', total: 6000, moneda: 'EUR', contrato_id: R },
                         { id: 'p1', numero: 'PRO1', tipo: 'proforma', total: 1, anulada: true, contrato_id: R }] },
      saldo: { [R]: saldoOk({ facturas: [{ id: 'f1', numero: 'INV1', total: 10000, cobrado: 6000 }] }) }
    });
    const or = sb.llamadas.find((l) => l[0] === 'or')[1];
    ok(or === 'id.eq.' + R + ',contrato_padre_id.eq.' + R + ',unidad_id.eq.' + U, 'los contratos se piden por id (raíz, hijos y unidad)');
    ok(!sb.llamadas.some((l) => l[0] === 'select' && /datos|\*/.test(l[1])), 'nunca se piden `datos` ni `*`');
    ok(sb.llamadas.some((l) => l[0] === 'rpc' && l[1] === 'contratos_equipo') && sb.llamadas.some((l) => l[0] === 'rpc' && l[1] === 'facturas_equipo'), 'lee por las RPC del equipo');
    ok(m.contratos.length === 1 && m.contratos[0].raiz && m.contratos[0].estado === 'firmado', 'sin obra: un contrato, firmado');
    ok(!m.obraOculta, 'sin obra no hay aviso de obra oculta');
    ok(m.pactado && m.pactado.importe === 0 && m.pactado.pactado, 'pactado por cobrar = 25.000 − 25.000');
    ok(m.abiertas.length === 1 && m.abiertas[0].pendiente === 4000, 'la factura abierta enseña lo que falta');
    ok(m.docs.grupos.factura.length === 1 && m.docs.grupos.recibi.length === 1 && m.docs.grupos.proforma.length === 0, 'los anulados no cuentan');
    const h = pinta(m);
    ok(/Pactado por cobrar/.test(h) && /Facturado sin cobrar/.test(h) && /Ya está dentro de «Pactado por cobrar»: no se suman\./.test(h), 'los dos pendientes, rotulados distinto');
    ok(/Sin facturar/.test(h) && /1 factura · 1 recibí · 0 proformas/.test(FP.fpHTML.docsResumen(m)), 'Documentos plegado con el recuento (singular con 1) y «Sin facturar»');
    ok(/facturas\/\?q=RP00101/.test(h), '«Ver en Facturas» busca por el contrato del que cuelgan los documentos');
  }
  // 2 · obra que no se ve: la fila dice que hay obra firmada y la lectura no la trae
  {
    const { m } = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(m.obraOculta, 'obra firmada que no llega: «hay una que no puedes ver»');
    ok(m.fuga, 'y los totales de la venta lo avisan');
    const h = pinta(m);
    ok(/Hay un contrato de construcción que no puedes ver\. Lo ve un administrador de la empresa\./.test(h), 'aviso con salida');
    ok(/Los totales de la venta incluyen documentos que no puedes abrir\./.test(h), 'aviso de la fuga');
    ok(!/no tiene contratos/.test(h), 'no dice «no hay»');
  }
  // 3 · tres obras: la firmada primero, la de otra parcela fuera, la sin parcela «de la venta»
  {
    const { m } = await corre(fila(), {
      contratos: { data: [obra('o2', 'CC2', { created_at: '2026-08-05' }), raizC, obra('o1', 'CC1', { bloqueado: true, fecha_firma: '2026-09-01' }),
                          obra('o3', 'CC3', { created_at: '2026-09-09' }), obra('ox', 'CCX', { unidad_id: 'otra' }), obra('ov', 'CCV', { unidad_id: null, created_at: '2026-09-20' })] },
      facturas: { data: [] }, saldo: { [R]: saldoOk() }
    });
    ok(m.contratos.map((c) => c.numero).join() === 'RP00101,CC1,CC2,CC3,CCV', 'orden: venta, obra firmada, borradores por fecha (la de otra parcela fuera): ' + m.contratos.map((c) => c.numero).join());
    ok(m.contratos.filter((c) => c.obra).length === 4 && m.contratos.find((c) => c.numero === 'CCV').deLaVenta, 'se enseñan todas; la sin parcela es «de la venta»');
    ok(!m.obraOculta, 'con obras visibles no hay aviso');
    ok(/de toda la venta, sin parcela asignada/.test(pinta(m)), 'rótulo de la obra de la venta');
    ok((pinta(m).match(/data-obra="1" style="[^"]*border-left/g) || []).length === 4, 'las construcciones llevan su filete');
  }
  // 3b · lo de otra parcela de la misma venta no entra en Documentos ni se le pide saldo (revisión del 15-oct)
  {
    const { m, sb } = await corre(fila(), {
      contratos: { data: [raizC, obra('o1', 'CC1', { bloqueado: true }), obra('ox', 'CCX', { unidad_id: 'otra' })] },
      facturas: { data: [{ id: 'fx', numero: 'INVX', tipo: 'factura', total: 9, moneda: 'EUR', contrato_id: 'ox' },
                         { id: 'f1', numero: 'INV1', tipo: 'factura', total: 5, moneda: 'EUR', contrato_id: 'o1' }] },
      saldo: { [R]: saldoOk(), o1: saldoOk(), ox: saldoOk({ facturas: [{ id: 'fx', numero: 'INVX', total: 9, cobrado: 0 }] }) }
    });
    ok(m.docs.grupos.factura.map((f) => f.numero).join() === 'INV1', 'la factura de la obra de otra parcela no sale');
    ok(!sb.llamadas.some((l) => l[0] === 'rpc' && l[1] === 'contrato_saldo' && l[2].p_contrato === 'ox'), 'ni se pide su saldo');
    ok(!sb.llamadas.some((l) => l[0] === 'in' && l[2].indexOf('ox') !== -1), 'ni sus documentos');
    ok(!m.abiertas.some((a) => a.numero === 'INVX'), 'ni sus facturas abiertas');
    ok(/q=CC1/.test(FP.fpHTML.docsCuerpo(m)) && !/q=RP00101/.test(FP.fpHTML.docsCuerpo(m)), '«Ver en Facturas» solo de los contratos con documentos');
  }
  // 3c · una obra liberada no tapa a la vigente que no se ve
  {
    const { m } = await corre(fila(), { contratos: { data: [raizC, obra('ol', 'CCL', { liberado_en: '2026-09-01' })] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(m.obraOculta && m.contratos.find((c) => c.numero === 'CCL').estado === 'liberado', 'liberada a la vista + vigente oculta = aviso');
  }
  // 3d · revisor 15-oct: venta que no se ve, catálogo vacío y el nombre del tipo
  {
    const a = await corre(fila({ obra_firmada: false, obra_de_contrato: false }), { contratos: { data: [] }, facturas: { data: [] } });
    ok(a.m.ventaOculta && /fp-venta-oculta/.test(FP.fpHTML.contratos(a.m)) && !/no tiene contratos/.test(FP.fpHTML.contratos(a.m)), 'venta que no llega: «no puedes ver», no «no hay»');
    ok(!/fp-venta"/.test(FP.fpHTML.contratos(Object.assign({}, a.m, { venta: { numero: 'CC00999', parcelas: 3 } }))), 'venta oculta: no se pinta su número');
    const b = await corre(fila(), { contratos: { data: [raizC] }, tipos: { data: [] } });
    ok(b.m.contratosError && /fp-contratos-sin-permiso/.test(FP.fpHTML.contratos(b.m)), 'catálogo vacío (no agente) = sin permiso, no «ningún tipo es obra»');
    global.lwTipoContrato = (t) => (t === 'reserva_parcela' ? 'Bloqueo de Parcela' : t);
    const c = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(/Bloqueo de Parcela/.test(FP.fpHTML.contratos(c.m)) && !/reserva_parcela/.test(FP.fpHTML.contratos(c.m)), 'el tipo sale con su nombre (lwTipoContrato es un const global, no de window)');
    delete global.lwTipoContrato;
  }
  // 4 · cobro no visible: no se calcula ni se pinta 0
  {
    const { m } = await corre(fila({ cobrado_suelo: null, cobrado_obra: null }), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(m.pactado.noVisible, 'sin cobro visible no hay resta');
    ok(/sin permiso para ver el cobro/.test(FP.fpHTML.pendientes(m)), 'lo dice');
  }
  // 5 · una lectura que falla lo dice en su bloque
  {
    const a = await corre(fila(), { contratos: { data: null, error: { code: 'XX', message: 'caída' } } });
    ok(a.m.contratosError && /role="alert"/.test(FP.fpHTML.contratos(a.m)) && !/no tiene contratos/.test(FP.fpHTML.contratos(a.m)), 'contratos caídos: error, no «no hay»');
    const b = await corre(fila(), { contratos: { revienta: new Error('red') } });
    ok(b.m.contratosError, 'red caída en contratos: error');
    const c = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: null, error: { message: 'caída' } }, saldo: { [R]: saldoOk() } });
    ok(c.m.docs.error && /fp-docs-error/.test(FP.fpHTML.docsCuerpo(c.m)), 'documentos caídos: error en Documentos');
    const d = await corre(fila(), { contratos: { data: [raizC] }, tipos: { data: null, error: { message: 'caída' } } });
    ok(d.m.contratosError, 'sin el catálogo de obra no se adivina cuál es la construcción');
    const e = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: { data: null, error: { code: 'XX', message: 'caída' } } } });
    ok(/fp-saldo-error/.test(FP.fpHTML.pendientes(e.m)) && !/Facturado sin cobrar<\/span><span[^>]*>0/.test(FP.fpHTML.pendientes(e.m)), 'saldo caído: error, no 0');
  }
  // 6 · 42501 en el saldo: «sin permiso», no 0
  {
    const { m } = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: { data: null, error: { code: '42501', message: 'No puedes ver este contrato' } } } });
    ok(m.cadenas.length === 1 && m.cadenas[0].noVisible, '42501 = no visible');
    ok(/Facturado sin cobrar[\s\S]*sin permiso para ver el cobro/.test(FP.fpHTML.pendientes(m)), 'rotulado «sin permiso»');
  }
  // 7 · venta de varias parcelas
  {
    const { m } = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } }, { parcelasDeVenta: 3 });
    const h = pinta(m);
    ok(/Venta RP00101 · 3 parcelas/.test(h) && /Es de toda la venta \(3 parcelas\)\./.test(h) && /Facturado sin cobrar · venta RP00101/.test(h), 'venta de 3 parcelas rotulada');
    ok(!/Sin facturar/.test(FP.fpHTML.docsResumen(m)) && /Sin facturar · venta RP00101/.test(FP.fpHTML.docsCuerpo(m)), '«Sin facturar» de la venta, no de la parcela');
    ok(!/no se suman/.test(h), 'en una venta de varias parcelas no se dice «ya está dentro»');
  }
  // 8 · precio de catálogo: no se rotula «pactado»
  {
    const { m } = await corre(fila({ obra_de_contrato: false, obra_firmada: false, obra_pactada: 50000 }), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    const h = FP.fpHTML.pendientes(m);
    ok(!m.pactado.pactado && m.pactado.catalogo.join() === 'obra', 'la obra es de catálogo');
    ok(/Por cobrar del precio/.test(h) && !/Pactado por cobrar/.test(h) && /El precio de construcción es de catálogo/.test(h), 'rótulo neutro y el porqué');
    const sinCol = fila(); delete sinCol.suelo_de_contrato; delete sinCol.obra_de_contrato;
    const b = await corre(sinCol, { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(!b.m.pactado.pactado, 'sin las columnas de origen no se afirma «pactado»');
    const c = await corre(fila({ contrato_firmado: false }), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(c.m.pactado.sinFirmar && /incluye contrato sin firmar/.test(FP.fpHTML.pendientes(c.m)), '«incluye contrato sin firmar»');
  }
  // 9 · facturado de más (RP00101, 15-oct): aviso con salida
  {
    const { m } = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk({ facturado_de_mas: 25000, por_facturar: 0 }) } });
    ok(/fp-facturado-de-mas/.test(FP.fpHTML.pendientes(m)) && /anula el que no corresponda/.test(FP.fpHTML.pendientes(m)), 'el exceso se ve aunque «por facturar» sea 0');
    ok(!/no se suman/.test(FP.fpHTML.pendientes(m)), 'con exceso no se afirma «ya está dentro»');
    const st = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk({ sin_precio: true, por_facturar: null, precio: null }) } });
    ok(/fp-sin-tope/.test(FP.fpHTML.pendientes(st.m)) && /no tiene tope de facturación/.test(FP.fpHTML.pendientes(st.m)), 'venta sin precio: aviso de «sin tope» (Administración, RP00079)');
    const b = await corre(fila(), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk({ facturas: [{ id: 'f1', numero: 'INV1', total: 121, subtotal: 100, cobrado: 0 }] }) } });
    ok(/Con impuestos: no se resta del precio pactado\./.test(FP.fpHTML.pendientes(b.m)) && !/no se suman/.test(FP.fpHTML.pendientes(b.m)), 'con impuestos tampoco');
  }
  // 10 · avance de obra con su nombre del catálogo
  {
    const { m, sb } = await corre(fila({ obra_fase: 'cimentacion', obra_fecha_entrega: '2027-03-01' }), { contratos: { data: [raizC] }, facturas: { data: [] }, saldo: { [R]: saldoOk() } });
    ok(m.obra && m.obra.fase === 'Cimentación' && /Fase de obra/.test(FP.fpHTML.obra(m)), 'avance de obra con nombre');
    ok(sb.llamadas.some((l) => l[0] === 'from' && l[1] === 'obra_fases'), 'lee obra_fases');
  }

  // 11 · parcela sin venta (SH-128, Calidad 15-oct): sin contrato no hay nada «por cobrar»
  {
    const { m } = await corre(fila({ contrato_id: null, contrato_numero: null, contrato_firmado: false, suelo_pactado: null, obra_pactada: null,
      suelo_de_contrato: false, obra_de_contrato: false, obra_firmada: false, precio_suelo: 60875, precio_construccion: 200000, cobrado_suelo: 0, cobrado_obra: 0 }),
      { contratos: { data: [] }, facturas: { data: [] } });
    ok(m.pactado === null && !/fp-pactado/.test(FP.fpHTML.pendientes(m)), 'sin venta no se pinta «Por cobrar del precio»');
    const b = await corre(fila({ contrato_id: null, contrato_numero: null, obra_firmada: false, obra_de_contrato: false, cobrado_suelo: null, cobrado_obra: null }), { contratos: { data: [] }, facturas: { data: [] } });
    ok(b.m.pactado === null, 'ni «sin permiso para ver el cobro» en una parcela sin venta');
  }
  // 12 · «Pactado» de la tarjeta = «Precio total» de la ficha = suelo + obra de CONTRATO (Calidad 15-oct, owner 14-oct)
  {
    // C5 · Mejan Village S7, medido en la viva: la tarjeta daba 65.000 (catálogo) y el desglose 26.000 + 49.000.
    ok(H.precioTotal({ precio: 65000, precio_suelo: 25000, precio_construccion: 40000, suelo_pactado: 26000, obra_pactada: 49000 }) === 75000, 'C5: 26.000 + 49.000 = 75.000');
    ok(H.precioTotal({ precio: 75000, precio_suelo: 25000, precio_construccion: 50000, suelo_pactado: null, obra_pactada: null }) === 75000, 'sin contrato: el de catálogo, parte a parte');
    ok(H.precioTotal({ precio: 30000, precio_suelo: 30000, precio_construccion: null, suelo_pactado: 32000, obra_pactada: null }) === 32000, 'solo suelo: el pactado, no el catálogo de la parcela');
    ok(H.precioTotal({ precio: 41000, precio_suelo: null, precio_construccion: null, suelo_pactado: null, obra_pactada: null }) === 41000, 'sin partes: el precio de la parcela');
    ok(H.precioTotal({ precio: null, precio_suelo: null, precio_construccion: null }) === null, 'sin nada: null, no 0');
    ok(!/fmtConEstimado\(u\.precio\b/.test(datos) && /pon\('u-total', fmtConEstimado\(precioTotal\(u\)/.test(datos), 'la tarjeta usa precioTotal');
    ok(/var dpTotal = precioTotal\(u\);/.test(datos), 'la ficha usa precioTotal');
  }

  // ── cableado ─────────────────────────────────────────────────────────────────────────────────────────────────
  const html = leer('intranet', 'v4', 'proyectos', 'index.html');
  ok(/<script src="\.\.\/assets\/ficha-parcela\.js(\?v=[0-9a-f]+)?" defer><\/script>/.test(html), 'proyectos carga ficha-parcela.js');
  const pos = (s) => html.indexOf(s);
  ok(pos('data-lw="dp-fase-zona"') < pos('data-lw="fp-contratos"') && pos('data-lw="fp-contratos"') < pos('>Precio y cobro<') &&
     pos('data-lw="dp-obra"') < pos('data-lw="fp-pendientes"') && pos('data-lw="fp-pendientes"') < pos('data-lw="fp-docs"') &&
     pos('data-lw="fp-docs"') < pos('data-lw="fp-obra"') && pos('data-lw="fp-obra"') < pos('data-lw="rp-bloque"'),
     'orden: datos → contratos → precio y cobro (con pendientes) → documentos → avance de obra → recordatorio');
  const fp = leer('intranet', 'v4', 'assets', 'ficha-parcela.js');
  ['fp-contratos', 'fp-contratos-cuerpo', 'fp-pendientes', 'fp-docs', 'fp-docs-resumen', 'fp-docs-cuerpo', 'fp-obra', 'fp-obra-cuerpo']
    .forEach((k) => ok(html.indexOf('data-lw="' + k + '"') > 0, 'contenedor ' + k));
  const i18n = leer('contracts', 'assets', 'i18n.js');
  const claves = new Set();
  i18n.replace(/^\s*'((?:[^'\\]|\\.)*)'\s*:/gm, (x, k) => { claves.add(k.replace(/\\'/g, "'")); return x; });
  const frases = new Set();
  fp.replace(/\bT\('((?:[^'\\]|\\.)*)'/g, (x, k) => { frases.add(k); return x; });
  ['Firmado', 'Reabierto', 'Sin firmar', 'Liberado', 'Facturas', 'Recibís', 'Proformas', 'Contratos de la parcela', 'Avance de obra',
   '%n factura', '%n facturas', '%n recibí', '%n recibís', '%n proforma', '%n proformas'].forEach((k) => frases.add(k));
  const faltan = [...frases].filter((k) => !claves.has(k));
  ok(!faltan.length, 'todas las frases tienen inglés; faltan: ' + faltan.join(' | '));

  /* ── inglés de la tarjeta y de la ficha (Calidad, 15-oct-2026) ──────────────────────────────────────────────────
     Con la interfaz en inglés salían en español «Pactado», «Precio y cobro», «Cerrar · volver a…»: el marcado
     estático no llevaba `data-lwt` y nada lo comprobaba. Esto recorre la plantilla de la tarjeta (con la cabecera de
     la vista Lista) y la de la ficha: todo texto visible con letras va marcado (`data-lwt` en su elemento, o
     `data-lwt-nodos` si comparte elemento con un dato) y su clave existe en el diccionario; lo mismo para
     aria-label/title/placeholder. Se saltan los iconos (ligaduras de material-symbols) y los huecos `data-lw` que
     rellena el JS. Una etiqueta nueva sin traducir pone esto en rojo. */
  const EN = (() => { const w = {}; new Function('window', i18n)(w); return w.LW_EN; })();
  const enDic = (k) => Object.prototype.hasOwnProperty.call(EN, k);
  const tramo = (desde, hasta) => {
    const a = html.indexOf(desde), b = html.indexOf(hasta, a);
    ok(a > 0 && b > a, 'index.html tiene el tramo ' + desde);
    return html.slice(a, b);
  };
  const ent = (s) => s.replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
  const attr = (a, nombre) => { const x = new RegExp('\\s' + nombre + '(?:="([^"]*)")?(?=\\s|$)').exec(a); return x ? (x[1] == null ? '' : ent(x[1])) : null; };
  const fugasIdioma = (frag) => {
    const out = [], pila = [];
    const VACIO = /^(input|img|br|hr|meta|link|source|path|circle|rect|line|polyline|polygon)$/i;
    const re = /<(\/?)([a-zA-Z][\w-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|([^<]+)/g;
    let x;
    frag = frag.replace(/<!--[\s\S]*?-->/g, '');
    while ((x = re.exec(frag))) {
      if (x[5] != null) {
        const t = ent(x[5]).trim();
        if (!/\p{L}/u.test(t)) continue;
        if (pila.some((e) => /material-symbols/.test(e.a))) continue;   // icono: el nombre de la ligadura no se traduce
        const p = pila[pila.length - 1] || { a: '' };
        if (attr(p.a, 'data-lw') != null) continue;                       // hueco: lo rellena el JS (con tx)
        const k = attr(p.a, 'data-lwt');
        if (k != null) { if (!enDic(k || t)) out.push('sin inglés: «' + (k || t) + '»'); }
        else if (attr(p.a, 'data-lwt-nodos') != null) { if (!enDic(t)) out.push('sin inglés: «' + t + '»'); }
        else out.push('sin data-lwt: «' + t + '»');
        continue;
      }
      const [, cierra, tag, a, solo] = x;
      if (cierra) { while (pila.length && pila.pop().t !== tag.toLowerCase()); continue; }
      if (pila.some((e) => attr(e.a, 'data-lwt') != null)) out.push('data-lwt con un elemento dentro (lo aplanaría): <' + tag + '>');
      [['aria-label', 'data-lwt-aria'], ['title', 'data-lwt-title'], ['placeholder', 'data-lwt-ph']].forEach(([n0, marca]) => {
        const v = attr(a, n0);
        if (!v || !/\p{L}/u.test(v)) return;
        if (attr(a, marca) == null) out.push(n0 + ' sin ' + marca + ': «' + v + '»');
        else if (!enDic(attr(a, marca) || v)) out.push('sin inglés: «' + v + '»');
      });
      if (!solo && !VACIO.test(tag)) pila.push({ t: tag.toLowerCase(), a: a });
    }
    return out;
  };
  // El propio comprobador caza lo que tiene que cazar (si no, un verde no diría nada).
  ok(fugasIdioma('<div><span class="lw-u-lbl">Pactado</span></div>').length === 1, 'el comprobador caza una etiqueta sin data-lwt');
  ok(fugasIdioma('<span data-lwt>Esto no está en el diccionario</span>').length === 1, 'y una marcada sin entrada');
  ok(fugasIdioma('<button aria-label="Editar unidad"><span class="material-symbols-outlined">edit</span></button>').length === 1, 'y un aria-label sin marcar (el icono no cuenta)');
  ok(fugasIdioma('<span data-lwt>Contrato <b>x</b></span>').some((s) => /aplanaría/.test(s)), 'y un data-lwt con hijos');
  ok(fugasIdioma('<p data-lwt-nodos>Cerrar · volver a <span data-lw="dp-proyecto">este proyecto</span></p>').length === (enDic('Cerrar · volver a') ? 0 : 1), 'data-lwt-nodos con un dato dentro vale');
  const tarjeta = tramo('<div id="d-unidades-cab"', '</div><!-- /d-parcelario-lista -->');
  const ficha = tramo('<div id="cajon-vista-parcela"', '</div><!-- /cajon-vista-parcela -->');
  ok(/data-lw-accion="abrir-detalle-unidad"/.test(tarjeta) && /data-lw="dp-total"/.test(ficha), 'los tramos son la tarjeta y la ficha');
  const fT = fugasIdioma(tarjeta), fF = fugasIdioma(ficha);
  ok(!fT.length, 'tarjeta del parcelario en inglés; fugas: ' + fT.join(' | '));
  ok(!fF.length, 'ficha de la parcela en inglés; fugas: ' + fF.join(' | '));

  /* Lo que pinta el JS de la tarjeta y de la ficha (datos.js): cada tx('…') tiene su inglés, y los textos que se
     escapaban del diccionario el 15-oct ya no salen como literal suelto. */
  const jsT = datos.slice(datos.indexOf('var barraUnidad = function'), datos.indexOf('function volverAProyecto'));
  ok(jsT.length > 1000, 'tramo de datos.js de la tarjeta y la ficha');
  const sinEn = [];
  jsT.replace(/\btx\('((?:[^'\\]|\\.)*)'/g, (y, k) => { if (!enDic(k)) sinEn.push(k); return y; });
  ok(!sinEn.length, 'cada tx() de la tarjeta y la ficha tiene inglés; faltan: ' + sinEn.join(' | '));
  ['sin cartera', 'con Carta', 'Sin socio', 'sin contrato', 'Reservada con Carta de Reserva firmada: aún no es compraventa', 'Editar ', 'Socio: ', 'Arquitecto: ', ' unidad', ' unidades']
    .forEach((lit) => {
      const sueltos = jsT.split("'" + lit + "'").length - jsT.split("tx('" + lit + "'").length;
      ok(sueltos === 0, '«' + lit + '» pasa por tx() en la tarjeta y la ficha');
    });
  ok(/function estadoVisible\(e\) \{ return ts\(etiquetaEstado\(e\)\); \}/.test(datos) && !/textContent = etiquetaEstado\(/.test(datos),
     'la pastilla de estado (tarjeta, ficha y chips) sale en el idioma de la interfaz');
  ok(['Disponible', 'Reservada', 'Bloqueada', 'Vendida', 'Cobrada', 'No disponible', 'Todas'].every(enDic), 'los seis estados y «Todas» tienen inglés');
  ok(/lwIdiomaAplicar\(caja\)/.test(jsT), 'las tarjetas clonadas se traducen al pintarlas (no dependen de cuándo corrió nav.js)');
  console.log('ficha_parcela.test.js: ' + n + ' comprobaciones OK');
})().catch((e) => { console.error(e); process.exit(1); });
