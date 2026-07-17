<?php
/**
 * COPIA este archivo a  private/mail.php  EN EL SERVIDOR (File Manager o FTP
 * de Hostinger) y rellena ahí la contraseña real — NUNCA en este archivo,
 * NUNCA en el chat con el agente. private/mail.php está en .gitignore, no
 * se sube a git.
 *
 * Usado por api/send_email.php para enviar por SMTP autenticado con el buzón
 * admin@lawangproperties.com en vez del mail() nativo de PHP (más fiable:
 * muchos hostings compartidos, Hostinger incluido, limitan o filtran como
 * spam el sendmail directo sin autenticar).
 *
 * Si este archivo (private/mail.php) no existe todavía en el servidor,
 * send_email.php sigue funcionando igual que antes con mail() nativo — no
 * hace falta nada más para que la app siga funcionando mientras tanto.
 *
 * Los valores de host/puerto son los estándar de Hostinger — verifícalos en
 * hPanel → Correos → [admin@lawangproperties.com] → Configurar el cliente de
 * correo, por si tu plan usa otros.
 *
 * pdf_service_url/pdf_service_secret: el servicio de render HTML→PDF con
 * Chromium real (infraestructura/contracts-pdf-service, desplegado en
 * Railway) — genera el PDF exacto del preview sin que el usuario tenga que
 * descargarlo y adjuntarlo a mano. Si se deja en blanco, send_email.php
 * sigue aceptando el adjunto manual (pdf_base64) como hasta ahora — no
 * hace falta rellenar esto para que el envío de email siga funcionando.
 */
return [
  'smtp_host'   => 'smtp.hostinger.com',
  'smtp_port'   => 587,          // 587 = STARTTLS (este archivo espera STARTTLS) · 465 = SSL directo
  'smtp_secure' => 'tls',        // 'tls' (puerto 587) o 'ssl' (puerto 465) — deben ir a juego
  'smtp_user'   => 'admin@lawangproperties.com',
  'smtp_pass'   => 'CAMBIAR_POR_LA_REAL',
  'from_email'  => 'admin@lawangproperties.com',
  'from_name'   => 'Lawang Tropical Properties',

  // deja estos dos en blanco ('') hasta que el servicio esté desplegado en Railway
  'pdf_service_url'    => '',   // ej. https://contracts-pdf-service-production.up.railway.app
  'pdf_service_secret' => '',   // el mismo valor que RENDER_SECRET en Railway
];
