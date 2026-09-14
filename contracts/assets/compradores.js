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

/* ── QUE HACE FALTA PARA DAR DE ALTA UN COMPRADOR — 14-sep-2026 ─────────────
   Owner: «exige los campos de nombre, email, prefijo + telefono, nacionalidad y
   pasaporte. Sin eso no se puede crear un cliente».

   Vive AQUI y no dentro del formulario porque hay DOS pantallas que crean
   `clients`: `/intranet/compradores/` (el formulario vivo) y el editor nativo de
   la v4 (`intranet/v4/assets/editores.js`), que va a sustituirla. Una lista de
   campos obligatorios escrita a mano en los dos sitios es, literalmente, el
   fallo que esta suite ya ha pagado tres veces: la copia diverge y la pantalla
   que se olvido sigue dando de alta fichas a medias sin que se note.

   Devuelve la lista de lo que FALTA, no un booleano: el aviso tiene que decir
   que campos son, o el agente prueba a ciegas.

   Solo se exige al CREAR, nunca al editar — decision explicita: hay mas de 200
   fichas antiguas sin nacionalidad ni pasaporte, y exigirlo tambien al guardar
   las dejaria imposibles de corregir en cualquier otra cosa. */
const CAMPOS_ALTA_COMPRADOR = [
  ['full_name',       'Nombre completo'],
  ['email',           'Email'],
  ['prefijo',         'Prefijo del telefono'],
  ['telefono',        'Telefono'],
  ['nationality',     'Nacionalidad'],
  ['passport_number', 'Pasaporte / NPWP']
];

function faltanDatosComprador(d){
  const v = d || {};
  const faltan = CAMPOS_ALTA_COMPRADOR
    .filter(([k]) => !trim(v[k]))
    .map(([, etiqueta]) => etiqueta);
  /* Un correo mal escrito no es un campo vacio, pero rompe lo mismo: es la llave
     con la que el comprador entra al portal y a la que se le manda el contrato.
     Comprobacion minima a proposito (algo@algo.algo) — validar RFC 5322 aqui
     rechaza direcciones reales, y el que sea falso pero bien formado lo caza el
     primer envio, no una expresion regular. */
  if(trim(v.email) && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(trim(v.email)))
    faltan.push('Email (no parece una direccion valida)');
  return faltan;
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

if(typeof module !== 'undefined') module.exports = { compradoresDeContrato, nombresFactura, documentosFactura, primerDato,
  CAMPOS_ALTA_COMPRADOR, faltanDatosComprador };
