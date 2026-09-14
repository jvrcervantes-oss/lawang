<?php
/**
 * palmfield/vivo.php — lo que /palmfield/index.php lee en vivo de Supabase. 14-sep-2026.
 *
 * Mismo patrón de tres niveles que `modelo/catalogo.php` (caché en disco 5 min -> red ->
 * caché vieja si la red falla): ver ese fichero para el porqué de cada nivel, no se repite
 * aquí. Reutiliza sus constantes `LW_SB_URL`/`LW_SB_KEY` (la clave publicable, la misma
 * que ya sirve el catálogo de modelos — no es secreta, la protege la función acotada).
 *
 * DOS cosas, cada una con su RPC público ya declarado en
 * `departamentos/seguridad/rls_publico.txt`:
 *
 *  · Tamaños de parcela DISPONIBLES — `parcelas_tamanos_disponibles()` (nueva,
 *    14-sep, revisión previa Seguridad+Datos). Sustituye el array `$PF_PARCELAS`
 *    escrito a mano el 4-sep, que ya había divergido de la realidad (traía 330 y 355,
 *    vendidos/bloqueados desde entonces; le faltaba 295).
 *
 *    ⚠️ SOLO alimenta la lista que se ENSEÑA. Nunca el precio: `$desdeTotal` (hero,
 *    meta/og, tabla comparativa Y el `value` que se manda al pixel de conversión de
 *    Meta Ads) sigue anclado a `LW_PF_TAMANO_MIN_PRECIO`, una constante fija y fechada
 *    en `index.php` — hallazgo de Datos en la revisión previa: el precio de portada de
 *    una landing de campaña de pago no puede moverse solo cada vez que se vende una
 *    parcela, eso es la zona gris del hard-stop de precio (CLAUDE.md). Si algún día se
 *    quiere que el precio SÍ siga al inventario en vivo, es una decisión del owner, no
 *    una consecuencia de leer esta lista.
 *
 *  · Fotos del HERO — reutiliza `investor_deck_fotos()` (ya en producción, la misma
 *    que usa investor-deck/palmfield desde el 11-sep), filtrando aquí las filas SIN
 *    `modelo_slug` (ámbito=proyecto) y con `uso='hero'`. Si no hay ninguna — el caso de
 *    HOY, las 4 fotos del proyecto en Supabase son renders de galería sin marcar como
 *    hero — el llamador se queda con las 4 imágenes estáticas ya curadas, una de las
 *    cuales es la ÚNICA foto real de obra que tiene la página: un render genérico sin
 *    marcar no la sustituye.
 */

require_once __DIR__ . '/../modelo/catalogo.php'; // LW_SB_URL, LW_SB_KEY

const LW_PF_PROYECTO = 'Palm Field W5';
const LW_PF_TTL       = 300; // segundos, igual que catalogo.php

function lw_pf_cache_path($nombre) {
    $priv = __DIR__ . '/../private';
    if (is_dir($priv) && is_writable($priv)) return $priv . '/' . $nombre;
    return sys_get_temp_dir() . '/' . $nombre;
}

/** POST a un RPC público con la clave publicable. null si no se pudo (nunca []: un
 *  array vacío es una respuesta VÁLIDA aquí -- 0 fotos hero o 0 tamaños son estados
 *  legítimos, al revés que en catalogo_publico()). */
function lw_pf_rpc($fn, array $params) {
    if (!function_exists('curl_init')) return null;
    $ch = curl_init(LW_SB_URL . '/rest/v1/rpc/' . $fn);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => json_encode($params),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 4,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER     => ['apikey: ' . LW_SB_KEY, 'Content-Type: application/json'],
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($code !== 200 || !is_string($body)) return null;
    $d = json_decode($body, true);
    return is_array($d) ? $d : null;
}

/** Caché de tres niveles para un RPC de este fichero. Devuelve el array (posiblemente
 *  vacío) o null si nunca se ha podido leer nada -- ni red ni caché en disco -- para
 *  que el llamador decida su propio fallback estático. */
function lw_pf_dato($cacheNombre, $fn, array $params) {
    $cache  = lw_pf_cache_path($cacheNombre);
    $fresca = is_file($cache) && (time() - filemtime($cache) < LW_PF_TTL);

    if ($fresca) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d)) return $d;
    }

    $d = lw_pf_rpc($fn, $params);
    if ($d !== null) {
        $tmp = $cache . '.' . getmypid() . '.tmp';
        if (@file_put_contents($tmp, json_encode($d)) !== false) @rename($tmp, $cache);
        return $d;
    }

    // Red caída: caché vieja antes que nada, aunque haya caducado.
    if (is_file($cache)) {
        $d = json_decode((string) @file_get_contents($cache), true);
        if (is_array($d)) return $d;
    }

    return null; // arranque en frío sin red: el llamador decide el fallback
}

/** Tamaños de parcela disponibles HOY, ordenados y sin duplicados. null si nunca se
 *  pudo leer nada (el llamador cae al array estático). Nunca se usa para dinero. */
function lw_pf_tamanos_disponibles() {
    $rows = lw_pf_dato('lw_pf_tamanos.json', 'parcelas_tamanos_disponibles', ['p_proyecto' => LW_PF_PROYECTO]);
    if ($rows === null) return null;
    $tam = [];
    foreach ($rows as $r) {
        if (isset($r['superficie_m2'])) $tam[] = (int) $r['superficie_m2'];
    }
    $tam = array_values(array_unique($tam));
    sort($tam, SORT_NUMERIC);
    return $tam; // puede ser [] -- 0 parcelas disponibles es un estado real
}

/** Fotos del PROYECTO (nunca de un modelo) marcadas `uso='hero'`, en orden. [] si se
 *  leyó bien pero no hay ninguna (el caso de hoy) -- el llamador sigue con las 4
 *  imágenes estáticas curadas. */
function lw_pf_fotos_hero() {
    $rows = lw_pf_dato('lw_pf_fotos.json', 'investor_deck_fotos', ['p_proyecto' => LW_PF_PROYECTO]);
    if ($rows === null) return [];
    $hero = [];
    foreach ($rows as $r) {
        if (empty($r['modelo_slug']) && ($r['uso'] ?? '') === 'hero' && !empty($r['path'])) {
            $hero[] = [
                'src' => LW_SB_URL . '/storage/v1/object/public/deck/' . $r['path'],
                'pie' => is_array($r['pie'] ?? null) ? ($r['pie']['en'] ?? '') : '',
                'tipo' => $r['tipo'] ?? 'foto',
                'orden' => (int) ($r['orden'] ?? 0),
            ];
        }
    }
    usort($hero, function ($a, $b) { return $a['orden'] <=> $b['orden']; });
    return $hero;
}
