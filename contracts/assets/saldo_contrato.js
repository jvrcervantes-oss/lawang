/* Saldo del contrato — qué se ha facturado, qué se ha cobrado, qué queda (5-oct-2026, owner).
   ════════════════════════════════════════════════════════════════════════════
   Capa compartida (Regla 0 de contexto/suite_lawang.md): la usan la ficha de la factura y el editor de
   documentos de v4. El editor clásico de /intranet/facturas/ NO la pinta todavía: el tope lo hace valer
   igualmente el servidor, solo falta el aviso previo. Una copia por pantalla sería la forma de que dos
   pantallas den dos cifras.

   LAS CIFRAS NO SE CALCULAN AQUÍ. Salen de la función `contrato_saldo` de la base, que usa la MISMA
   cuenta (`_cadena_saldo`) con la que `factura_guarda` hace valer el tope: lo que se ve y lo que se
   exige no pueden divergir. Este fichero solo las pide y las pinta.

   POR QUÉ POR CADENA Y NO POR CONTRATO SUELTO. La factura de un contrato de construcción incluye el pago
   del suelo de su Bloqueo padre: medido en producción, 39 de 122 contratos «se pasaban» de su precio si
   se miraban sueltos y solo 3 de 103 cadenas. La cadena es la raíz + sus hijos, sin la Carta de Reserva
   (declara el mismo importe que el contrato que la sustituye: ver cuentaGrupo en operaciones-cuentas.js).

   LAS MARCAS POR HITO son una lectura, no un dato guardado: un hito cuenta como facturado si alguna
   línea de una factura viva tiene exactamente su descripción. Un recibí se aplica a la factura entera,
   no a una línea: el cobrado de la factura se reparte por orden de líneas. Si alguien reescribe a mano
   la descripción de una línea, esa línea deja de contar para el hito (y el servidor sigue cuadrando el
   total de la cadena, que es lo que importa al dinero). */

(function (root) {
  'use strict';
  function r2(n) { return Math.round((Number(n) || 0) * 100) / 100; }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  /* hitos: [{ ... }] tal como los pinta cada pantalla; descFn(h) = la descripción que esa pantalla pone
     en la línea al pulsar el hito (`descHito` / `descHitoDoc`). facturas: saldo.facturas. */
  function lwSaldoMarcasHitos(hitos, facturas, descFn) {
    var out = (hitos || []).map(function () { return { facturado: 0, cobrado: 0, facturas: [] }; });
    var idx = {};
    (hitos || []).forEach(function (h, i) {
      var d = String(descFn(h) || '').trim();
      if (d && idx[d] === undefined) idx[d] = i;
    });
    (facturas || []).forEach(function (f) {
      var resto = Math.max(Number(f.cobrado) || 0, 0);
      (f.lineas || []).forEach(function (l) {
        var imp = Number(l.importe) || 0;
        var pago = Math.min(resto, Math.max(imp, 0));
        resto = r2(resto - pago);
        var i = idx[String(l.descripcion || '').trim()];
        if (i === undefined) return;
        out[i].facturado = r2(out[i].facturado + imp);
        out[i].cobrado = r2(out[i].cobrado + pago);
        if (out[i].facturas.indexOf(f.numero) < 0) out[i].facturas.push(f.numero);
      });
    });
    return out;
  }

  /* Lo que queda por facturar si el documento que se edita ya está guardado: el servidor cuenta también
     ese documento dentro de «facturado», y aquí se está reescribiendo. */
  function lwSaldoPorFacturar(saldo, propioId) {
    if (!saldo || saldo.por_facturar == null) return null;
    var propio = (saldo.facturas || []).filter(function (f) { return f.id === propioId; })[0];
    var suyo = propio ? (Number(propio.subtotal != null ? propio.subtotal : propio.total) || 0) : 0; // sin impuesto: la cuenta del servidor es sobre el subtotal
    return r2(Number(saldo.por_facturar) + suyo);
  }

  /* Aviso en la pantalla cuando el documento se pasa. NO manda: el que impide guardar es el servidor. */
  function lwSaldoAviso(saldo, totalDoc, propioId, fmt) {
    var pf = lwSaldoPorFacturar(saldo, propioId);
    if (pf == null || !(totalDoc > 0)) return '';
    if (totalDoc <= pf + 0.005) return '';
    return 'Este documento suma ' + fmt(totalDoc, saldo.moneda) + ' y al contrato le quedan ' + fmt(pf, saldo.moneda)
      + ' por facturar: no se podrá guardar.';
  }

  function lwSaldoEstilo() {
    if (typeof document === 'undefined' || document.getElementById('lw-saldo-css')) return;
    var s = document.createElement('style'); s.id = 'lw-saldo-css';
    s.textContent =
      '.lw-saldo{border:1px solid #E4DCCB;border-radius:12px;padding:12px 14px;background:#fff;margin:10px 0}' +
      '.lw-saldo .lw-s-t{font:600 11px/1.2 inherit;letter-spacing:.1em;text-transform:uppercase;color:#6E7B5A;margin:0 0 8px}' +
      '.lw-saldo .lw-s-c{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}' +
      '@media (max-width:560px){.lw-saldo .lw-s-c{grid-template-columns:repeat(2,minmax(0,1fr))}}' +
      '.lw-saldo .lw-s-k{font-size:10.5px;letter-spacing:.08em;text-transform:uppercase;color:#8A8474;font-weight:600}' +
      '.lw-saldo .lw-s-v{font-size:15px;font-weight:700;white-space:nowrap;font-variant-numeric:tabular-nums;color:#2E3437}' +
      '.lw-saldo .lw-s-v.lw-l{color:#104C4F}' +
      '.lw-saldo .lw-s-b{display:flex;height:10px;border-radius:99px;overflow:hidden;background:#EFEEE8;margin:10px 0 4px}' +
      '.lw-saldo .lw-s-b i{display:block;height:100%}' +
      '.lw-saldo .lw-s-c6{grid-template-columns:repeat(6,minmax(0,1fr))}' +
      '@media (max-width:760px){.lw-saldo .lw-s-c6{grid-template-columns:repeat(2,minmax(0,1fr))}}' +
      '.lw-saldo .lw-s-v.lw-n{color:#104C4F}.lw-saldo .lw-s-v.lw-r{color:#9E2F26}' +
      '.lw-saldo .lw-s-p{background:repeating-linear-gradient(45deg,#7FB3B5,#7FB3B5 4px,#A9CDCE 4px,#A9CDCE 8px);transition:width .15s ease-out}' +
      '.lw-saldo .lw-s-p.lw-r{background:repeating-linear-gradient(45deg,#9E2F26,#9E2F26 4px,#C46A62 4px,#C46A62 8px)}' +
      '.lw-saldo .lw-s-l{display:flex;flex-wrap:wrap;gap:3px 12px;font-size:11px;color:#75786E}' +
      '.lw-saldo .lw-s-l b{display:inline-block;width:9px;height:9px;border-radius:99px;margin-right:4px;vertical-align:-1px}' +
      '.lw-saldo .lw-s-pb{background:#7FB3B5!important}.lw-saldo .lw-s-pb.lw-r{background:#9E2F26!important}' +
      '@media (prefers-reduced-motion:reduce){.lw-saldo .lw-s-p{transition:none}}' +
      '.lw-saldo .lw-s-n{font-size:12px;color:#75786E;margin:6px 0 0;line-height:1.45}' +
      '.lw-saldo .lw-s-av{font-size:12.5px;margin:8px 0 0;padding:8px 10px;border-radius:8px;background:#FBF3E4;color:#8A6A34}' +
      '.lw-mk{display:flex;flex-wrap:wrap;gap:5px;margin-top:5px}' +
      '.lw-mk span{font-size:10.5px;font-weight:600;padding:1px 8px;border-radius:99px;letter-spacing:.03em;white-space:nowrap}' +
      '.lw-mk .lw-f{background:#FBF3E4;color:#8A6A34}.lw-mk .lw-c{background:#E4F0DA;color:#3F5230}';
    document.head.appendChild(s);
  }

  /* fmt(n, moneda) → texto: lo pone la pantalla (fmtMoneda), para que el formato sea el de siempre.
     borrador (solo el editor): lo que suman los conceptos del documento que se está escribiendo. La barra
     enseña ese tramo en vivo y lo que quedaría por facturar; si se pasa, el tramo sale en rojo y el aviso
     lo dice. El documento ya guardado se cuenta una vez: su importe entra como borrador, no como facturado. */
  function lwSaldoHTML(saldo, fmt, propioId, borrador) {
    if (!saldo) return '';
    var mon = saldo.moneda, pr = saldo.precio == null ? null : Number(saldo.precio);
    var fa = Number(saldo.facturado) || 0, co = Number(saldo.cobrado) || 0, pc = Number(saldo.por_cobrar) || 0;
    var pf = saldo.por_facturar == null ? null : Number(saldo.por_facturar);
    var base = pr && pr > 0 ? pr : null;
    var prev = borrador == null ? null : r2(Math.max(Number(borrador) || 0, 0));
    var pfAdj = lwSaldoPorFacturar(saldo, propioId);
    var pasa = false;
    if (prev != null) {
      var propio = (saldo.facturas || []).filter(function (f) { return f.id === propioId; })[0];
      if (propio) fa = r2(fa - (Number(propio.subtotal != null ? propio.subtotal : propio.total) || 0));
      pasa = pfAdj != null && prev > pfAdj + 0.005;
    }
    var w = function (x) { return base ? Math.max(0, Math.min(100, x / base * 100)).toFixed(2) : '0'; };
    var nota = saldo.sin_precio
      ? 'Algún contrato de esta venta no tiene precio fijado: sin precio no hay tope, y «por facturar» no se puede calcular.'
      : 'Venta ' + esc(saldo.cadena) + ': precio de todos sus contratos (sin la Carta de Reserva), sin impuestos.';
    var quedara = pfAdj == null || prev == null ? null : Math.max(r2(pfAdj - prev), 0);
    var cif = function (k, v, cls) { return '<div><div class="lw-s-k">' + k + '</div><div class="lw-s-v' + (cls ? ' ' + cls : '') + '">' + v + '</div></div>'; };
    var cifras = cif('Precio', pr == null ? '—' : esc(fmt(pr, mon))) + cif('Facturado', esc(fmt(fa, mon))) +
      cif('Cobrado', esc(fmt(co, mon)), 'lw-l') + cif('Por cobrar', esc(fmt(pc, mon)));
    if (prev != null) cifras += cif('Este documento', esc(fmt(prev, mon)), pasa ? 'lw-r' : 'lw-n') +
      cif('Quedará por facturar', quedara == null ? '—' : esc(fmt(quedara, mon)), pasa ? 'lw-r' : '');
    else cifras += cif('Por facturar', pf == null ? '—' : esc(fmt(pf, mon)));
    var restoBarra = base ? Math.max(base - fa, 0) : 0;
    var seg = prev == null ? '' : '<i class="lw-s-p' + (pasa ? ' lw-r' : '') + '" style="width:' + w(Math.min(prev, restoBarra || prev)) + '%"></i>';
    var aviso = pasa ? lwSaldoAviso(saldo, prev, propioId, fmt) : '';
    return '<div class="lw-saldo" data-lw="saldo-contrato"><p class="lw-s-t">Saldo del contrato</p><div class="lw-s-c' + (prev != null ? ' lw-s-c6' : '') + '">' +
      cifras + '</div>' +
      (base ? '<div class="lw-s-b" role="img" aria-label="Cobrado ' + esc(fmt(co, mon)) + ', facturado sin cobrar ' + esc(fmt(Math.max(fa - co, 0), mon)) +
        (prev != null ? ', este documento ' + esc(fmt(prev, mon)) : '') + '"><i style="width:' + w(co) + '%;background:#104C4F"></i><i style="width:' + w(Math.max(fa - co, 0)) + '%;background:#C9892B"></i>' + seg + '</div>' +
        (prev != null ? '<div class="lw-s-l"><span><b style="background:#104C4F"></b>Cobrado</span><span><b style="background:#C9892B"></b>Facturado sin cobrar</span><span><b class="lw-s-pb' + (pasa ? ' lw-r' : '') + '"></b>Este documento</span></div>' : '') : '') +
      '<p class="lw-s-n">' + nota + '</p>' + (aviso ? '<p class="lw-s-av" data-lw="aviso-tope">' + esc(aviso) + '</p>' : '') + '</div>';
  }

  function lwSaldoMarcaHTML(m, moneda, fmt) {
    if (!m || (!m.facturado && !m.cobrado)) return '';
    return '<span class="lw-mk" data-lw="marca-hito">' +
      (m.facturado ? '<span class="lw-f" title="' + esc(m.facturas.join(', ')) + '">Facturado ' + esc(fmt(m.facturado, moneda)) + '</span>' : '') +
      (m.cobrado ? '<span class="lw-c">Cobrado ' + esc(fmt(m.cobrado, moneda)) + '</span>' : '') + '</span>';
  }

  /* Pide el saldo. Una consulta caída no es «saldo 0»: devuelve null y la pantalla no pinta nada. */
  function lwSaldoCarga(sb, contratoId) {
    if (!sb || !contratoId) return Promise.resolve(null);
    return sb.rpc('contrato_saldo', { p_contrato: contratoId }).then(function (r) {
      if (r.error) { console.error('saldo del contrato:', r.error.message); return null; }
      return r.data || null;
    });
  }

  var api = { lwSaldoMarcasHitos: lwSaldoMarcasHitos, lwSaldoPorFacturar: lwSaldoPorFacturar, lwSaldoAviso: lwSaldoAviso,
              lwSaldoEstilo: lwSaldoEstilo, lwSaldoHTML: lwSaldoHTML, lwSaldoMarcaHTML: lwSaldoMarcaHTML, lwSaldoCarga: lwSaldoCarga };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else Object.keys(api).forEach(function (k) { root[k] = api[k]; });
})(typeof window !== 'undefined' ? window : this);
