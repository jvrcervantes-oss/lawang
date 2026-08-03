<?php
/**
 * lead.php — captura de contacto. Dos formularios, dos ficheros:
 *   · verja de descargas de la ficha de producto  → private/leads.csv       (solo email)
 *   · "Solicitar llamada" de /modelo/<id>         → private/leads_llamada.csv (nombre+tel+consentimiento)
 *
 * Ficheros separados a propósito: son datos de forma distinta y el histórico de leads.csv
 * lleva una cabecera de 5 columnas en producción. Meter filas de 8 bajo esa cabecera deja
 * un CSV que se lee mal justo el día que empiece a entrar volumen desde la pauta.
 * Sin dependencias externas.
 */
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'error' => 'method']);
    exit;
}

// Trampa de bots: el campo va oculto por CSS, un humano no lo ve. Si viene relleno se
// responde "ok" y no se guarda nada — un 4xx le diría al bot qué corregir.
if (trim(isset($_POST['website']) ? $_POST['website'] : '') !== '') {
    echo json_encode(['ok' => true]);
    exit;
}

// Freno de caudal: este endpoint es publico por diseno (lo llama el formulario), asi que
// nada impedia meter miles de filas en Supabase y disparar otros tantos correos SMTP.
// Cubo separado por formulario, y mas holgado en el de llamada: la pauta va a moviles
// españoles bajo CGNAT, donde cientos de visitantes comparten IP publica. Con el cubo
// compartido de 8, el 9º visitante de la campaña recibia un 429 sin haber enviado nada.
require_once __DIR__ . '/throttle.php';
$__ip     = $_SERVER['REMOTE_ADDR'] ?? 'sin-ip';
$__llamada = trim(isset($_POST['name']) ? $_POST['name'] : '') !== ''
          || trim(isset($_POST['phone']) ? $_POST['phone'] : '') !== '';
$__cubo   = ($__llamada ? 'llamada_' : 'lead_') . $__ip;
$__tope   = $__llamada ? 15 : 8;
if (lawang_throttle_blocked($__cubo, $__tope, 600)) {
    http_response_code(429);
    header('Retry-After: 600');
    echo json_encode(['ok' => false, 'error' => 'too_many']);
    exit;
}
lawang_throttle_register($__cubo, 600);

$email    = isset($_POST['email'])    ? trim($_POST['email'])    : '';
$source   = isset($_POST['source'])   ? trim($_POST['source'])   : '';
$property = isset($_POST['property']) ? trim($_POST['property']) : '';

// Validación de email
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(422);
    echo json_encode(['ok' => false, 'error' => 'email']);
    exit;
}

// Recorta campos para evitar inyección de CSV / payloads enormes
$clean = function ($s) {
    $s = preg_replace('/[\r\n]+/', ' ', $s);
    $s = mb_substr($s, 0, 200);
    // Anti inyección de fórmula CSV (Excel ejecuta celdas que empiezan por = + - @)
    if ($s !== '' && strpos('=+-@', $s[0]) !== false) {
        $s = "'" . $s;
    }
    return $s;
};
$source   = $clean($source);
$property = $clean($property);
// El email tambien: `filter_var` da por bueno un local-part que empieza por = + - @
// (ej. "=cmd|'/c calc'!A0"@x.com) y ventas abre este CSV en Excel.
$email    = $clean($email);
// Atribucion de campaña. Sin esto no hay coste por lead por anuncio ni forma de subir
// la conversion offline cuando la venta se cierre por telefono semanas despues.
$campana  = $clean(isset($_POST['campana']) ? trim($_POST['campana']) : '');

// private/ no es servible por web (fuera del docroot lógico); se crea si falta
$dir = __DIR__ . '/../private';
if (!is_dir($dir)) { @mkdir($dir, 0755, true); }

// ── Solicitud de llamada (landing /modelo/<id>) ────────────────────────────────
// Se distingue por traer nombre o teléfono. Aquí los tres campos son obligatorios:
// un lead de ticket alto sin teléfono no se puede trabajar, y sin consentimiento
// expreso no se puede contactar a un residente en la UE (RGPD).
$name  = $clean(isset($_POST['name'])  ? trim($_POST['name'])  : '');
$phone = $clean(isset($_POST['phone']) ? trim($_POST['phone']) : '');
/**
 * Rango de presupuesto que ELIGE el lead. Es lo que separa el seguimiento por gama en el
 * CRM, asi que no hace falta abrir una campana de Meta por cada gama.
 *
 * Se guarda el RANGO, no una cifra. Un importe obliga a inventar el suelo de cada tramo
 * (nuestros precios no estan cerrados; los unicos que existen son los de otro operador),
 * hace que dos tramos se toquen en su frontera, y en GHL un campo de moneda se pinta en
 * la divisa de la location — que no es EUR — asi que el comercial leeria otra cantidad.
 * El rango no tiene ninguno de los tres problemas.
 *
 * En el formulario viaja un codigo corto y no la etiqueta: asi se puede reescribir el texto
 * de cara al usuario sin que un `<option>` cacheado en un navegador deje de casar con la
 * lista. Al CSV y al CRM va la etiqueta, que es lo que lee una persona.
 */
$rangos = [
    'bajo'  => 'Menos de 100.000 EUR',
    'medio' => 'Entre 100.000 y 175.000 EUR',
    'alto'  => 'Mas de 175.000 EUR',
    'nose'  => 'Todavia no lo tiene claro',
];
$rango = isset($_POST['presupuesto']) ? (string) $_POST['presupuesto'] : '';
if (!isset($rangos[$rango])) $rango = '';   // fuera de la lista = no contesto

if ($name !== '' || $phone !== '') {
    $consent = isset($_POST['consent']) && $_POST['consent'] === '1';
    if ($name === '' || $phone === '' || !$consent) {
        http_response_code(422);
        echo json_encode(['ok' => false, 'error' => 'campos']);
        exit;
    }

    $file = $dir . '/leads_llamada.csv';

    // La cabecera solo se escribe cuando el fichero NACE, y en produccion ya existe con las
    // 10 columnas de antes. Sin esto, las filas nuevas traen 11 valores bajo 10 nombres:
    // ventas abre una columna sin titulo y cualquier lectura por cabecera (Excel, pandas)
    // desalinea o revienta. Corre una sola vez — en cuanto la cabecera lleva `presupuesto`
    // la condicion es falsa para siempre.
    if (is_file($file) && ($__fh = @fopen($file, 'r'))) {
        $__cab = fgetcsv($__fh);
        fclose($__fh);
        if ($__cab && !in_array('presupuesto', $__cab, true)) {
            $__lineas = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            if ($__lineas) {
                $__lineas[0] .= ',presupuesto';
                // Temporal + rename, nunca escritura en sitio: si el proceso muere a mitad,
                // el CSV con los leads reales sigue entero. rename() sobre el mismo volumen
                // es atomico, asi que ventas nunca ve el fichero a medias.
                $__tmp = $file . '.tmp';
                if (@file_put_contents($__tmp, implode("\n", $__lineas) . "\n", LOCK_EX) !== false) {
                    @rename($__tmp, $file);
                } else {
                    @unlink($__tmp);
                }
            }
        }
    }

    $new  = !file_exists($file);
    $fh   = @fopen($file, 'a');
    if ($fh === false) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'write']);
        exit;
    }

    // Aviso a ventas. Un formulario que solo escribe en un CSV que nadie abre no es
    // captación: el lead se enfría en el disco. Se guarda si el envío salió o no,
    // que es lo único que permite darse cuenta de que el correo dejó de salir.
    $enviado = @mail(
        'sales@lawangproperties.com',
        'Nueva solicitud de llamada - ' . ($property !== '' ? $property : 'web'),
        "Modelo: $property\nNombre: $name\nEmail: $email\nTelefono: $phone\n"
        // "no contesto" y "eligio no saberlo" NO son lo mismo para quien va a llamar: el
        // segundo es un lead trabajable que dijo algo. Colapsarlos en "sin definir" tira
        // justo la senal que este campo venia a dar.
        . 'Presupuesto: ' . ($rango !== '' ? $rangos[$rango] : 'no contesto') . "\n"
        . "Origen: $source\nCampana: $campana\nFecha: " . date('c'),
        // From de un buzón del propio dominio: con un remitente ajeno el correo cae en spam.
        "From: no-reply@lawangproperties.com\r\nReply-To: $email\r\n"
        . "Content-Type: text/plain; charset=UTF-8\r\n",
        // Envelope sender. Sin -f, Hostinger manda con el usuario del sistema como
        // remitente de sobre, el SPF de lawangproperties.com falla y el aviso cae en
        // spam. Mismo parametro que usa contracts/api/send_email.php.
        '-fno-reply@lawangproperties.com'
    ) ? 'si' : 'NO';

    // La columna nueva va al FINAL y no junto a `modelo`, que es donde encajaria leyendolo:
    // en medio desalinearia todas las filas ya escritas.
    if ($new) {
        fputcsv($fh, ['timestamp', 'nombre', 'email', 'telefono', 'modelo', 'source', 'campana', 'consentimiento', 'ip', 'avisado', 'presupuesto']);
    }
    fputcsv($fh, [
        date('c'), $name, $email, $phone, $property, $source, $campana, 'si',
        isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '',
        // La etiqueta, no el codigo: este CSV lo abre ventas, y "alto" no le dice nada.
        $enviado, $rango !== '' ? $rangos[$rango] : '',
    ]);
    fclose($fh);

    // Se responde ANTES de hablar con el CRM. Dos llamadas HTTP salientes son hasta 8s de
    // espera, y el evento `Lead` del pixel se dispara en el `.then` de este fetch: si el
    // visitante cierra el movil durante la espera, la fila esta en el CSV pero Meta nunca
    // ve la conversion y la campana optimiza contra un numero falso.
    echo json_encode(['ok' => true]);
    if (function_exists('litespeed_finish_request')) litespeed_finish_request(); // Hostinger
    elseif (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
    else { @ob_end_flush(); @flush(); } // sin FPM el visitante espera igual, pero no se pierde nada

    // CRM. Va el ultimo y no rompe nada si falla: el lead ya esta en el CSV y ventas ya
    // tiene el correo. Solo entran aqui los leads de llamada — la verja de descargas es
    // solo un email y ensuciaria el pipeline con contactos que no se pueden trabajar.
    require_once __DIR__ . '/ghl.php';
    lawang_ghl_upsert($name, $email, $phone, $property, $source, $campana,
        $rango !== '' ? $rangos[$rango] : '');
    exit;
}

// ── Verja de descargas (solo email) ────────────────────────────────────────────
$file = $dir . '/leads.csv';

$new = !file_exists($file);
$fh  = @fopen($file, 'a');
if ($fh === false) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'write']);
    exit;
}
if ($new) {
    fputcsv($fh, ['timestamp', 'email', 'source', 'property', 'ip']);
}
fputcsv($fh, [
    date('c'),
    $email,
    $source,
    $property,
    $_SERVER['REMOTE_ADDR'] ?? '',
]);
fclose($fh);

echo json_encode(['ok' => true]);
