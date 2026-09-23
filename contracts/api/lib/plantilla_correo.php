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
 * titular en Cormorant con su rayita verde, cuerpo en Jost, caja de acción con
 * botón en píldora Deep Lagoon, pie en lino. El TEXTO de la maqueta NO se tomó:
 * traía una TIR del 14,8 %, una autoridad monetaria de Singapur, sedes, un
 * director y una «firma criptográfica» inventados — y un correo de Lawang que
 * los repitiera sería una declaración falsa con su marca (regla del estudio,
 * reincidente dos veces: de un mockup se toma la piel, nunca el texto).
 *
 * Límites de un cliente de correo, que mandan sobre la maqueta:
 *  · tablas y estilos EN LÍNEA; nada de Tailwind ni sombras ni degradados;
 *  · Cormorant/Jost van en la pila con Georgia/Helvetica detrás, SIN <link> a
 *    Google Fonts (23-sep-2026, consulta de deploy de Legal): al cargarla, el
 *    cliente de correo del comprador mandaba su IP a Google, una transferencia
 *    que la política de privacidad no declara. Se ve Cormorant/Jost solo si
 *    las tiene instaladas quien lee; el resto cae al respaldo, como ya hacían
 *    Gmail y Outlook;
 *  · border-radius lo ignora Outlook de escritorio: queda cuadrado, no roto.
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
function lw_plantilla_correo(string $mensajeTexto, ?string $encabezado = null, ?array $cta = null, ?string $etiqueta = null): string {
  $e = fn(string $s): string => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
  $serif = "'Cormorant Garamond',Georgia,'Times New Roman',serif";
  $sans  = "Jost,'Helvetica Neue',Helvetica,Arial,sans-serif";

  // ── cuerpo: párrafos, viñetas y rótulos de sección ───────────────────────
  $bloques = preg_split("/\r?\n\s*\r?\n/", trim(str_replace("\r\n", "\n", $mensajeTexto)));
  $cuerpoHtml = '';
  foreach ($bloques as $bloque) {
    $lineas = explode("\n", $bloque);
    $parrafo = [];
    $vuelca = function () use (&$parrafo, &$cuerpoHtml, $e, $sans) {
      if (!$parrafo) return;
      $cuerpoHtml .= '<p style="margin:0 0 18px;font-family:' . $sans . ';font-size:15px;line-height:26px;color:#2C3028;">'
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
          . '<td valign="top" style="width:18px;padding-top:10px;"><div style="width:6px;height:6px;border-radius:3px;background:#485B37;font-size:0;line-height:0;">&nbsp;</div></td>'
          . '<td style="font-family:' . $sans . ';font-size:15px;line-height:25px;color:#2C3028;">' . $e($m[1]) . '</td></tr></table>';
      } elseif (preg_match('/^\d{1,2}[.)]\s+(.{3,90})$/u', $t, $m) && mb_strtoupper($m[1], 'UTF-8') === $m[1] && preg_match('/\p{Lu}{3}/u', $m[1])) {
        $vuelca();
        $cuerpoHtml .= '<div style="margin:30px 0 14px;padding-bottom:8px;border-bottom:1px solid #EFECE4;font-family:' . $serif . ';font-size:13px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:#485B37;">'
          . $e($t) . '</div>';
      } else {
        $parrafo[] = $t;
      }
    }
    $vuelca();
  }

  // ── titular ───────────────────────────────────────────────────────────────
  $encabezadoHtml = $encabezado !== null && trim($encabezado) !== ''
    ? '<div style="font-family:' . $serif . ';font-size:28px;line-height:34px;font-weight:600;color:#314322;">' . $e(trim($encabezado)) . '</div>'
      . '<div style="width:40px;height:2px;background:#485B37;border-radius:2px;margin:10px 0 24px;font-size:0;line-height:0;">&nbsp;</div>'
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
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F5F2EB;border:1px solid #E4DFD5;border-radius:16px;">
              <tr>
                <td align="center" style="padding:28px 24px;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="background:#104C4F;border-radius:999px;">
                        <a href="{$u}" style="display:inline-block;padding:14px 32px;font-family:{$sans};font-size:12px;font-weight:600;letter-spacing:1.5px;text-transform:uppercase;color:#FFFFFF;text-decoration:none;border-radius:999px;">{$t}</a>
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
        . '<a href="' . $u . '" style="color:#104C4F;">' . $u . '</a></p>';
    }
  }

  // ── barra superior: rótulo y fecha ────────────────────────────────────────
  $meses = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  $hoy = (int)date('j') . ' ' . $meses[(int)date('n') - 1] . ' ' . date('Y');
  $rotulo = $e(trim((string)$etiqueta) !== '' ? trim((string)$etiqueta) : 'Lawang Properties');
  $anio = date('Y');
  $logo = LW_CORREO_LOGO_URL;

  return <<<HTML
<meta charset="UTF-8">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F4F1EA;margin:0;padding:32px 12px;">
  <tr>
    <td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:640px;background:#FFFFFF;border:1px solid #E4DFD5;border-radius:16px;overflow:hidden;">

        <!-- barra superior -->
        <tr>
          <td style="padding:18px 40px 16px;border-bottom:1px solid #F0ECE4;font-family:{$sans};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:#7A7E73;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
              <td style="font-family:{$sans};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:#7A7E73;"><span style="display:inline-block;width:6px;height:6px;border-radius:3px;background:#485B37;vertical-align:middle;margin-right:8px;"></span>{$rotulo}</td>
              <td align="right" style="font-family:{$sans};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:#7A7E73;">{$hoy}</td>
            </tr></table>
          </td>
        </tr>

        <!-- marca -->
        <tr>
          <td align="center" style="padding:32px 40px 8px;">
            <img src="{$logo}" width="200" height="28" alt="LAWANG"
                 style="display:block;width:200px;height:28px;border:0;margin:0 auto;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:360px;margin:18px auto 0;"><tr>
              <td valign="middle"><div style="height:1px;background:#E4DFD5;font-size:0;line-height:0;">&nbsp;</div></td>
              <td valign="middle" style="width:1%;white-space:nowrap;padding:0 14px;font-family:{$serif};font-size:11px;letter-spacing:3px;text-transform:uppercase;color:#6A6E63;">Properties</td>
              <td valign="middle"><div style="height:1px;background:#E4DFD5;font-size:0;line-height:0;">&nbsp;</div></td>
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
        <!-- pie -->
        <tr>
          <td style="padding:32px 0 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#EFECE4;border-top:1px solid #E2DDD3;">
              <tr>
                <td style="padding:26px 40px 28px;font-family:{$sans};font-size:11.5px;line-height:18px;color:#676C60;">
                  {$enClaroHtml}
                  <p style="margin:0 0 6px;font-family:{$serif};font-size:12px;font-weight:600;letter-spacing:2.5px;text-transform:uppercase;color:#1E221B;">Lawang Tropical Properties</p>
                  <p style="margin:0;"><a href="mailto:sales@lawangproperties.com" style="color:#104C4F;text-decoration:none;">sales@lawangproperties.com</a> &middot; <a href="https://lawangproperties.com" style="color:#104C4F;text-decoration:none;">lawangproperties.com</a></p>
                  <p style="margin:14px 0 0;font-size:10.5px;color:#868B7E;">&copy; {$anio} Lawang Tropical Properties</p>
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
