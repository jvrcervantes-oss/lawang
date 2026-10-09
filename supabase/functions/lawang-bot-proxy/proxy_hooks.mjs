// Gancho del test (solo node): sustituye el import jsr de supabase-js por un doble. Ver lawang_bot_proxy.test.js.
export async function resolve(esp, ctx, siguiente) {
  if (esp.startsWith('jsr:@supabase/supabase-js')) return { url: new URL('./supabase_falso.mjs', import.meta.url).href, shortCircuit: true };
  return siguiente(esp, ctx);
}
