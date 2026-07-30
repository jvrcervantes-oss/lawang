/* Quién compra en un contrato de Lawang, normalizado a una sola lista.
   Fuera del HTML para poder pasarle un test de verdad (compradores.test.js).
   Se carga con <script src> en index.html y con require() en node.

   Dónde vive cada comprador en `contratos.datos` (verificado 30-jul-2026 sobre
   los 26 contratos reales):
   - Adquiriente I  → `datos.fields.adq1_*`, en TODOS los contratos.
   - Adquiriente II, III, IV… → `datos.compradores[]`, que es como los guarda
     /contracts (COMPRADORES[0] es el II — de ahí el `romano(i+2)` de app.html).
   - `adq2_*`/`adq3_*` son el formato viejo: solo 2 contratos los llevan, y los
     nuevos los dejan vacíos. Se leen igual o esos dos pierden compradores.

   Leer solo `adq1..3_*` (lo que hacía la factura hasta hoy) deja fuera a los
   adquirientes II+ de CC00007, CC00008 (3 extras), RP00012, RP00016 y RP00018:
   la factura salía a un nombre cuando el contrato va a varios. */

const trim = v => String(v == null ? '' : v).trim();

function compradoresDeContrato(fields, extras){
  const f = fields || {};
  const crudos = [
    { nombre:f.adq1_nombre, pasaporte:f.adq1_pasaporte, domicilio:f.adq1_domicilio, email:f.adq1_email },
    { nombre:f.adq2_nombre, pasaporte:f.adq2_pasaporte, domicilio:f.adq2_domicilio, email:f.adq2_email },
    { nombre:f.adq3_nombre, pasaporte:f.adq3_pasaporte, domicilio:f.adq3_domicilio, email:f.adq3_email }
  ].concat(Array.isArray(extras) ? extras : []);

  const vistos = new Set(), lista = [];
  crudos.forEach(c => {
    const nombre = trim(c && c.nombre).replace(/\s+/g, ' ');
    if(!nombre) return;
    const clave = nombre.toLowerCase();
    if(vistos.has(clave)) return;   // un contrato viejo puede repetir a la misma persona en adq2_* y en compradores[]
    vistos.add(clave);
    lista.push({ nombre, pasaporte:trim(c.pasaporte), domicilio:trim(c.domicilio), email:trim(c.email) });
  });
  return lista;
}

// La factura va a nombre de todos los que firman el contrato, no solo del primero.
function nombresFactura(lista){ return (lista || []).map(c => c.nombre).join(' · '); }

/* Documentos de identidad. Con un comprador va el número suelto; con varios se
   etiqueta con el nombre, porque si no no se sabe de quién es cada pasaporte.
   A quien no tenga pasaporte guardado no se le inventa nada: no aparece. */
function documentosFactura(lista){
  const con = (lista || []).filter(c => c.pasaporte);
  if(!con.length) return '';
  if((lista || []).length === 1) return con[0].pasaporte;
  return con.map(c => c.nombre + ': ' + c.pasaporte).join(' · ');
}

// Primer valor no vacío de un campo (domicilio/email de notificaciones de la factura).
function primerDato(lista, campo){
  const c = (lista || []).find(x => x[campo]);
  return c ? c[campo] : '';
}

if(typeof module !== 'undefined') module.exports = { compradoresDeContrato, nombresFactura, documentosFactura, primerDato };
