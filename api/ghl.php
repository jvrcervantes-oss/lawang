<?php
/**
 * ghl.php — alta del lead en GoHighLevel (CRM) desde el formulario de /modelo/<id>.
 *
 * Se llama DESPUES de escribir el CSV y de avisar a ventas, y falla en silencio: si GHL
 * esta caido o el token caduco, el lead ya esta guardado y el comercial ya tiene el correo.
 * Un CRM que devuelve 500 no puede tumbar la captacion de un clic pagado.
 *
 * Credenciales fuera de git, mismo patron que private/mail.php:
 *   private/ghl.php  ->  <?php return ['pit' => 'pit-xxx', 'location' => 'vOEs...'];
 * Sin ese fichero esto no hace nada. El token lo pega el owner; nunca viaja por el repo.
 *
 * API v2 (LeadConnector). La v1 murio el 31-dic-2025: la cabecera Version es obligatoria
 * en toda llamada y su ausencia devuelve 401, no 400.
 */

const GHL_BASE    = 'https://services.leadconnectorhq.com';
const GHL_VERSION = '2021-07-28';

// Campos personalizados de la location (creados por API el 29-jul-2026). Van por id y no
// por fieldKey: el key se puede renombrar desde la UI y el id no.
const GHL_CF_MODELO = 'KUGzZ2Kv9t0DiUq013mk'; // SINGLE_OPTIONS: el valor DEBE estar en la lista
const GHL_CF_ORIGEN = 'HzpYLNaXWv1EACm9dEJ0';

// Pipeline por defecto de la location y su primera etapa.
const GHL_PIPELINE = 'z01nrWJymUar2sX7RKv5';
const GHL_ETAPA    = 'feb13ad0-6adb-4233-b784-1222e8e0a579'; // New Lead

/** id de modelo -> opcion exacta del desplegable en GHL. Un valor fuera de la lista se
 *  descarta sin error y el lead entra sin modelo, que es justo el dato que lo cualifica. */
function lawang_ghl_modelo($id)
{
    $mapa = [
        'dali' => 'Dali', 'dune' => 'Dune', 'dream' => 'Dream',
        'trinity' => 'Trinity', 'temple' => 'Temple',
    ];
    return isset($mapa[$id]) ? $mapa[$id] : 'Sin definir';
}

/** Telefono a E.164, que es lo unico que GHL sabe marcar. */
function lawang_ghl_tel($tel)
{
    $t = preg_replace('/[^0-9+]/', '', $tel);
    if (strpos($t, '00') === 0)  $t = '+' . substr($t, 2);
    // ponytail: el formulario no pide prefijo y la pauta va a Espana. Nueve digitos sueltos
    // se asumen espanoles. Si se abre pauta a otro pais, poner un selector de pais en el
    // formulario en vez de anadir aqui otro if.
    if (strpos($t, '+') !== 0 && strlen($t) === 9) $t = '+34' . $t;
    return $t;
}

function lawang_ghl_post($ruta, array $cuerpo, $pit)
{
    $ch = curl_init(GHL_BASE . $ruta);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => json_encode($cuerpo),
        CURLOPT_RETURNTRANSFER => true,
        // El visitante esta esperando en la pagina: 4s de techo, no el default de 300.
        CURLOPT_TIMEOUT        => 4,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_HTTPHEADER     => [
            'Authorization: Bearer ' . $pit,
            'Version: ' . GHL_VERSION,
            'Content-Type: application/json',
            'Accept: application/json',
        ],
    ]);
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return [$code, $res ? json_decode($res, true) : null];
}

/**
 * Da de alta (o actualiza) el contacto y le abre una oportunidad en el pipeline.
 * Devuelve true solo si el contacto entro. Nunca lanza.
 */
function lawang_ghl_upsert($nombre, $email, $tel, $modeloId, $origen, $campana)
{
    $path = __DIR__ . '/../private/ghl.php';
    if (!is_file($path) || !function_exists('curl_init')) return false;
    $cfg = @include $path;
    if (!is_array($cfg) || empty($cfg['pit']) || empty($cfg['location'])) return false;

    $partes  = preg_split('/\s+/', trim($nombre), 2);
    $modelo  = lawang_ghl_modelo($modeloId);

    $contacto = [
        'locationId' => $cfg['location'],
        'firstName'  => $partes[0],
        'lastName'   => isset($partes[1]) ? $partes[1] : '',
        'name'       => $nombre,
        'email'      => $email,
        'phone'      => lawang_ghl_tel($tel),
        'source'     => $origen !== '' ? $origen : 'web',
        'tags'       => ['landing-modelo', 'modelo-' . strtolower($modeloId)],
        'customFields' => [
            ['id' => GHL_CF_MODELO, 'field_value' => $modelo],
            // La cadena utm_*/fbclid tal cual: sin ella no hay coste por lead por anuncio.
            ['id' => GHL_CF_ORIGEN, 'field_value' => $campana !== '' ? $campana : $origen],
        ],
    ];
    // ponytail: ticket_estimado_eur se deja vacio a proposito. Los unicos precios que
    // tenemos son los de OTRO operador (bonian.lawangproperties.com); meterlos aqui seria
    // fabricar la cifra por la que luego se puja. Se rellena cuando el owner cierre precio.

    list($code, $out) = lawang_ghl_post('/contacts/upsert', $contacto, $cfg['pit']);
    $id = isset($out['contact']['id']) ? $out['contact']['id'] : null;
    if ($code < 200 || $code >= 300 || !$id) {
        error_log('GHL upsert ' . $code . ' ' . substr(json_encode($out), 0, 300));
        return false;
    }

    // Oportunidad: sin ella el CRM es una lista de contactos y el pipeline sale a cero,
    // que es justo el numero que mira el owner para decidir si la pauta funciona.
    list($c2, $o2) = lawang_ghl_post('/opportunities/', [
        'pipelineId'      => GHL_PIPELINE,
        'locationId'      => $cfg['location'],
        'pipelineStageId' => GHL_ETAPA,
        'name'            => $nombre . ' — ' . $modelo,
        'status'          => 'open',
        'contactId'       => $id,
    ], $cfg['pit']);
    if ($c2 < 200 || $c2 >= 300) {
        error_log('GHL opp ' . $c2 . ' ' . substr(json_encode($o2), 0, 300));
    }

    return true;
}
