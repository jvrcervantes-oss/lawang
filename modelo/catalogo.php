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
        unset($m['_aviso']);
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

/* Regenerar el respaldo:  php modelo/catalogo.php --respaldo
   Solo CLI. Se corre cuando se cambia algo del catálogo que deba sobrevivir a un
   arranque en frío sin red; no hace falta en cada edición de precio. */
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
}
