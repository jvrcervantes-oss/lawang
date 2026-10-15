/* node recibi_historico_exento.test.js — recibí histórico sin justificante (LAW-40), 15-oct-2026.
   La pantalla libra del justificante con el MISMO límite que guardar_recibi (Seguridad, 15-oct-2026): la marca,
   ningún justificante guardado y su propio contrato. Falla si:
   1) `histSinJustExento` de editores.js deja pasar un recibí que ya tuvo justificante, que cambió de contrato o
      que no tiene contrato;
   2) el rótulo del justificante o la comprobación de guardar dejan de usar esa misma función (volverían a mirar
      solo la marca y el usuario se enteraría por el error del servidor). */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SRC = fs.readFileSync(path.join(__dirname, 'editores.js'), 'utf8');
const m = SRC.match(/function histSinJustExento\(\) \{[\s\S]*?\n {8}\}/);
assert.ok(m, 'no se encuentra histSinJustExento en editores.js');

function exento(existente, contratoActual) {
  const ctx = { existente, estadoContrato: { id: contratoActual } };
  vm.createContext(ctx);
  vm.runInContext(m[0] + '\n;this.__r = histSinJustExento();', ctx);
  return ctx.__r;
}

let n = 0;
const ok = (c, msg) => { assert.ok(c, msg); n++; };
const base = { historico_sin_justificante: true, justificantes: [], contrato_id: 'K1' };

ok(exento(base, 'K1') === true, 'histórico sin justificante en su contrato: exento');
ok(exento({ ...base, justificantes: undefined }, 'K1') === true, 'sin columna justificantes: exento');
ok(exento({ ...base, historico_sin_justificante: false }, 'K1') === false, 'sin la marca: no exento');
ok(exento({ ...base, justificantes: [{ path: 'x.pdf' }] }, 'K1') === false, 'ya tuvo justificante: no exento (H7)');
ok(exento(base, 'K2') === false, 'llevado a otro contrato: no exento (H8)');
ok(exento({ ...base, contrato_id: null }, null) === false, 'sin contrato: no exento');
ok(exento(null, 'K1') === false, 'recibí nuevo: no exento');

// 2) los dos usos pasan por la función, ninguno mira la marca a secas
ok(/var esHistSinJust = histSinJustExento\(\);/.test(SRC), 'el rótulo del justificante usa histSinJustExento');
ok(/!justificantes\.length && !histSinJustExento\(\)\) return \{ error/.test(SRC), 'guardar usa histSinJustExento');
const usos = SRC.split('\n').filter((l) => /existente\.historico_sin_justificante/.test(l));
ok(usos.length === 1, 'la marca solo se lee dentro de histSinJustExento (hay ' + usos.length + ')');

console.log('recibi_historico_exento: ' + n + ' comprobaciones OK');
