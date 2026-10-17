// Gancho del arnés de pruebas de ficheros-contrato (solo node; Deno no lo lee): el import `jsr:@supabase/supabase-js@2` de
// index.ts pasa a sb_falso.mjs, que delega en el doble que monta cada prueba. Ver reenvia_caducada.test.js.
export async function resolve(especificador, contexto, siguiente) {
  if (especificador.startsWith('jsr:@supabase/supabase-js')) {
    return { url: new URL('./sb_falso.mjs', import.meta.url).href, shortCircuit: true };
  }
  return siguiente(especificador, contexto);
}
