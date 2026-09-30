// Gancho de resolución del arnés de pruebas (solo node; Deno no lo lee). Sustituye el import de
// `npm:nodemailer@…` de index.ts por un doble que no abre ninguna conexión. Ver arnes.mjs.
export async function resolve(especificador, contexto, siguiente) {
  if (especificador.startsWith('npm:nodemailer')) {
    return { url: new URL('./nodemailer_falso.mjs', import.meta.url).href, shortCircuit: true };
  }
  return siguiente(especificador, contexto);
}
