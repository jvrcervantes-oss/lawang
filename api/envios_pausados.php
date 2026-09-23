<?php
/**
 * Modo mantenimiento de ENVÍOS para la web pública (owner, 23-sep-2026).
 *
 * El interruptor vive en la base (`mantenimiento`, se pausa en /intranet/v4/ajustes/)
 * y contracts/api/send_email.php ya lo respeta. Estos dos avisos a ventas salen por
 * mail() y no pasan por ahí, así que preguntan aquí: api/lead.php y
 * api/booking-notify.php. Con la pausa puesta no envían y el CSV lo apunta como
 * avisado = 'NO'. El lead no se pierde: la fila se escribe igual.
 *
 * Si no se puede preguntar, NO se envía (misma regla que send_email.php). El
 * timeout es corto porque este código corre dentro del envío del formulario.
 */
if (!function_exists('lw_envios_pausados')) {
  function lw_envios_pausados(): bool {
    $ch = curl_init('https://vtulllundrfennhjddhc.supabase.co/rest/v1/rpc/envios_pausados');
    curl_setopt_array($ch, [
      CURLOPT_POST => true,
      CURLOPT_POSTFIELDS => '{}',
      // publishable: va en el front, no es secreto
      CURLOPT_HTTPHEADER => ['apikey: sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg', 'Content-Type: application/json'],
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_CONNECTTIMEOUT => 2,
      CURLOPT_TIMEOUT => 3,
    ]);
    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($resp === false || $code !== 200) return true;
    return trim((string) $resp) !== 'false';
  }
}
