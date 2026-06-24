<?php
require __DIR__ . '/bootstrap.php';
$agent = require_agent();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail('Método no permitido', 405);
require_same_origin();
csrf_check();

$in   = json_in();
$slug = preg_replace('/[^a-z0-9_]/', '', strtolower($in['slug'] ?? ''));
$data = is_array($in['data'] ?? null) ? $in['data'] : [];
if ($slug === '') fail('Falta la plantilla');
if (!$data)      fail('Sin datos');

// ---- cargar plantilla desde el manifiesto (sin path traversal) ----
$TPL_DIR  = __DIR__ . '/../templates';
$manifest = json_decode(@file_get_contents($TPL_DIR . '/templates.json') ?: 'null', true);
$tpl = null;
foreach (($manifest['templates'] ?? []) as $t) { if ($t['slug'] === $slug) { $tpl = $t; break; } }
if (!$tpl) fail('Plantilla no encontrada', 404);
$path = $TPL_DIR . '/' . basename($tpl['file']);
if (!is_file($path)) fail('Archivo de plantilla ausente', 500);
$html = file_get_contents($path);

// ---- merge server-side (idéntico al cliente: opcionales por comentario + marcadores) ----
function render_contract(string $html, array $data): string {
  $html = preg_replace_callback('/<!--opt:([a-z0-9_]+)-->.*?<!--\/opt:\1-->/s', function ($m) use ($data) {
    return trim((string)($data[$m[1]] ?? '')) === '' ? '' : $m[0];
  }, $html);
  $html = preg_replace_callback('/\{\{([a-z0-9_]+)\}\}/', function ($m) use ($data) {
    $k = $m[1];
    if ($k === 'campo') return $m[0];
    $v = (string)($data[$k] ?? '');
    if (str_starts_with($k, 'firma')) return $v;            // data URI PNG o vacío
    return $v !== '' ? htmlspecialchars($v, ENT_QUOTES, 'UTF-8') : '—';
  }, $html);
  return $html;
}

// ---- validar firma(s): solo PNG/JPEG en data URI ----
foreach (['firma_adquiriente', 'firma_promotor'] as $sk) {
  if (!empty($data[$sk]) && !preg_match('#^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$#', $data[$sk])) {
    fail('Firma con formato no válido');
  }
}
$signed = (!empty($data['firma_adquiriente']) || !empty($data['firma_promotor'])) ? 1 : 0;

// Documento renderizado (snapshot exacto del contrato). El PDF lo hace el navegador
// al imprimir; aquí guardamos el HTML como registro/auditoría y re-descarga.
$merged = render_contract($html, $data);

// ---- guardar snapshot HTML en private/contratos/ ----
$OUT_DIR = __DIR__ . '/../private/contratos';
if (!is_dir($OUT_DIR)) @mkdir($OUT_DIR, 0750, true);
function uuidv4(): string {
  $d = random_bytes(16);
  $d[6] = chr((ord($d[6]) & 0x0f) | 0x40);
  $d[8] = chr((ord($d[8]) & 0x3f) | 0x80);
  return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($d), 4));
}
$id   = uuidv4();
$file = $id . '.html';
if (file_put_contents($OUT_DIR . '/' . $file, $merged) === false) fail('No se pudo guardar el contrato', 500);

// ---- registrar en BD (sin las imágenes de firma para no inflar) ----
$meta  = $tpl['meta_fields'] ?? [];
$buyer = !empty($meta['buyer'])   ? ($data[$meta['buyer']]   ?? null) : null;
$proj  = !empty($meta['project']) ? ($data[$meta['project']] ?? null) : null;
$store = $data;
foreach ($store as $k => $v) { if (str_starts_with($k, 'firma')) unset($store[$k]); }

$st = db()->prepare(
  'INSERT INTO contracts (id, template_slug, template_name, agent_id, buyer_name, project_name, signed, data_json, doc_file, doc_bytes)
   VALUES (?,?,?,?,?,?,?,?,?,?)'
);
$st->execute([
  $id, $slug, $tpl['name'], (int)$agent['id'],
  $buyer ? mb_substr((string)$buyer, 0, 200) : null,
  $proj ? mb_substr((string)$proj, 0, 200) : null,
  $signed, json_encode($store, JSON_UNESCAPED_UNICODE), $file, strlen($merged),
]);

json_out([
  'ok' => true,
  'id' => $id,
  'view' => 'api/contratos.php?action=view&id=' . $id,
]);
