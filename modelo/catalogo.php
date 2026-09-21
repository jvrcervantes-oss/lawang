<?php
/**
 * catalogo.php — de dónde saca la web los modelos de villa. 7-sep-2026.
 *
 * ANTES: `modelos.php` era un array escrito a mano en el repo. Eso violaba la
 * norma «si el cliente lo puede dar de alta, no puede vivir en un fichero»
 * (contexto/suite_lawang.md, 17-ago-2026) y ya había mordido: el 7-sep la web
 * publicaba Dune a 68.000 € y la intranet precargaba los contratos con 64.000,
 * porque eran dos ficheros distintos que nadie cruzaba.
 *
 * AHORA: la fuente es la tabla `modelos` de Supabase, que se edita desde
 * /intranet/modelos/. Esta capa la trae y la deja con la MISMA forma de array
 * que tenía el fichero, para que `index.php`, `lib.php`, `datos.php` y
 * `test_modelo.php` no se enteren. Ese contrato es deliberado: cambiar de dónde
 * sale un dato no tiene por qué cambiar a quien lo usa.
 *
 * TRES NIVELES, y ninguno es opcional
 * -----------------------------------
 * 1. CACHÉ EN DISCO (5 min). Una página pública no puede salir a la red en cada
 *    visita: son ~200 ms de un tercero metidos en el camino crítico de una
 *    landing de campaña. Con 5 minutos, un cambio de precio del owner está
 *    publicado enseguida y la web sigue siendo un fichero local el 99% de las
 *    veces.
 * 2. RED, solo cuando la caché ha caducado. Si falla, NO se rompe la página:
 *    se sigue sirviendo la caché vieja. Una web sin precios no es más segura
 *    que una con el precio de hace diez minutos, es solo una web rota.
 * 3. RESPALDO VERSIONADO (`catalogo_respaldo.json`). Para el arranque en frío:
 *    servidor recién desplegado, sin caché todavía, y Supabase sin responder.
 *    Sin esto ese caso da una web sin ningún modelo.
 *
 * ⚠️ EL RESPALDO NO ES UNA SEGUNDA FUENTE Y NO SE EDITA A MANO. Es una foto que
 * regenera `php modelo/catalogo.php --respaldo`. Si alguien corrige un precio
 * ahí, ese cambio vive hasta el siguiente fetch con red y luego desaparece sin
 * avisar — que es la peor forma de fallar. El precio se cambia en
 * /intranet/modelos/.
 *
 * LO QUE ESTA CAPA NO PUEDE VER, a propósito: `catalogo_publico()` es una
 * FUNCIÓN de la base, no una tabla abierta, y devuelve solo los modelos con
 * `publicado = true` y solo columnas elegidas a mano. Ni las notas internas ni
 * `modelos_villa` —los precios pactados por proyecto— salen de ahí. Con una
 * policy sobre la tabla, una columna nueva se publicaría sola el día que
 * alguien la añadiera; con una función, no.
 */

// Clave PUBLICABLE (la misma que ya sirve `contracts/assets/guard.js` a
// cualquier visitante). No es un secreto: lo que protege los datos es la RLS y
// el hecho de que esto sea una función acotada, no la clave.
const LW_SB_URL  = 'https://vtulllundrfennhjddhc.supabase.co';
const LW_SB_KEY  = 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg';
const LW_CAT_TTL = 300;   // segundos

/** Dónde se escribe la caché. `private/` está cerrado por .htaccess; si no se
 *  puede escribir ahí (permisos de un deploy nuevo), el temporal del sistema
 *  sirve igual — es una caché, no un dato que haya que conservar. */
function lw_cat_cache_path() {
    $priv = __DIR__ . '/../private';
    if (is_dir($priv) && is_writable($priv)) return $priv . '/catalogo_modelos.json';
    return sys_get_temp_dir() . '/lw_catalogo_modelos.json';
}

/** Trae el catálogo de Supabase. Devuelve el array o null si no se pudo. */
function lw_cat_fetch() {
    if (!function_exists('curl_init')) return null;
    $ch = curl_init(LW_SB_URL . '/rest/v1/rpc/catalogo_publico');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => '{}',
        CURLOPT_RETURNTRANSFER => true,
        // Cortos a propósito: esto está en el camino de una página pública. Más
        // vale servir la caché vieja que hacer esperar tres segundos a alguien
        // que llegó por un anuncio.
        CURLOPT_TIMEOUT        => 4,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER     => [
            'apikey: ' . LW_SB_KEY,
            'Content-Type: application/json',
        ],
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($body) || $body === '') return null;
    $d = json_decode($body, true);
    // Un array vacío es una respuesta VÁLIDA de la API y a la vez una web sin
    // modelos. Se trata como fallo: es mucho más probable que sea un despiste
    // (todos sin publicar) que la intención real de vaciar el catálogo.
    return (is_array($d) && $d) ? $d : null;
}

/** La forma que espera el resto del sitio. Lo que llega de la base es casi eso;
 *  aquí se rellenan las claves que la plantilla da por hechas. */
function lw_cat_normaliza(array $d) {
    $out = [];
    foreach ($d as $slug => $m) {
        // `_aviso` es un STRING hermano de los modelos que `--respaldo` (mas abajo)
        // escribe en catalogo_respaldo.json para quien abra el JSON a mano — nunca un
        // modelo. Sin este salto, el arranque en frio sin red (el UNICO camino que lee
        // el respaldo) tiraba abajo /dali, /palmfield y /modelo/<id> con un fatal ("no se
        // puede usar un string como array") justo el dia que la caché habia caducado Y
        // Supabase no respondia — el caso exacto para el que existe el respaldo. El
        // `unset($m['_aviso'])` de mas abajo NO arreglaba esto: `_aviso` nunca estuvo
        // DENTRO de un `$m` de modelo, asi que ese unset no borraba nada (hallazgo de
        // verificacion local, 21-sep-2026 — `php -S` + `php -l` disponibles por primera
        // vez en el entorno).
        if ($slug === '_aviso' || !is_array($m)) continue;
        // `sub_en` existe porque la plantilla lo lee. Desde el pivote australiano
        // (2-sep) el sitio es solo inglés y `lw_i18n` ya solo pinta la versión en
        // inglés, así que las dos claves llevan el mismo texto — pero quitar una
        // dejaría la ficha sin subtítulo, que es una regresión silenciosa.
        $m['sub']    = $m['sub'] ?? '';
        $m['sub_en'] = $m['sub'];
        // La ficha itera `incluido` y busca `incluido_en` con fallback. Se
        // rellenan los dos por el mismo motivo de arriba.
        if (!empty($m['alcance']) && is_array($m['alcance'])) {
            $m['alcance']['incluido']       = $m['alcance']['incluido']    ?? [];
            $m['alcance']['no_incluido']    = $m['alcance']['no_incluido'] ?? [];
            $m['alcance']['incluido_en']    = $m['alcance']['incluido'];
            $m['alcance']['no_incluido_en'] = $m['alcance']['no_incluido'];
        }
        if (!empty($m['acabados']) && is_array($m['acabados'])) {
            foreach ($m['acabados'] as $i => $a) {
                $m['acabados'][$i]['n_en'] = $a['n_en'] ?? ($a['n'] ?? '');
                $m['acabados'][$i]['d_en'] = $a['d_en'] ?? ($a['d'] ?? '');
            }
        }
        // Numéricos de verdad: la plantilla hace (int) y compara, y un "47" de
        // JSON colándose como texto es de los que no dan error, solo un orden raro.
        foreach (['dormitorios', 'banos', 'villa_m2', 'terraza_m2'] as $k) {
            if (isset($m[$k])) $m[$k] = 0 + $m[$k];
        }
        if (!empty($m['techos'])) {
            foreach ($m['techos'] as $ck => $t) {
                foreach (['now', 'y2027'] as $k) {
                    if (isset($t[$k])) $m['techos'][$ck][$k] = 0 + $t[$k];
                }
            }
        }
        if (!empty($m['extras'])) {
            foreach ($m['extras'] as $ek => $v) $m['extras'][$ek] = 0 + $v;
        }
        $out[$slug] = $m;
    }
    return $out;
}

/** El catálogo, por los tres niveles. `static` porque `modelos.php` se requiere
 *  desde varios sitios en la misma petición y no tiene sentido leer el disco
 *  cuatro veces. */
function lw_catalogo() {
    static $memo = null;
    if ($memo !== null) return $memo;

    $cache  = lw_cat_cache_path();
    $fresca = is_file($cache) && (time() - filemtime($cache) < LW_CAT_TTL);

    if ($fresca) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d) && $d) return $memo = lw_cat_normaliza($d);
    }

    if ($d = lw_cat_fetch()) {
        // Escritura atómica: un rename sobre el mismo sistema de ficheros. Sin
        // esto, dos visitas simultáneas pueden leer un JSON a medio escribir, y
        // eso da una web sin modelos durante un instante imposible de reproducir.
        $tmp = $cache . '.' . getmypid() . '.tmp';
        if (@file_put_contents($tmp, json_encode($d, JSON_UNESCAPED_UNICODE)) !== false) {
            @rename($tmp, $cache);
        }
        return $memo = lw_cat_normaliza($d);
    }

    // La red falló. Caché vieja antes que nada: una web con el precio de hace un
    // rato es infinitamente mejor que una web sin precios.
    if (is_file($cache)) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d) && $d) return $memo = lw_cat_normaliza($d);
    }

    // Arranque en frío sin red. El respaldo versionado es el último recurso.
    $resp = __DIR__ . '/catalogo_respaldo.json';
    if (is_file($resp)) {
        $d = json_decode((string) @file_get_contents($resp), true);
        if (is_array($d) && $d) return $memo = lw_cat_normaliza($d);
    }

    return $memo = [];
}

/**
 * ── Fotos de modelo (21-sep-2026) ────────────────────────────────────────────────────
 *
 * MISMOS tres niveles de arriba, mismo motivo: `lw_modelo_imgs()` (modelo/lib.php) leía
 * antes `assets/img/buildings/<id>/web/*.webp` EN DISCO — nadie las podía subir desde la
 * intranet, hacía falta un deploy para añadir o quitar una foto. La fuente real es
 * `deck_fotos` (ambito='modelo'), la misma tabla que ya alimenta el investor deck desde
 * /intranet/modelos/ → "Fotos del deck...". Ver la migración `modelo_fotos_publico.sql`
 * para el porqué completo (el dato tiene un dueño, RLS, bucket público).
 *
 * Cada foto trae `path` (relativo al bucket `deck`, público) y `pie` (el `alt` real, no
 * inventado — el uploader de la intranet lo exige en inglés antes de guardar).
 */
function lw_fotos_cache_path() {
    $priv = __DIR__ . '/../private';
    if (is_dir($priv) && is_writable($priv)) return $priv . '/catalogo_fotos_modelo.json';
    return sys_get_temp_dir() . '/lw_catalogo_fotos_modelo.json';
}

function lw_fotos_fetch() {
    if (!function_exists('curl_init')) return null;
    $ch = curl_init(LW_SB_URL . '/rest/v1/rpc/modelo_fotos_publico');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => '{}',
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 4,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER     => [
            'apikey: ' . LW_SB_KEY,
            'Content-Type: application/json',
        ],
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($body) || $body === '') return null;
    $d = json_decode($body, true);
    // A diferencia de lw_cat_fetch(): un objeto vacío SÍ es válido aquí (un modelo
    // recién publicado puede no tener fotos todavía, y eso no debe tirar la caché
    // entera a "fallo de red" — sería servir fotos de ayer para TODOS los modelos
    // solo porque uno nuevo está vacío).
    return is_array($d) ? $d : null;
}

function lw_fotos_catalogo() {
    static $memo = null;
    if ($memo !== null) return $memo;

    $cache  = lw_fotos_cache_path();
    $fresca = is_file($cache) && (time() - filemtime($cache) < LW_CAT_TTL);

    if ($fresca) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d)) return $memo = $d;
    }

    $d = lw_fotos_fetch();
    if ($d !== null) {
        $tmp = $cache . '.' . getmypid() . '.tmp';
        if (@file_put_contents($tmp, json_encode($d, JSON_UNESCAPED_UNICODE)) !== false) {
            @rename($tmp, $cache);
        }
        return $memo = $d;
    }

    if (is_file($cache)) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d)) return $memo = $d;
    }

    $resp = __DIR__ . '/catalogo_fotos_respaldo.json';
    if (is_file($resp)) {
        $d = json_decode((string) @file_get_contents($resp), true);
        if (is_array($d)) { unset($d['_aviso']); return $memo = $d; }
    }

    return $memo = [];
}

/** URLs públicas ya resueltas de un modelo, en el orden que fijó quien las subió desde
 *  la intranet (`orden` de deck_fotos) — nunca alfabético ni por fecha de subida.
 *  `$cat` es inyectable (fixture de test_modelo.php); por defecto, la caché/red real. */
function lw_fotos_urls($id, $cat = null) {
    $cat = $cat ?? lw_fotos_catalogo();
    if (empty($cat[$id]) || !is_array($cat[$id])) return [];
    $out = [];
    foreach ($cat[$id] as $f) {
        if (!empty($f['path'])) $out[] = LW_SB_URL . '/storage/v1/object/public/deck/' . $f['path'];
    }
    return $out;
}

/**
 * URL pública de la primera foto de un modelo cuyo PIE (el `alt` real, subido desde la
 * intranet) contenga alguno de los patrones dados, en orden de preferencia. Sin match,
 * `null` — quien llama decide el respaldo posicional, esto no inventa una foto.
 *
 * Existe porque el pie ya no es un adorno: desde que las fotos vienen de `deck_fotos`
 * (21-sep-2026) cada una trae una etiqueta real ("Dali Top View", "Bamboo Exterior") que
 * dice QUÉ es, y adivinarlo por posición (antes "la 3ª foto es el techo bambú porque así
 * las miré yo una vez") se desincroniza en cuanto alguien reordena o añade fotos desde
 * /intranet/modelos/. Buscar por texto es la misma fuente que ya ve el visitante.
 *
 * `$cat` inyectable por el mismo motivo que `lw_fotos_urls()`: `test_modelo.php` prueba
 * el orden de preferencia y el respaldo sin depender de qué haya subido nadie hoy a
 * /intranet/modelos/ (ni de tener red desde donde se corra el test).
 */
function lw_foto_por_pie($id, array $patrones, $cat = null) {
    $cat = $cat ?? lw_fotos_catalogo();
    if (empty($cat[$id]) || !is_array($cat[$id])) return null;
    foreach ($patrones as $patron) {
        foreach ($cat[$id] as $f) {
            if (empty($f['path']) || empty($f['pie'])) continue;
            if (stripos($f['pie'], $patron) !== false) {
                return LW_SB_URL . '/storage/v1/object/public/deck/' . $f['path'];
            }
        }
    }
    return null;
}

/* Regenerar los respaldos:  php modelo/catalogo.php --respaldo
   Solo CLI. Se corre cuando se cambia algo del catálogo que deba sobrevivir a un
   arranque en frío sin red; no hace falta en cada edición de precio o cada foto nueva. */
if (PHP_SAPI === 'cli' && isset($argv[1]) && $argv[1] === '--respaldo') {
    $d = lw_cat_fetch();
    if (!$d) { fwrite(STDERR, "No se ha podido leer el catálogo de Supabase.\n"); exit(1); }
    $d['_aviso'] = 'FOTO GENERADA — no editar a mano. La fuente es la tabla `modelos` '
                 . 'de Supabase, que se edita en /intranet/modelos/. Se regenera con '
                 . '`php modelo/catalogo.php --respaldo`. Un cambio hecho aquí vive hasta '
                 . 'el siguiente fetch con red y luego desaparece sin avisar.';
    file_put_contents(__DIR__ . '/catalogo_respaldo.json',
        json_encode($d, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");
    unset($d['_aviso']);
    echo 'Respaldo regenerado: ' . count($d) . " modelos.\n";

    $df = lw_fotos_fetch();
    if ($df === null) { fwrite(STDERR, "No se ha podido leer las fotos de Supabase.\n"); exit(1); }
    $df['_aviso'] = 'FOTO GENERADA — no editar a mano. La fuente es `deck_fotos`, que se '
                  . 'edita en /intranet/modelos/ → "Fotos del deck...". Se regenera con '
                  . '`php modelo/catalogo.php --respaldo`.';
    file_put_contents(__DIR__ . '/catalogo_fotos_respaldo.json',
        json_encode($df, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");
    unset($df['_aviso']);
    echo 'Respaldo de fotos regenerado: ' . count($df) . " modelos.\n";
}
