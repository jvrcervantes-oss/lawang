// deck-documento — descarga PÚBLICA de un documento subido a Documentación y publicado en el investor deck
// (owner, 28-sep-2026: «subo el dosier de un proyecto y no aparece en el investor deck»).
//
// Llamadores con nombre: los dos decks (investor-deck/index.php y investor-deck/palmfield/index.html), que reciben
// esta url de la RPC anon investor_deck_documentos. verify_jwt=false: quien abre el deck no tiene sesión.
//
// GET ?id=<uuid> → la RPC investor_deck_documento_ruta (solo service_role) decide si ese documento lo puede ver el
// público AHORA (publicado, no confidencial, deck abierto, tipo y MIME permitidos): la ruta sale de la base, nunca
// de la petición. Si sí, URL firmada de 60 s con descarga forzada y 302. Si no, o si algo falla: el MISMO 404,
// sin decir por qué (no sirve de oráculo). Revisión previa Seguridad + Desarrollo, 28-sep-2026.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

const FIRMA_SEG = 60;   // basta para que empiece la descarga; una ya empezada termina aunque caduque
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// La misma forma que exige la base (investor_deck_documento_visible): si una fila futura trae otra cosa, no se firma.
const RUTA = /^proyectos\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(pdf|jpe?g|png|webp|docx|xlsx|pptx)$/;

const CABECERAS = {
  'Cache-Control': 'no-store',            // una redirección guardada apuntaría a una firma ya caducada
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
};

const noEncontrado = () => new Response('Document not available.', {
  status: 404, headers: { ...CABECERAS, 'Content-Type': 'text/plain; charset=utf-8' },
});

// Nombre de descarga por lista blanca: sin acentos, solo [A-Za-z0-9 ._-], 80 caracteres. La extensión, de la ruta.
function nombreDescarga(titulo: unknown, ext: string): string {
  const base = String(titulo ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9 ._-]+/g, ' ').replace(/\s+/g, ' ').trim().replace(/^[.\s]+|[.\s]+$/g, '').slice(0, 80);
  return (base || 'document') + '.' + ext;
}

Deno.serve(async (req) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return new Response('Method not allowed.', {
      status: 405, headers: { ...CABECERAS, 'Allow': 'GET, HEAD', 'Content-Type': 'text/plain; charset=utf-8' },
    });
  }
  const id = new URL(req.url).searchParams.get('id') ?? '';
  if (!UUID.test(id)) return noEncontrado();
  try {
    const { data, error } = await admin.rpc('investor_deck_documento_ruta', { p_id: id });
    // Al servidor sí se le dice qué pasó (revisor, 28-sep): un 404 que nadie ve en los logs lo acabaría descubriendo
    // el inversor. Al cliente, el mismo 404 de siempre.
    if (error) console.error('deck-documento: la RPC de ruta falló', id, error.message);
    const fila = !error && Array.isArray(data) ? data[0] : null;
    const ruta = fila ? String(fila.path ?? '') : '';
    const m = RUTA.exec(ruta);
    if (!m) return noEncontrado();
    const { data: firma, error: eF } = await admin.storage.from('documentacion')
      .createSignedUrl(ruta, FIRMA_SEG, { download: nombreDescarga(fila.titulo, m[1]) });
    if (eF || !firma?.signedUrl) {
      console.error('deck-documento: no se pudo firmar', id, eF?.message ?? 'sin url');
      return noEncontrado();
    }
    return new Response(null, { status: 302, headers: { ...CABECERAS, 'Location': firma.signedUrl } });
  } catch (e) {
    console.error('deck-documento: excepción', id, e instanceof Error ? e.message : String(e));
    return noEncontrado();
  }
});
