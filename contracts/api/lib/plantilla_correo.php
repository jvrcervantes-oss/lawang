<?php
declare(strict_types=1);

/**
 * Plantilla de marca compartida para TODO correo que sale de la intranet
 * (contratos, facturas, avisos internos) -- 1-sep-2026, encargo del owner:
 * unificar el formato con el mismo diseno que ya usa el email de acceso al
 * portal (contracts/edge/correo/magic-link.html, la plantilla de Supabase
 * Auth "Clients | Lawang Estate"). Antes send_email.php mandaba TODO en
 * texto plano (`Content-Type: text/plain`), sin marca ni formato -- ni
 * facturas, ni contratos, ni los avisos de Soporte nuevos.
 *
 * MISMAS REGLAS que magic-link.html, y por el mismo motivo (ver su cabecera):
 * tablas y estilos EN LINEA, sin <style> externo -- Gmail y Outlook lo
 * descartan.
 *
 * DOS DIFERENCIAS DELIBERADAS respecto al original, las dos correcciones
 * pedidas por el owner ("mira a ver si tienes que actualizar fuentes o
 * colores"):
 *   1. LOGO. Iba en base64 (data URI) por miedo a que un logo remoto saliera
 *      bloqueado. CAMBIADO el 23-sep-2026 (LAW-282) a URL absoluta en
 *      lawangproperties.com: Gmail web -- el buzon mas usado por los
 *      compradores -- NO pinta nunca un data URI y SI muestra por defecto las
 *      imagenes remotas (via su proxy); con el diseño nuevo el logo va en el
 *      centro y el hueco se notaba. Donde el cliente bloquee imagenes
 *      remotas (Outlook escritorio con la opcion por defecto), degrada al
 *      `alt` «LAWANG», igual que antes con el data URI. Es de primera parte
 *      (nuestro dominio), no un tercero como era Google Fonts.
 *   2. El boton usaba `#485B37` (Territorial Green) como color de fondo.
 *      Ese color esta declarado en TODA la suite como "acento, y SOLO
 *      acento" (ver `--tg` en intranet/index.html y comentarios
 *      hermanos) -- nunca el relleno de un boton. El boton primario real
 *      de la suite entera (`.lw-btn.primary`, `.btn-oscuro`) usa siempre
 *      `#104C4F` (Deep Lagoon, `--dl`). Se corrige aqui Y en
 *      magic-link.html, mismo dia, para que no diverjan otra vez.
 *   El resto de la paleta (fondo `#F5F0E6`, tarjeta `#FFFDF8`, borde
 *   `#E4DCCB`, texto `#2E3437`, muted `#8F9B7A`) y la tipografia (Georgia
 *   serif para titulos -- sustituto seguro de Cormorant Garamond, que no
 *   carga en un cliente de correo -- Helvetica/Arial para cuerpo) ya
 *   coincidian con el resto de la suite: no hacia falta tocarlas.
 */

// Logo por URL absoluta, no en base64 (23-sep-2026, LAW-282): Gmail web y Outlook
// escritorio no pintan imagenes data: y la cabecera salia como el alt «LAWANG».
// PNG y no WebP a proposito: Outlook escritorio no pinta WebP. Mismo fichero que
// iba en base64 (480x67), extraido byte a byte a assets/img/lawang-logo-correo.png.
const LW_CORREO_LOGO_URL = 'https://lawangproperties.com/assets/img/lawang-logo-correo.png';

/**
 * Envuelve un mensaje de TEXTO PLANO en la tarjeta de marca.
 *
 * 23-sep-2026 — DISEÑO NUEVO, estándar de TODO correo del sistema (owner:
 * «implementa esto como diseño del email estándar», maqueta Stitch
 * `plantilla_email_corporativo_profesional`). De la maqueta se tomó la PIEL:
 * barra superior con punto verde y fecha, logo centrado con filete y rótulo,
 * titular con su rayita verde, caja de acción con
 * botón en píldora Deep Lagoon, pie en lino. El TEXTO de la maqueta NO se tomó:
 * traía una TIR del 14,8 %, una autoridad monetaria de Singapur, sedes, un
 * director y una «firma criptográfica» inventados — y un correo de Lawang que
 * los repitiera sería una declaración falsa con su marca (regla del estudio,
 * reincidente dos veces: de un mockup se toma la piel, nunca el texto).
 *
 * Límites de un cliente de correo, que mandan sobre la maqueta:
 *  · tablas y estilos EN LÍNEA; nada de Tailwind ni sombras ni degradados;
 *  · LETRA: Neue Kabel, la de la web (owner, 23-sep-2026, con sus propios
 *    ficheros: assets/fonts/correo/*.woff, Regular/Medium/Bold). Va por
 *    @font-face a NUESTRO dominio, nunca por Google Fonts: la primera versión
 *    enlazaba Google y el cliente de correo del comprador le mandaba su IP, una
 *    transferencia que la política de privacidad no declara (Legal, consulta
 *    de deploy). La pintan Apple Mail, iOS y Outlook para Mac; Gmail y Outlook
 *    de escritorio ignoran @font-face y caen a Helvetica/Arial;
 *  · border-radius lo ignora Outlook de escritorio: queda cuadrado, no roto.
 *  · FONDO de la tarjeta: assets/img/correo-grano.jpg, una loseta de 512 px que
 *    se repite a 256 (nítida en retina). Es grano SINTÉTICO medido sobre la
 *    «Textura Arquitectónica Sutil» del owner (mismo color medio y misma
 *    desviación), no un recorte: el owner la quería en todo el correo sin el
 *    isotipo, y un recorte en espejo dibujaba un caleidoscopio al repetirse.
 *    Outlook de escritorio no pinta fondos: queda el Raw Linen liso de bgcolor.
 *  · MARCA DE AGUA: assets/img/correo-moanito.png — la mitad izquierda del
 *    moanito (Moanito_6.png del owner), teñida de Stone Sand al 15 % y anclada
 *    al borde derecho, así que se ve «cortado al 50 %» como pidió el owner.
 *    Se ESCALA a la altura del correo (owner, 23-sep): `background-size:
 *    auto min(calc(100% - 48px), 560px)` — en un correo corto encoge para caber
 *    entero, en uno largo se queda en 560 px. Apple Mail/iOS lo entienden;
 *    Gmail descarta la declaración entera por el min() y lo pinta a su tamaño
 *    natural, 144×560, que es el mismo tope. Outlook de escritorio no la muestra.
 *
 * El texto se escapa SIEMPRE (nunca se asume HTML de entrada). Dos marcas de
 * texto plano se pintan con forma, porque son las que ya escribe el equipo:
 *  · una línea que empieza por «• » → viñeta con punto verde;
 *  · una línea «N. TÍTULO EN MAYÚSCULAS» → rótulo de sección.
 * Todo lo demás, párrafos con sus saltos de línea tal cual.
 *
 * $encabezado: titular opcional dentro de la tarjeta.
 * $cta: ['url' => …, 'texto' => …] — lo decide quien llama (send_email.php
 *   valida la lista blanca); aquí solo se pinta, con la URL también en claro.
 * $etiqueta: rótulo de la barra superior (por defecto «Lawang Properties», owner 23-sep).
 */
/* PALETAS (owner, 23-sep-2026: «estos son los colores oficiales de Lawang, haz
   varias versiones»). SOLO los siete oficiales — Territorial Green #485B37,
   Deep Lagoon #104C4F, Burnt Earth #42210B, Soft Canopy #8F9B7A, Volcanic Ash
   #2E3437, Stone Sand #BEB3A5, Raw Linen #F5F0E6 — más `transparent`. Regla de
   la suite que se mantiene en todas: el botón es Deep Lagoon; Territorial Green
   es acento, nunca relleno de botón. Elegir otra = cambiar LW_CORREO_PALETA. */
const LW_CORREO_PALETA = 'canopy';   // elegida por el owner el 23-sep-2026
function lw_correo_paleta(string $nombre): array {
  $TG = '#485B37'; $DL = '#104C4F'; $BE = '#42210B'; $SC = '#8F9B7A';
  $VA = '#2E3437'; $SS = '#BEB3A5'; $RL = '#F5F0E6';
  $base = [
    'fondo' => $RL, 'tarjeta' => $RL, 'texto' => $VA, 'titular' => $VA, 'acento' => $TG,
    'linea' => $SS, 'caja' => $RL, 'boton' => $DL, 'boton_texto' => $RL,
    'barra_fondo' => 'transparent', 'barra_texto' => $VA, 'barra_linea' => $SS, 'barra_punto' => $TG,
    'rotulo_logo' => $SC,
    'pie_fondo' => $SS, 'pie_linea' => $SS, 'pie_texto' => $VA, 'pie_marca' => $VA,
    'pie_enlace' => $DL, 'pie_suave' => $VA,
  ];
  $variantes = [
    // lino: todo claro, verde de acento, pie en piedra
    'lino'   => [],
    // laguna: barra y pie en Deep Lagoon, titular y acentos en laguna
    'laguna' => ['fondo' => $SS, 'titular' => $DL, 'acento' => $DL,
                 'barra_fondo' => $DL, 'barra_texto' => $RL, 'barra_linea' => $DL, 'barra_punto' => $RL,
                 'pie_fondo' => $DL, 'pie_linea' => $DL, 'pie_texto' => $RL, 'pie_marca' => $RL,
                 'pie_enlace' => $RL, 'pie_suave' => $SS],
    // tierra: acentos y pie en Burnt Earth (lo de Construcción / Tepi Sungai)
    'tierra' => ['titular' => $BE, 'acento' => $BE, 'barra_punto' => $BE,
                 'pie_fondo' => $BE, 'pie_linea' => $BE, 'pie_texto' => $RL, 'pie_marca' => $RL,
                 'pie_enlace' => $RL, 'pie_suave' => $SS],
    // canopy: marco verde suave, pie en ceniza volcánica
    // canopy (la ELEGIDA, 23-sep): marco verde suave, pie en ceniza volcánica y
    // botón en Burnt Earth por decisión del owner — la única paleta donde el
    // botón no es Deep Lagoon. La caja del botón es transparente: deja ver el grano.
    'canopy' => ['fondo' => $SC, 'linea' => $SS, 'boton' => $BE, 'caja' => 'transparent',
                 'pie_fondo' => $VA, 'pie_linea' => $VA, 'pie_texto' => $RL, 'pie_marca' => $RL,
                 'pie_enlace' => $SC, 'pie_suave' => $SS],
  ];
  return array_merge($base, $variantes[$nombre] ?? []);
}

function lw_plantilla_correo(string $mensajeTexto, ?string $encabezado = null, ?array $cta = null, ?string $etiqueta = null, ?string $contacto = null, ?string $paleta = null): string {
  $C = lw_correo_paleta($paleta ?? LW_CORREO_PALETA);
  $e = fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
  // Neue Kabel, la letra de la web y de la intranet (owner, 23-sep-2026), servida
  // desde NUESTRO dominio con el @font-face de abajo — no Google Fonts, que
  // mandaba la IP del lector a un tercero. Donde el cliente no carga fuentes
  // (Gmail, Outlook) cae a Helvetica/Arial, que es de la misma familia de palo seco.
  $sans  = "'Neue Kabel','Helvetica Neue',Helvetica,Arial,sans-serif";
  $serif = $sans;   // titulares y rótulos: misma familia, otro peso

  // ── cuerpo: párrafos, viñetas y rótulos de sección ───────────────────────
  $bloques = preg_split("/\r?\n\s*\r?\n/", trim(str_replace("\r\n", "\n", $mensajeTexto)));
  $cuerpoHtml = '';
  foreach ($bloques as $bloque) {
    $lineas = explode("\n", $bloque);
    $parrafo = [];
    $vuelca = function () use (&$parrafo, &$cuerpoHtml, $e, $sans, $C) {
      if (!$parrafo) return;
      $cuerpoHtml .= '<p style="margin:0 0 18px;font-family:' . $sans . ';font-size:15px;line-height:26px;color:' . $C['texto'] . ';">'
        . implode('<br>', array_map($e, $parrafo)) . '</p>';
      $parrafo = [];
    };
    foreach ($lineas as $l) {
      $t = trim($l);
      // viñeta solo con «•» o «·»: el guion NO (23-sep-2026, Administración):
      // «- 5.000.000 IDR» escrito a mano es un importe negativo y perdía el signo
      if (preg_match('/^[•·]\s+(.+)$/u', $t, $m)) {
        $vuelca();
        $cuerpoHtml .= '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 10px;"><tr>'
          . '<td valign="top" style="width:18px;padding-top:10px;"><div style="width:6px;height:6px;border-radius:3px;background:' . $C['acento'] . ';font-size:0;line-height:0;">&nbsp;</div></td>'
          . '<td style="font-family:' . $sans . ';font-size:15px;line-height:25px;color:' . $C['texto'] . ';">' . $e($m[1]) . '</td></tr></table>';
      } elseif (preg_match('/^\d{1,2}[.)]\s+(.{3,90})$/u', $t, $m) && mb_strtoupper($m[1], 'UTF-8') === $m[1] && preg_match('/\p{Lu}{3}/u', $m[1])) {
        $vuelca();
        $cuerpoHtml .= '<div style="margin:30px 0 14px;padding-bottom:8px;border-bottom:1px solid ' . $C['linea'] . ';font-family:' . $serif . ';font-size:12px;font-weight:500;letter-spacing:2px;text-transform:uppercase;color:' . $C['acento'] . ';">'
          . $e($t) . '</div>';
      } else {
        $parrafo[] = $t;
      }
    }
    $vuelca();
  }

  // ── titular ───────────────────────────────────────────────────────────────
  $encabezadoHtml = $encabezado !== null && trim($encabezado) !== ''
    ? '<div style="font-family:' . $serif . ';font-size:26px;line-height:32px;font-weight:500;letter-spacing:-0.2px;color:' . $C['titular'] . ';">' . $e(trim($encabezado)) . '</div>'
      . '<div style="width:40px;height:2px;background:' . $C['acento'] . ';border-radius:2px;margin:10px 0 24px;font-size:0;line-height:0;">&nbsp;</div>'
    : '';

  // ── caja de acción ────────────────────────────────────────────────────────
  // Media pareja no produce medio botón, produce uno roto: sin las dos, nada.
  $ctaUrl   = is_array($cta) ? trim((string)($cta['url'] ?? '')) : '';
  $ctaTexto = is_array($cta) ? trim((string)($cta['texto'] ?? '')) : '';
  $accionHtml = '';
  $enClaroHtml = '';
  if ($ctaUrl !== '' && $ctaTexto !== '') {
    $u = $e($ctaUrl); $t = $e($ctaTexto);
    $accionHtml = <<<BTN
        <tr>
          <td style="padding:8px 40px 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{$C['caja']};border:1px solid {$C['linea']};border-radius:16px;">
              <tr>
                <td align="center" style="padding:28px 24px;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="background:{$C['boton']};border-radius:999px;">
                        <a href="{$u}" style="display:inline-block;padding:14px 32px;font-family:{$sans};font-size:12px;font-weight:600;letter-spacing:1.5px;text-transform:uppercase;color:{$C['boton_texto']};text-decoration:none;border-radius:999px;">{$t}</a>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>
BTN;
    // `mailto:` y `wa.me` no se repiten en claro: ya están en el cuerpo del aviso
    if (stripos($ctaUrl, 'http') === 0) {
      $enClaroHtml = '<p style="margin:0 0 14px;word-break:break-all;">'
        . 'Si el botón no funciona, copia esta dirección en tu navegador &middot; '
        . 'If the button does not work, paste this address into your browser:<br>'
        . '<a href="' . $u . '" style="color:' . $C['pie_enlace'] . ';">' . $u . '</a></p>';
    }
  }

  // ── barra superior: rótulo y fecha ────────────────────────────────────────
  $meses = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  $hoy = (int)date('j') . ' ' . $meses[(int)date('n') - 1] . ' ' . date('Y');
  $rotulo = $e(trim((string)$etiqueta) !== '' ? trim((string)$etiqueta) : 'Lawang Properties');
  $anio = date('Y');
  /* Contacto del pie (owner, 23-sep-2026): «admin para temas intranet y sales
     para tema ventas (investor deck, modelos…)», y precisado el mismo día: «el
     contrato para firmar viene de la intranet, el correo debe ser admin@».
     Así que admin@ POR DEFECTO — todo lo que sale de la intranet: contratos,
     firma, facturas, avisos, soporte, altas, comunicados. sales@ SOLO cuando
     quien llama lo pide: el aviso de lead de la web (api/lead.php, que cubre
     modelos y configurador) y el código del investor deck. Opt-in y no una
     lista de URLs: una lista a mano es el bug. */
  if ($contacto !== 'sales') { $contacto = 'admin'; }
  $mail = $contacto . '@lawangproperties.com';
  $logo = LW_CORREO_LOGO_URL;

  return <<<HTML
<meta charset="UTF-8">
<style>
@font-face{font-family:'Neue Kabel';src:url('https://lawangproperties.com/assets/fonts/correo/NeueKabel-Regular.woff') format('woff');font-weight:400;font-style:normal;}
@font-face{font-family:'Neue Kabel';src:url('https://lawangproperties.com/assets/fonts/correo/NeueKabel-Medium.woff') format('woff');font-weight:500;font-style:normal;}
@font-face{font-family:'Neue Kabel';src:url('https://lawangproperties.com/assets/fonts/correo/NeueKabel-Bold.woff') format('woff');font-weight:600 700;font-style:normal;}
</style>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{$C['fondo']};margin:0;padding:32px 12px;">
  <tr>
    <td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{$C['tarjeta']}" background="https://lawangproperties.com/assets/img/correo-grano.jpg" style="max-width:760px;background-color:{$C['tarjeta']};background-image:url('https://lawangproperties.com/assets/img/correo-grano.jpg');background-repeat:repeat;background-position:0 0;background-size:256px 256px;border:1px solid {$C['linea']};border-radius:16px;overflow:hidden;">

        <!-- barra superior -->
        <tr>
          <td style="padding:18px 40px 16px;background:{$C['barra_fondo']};border-bottom:1px solid {$C['barra_linea']};font-family:{$sans};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:{$C['barra_texto']};">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
              <td style="font-family:{$sans};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:{$C['barra_texto']};"><span style="display:inline-block;width:6px;height:6px;border-radius:3px;background:{$C['barra_punto']};vertical-align:middle;margin-right:8px;"></span>{$rotulo}</td>
              <td align="right" style="font-family:{$sans};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:{$C['barra_texto']};">{$hoy}</td>
            </tr></table>
          </td>
        </tr>

        <!-- marca de agua: medio moanito contra el borde derecho (owner, 23-sep-2026).
             Una capa propia con UNA sola imagen de fondo: varios fondos en el
             mismo elemento no los pinta Gmail. El grano sigue en la tarjeta. -->
        <tr>
          <td background="https://lawangproperties.com/assets/img/correo-moanito.png" style="background-image:url('https://lawangproperties.com/assets/img/correo-moanito.png');background-repeat:no-repeat;background-position:right 24px;background-size:auto min(calc(100% - 48px), 560px);">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
        <!-- marca -->
        <tr>
          <td align="center" style="padding:32px 40px 8px;">
            <img src="{$logo}" width="200" height="28" alt="LAWANG"
                 style="display:block;width:200px;height:28px;border:0;margin:0 auto;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:360px;margin:18px auto 0;"><tr>
              <td valign="middle"><div style="height:1px;background:{$C['linea']};font-size:0;line-height:0;">&nbsp;</div></td>
              <td valign="middle" style="width:1%;white-space:nowrap;padding:0 14px;font-family:{$serif};font-size:11px;letter-spacing:3px;text-transform:uppercase;color:{$C['rotulo_logo']};">Properties</td>
              <td valign="middle"><div style="height:1px;background:{$C['linea']};font-size:0;line-height:0;">&nbsp;</div></td>
            </tr></table>
          </td>
        </tr>

        <!-- cuerpo -->
        <tr>
          <td style="padding:28px 40px 8px;">
            {$encabezadoHtml}
            {$cuerpoHtml}
          </td>
        </tr>

{$accionHtml}
            </table>
          </td>
        </tr>
        <!-- pie -->
        <tr>
          <td style="padding:32px 0 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{$C['pie_fondo']};border-top:1px solid {$C['pie_linea']};">
              <tr>
                <td style="padding:26px 40px 28px;font-family:{$sans};font-size:11.5px;line-height:18px;color:{$C['pie_texto']};">
                  {$enClaroHtml}
                  <p style="margin:0 0 6px;font-family:{$serif};font-size:12px;font-weight:600;letter-spacing:2.5px;text-transform:uppercase;color:{$C['pie_marca']};">Lawang Tropical Properties</p>
                  <p style="margin:0;"><a href="mailto:{$mail}" style="color:{$C['pie_enlace']};text-decoration:none;">{$mail}</a> &middot; <a href="https://lawangproperties.com" style="color:{$C['pie_enlace']};text-decoration:none;">lawangproperties.com</a></p>
                  <p style="margin:14px 0 0;font-size:10.5px;color:{$C['pie_suave']};">&copy; {$anio} Lawang Tropical Properties</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
HTML;
}

/**
 * Versión en texto plano del MISMO correo (24-sep-2026). Hostinger bloqueó el
 * SMTP de admin@ por «Content Spam» y los filtros puntúan peor un correo que
 * solo trae HTML: send_email.php manda ahora multipart/alternative con esta
 * parte delante de la HTML. Sale de los mismos datos que lw_plantilla_correo(),
 * no del HTML ya montado, para que las dos versiones digan lo mismo.
 */
function lw_texto_plano_correo(string $mensajeTexto, ?string $encabezado = null, ?array $cta = null, ?string $contacto = null): string {
  $partes = [];
  if ($encabezado !== null && trim($encabezado) !== '') { $partes[] = trim($encabezado); }
  // las viñetas «•»/«·» y los rótulos «1. TÍTULO» ya se leen bien en plano
  $partes[] = trim(str_replace("\r\n", "\n", $mensajeTexto));
  $ctaUrl   = is_array($cta) ? trim((string)($cta['url'] ?? '')) : '';
  $ctaTexto = is_array($cta) ? trim((string)($cta['texto'] ?? '')) : '';
  if ($ctaUrl !== '' && $ctaTexto !== '') {
    $partes[] = $ctaTexto . ': ' . preg_replace('/^mailto:/i', '', $ctaUrl);
  }
  $mail = ($contacto === 'sales' ? 'sales' : 'admin') . '@lawangproperties.com';
  $partes[] = "--\nLawang Tropical Properties\n{$mail} - https://lawangproperties.com";
  return implode("\n\n", $partes) . "\n";
}
