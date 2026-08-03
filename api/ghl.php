<?php
/**
 * ghl.php — alta del lead en GoHighLevel (CRM) desde el formulario de /modelo/<id>.
 *
 * Se llama DESPUES de escribir el CSV, de avisar a ventas y de haber respondido ya al
 * navegador. Falla en silencio: si GHL esta caido o el token caduco, el lead ya esta
 * guardado y el comercial ya tiene el correo. Un CRM que devuelve 500 no puede tumbar la
 * captacion de un clic pagado.
 *
 * Credenciales fuera de git, en JSON y NO en PHP:
 *   private/ghl.json  ->  {"pit": "pit-xxx", "location": "vOEs...", "usuario": "SbNu..."}
 * Lo escribe el owner a mano. Un .php escrito a mano puede traer un BOM, un salto tras el
 * cierre o un punto y coma de menos, y eso no es un valor raro: es salida suelta o un parse
 * error que mata el request DESPUES de haber escrito el CSV y mandado el correo — el
 * visitante veria "no hemos podido enviar" y reenviaria, duplicando fila y aviso. Un JSON
 * mal escrito solo devuelve null.
 *
 * API v2 (LeadConnector). La v1 murio el 31-dic-2025: la cabecera Version es obligatoria
 * en toda llamada y su ausencia devuelve 401, no 400.
 */

// Es un include, no un endpoint: pedirlo directo devolvia 200 con cuerpo vacio. No filtraba
// nada —solo define funciones— pero un fichero alcanzable es superficie que no hace falta, y
// si un dia PHP muestra un error aqui, el error lleva rutas. Mismo guard que `config.php`.
// Va ADEMAS de la regla del .htaccess, no en su lugar: `RedirectMatch` casa la URL y se
// esquiva con PATH_INFO (`/api/ghl.php/x`), como se vio el 3-ago-2026 con los arneses.
if (basename($_SERVER['SCRIPT_FILENAME'] ?? '') === 'ghl.php') {
    http_response_code(404);
    exit;
}

const GHL_BASE    = 'https://services.leadconnectorhq.com';
const GHL_VERSION = '2021-07-28';

// Campos personalizados de la location (creados por API el 29-jul-2026). Van por id y no
// por fieldKey: el key se puede renombrar desde la UI y el id no.
const GHL_CF_MODELO = 'KUGzZ2Kv9t0DiUq013mk'; // SINGLE_OPTIONS: el valor DEBE estar en la lista
const GHL_CF_ORIGEN = 'HzpYLNaXWv1EACm9dEJ0';
// SINGLE_OPTIONS y no el MONETORY `ticket_estimado_eur` que existe al lado: GHL pinta los
// campos de moneda en la divisa de la LOCATION, que no es EUR, asi que el comercial leeria
// "175.000 $" donde el lead dijo euros. Ademas un importe obliga a inventar el suelo de
// cada tramo. `ticket_estimado_eur` se queda vacio hasta que el owner cierre precio.
const GHL_CF_RANGO = '96nFi6lSogaQagjTw3Lj'; // el valor DEBE estar en la lista de opciones

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
 * Rastro de los leads que NO entraron al CRM. El fichero solo existe si algo fallo, asi
 * que su presencia ES el aviso. Sin esto, con el token caducado los leads dejan de entrar
 * en el pipeline y no hay forma de saber cuantos faltan: el `error_log` no lo mira nadie
 * y ademas no puede llevar datos personales.
 */
function lawang_ghl_pendiente($email, $modelo, $paso, $code)
{
    $dir  = __DIR__ . '/../private';
    $file = $dir . '/crm_pendientes.csv';
    $new  = !file_exists($file);
    $fh   = @fopen($file, 'a');
    if ($fh === false) return;
    if ($new) fputcsv($fh, ['timestamp', 'email', 'modelo', 'paso', 'http']);
    fputcsv($fh, [date('c'), $email, $modelo, $paso, $code]);
    fclose($fh);
}

/**
 * Da de alta (o actualiza) el contacto y su oportunidad en el pipeline.
 * Devuelve true solo si el contacto entro. Nunca lanza.
 */
function lawang_ghl_upsert($nombre, $email, $tel, $modeloId, $origen, $campana, $rango = '')
{
    $path = __DIR__ . '/../private/ghl.json';
    if (!is_file($path) || !function_exists('curl_init')) return false;
    $cfg = json_decode((string) @file_get_contents($path), true);
    if (!is_array($cfg) || empty($cfg['pit']) || empty($cfg['location'])) return false;

    $partes = preg_split('/\s+/', trim($nombre), 2);
    $modelo = lawang_ghl_modelo($modeloId);

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
    // Rango que declara el LEAD, nunca derivado de nuestro precio: los unicos que tenemos
    // son los de OTRO operador (bonian.lawangproperties.com) y pujar por un numero
    // fabricado decide mal el gasto. Vacio = no contesto. Ojo: "Todavia no lo tiene claro"
    // SI es una respuesta y viaja como opcion — no es lo mismo que el silencio.
    if ($rango !== '') {
        $contacto['customFields'][] = ['id' => GHL_CF_RANGO, 'field_value' => $rango];
    }

    list($code, $out) = lawang_ghl_post('/contacts/upsert', $contacto, $cfg['pit']);
    $id = isset($out['contact']['id']) ? $out['contact']['id'] : null;
    if ($code < 200 || $code >= 300 || !$id) {
        // Solo codigo y traceId: el cuerpo de error de GHL devuelve los valores enviados
        // (telefono, email) y el log de PHP no tiene retencion ni borrado.
        error_log('GHL contacto ' . $code . ' trace=' . (isset($out['traceId']) ? $out['traceId'] : '-'));
        lawang_ghl_pendiente($email, $modelo, 'contacto', $code);
        return false;
    }

    // `upsert` y no `POST /opportunities/`: el mismo lead que vuelve otro dia o llega por
    // dos anuncios abriria una segunda oportunidad en "New Lead", y ese recuento es el
    // unico numero con el que se juzga si la pauta funciona — inflado, decide mal el gasto.
    $opp = [
        'pipelineId'      => GHL_PIPELINE,
        'locationId'      => $cfg['location'],
        'pipelineStageId' => GHL_ETAPA,
        'name'            => $nombre . ' — ' . $modelo,
        'status'          => 'open',
        'contactId'       => $id,
    ];
    // Sin dueno, una oportunidad sin atender es indistinguible de una recien entrada.
    if (!empty($cfg['usuario'])) $opp['assignedTo'] = $cfg['usuario'];

    list($c2, $o2) = lawang_ghl_post('/opportunities/upsert', $opp, $cfg['pit']);
    if ($c2 < 200 || $c2 >= 300) {
        error_log('GHL oportunidad ' . $c2 . ' trace=' . (isset($o2['traceId']) ? $o2['traceId'] : '-'));
        lawang_ghl_pendiente($email, $modelo, 'oportunidad', $c2);
    }

    return true;
}
