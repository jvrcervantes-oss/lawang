<?php
/**
 * diag_ghl.php — TEMPORAL. Borrar en cuanto el alta en el CRM funcione.
 *
 * Existe porque private/ es 404 por web (correcto) y desde fuera no hay forma de saber
 * por que lawang_ghl_upsert() no llega a GHL: el diseno es fail-open y no se queja.
 *
 * NO IMPRIME NINGUN SECRETO: del token solo dice si existe, cuanto mide y si empieza por
 * "pit-". Del CSV de pendientes, solo fecha, paso y codigo HTTP — la columna del email se
 * descarta. Aun asi es un endpoint publico: vive lo justo y se borra.
 */
header('Content-Type: application/json; charset=utf-8');

$out = [];
$path = __DIR__ . '/../private/ghl.json';

// 1. ¿Esta el fichero donde el codigo lo busca?
$out['ruta_buscada'] = realpath(__DIR__ . '/..') . '/private/ghl.json';
$out['existe']       = is_file($path);
$out['bytes']        = $out['existe'] ? filesize($path) : null;

if ($out['existe']) {
    $crudo = (string) file_get_contents($path);
    // Un BOM o un espacio antes del "{" rompen json_decode sin decir por que.
    $out['empieza_por']   = substr(bin2hex(substr($crudo, 0, 3)), 0, 6);
    $out['tiene_bom']     = substr($crudo, 0, 3) === "\xEF\xBB\xBF";
    $cfg = json_decode($crudo, true);
    $out['json_valido']   = is_array($cfg);
    $out['json_error']    = json_last_error_msg();
    if (is_array($cfg)) {
        $out['claves']        = array_keys($cfg);           // nombres, nunca valores
        $pit                  = isset($cfg['pit']) ? (string) $cfg['pit'] : '';
        $out['pit_longitud']  = strlen($pit);
        $out['pit_prefijo_ok'] = strpos($pit, 'pit-') === 0;
        $out['pit_placeholder'] = $pit === 'pit-TU-TOKEN';
        $out['location']      = isset($cfg['location']) ? $cfg['location'] : null; // no es secreto
        $out['usuario']       = isset($cfg['usuario']) ? $cfg['usuario'] : null;   // tampoco

        // 2. ¿Sale la conexion de este servidor, y que contesta GHL con ESE token?
        $out['curl'] = function_exists('curl_init');
        if ($out['curl'] && $pit !== '') {
            $ch = curl_init('https://services.leadconnectorhq.com/locations/' . $cfg['location']);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 8,
                CURLOPT_HTTPHEADER => [
                    'Authorization: Bearer ' . $pit,
                    'Version: 2021-07-28',
                    'Accept: application/json',
                ],
            ]);
            $r = curl_exec($ch);
            $out['prueba_http']  = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $out['prueba_curl']  = curl_error($ch) ?: null;
            // El cuerpo puede traer el mensaje de scope; se recorta y no lleva secretos.
            $out['prueba_cuerpo'] = $r === false ? null : substr((string) $r, 0, 200);
            curl_close($ch);
        }
    }
}

// 3. ¿El lead.php desplegado es el que llama al CRM?
$lead = @file_get_contents(__DIR__ . '/lead.php');
$out['lead_llama_al_crm'] = $lead !== false && strpos($lead, 'lawang_ghl_upsert') !== false;
$out['lead_cierra_antes']  = $lead !== false && strpos($lead, 'litespeed_finish_request') !== false;
$out['finish_disponible']  = [
    'litespeed' => function_exists('litespeed_finish_request'),
    'fastcgi'   => function_exists('fastcgi_finish_request'),
];

// 4. Ultimas filas del registro de fallos, SIN la columna del email.
$pend = __DIR__ . '/../private/crm_pendientes.csv';
$out['pendientes_existe'] = is_file($pend);
if (is_file($pend)) {
    $filas = array_slice(array_filter(explode("\n", (string) file_get_contents($pend))), -4);
    $out['pendientes'] = array_map(function ($l) {
        $c = str_getcsv($l);
        unset($c[1]);                       // fuera el email
        return implode(' | ', $c);
    }, $filas);
}

echo json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
