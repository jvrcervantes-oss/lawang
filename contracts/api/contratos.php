<?php
require __DIR__ . '/bootstrap.php';
$agent = require_agent();
$isAdmin = ($agent['role'] ?? '') === 'admin';

$action = $_GET['action'] ?? 'list';

if ($action === 'list') {
  if ($isAdmin) {
    $st = db()->prepare(
      'SELECT c.id, c.template_name, c.buyer_name, c.project_name, c.signed, c.doc_bytes, c.created_at, a.name AS agent
         FROM contracts c JOIN agents a ON a.id = c.agent_id
        ORDER BY c.created_at DESC LIMIT 200'
    );
    $st->execute();
  } else {
    $st = db()->prepare(
      'SELECT id, template_name, buyer_name, project_name, signed, doc_bytes, created_at
         FROM contracts WHERE agent_id = ? ORDER BY created_at DESC LIMIT 200'
    );
    $st->execute([(int)$agent['id']]);
  }
  json_out(['ok' => true, 'contracts' => $st->fetchAll()]);
}

if ($action === 'view') {
  $id = preg_replace('/[^a-f0-9\-]/', '', strtolower($_GET['id'] ?? ''));
  if ($id === '') fail('Falta id', 400);

  // Comprobación de propiedad (IDOR-safe): el agente solo accede a lo suyo
  if ($isAdmin) {
    $st = db()->prepare('SELECT doc_file FROM contracts WHERE id = ? LIMIT 1');
    $st->execute([$id]);
  } else {
    $st = db()->prepare('SELECT doc_file FROM contracts WHERE id = ? AND agent_id = ? LIMIT 1');
    $st->execute([$id, (int)$agent['id']]);
  }
  $row = $st->fetch();
  if (!$row) fail('No encontrado', 404);

  // ruta segura: solo basename, dentro de private/contratos/
  $file = basename($row['doc_file']);
  $path = __DIR__ . '/../private/contratos/' . $file;
  if (!is_file($path)) fail('Archivo ausente', 404);

  // Snapshot HTML del contrato (el usuario imprime → PDF desde el navegador)
  header('Content-Type: text/html; charset=utf-8');
  header('X-Content-Type-Options: nosniff');
  header("Content-Security-Policy: default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com");
  readfile($path);
  exit;
}

fail('Acción no válida', 404);
