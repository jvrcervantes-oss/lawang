<?php
require __DIR__ . '/bootstrap.php';
require_agent();

$TPL_DIR = __DIR__ . '/../templates';
$manifest = json_decode(@file_get_contents($TPL_DIR . '/templates.json') ?: 'null', true);
if (!$manifest || empty($manifest['templates'])) fail('Manifiesto de plantillas no disponible', 500);

$action = $_GET['action'] ?? 'list';

if ($action === 'list') {
  $list = array_map(fn($t) => [
    'slug' => $t['slug'], 'name' => $t['name'], 'desc' => $t['desc'] ?? '',
  ], $manifest['templates']);
  json_out(['ok' => true, 'templates' => $list]);
}

if ($action === 'get') {
  $slug = preg_replace('/[^a-z0-9_]/', '', strtolower($_GET['slug'] ?? ''));
  $tpl = null;
  foreach ($manifest['templates'] as $t) { if ($t['slug'] === $slug) { $tpl = $t; break; } }
  if (!$tpl) fail('Plantilla no encontrada', 404);

  // cargar el HTML de forma segura (solo desde templates/, sin path traversal)
  $file = basename($tpl['file']);
  $path = $TPL_DIR . '/' . $file;
  if (!is_file($path)) fail('Archivo de plantilla ausente', 500);
  $html = file_get_contents($path);

  json_out([
    'ok' => true,
    'slug' => $tpl['slug'],
    'name' => $tpl['name'],
    'sections' => $tpl['sections'] ?? [],
    'html' => $html,
  ]);
}

fail('Acción no válida', 404);
