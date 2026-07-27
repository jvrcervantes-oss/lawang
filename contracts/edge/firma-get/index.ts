// firma-get — el comprador abre firmar.html?t=<token> y esta función le
// devuelve el HTML del contrato (snapshot de confianza congelado por el estudio)
// para que lo lea antes de firmar. NO expone la tabla a anon: todo pasa por aquí
// con service_role y validación del token. Desplegar con verify_jwt=false.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });

async function sha256hex(s: string): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
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
    // en pantalla la zona de firma va vacía (es donde firmará); el centinela solo
    // lo rellena firma-submit con la firma real.
    html = html.replaceAll('%%FIRMA_ADQUIRIENTE%%', '');

    const c = (row as any).contratos;
    return json({ html, numero: c?.numero ?? null, tipo: c?.tipo ?? null, firmante_nombre: row.firmante_nombre ?? null });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
