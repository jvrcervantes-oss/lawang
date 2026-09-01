<?php
/**
 * Envía un contrato por email con el PDF adjunto.
 * Standalone a propósito: no hay backend PHP en este proyecto (login y datos
 * viven en Supabase Auth/RLS, ver DEPLOY.md), así que este endpoint no tiene
 * sesión de la que tirar. Remitente SIEMPRE fijo (nunca lo decide quien llama):
 *   - si existe private/mail.php con contraseña real → SMTP autenticado
 *     (admin@lawangproperties.com, vía lib/SmtpMailer.php, sin dependencias)
 *   - si no → mail() nativo de PHP con sales@lawangproperties.com, igual que
 *     hasta ahora (fallback automático, no rompe nada si aún no se configuró)
 *
 * AUTENTICACIÓN (6-ago-2026). Antes el único filtro era same-origin, que un
 * `curl` sin cabecera `Origin` se salta entero: cualquiera podía usar nuestro
 * SMTP para escribir a quien quisiera con la marca de Lawang. Eso es materia
 * prima de phishing, no una molestia.
 * Tres vías, porque hay tres llamantes legítimos y ninguno comparte credencial:
 *   1. SESIÓN de la suite  — el navegador manda su access token de Supabase en
 *      `Authorization: Bearer`; se valida contra /auth/v1/user del proyecto.
 *      Lo usan contratos y facturas.
 *   2. SECRETO COMPARTIDO  — la Edge `firma-submit` manda `X-Render-Secret`, que
 *      es el MISMO secreto del servicio de render que esta config ya tiene. No
 *      se inventa un secreto nuevo: la Edge no tiene sesión de usuario y crear
 *      uno habría dejado esto pendiente del owner. ponytail: si algún día ese
 *      secreto se rota por otro motivo, hay que rotarlo en los dos sitios; la
 *      salida limpia sería un secreto propio en private/mail.php.
 *   3. AVISO INTERNO       — sin credencial se admite SOLO correo de texto (sin
 *      adjunto) a una dirección de NUESTRO dominio. Es lo que hace el aviso
 *      nocturno de almacenamiento (`sql/aviso_almacenamiento.sql`, vía pg_net
 *      desde Postgres, que no puede llevar secreto sin escribirlo en el cuerpo
 *      de la función). Un tercero que abuse de esta vía solo consigue escribir
 *      a nuestro propio buzón: no hay víctima externa ni suplantación.
 * El same-origin se conserva como primera criba, pero ya no es la única.
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

// ---- config de private/mail.php (SMTP + servicio de render), si existe ----
// Se carga ANTES de autenticar: la vía 2 compara contra `pdf_service_secret`.
$mailConfig = null;
$mailConfigPath = __DIR__ . '/../private/mail.php';
if (is_file($mailConfigPath)) {
  $cfg = require $mailConfigPath;
  if (is_array($cfg) && !empty($cfg['smtp_pass']) && $cfg['smtp_pass'] !== 'CAMBIAR_POR_LA_REAL') {
    $mailConfig = $cfg;
  }
}

// ---- auth, vías 1 y 2 (las que se resuelven con cabeceras) ----
const SUPA_URL  = 'https://vtulllundrfennhjddhc.supabase.co';
const SUPA_ANON = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';   // publishable: va en el front, no es secreto

/** ¿El bearer es una sesión viva de la suite? Se pregunta a Supabase en vez de
 *  verificar la firma aquí: son 10 líneas contra montar validación de JWKS en
 *  PHP a mano, y de paso una cuenta revocada deja de valer al instante. */
function sesion_valida(string $jwt): bool {
  $ch = curl_init(SUPA_URL . '/auth/v1/user');
  curl_setopt_array($ch, [
    CURLOPT_HTTPHEADER => ['apikey: ' . SUPA_ANON, 'Authorization: Bearer ' . $jwt],
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 10,
  ]);
  $resp = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  // 200 con un `id` dentro = usuario real. Un 200 sin id no debería pasar, pero
  // dar por bueno un cuerpo que no se ha mirado es cómo se cuelan estas cosas.
  return $code === 200 && is_string($resp) && str_contains($resp, '"id"');
}

$autorizado = false;
$via = '';
/* El token se lee de DOS cabeceras y `X-Suite-Token` es la que usa el front.
   Motivo: Apache no siempre entrega `Authorization` a PHP (se pierde según el
   SAPI y hace falta `CGIPassAuth` o una regla de rewrite). Si eso pasara aquí,
   el correo de contratos y de facturas moriría con un 401 y el diagnóstico
   sería "pues a mí me funcionaba". Una cabecera `X-` nunca se filtra.
   `Authorization` se sigue aceptando para no romper a ningún llamante que ya la
   mande — y porque es la forma estándar. */
$bearer = trim($_SERVER['HTTP_X_SUITE_TOKEN'] ?? '');
if ($bearer === '' && preg_match('/^Bearer\s+(.+)$/i', trim($_SERVER['HTTP_AUTHORIZATION'] ?? ''), $m)) {
  $bearer = trim($m[1]);
}
$secreto = trim($_SERVER['HTTP_X_RENDER_SECRET'] ?? '');
if ($secreto !== '' && $mailConfig && !empty($mailConfig['pdf_service_secret'])
    && hash_equals((string) $mailConfig['pdf_service_secret'], $secreto)) {
  $autorizado = true; $via = 'servicio';                      // vía 2: la Edge de firma
} elseif ($bearer !== '' && $bearer !== SUPA_ANON && sesion_valida($bearer)) {
  $autorizado = true; $via = 'sesion';                        // vía 1: equipo con login
}

$in = json_decode(file_get_contents('php://input') ?: '[]', true);
if (!is_array($in)) { fail('JSON inválido'); }

$to       = trim((string)($in['to'] ?? ''));
$subject  = trim((string)($in['subject'] ?? 'Contrato — Lawang Tropical Properties'));
$message  = trim((string)($in['message'] ?? ''));
// \p{L}/\p{N} (Unicode) en vez de A-Za-z0-9: si no, cada tilde del nombre del
// comprador (José, García…) y cada "+" del separador de palabras se comía la
// regex ASCII y dejaba el adjunto con guiones bajos ilegibles.
$filename = preg_replace('/[^\p{L}\p{N}+_\-.]/u', '_', (string)($in['filename'] ?? 'contrato.pdf'));
$pdfB64   = (string)($in['pdf_base64'] ?? '');
$html     = (string)($in['html'] ?? '');

// `attach:false` = correo de solo texto, sin adjunto. Lo usa el envío del enlace
// de firma: ahí el documento se lee en el navegador (el snapshot que firma el
// comprador), así que adjuntar el contrato sin firmar duplicaría el documento y
// mandaría un PDF con pinta de definitivo que nadie ha firmado.
$attach = ($in['attach'] ?? true) !== false;

if (!filter_var($to, FILTER_VALIDATE_EMAIL)) { fail('Destinatario no válido'); }
if (mb_strlen($subject) > 200) { fail('Asunto demasiado largo'); }
if (mb_strlen($message) > 5000) { fail('Mensaje demasiado largo'); }
if (!$attach && $message === '') { fail('Un correo sin adjunto necesita mensaje'); }
if ($attach && $pdfB64 === '' && $html === '') { fail('Falta el PDF o el HTML a renderizar'); }
// 100MB reales ≈ 134MB en base64 — límite subido a petición explícita. Aviso real:
// la práctica totalidad de servidores de correo (Gmail incluido) rechazan adjuntos
// por encima de ~25MB sea cual sea este límite; esto solo evita cargas absurdas.
if (strlen($pdfB64) > 140 * 1024 * 1024) { fail('El PDF es demasiado grande'); }
if (strlen($html) > 25 * 1024 * 1024) { fail('El HTML es demasiado grande'); }

/* ---- auth, vía 3: aviso interno sin credencial ----
   Se decide aquí y no arriba porque depende del contenido: solo pasa un correo
   de TEXTO (sin adjunto) dirigido a NUESTRO propio dominio. Es lo que manda el
   aviso nocturno de almacenamiento desde Postgres con pg_net, que no puede
   llevar un secreto sin escribirlo en el cuerpo de la función.
   Lo que esto NO permite, que es el punto: escribir a un tercero, ni adjuntar un
   PDF con pinta de contrato. Un abuso de esta vía solo llena nuestro buzón. */
$DOMINIO = 'lawangproperties.com';
$interno = !$attach
  && preg_match('/@(.+)$/', $to, $md)
  && (strcasecmp($md[1], $DOMINIO) === 0 || str_ends_with(strtolower($md[1]), '.' . $DOMINIO));
if (!$autorizado && $interno) { $autorizado = true; $via = 'aviso-interno'; }

if (!$autorizado) {
  // 401 y no 403: falta credencial, no es que la credencial no valga.
  fail('No autorizado: hace falta una sesión de la suite (X-Suite-Token) '
     . 'o el secreto del servicio. Solo los avisos internos de texto a @' . $DOMINIO . ' van sin credencial.', 401);
}
// Qué vía autorizó cada envío. Un solo renglón, y es el dato con el que se
// comprueba en producción que los tres llamantes entran por donde deben — sin
// esto, "funciona" y "funciona por la puerta de atrás" se ven igual.
error_log('send_email: autorizado por ' . $via . ' -> ' . $to);

// ---- PDF: renderizado con Chromium real (Railway) si hay HTML + servicio
// configurado; si eso falla o no está configurado, cae al adjunto manual
// (pdf_base64) cuando el cliente lo mandó como respaldo. ----
$pdfBytes = null;
if ($attach) {
  if ($html !== '' && $mailConfig && !empty($mailConfig['pdf_service_url']) && !empty($mailConfig['pdf_service_secret'])) {
    $pdfBytes = render_pdf_via_service($html, $mailConfig['pdf_service_url'], $mailConfig['pdf_service_secret']);
  }
  if ($pdfBytes === null && $pdfB64 !== '') {
    $decoded = base64_decode($pdfB64, true);
    if ($decoded !== false && substr($decoded, 0, 4) === '%PDF') {
      $pdfBytes = $decoded;
    }
  }
  if ($pdfBytes === null) {
    fail('No se pudo generar ni adjuntar el PDF (servicio de render no disponible y no se adjuntó uno manualmente)', 502);
  }
}

function render_pdf_via_service(string $html, string $url, string $secret): ?string {
  $ch = curl_init(rtrim($url, '/') . '/render-pdf');
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode(['html' => $html], JSON_UNESCAPED_UNICODE),
    CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'X-Render-Secret: ' . $secret],
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 40,
  ]);
  $resp = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  $err  = curl_error($ch);
  curl_close($ch);
  if ($resp === false || $code !== 200 || substr((string) $resp, 0, 4) !== '%PDF') {
    error_log("render_pdf_via_service falló (HTTP {$code}): " . ($err ?: substr((string) $resp, 0, 300)));
    return null;
  }
  return $resp;
}

$from     = $mailConfig['from_email'] ?? 'sales@lawangproperties.com';
$fromName = $mailConfig['from_name'] ?? 'Lawang Tropical Properties';

$boundary = 'lwc_' . bin2hex(random_bytes(16));

// Plantilla de marca compartida (1-sep-2026, encargo del owner: unificar el
// formato de TODO correo de la intranet con el mismo diseño que ya usa el
// email de acceso al portal). Antes esta parte era texto plano a secas.
require_once __DIR__ . '/lib/plantilla_correo.php';
$mensajeHtml = lw_plantilla_correo($message);

// multipart/mixed con una sola parte de HTML es correo válido, así que el
// camino sin adjunto reusa la misma estructura (y el mismo SmtpMailer) en vez
// de abrir una segunda forma de construir el mensaje.
$body  = "--{$boundary}\r\n";
$body .= "Content-Type: text/html; charset=UTF-8\r\n";
$body .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
$body .= $mensajeHtml . "\r\n\r\n";
if ($pdfBytes !== null) {
  $body .= "--{$boundary}\r\n";
  $body .= "Content-Type: application/pdf; name=\"{$filename}\"\r\n";
  $body .= "Content-Transfer-Encoding: base64\r\n";
  $body .= "Content-Disposition: attachment; filename=\"{$filename}\"\r\n\r\n";
  $body .= chunk_split(base64_encode($pdfBytes)) . "\r\n";
}
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
