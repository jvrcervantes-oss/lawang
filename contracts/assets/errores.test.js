/* Test de lwErrorHumano (suite-comun.js). `node contracts/assets/errores.test.js`.
   ============================================================================
   Cada caso es un error REAL que la suite ha enseñado en crudo alguna vez
   (22-sep-2026). La regla que protege: lo NUESTRO se enseña tal cual, lo de
   Postgres/PostgREST/Storage se traduce, y nunca se tapa un mensaje ya escrito
   para la persona. */
global.window = {};
global.console = Object.assign({}, console, { error: () => {} });   // el crudo va a consola; aquí no hace ruido
const { lwErrorHumano: h } = require('./suite-comun.js');

let fallos = 0;
function es(entrada, prefijo, esperado, porque) {
  const dio = h(entrada, prefijo);
  if (dio !== esperado) {
    fallos++;
    console.log(`  FALLA  ${JSON.stringify(entrada)} → ${JSON.stringify(dio)}\n         se esperaba ${JSON.stringify(esperado)}\n         ${porque}`);
  }
}

// ── Lo NUESTRO pasa tal cual, sea cual sea el código ────────────────────────
es({ code: 'P0001', message: 'Esta operación tiene una comisión pagada: resuélvelo a mano' }, null,
   'Esta operación tiene una comisión pagada: resuélvelo a mano', 'RAISE propio con P0001');
es({ code: '23514', message: 'el recibí necesita un justificante de pago adjunto' }, 'No se pudo guardar',
   'No se pudo guardar: el recibí necesita un justificante de pago adjunto',
   'guardar_recibi usa 23514 con texto nuestro: un mapa por código lo tapaba (hallazgo Desarrollo)');
es({ code: '42501', message: 'sin permiso para crear recibís' }, null,
   'sin permiso para crear recibís', '42501 con texto nuestro no es «permission denied»');
es({ code: '23503', message: 'La ficha de X tiene documentos a su nombre (INV-1). Reasígnalos antes de borrar esta.' }, null,
   'La ficha de X tiene documentos a su nombre (INV-1). Reasígnalos antes de borrar esta.',
   'borrar_comprador reutiliza 23503 a propósito');

// ── Lo de Postgres se traduce, por plantilla inglesa ─────────────────────────
es({ code: '23503', message: 'update or delete on table "clients" violates foreign key constraint "facturas_client_id_fkey" on table "facturas"' }, 'No se pudo borrar',
   'No se pudo borrar: Está enlazado a otros datos y no se puede borrar', 'FK al borrar el padre');
es({ code: '23503', message: 'insert or update on table "facturas" violates foreign key constraint "facturas_contrato_id_fkey"' }, null,
   'Apunta a un dato que ya no existe: recarga y vuelve a intentarlo', 'FK al escribir el hijo: la otra dirección');
es({ code: '23505', message: 'duplicate key value violates unique constraint "facturas_numero_key"' }, null,
   'Ya existe uno igual', 'UNIQUE');
es({ code: '23514', message: 'new row for relation "facturas" violates check constraint "facturas_contrato_obligatorio"' }, 'No se pudo borrar',
   'No se pudo borrar: Un dato no cumple una regla del sistema', 'el error del 22-sep, tal como lo vio el owner');
es({ code: '42501', message: 'new row violates row-level security policy for table "contratos"' }, null,
   'No tienes permiso para hacer esto', 'RLS');
es({ code: '42501', message: 'permission denied for table clients' }, null,
   'No tienes permiso para hacer esto', 'sin GRANT');
es({ code: '23502', message: 'null value in column "sociedad" of relation "facturas" violates not-null constraint' }, null,
   'Falta un dato obligatorio', 'NOT NULL');

// ── PostgREST, red y Storage ─────────────────────────────────────────────────
es({ code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' }, null,
   'No existe o no tienes acceso', '.single() con 0 filas: no existe o la RLS lo esconde');
es({ code: 'PGRST301', message: 'JWT expired' }, null,
   'Tu sesión ha caducado: vuelve a entrar', 'token caducado: accionable');
es({ code: '', message: 'TypeError: Failed to fetch' }, 'No se pudo cargar',
   'No se pudo cargar: No hay conexión con la base: comprueba la red y vuelve a intentarlo',
   'supabase-js devuelve code vacío en fallo de red: un helper que solo mire code nunca entra aquí');
es(new TypeError('Failed to fetch'), null,
   'No hay conexión con la base: comprueba la red y vuelve a intentarlo', 'fetch nativo');
es({ statusCode: '413', message: 'The object exceeded the maximum allowed size' }, 'No se pudo subir',
   'No se pudo subir: El fichero es demasiado grande', 'Storage trae statusCode, no SQLSTATE');
es({ statusCode: '404', message: 'Object not found' }, null,
   'El fichero no está donde debería', 'Storage 404');

// ── Bordes ───────────────────────────────────────────────────────────────────
es(null, 'No se pudo guardar', 'No se pudo guardar: Algo ha fallado', 'sin error no se revienta el catch');
es('texto suelto', null, 'texto suelto', 'un string se enseña');
es({ message: '' }, null, 'Algo ha fallado', 'mensaje vacío');

if (fallos) { console.log(`\n${fallos} fallo(s)`); process.exit(1); }
console.log('OK errores.test.js — lo nuestro se enseña, lo de Postgres se traduce');
