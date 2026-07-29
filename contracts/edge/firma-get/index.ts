// firma-get — el comprador abre firmar.html?t=<token> y esta función le
// devuelve el HTML del contrato (snapshot de confianza congelado por el estudio)
// para que lo lea antes de firmar. NO expone la tabla a anon: todo pasa por aquí
// con service_role y validación del token. Desplegar con verify_jwt=false.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
// Origen restringido: con '*' cualquier web podia empotrar el contrato real del
// comprador y hacerlo pasar por suya. El token sigue siendo la credencial, pero
// no hay motivo para que un tercero pueda leer la respuesta desde su pagina.
const ORIGENES = [
  'https://lawangproperties.com',
  'https://www.lawangproperties.com',
  'https://sumbahills.lawangproperties.com',
];
const corsFor = (req: Request) => {
  const o = req.headers.get('origin') ?? '';
  const ok = ORIGENES.includes(o) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o);
  return {
    'Access-Control-Allow-Origin': ok ? o : ORIGENES[0],
    'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin', // sin esto una CDN cachea el header de un origen y se lo sirve a otro
  };
};

async function sha256hex(s: string): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (o: unknown, s = 200) =>
    new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'metodo' }, 405);
  try {
    const { token } = await req.json().catch(() => ({}));
    if (!token || typeof token !== 'string') return json({ error: 'token' }, 400);
    const hash = await sha256hex(token);

    const { data: row } = await sb
      .from('contrato_firmas')
      .select('id, estado, expira_en, snapshot_path, firmante_nombre, contratos(numero, tipo)')
      .eq('token_hash', hash)
      .maybeSingle();

    if (!row) return json({ error: 'no_encontrado' }, 404);
    if (row.estado === 'firmado') return json({ error: 'ya_firmado' }, 409);
    if (row.estado !== 'pendiente') return json({ error: 'no_disponible' }, 409);
    if (new Date(row.expira_en) < new Date()) return json({ error: 'expirado' }, 410);

    const { data: file, error } = await sb.storage.from('contratos-firmados').download(row.snapshot_path);
    if (error || !file) return json({ error: 'sin_snapshot' }, 500);
    let html = await file.text();
    // en pantalla las zonas de firma pendientes van vacías; los centinelas
    // (%%FIRMA_ADQUIRIENTE%% del I, %%FIRMA_ADQ_n%% de los demás — firma en
    // cadena) solo los rellena firma-submit con la firma real de cada turno.
    html = html.replace(/%%FIRMA_ADQ(?:UIRIENTE|_\d+)%%/g, '');

    const c = (row as any).contratos;
    return json({ html, numero: c?.numero ?? null, tipo: c?.tipo ?? null, firmante_nombre: row.firmante_nombre ?? null });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
