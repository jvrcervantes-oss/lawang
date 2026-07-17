<?php
/**
 * Envía un contrato por email con el PDF adjunto.
 * Standalone a propósito: NO usa bootstrap.php (exige MySQL/config.php de la
 * fase-4 sin desplegar). Remitente SIEMPRE fijo (nunca lo decide quien llama):
 *   - si existe private/mail.php con contraseña real → SMTP autenticado
 *     (admin@lawangproperties.com, vía lib/SmtpMailer.php, sin dependencias)
 *   - si no → mail() nativo de PHP con sales@lawangproperties.com, igual que
 *     hasta ahora (fallback automático, no rompe nada si aún no se configuró)
 *
 * Sin autenticación (la app tampoco la tiene hoy): el único filtro es que la
 * petición venga del propio origen. No es a prueba de un atacante decidido
 * con curl -- si esto pasa a tener volumen real de uso, añadir auth de verdad.
 */
declare(strict_types=1);

// límite de 100MB (ver más abajo) puede pasar el memory_limit por defecto de
// hosting compartido (128M) al decodificar base64 + montar el MIME; intento
// subirlo, si el hosting no lo permite simplemente no tiene efecto.
@ini_set('memory_limit', '256M');

header('Content-Type: application/json; charset=utf-8');

function fail(string $msg, int $code = 400): void {
  http_response_code($code);
  echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
  exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') { fail('Método no permitido', 405); }

// ---- same-origin: bloquea el uso trivial desde otras webs ----
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin !== '' && parse_url($origin, PHP_URL_HOST) !== ($_SERVER['HTTP_HOST'] ?? null)) {
  fail('Origen no permitido', 403);
}

$in = json_decode(file_get_contents('php://input') ?: '[]', true);
if (!is_array($in)) { fail('JSON inválido'); }

$to       = trim((string)($in['to'] ?? ''));
$subject  = trim((string)($in['subject'] ?? 'Contrato — Lawang Tropical Properties'));
$message  = trim((string)($in['message'] ?? ''));
$filename = preg_replace('/[^A-Za-z0-9_\-.]/', '_', (string)($in['filename'] ?? 'contrato.pdf'));
$pdfB64   = (string)($in['pdf_base64'] ?? '');

if (!filter_var($to, FILTER_VALIDATE_EMAIL)) { fail('Destinatario no válido'); }
if (mb_strlen($subject) > 200) { fail('Asunto demasiado largo'); }
if (mb_strlen($message) > 5000) { fail('Mensaje demasiado largo'); }
if ($pdfB64 === '') { fail('Falta el PDF'); }
// 100MB reales ≈ 134MB en base64 — límite subido a petición explícita. Aviso real:
// la práctica totalidad de servidores de correo (Gmail incluido) rechazan adjuntos
// por encima de ~25MB sea cual sea este límite; esto solo evita cargas absurdas.
if (strlen($pdfB64) > 140 * 1024 * 1024) { fail('El PDF es demasiado grande'); }

$pdfBytes = base64_decode($pdfB64, true);
if ($pdfBytes === false || substr($pdfBytes, 0, 4) !== '%PDF') { fail('El adjunto no es un PDF válido'); }

// ---- remitente: SMTP autenticado si hay credenciales configuradas en
// private/mail.php (admin@lawangproperties.com), si no, mail() nativo con
// sales@lawangproperties.com como hasta ahora. Los dos caminos comparten el
// mismo cuerpo MIME — solo cambia cómo se entrega. ----
$mailConfig = null;
$mailConfigPath = __DIR__ . '/../private/mail.php';
if (is_file($mailConfigPath)) {
  $cfg = require $mailConfigPath;
  if (is_array($cfg) && !empty($cfg['smtp_pass']) && $cfg['smtp_pass'] !== 'CAMBIAR_POR_LA_REAL') {
    $mailConfig = $cfg;
  }
}

$from     = $mailConfig['from_email'] ?? 'sales@lawangproperties.com';
$fromName = $mailConfig['from_name'] ?? 'Lawang Tropical Properties';

$boundary = 'lwc_' . bin2hex(random_bytes(16));

$body  = "--{$boundary}\r\n";
$body .= "Content-Type: text/plain; charset=UTF-8\r\n";
$body .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
$body .= $message . "\r\n\r\n";
$body .= "--{$boundary}\r\n";
$body .= "Content-Type: application/pdf; name=\"{$filename}\"\r\n";
$body .= "Content-Transfer-Encoding: base64\r\n";
$body .= "Content-Disposition: attachment; filename=\"{$filename}\"\r\n\r\n";
$body .= chunk_split(base64_encode($pdfBytes)) . "\r\n";
$body .= "--{$boundary}--";

if ($mailConfig) {
  require_once __DIR__ . '/lib/SmtpMailer.php';
  try {
    $smtp = new SmtpMailer(
      $mailConfig['smtp_host'], (int) $mailConfig['smtp_port'], $mailConfig['smtp_secure'],
      $mailConfig['smtp_user'], $mailConfig['smtp_pass']
    );
    $smtp->send($from, $fromName, $to, $subject, $body, $boundary);
    echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE);
  } catch (Throwable $e) {
    fail('No se pudo enviar por SMTP: ' . $e->getMessage(), 500);
  }
  exit;
}

// ---- fallback: mail() nativo (sin private/mail.php configurado todavía) ----
$headers = "From: {$fromName} <{$from}>\r\n"
  . "Reply-To: {$from}\r\n"
  . "MIME-Version: 1.0\r\n"
  . "Content-Type: multipart/mixed; boundary=\"{$boundary}\"\r\n";
$encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
$ok = mail($to, $encodedSubject, $body, $headers, "-f{$from}");

if ($ok) {
  echo json_encode(['ok' => true], JSON_UNESCAPED_UNICODE);
} else {
  fail('El servidor no pudo enviar el correo (revisar que Hostinger tenga mail() habilitado para este dominio, o configurar private/mail.php para usar SMTP)', 500);
}
