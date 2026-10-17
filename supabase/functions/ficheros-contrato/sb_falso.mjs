// Doble de supabase-js para las pruebas de ficheros-contrato (solo node). Cada cliente lo fabrica `globalThis.__sbFalso`,
// que monta la prueba: así el MISMO index.ts habla con una base de mentira, sin red.
export function createClient(url, clave, opciones) {
  return globalThis.__sbFalso(clave, opciones);
}
