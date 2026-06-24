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

// ---- merge (idéntico al cliente: opcionales por comentario + marcadores) ----
function render_contract(string $html, array $data): string {
  // 1) bloques opcionales: <!--opt:KEY--> ... <!--/opt:KEY-->  (se quitan si KEY vacío)
  $html = preg_replace_callback('/<!--opt:([a-z0-9_]+)-->.*?<!--\/opt:\1-->/s', function ($m) use ($data) {
    return trim((string)($data[$m[1]] ?? '')) === '' ? '' : $m[0];
  }, $html);
  // 2) marcadores {{campo}}
  $html = preg_replace_callback('/\{\{([a-z0-9_]+)\}\}/', function ($m) use ($data) {
    $k = $m[1];
    if ($k === 'campo') return $m[0]; // ejemplo dentro de un comentario CSS
    $v = (string)($data[$k] ?? '');
    if (str_starts_with($k, 'firma')) return $v;   // data URI PNG o vacío
    return $v !== '' ? htmlspecialchars($v, ENT_QUOTES, 'UTF-8') : '—';
  }, $html);
  return $html;
}

// quitar Google Fonts (mPDF no descarga woff2; usaría fuente por defecto)
$html = preg_replace('#<link[^>]+fonts\.(googleapis|gstatic)\.com[^>]*>#i', '', $html);
$merged = render_contract($html, $data);

// ---- validar firma(s): solo PNG/JPEG en data URI ----
foreach (['firma_adquiriente', 'firma_promotor'] as $sk) {
  if (!empty($data[$sk]) && !preg_match('#^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$#', $data[$sk])) {
    fail('Firma con formato no válido');
  }
}
$signed = (!empty($data['firma_adquiriente']) || !empty($data['firma_promotor'])) ? 1 : 0;

// ---- generar PDF con mPDF ----
$autoload = __DIR__ . '/../vendor/autoload.php';
if (!is_file($autoload)) fail('mPDF no instalado en el servidor (composer require mpdf/mpdf)', 500);
require $autoload;

try {
  $mpdf = new \Mpdf\Mpdf([
    'mode' => 'utf-8', 'format' => 'A4',
    'margin_left' => 18, 'margin_right' => 18, 'margin_top' => 18, 'margin_bottom' => 20,
    'tempDir' => sys_get_temp_dir(),
  ]);
  $mpdf->SetTitle($tpl['name']);
  $mpdf->SetAuthor('Lawang Tropical Properties');
  $mpdf->WriteHTML($merged);
  $pdfBytes = $mpdf->Output('', \Mpdf\Output\Destination::STRING_RETURN);
} catch (\Throwable $e) {
  fail('Error generando el PDF' . (($GLOBALS['CONFIG']['debug'] ?? false) ? ': ' . $e->getMessage() : ''), 500);
}

// ---- guardar archivo en private/contratos/ ----
$OUT_DIR = __DIR__ . '/../private/contratos';
if (!is_dir($OUT_DIR)) @mkdir($OUT_DIR, 0750, true);
function uuidv4(): string {
  $d = random_bytes(16);
  $d[6] = chr((ord($d[6]) & 0x0f) | 0x40);
  $d[8] = chr((ord($d[8]) & 0x3f) | 0x80);
  return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($d), 4));
}
$id   = uuidv4();
$file = $id . '.pdf';
if (file_put_contents($OUT_DIR . '/' . $file, $pdfBytes) === false) fail('No se pudo guardar el PDF', 500);

// ---- registrar en BD (sin guardar las imágenes de firma para no inflar) ----
$meta  = $tpl['meta_fields'] ?? [];
$buyer = $meta['buyer']   ? ($data[$meta['buyer']]   ?? null) : null;
$proj  = $meta['project'] ? ($data[$meta['project']] ?? null) : null;
$store = $data;
foreach ($store as $k => $v) { if (str_starts_with($k, 'firma')) unset($store[$k]); }

$st = db()->prepare(
  'INSERT INTO contracts (id, template_slug, template_name, agent_id, buyer_name, project_name, signed, data_json, pdf_file, pdf_bytes)
   VALUES (?,?,?,?,?,?,?,?,?,?)'
);
$st->execute([
  $id, $slug, $tpl['name'], (int)$agent['id'],
  $buyer ? mb_substr($buyer, 0, 200) : null,
  $proj ? mb_substr($proj, 0, 200) : null,
  $signed, json_encode($store, JSON_UNESCAPED_UNICODE), $file, strlen($pdfBytes),
]);

json_out([
  'ok' => true,
  'id' => $id,
  'download' => 'api/contratos.php?action=pdf&id=' . $id,
  'bytes' => strlen($pdfBytes),
]);
