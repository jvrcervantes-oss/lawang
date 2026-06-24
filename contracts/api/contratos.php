<?php
require __DIR__ . '/bootstrap.php';
$agent = require_agent();
$isAdmin = ($agent['role'] ?? '') === 'admin';

$action = $_GET['action'] ?? 'list';

if ($action === 'list') {
  if ($isAdmin) {
    $st = db()->prepare(
      'SELECT c.id, c.template_name, c.buyer_name, c.project_name, c.signed, c.pdf_bytes, c.created_at, a.name AS agent
         FROM contracts c JOIN agents a ON a.id = c.agent_id
        ORDER BY c.created_at DESC LIMIT 200'
    );
    $st->execute();
  } else {
    $st = db()->prepare(
      'SELECT id, template_name, buyer_name, project_name, signed, pdf_bytes, created_at
         FROM contracts WHERE agent_id = ? ORDER BY created_at DESC LIMIT 200'
    );
    $st->execute([(int)$agent['id']]);
  }
  json_out(['ok' => true, 'contracts' => $st->fetchAll()]);
}

if ($action === 'pdf') {
  $id = preg_replace('/[^a-f0-9\-]/', '', strtolower($_GET['id'] ?? ''));
  if ($id === '') fail('Falta id', 400);

  // Comprobación de propiedad (IDOR-safe): el agente solo accede a lo suyo
  if ($isAdmin) {
    $st = db()->prepare('SELECT pdf_file, buyer_name FROM contracts WHERE id = ? LIMIT 1');
    $st->execute([$id]);
  } else {
    $st = db()->prepare('SELECT pdf_file, buyer_name FROM contracts WHERE id = ? AND agent_id = ? LIMIT 1');
    $st->execute([$id, (int)$agent['id']]);
  }
  $row = $st->fetch();
  if (!$row) fail('No encontrado', 404);

  // ruta segura: solo basename, dentro de private/contratos/
  $file = basename($row['pdf_file']);
  $path = __DIR__ . '/../private/contratos/' . $file;
  if (!is_file($path)) fail('Archivo ausente', 404);

  $dl = isset($_GET['dl']);
  $name = 'Contrato-' . preg_replace('/[^A-Za-z0-9_\-]/', '_', (string)($row['buyer_name'] ?: 'Lawang')) . '.pdf';
  header('Content-Type: application/pdf');
  header('Content-Disposition: ' . ($dl ? 'attachment' : 'inline') . '; filename="' . $name . '"');
  header('Content-Length: ' . filesize($path));
  header('X-Content-Type-Options: nosniff');
  readfile($path);
  exit;
}

fail('Acción no válida', 404);
