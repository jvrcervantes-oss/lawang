// envia-correo · plantilla del correo de LAWANG. Port de proyectos/Lawang/contracts/api/lib/plantilla_correo.php
// (paleta «canopy», la elegida por el owner el 23-sep-2026; documento completo con color-scheme «light only» del
// 30-sep-2026). `index.ts` y `valida.ts` son IDÉNTICOS a los del maestro (test_canon_envia_correo.py); esta piel no:
// es la identidad de Lawang. Mismas firmas exportadas que la del maestro: plantillaHtml, plantillaTexto, Marca, Cta, esc.
//
// El HTML de salida se compara byte a byte con el del PHP en dorada.test.js (php local, fecha fija). Los dos bloques
// grandes —el documento y la caja del botón— están COPIADOS del heredoc del PHP, no reescritos: ahí es donde se separan
// las pieles. Si tocas la piel, tócala en los DOS sitios mientras el PHP siga sirviendo `lead.php` y `booking-notify.php`.
//
// Diferencias conocidas con el PHP (todas en dorada.test.js, con su motivo):
//  · la fecha sale en UTC (el PHP, en la zona del servidor de Hostinger);
//  · `admin@`/`sales@` y el enlace del pie salen de `dominio_web` de config_instancia (el PHP lo escribía a fuego; con
//    lawangproperties.com el resultado es el mismo);
//  · `logo_correo_url` de config_instancia NO se usa: el logo lleva su halo y un alto fijo de 38 px (ver LOGO_URL).
//  · un `\d` con dígitos no ASCII en un rótulo «N. TÍTULO» (PCRE con /u los acepta, JS no): no ocurre en la práctica.

export type Marca = {
  marca: string;          // config_instancia.marca (esta piel la usa solo para el asunto por defecto, en index.ts)
  dominio: string;        // config_instancia.dominio_web: pie y buzones admin@/sales@
  remitente: string;      // SMTP_FROM (esta piel no lo pinta: el contacto del pie es admin@/sales@)
  logoUrl?: string;       // config_instancia.logo_correo_url — no usado por esta piel
  contacto?: 'sales' | null;   // 'sales' solo lo piden lo de ventas de la web (investor deck); todo lo demás, admin@
};

export type Cta = { url: string; texto: string } | null;

// Logo por URL absoluta y con halo (30-sep-2026): Gmail invierte los colores del correo en modo oscuro pero no las
// imágenes; el halo claro separa las letras del fondo oscurecido. El grano va como CAPA con transparencia sobre una base.
const LOGO_URL = 'https://lawangproperties.com/assets/img/lawang-logo-correo-halo.png';
const GRANO_URL = 'https://lawangproperties.com/assets/img/correo-grano.png';
const GRANO_BASE = '#FFFFF3';   // el máximo de cada canal del grano: la capa solo oscurece

// Paleta «canopy» = base ∪ variante canopy del PHP, ya resuelta. Los siete oficiales de Lawang: Territorial Green,
// Deep Lagoon, Burnt Earth, Soft Canopy, Volcanic Ash, Stone Sand, Raw Linen.
const TG = '#485B37', BE = '#42210B', SC = '#8F9B7A', VA = '#2E3437', SS = '#BEB3A5', RL = '#F5F0E6';
const C = {
  fondo: SC, tarjeta: RL, texto: VA, titular: VA, acento: TG, linea: SS, caja: 'transparent', boton: BE, boton_texto: RL,
  barra_fondo: 'transparent', barra_texto: VA, barra_linea: SS, barra_punto: TG, rotulo_logo: SC,
  pie_fondo: VA, pie_linea: VA, pie_texto: RL, pie_marca: RL, pie_enlace: SC, pie_suave: SS,
};
const SANS = "'Neue Kabel','Helvetica Neue',Helvetica,Arial,sans-serif";
const SERIF = SANS;   // titulares y rótulos: misma familia, otro peso
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/** htmlspecialchars(…, ENT_QUOTES, 'UTF-8') de PHP. */
export function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

/** trim() de PHP: solo espacio, \t, \n, \r, NUL y VT (el trim de JS quita también NBSP y otros). */
const phpTrim = (s: string) => s.replace(/^[ \t\n\r\0\x0B]+|[ \t\n\r\0\x0B]+$/g, '');

function cuerpoHtmlDe(mensaje: string): string {
  let cuerpoHtml = '';
  const bloques = phpTrim(mensaje.replace(/\r\n/g, '\n')).split(/\r?\n[\t\n\v\f\r ]*\r?\n/);   // \s de PCRE sin /u: solo ASCII
  for (const bloque of bloques) {
    let parrafo: string[] = [];
    const vuelca = () => {
      if (!parrafo.length) return;
      cuerpoHtml += '<p style="margin:0 0 18px;font-family:' + SANS + ';font-size:15px;line-height:26px;word-break:break-word;overflow-wrap:anywhere;color:' + C.texto + ';">'
        + parrafo.map(esc).join('<br>') + '</p>';
      parrafo = [];
    };
    for (const l of bloque.split('\n')) {
      const t = phpTrim(l);
      // viñeta solo con «•» o «·»: el guion NO (23-sep-2026, Administración): «- 5.000.000 IDR» escrito a mano es un
      // importe negativo y perdía el signo
      const v = /^[•·]\s+([^\n]+)$/u.exec(t);
      const r = /^\d{1,2}[.)]\s+([^\n]{3,90})$/u.exec(t);
      if (v) {
        vuelca();
        cuerpoHtml += '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 10px;"><tr>'
          + '<td valign="top" style="width:18px;padding-top:10px;"><div style="width:6px;height:6px;border-radius:3px;background:' + C.acento + ';font-size:0;line-height:0;">&nbsp;</div></td>'
          + '<td style="font-family:' + SANS + ';font-size:15px;line-height:25px;word-break:break-word;overflow-wrap:anywhere;color:' + C.texto + ';">' + esc(v[1]) + '</td></tr></table>';
      } else if (r && r[1].toUpperCase() === r[1] && /\p{Lu}{3}/u.test(r[1])) {
        vuelca();
        cuerpoHtml += '<div style="margin:30px 0 14px;padding-bottom:8px;border-bottom:1px solid ' + C.linea + ';font-family:' + SERIF + ';font-size:12px;font-weight:500;letter-spacing:2px;text-transform:uppercase;color:' + C.acento + ';">'
          + esc(t) + '</div>';
      } else {
        parrafo.push(t);
      }
    }
    vuelca();
  }
  return cuerpoHtml;
}

export function plantillaHtml(mensaje: string, encabezado: string, cta: Cta, etiqueta: string, m: Marca, hoy = new Date()): string {
  const cuerpoHtml = cuerpoHtmlDe(mensaje);

  // ── titular ─────────────────────────────────────────────────────────────
  const encabezadoHtml = phpTrim(encabezado) !== ''
    ? '<div style="font-family:' + SERIF + ';font-size:26px;line-height:32px;font-weight:500;letter-spacing:-0.2px;color:' + C.titular + ';">' + esc(phpTrim(encabezado)) + '</div>'
      + '<div style="width:40px;height:2px;background:' + C.acento + ';border-radius:2px;margin:10px 0 24px;font-size:0;line-height:0;">&nbsp;</div>'
    : '';

  // ── caja de acción: media pareja no produce medio botón, produce uno roto: sin las dos, nada ──
  const ctaUrl = cta ? phpTrim(cta.url) : '', ctaTexto = cta ? phpTrim(cta.texto) : '';
  let accionHtml = '', enClaroHtml = '';
  if (ctaUrl !== '' && ctaTexto !== '') {
    const u = esc(ctaUrl), t = esc(ctaTexto);
    accionHtml = `        <tr>
          <td class="lw-px" style="padding:8px 40px 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${C.caja};border:1px solid ${C.linea};border-radius:16px;">
              <tr>
                <td align="center" style="padding:28px 24px;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="background:${C.boton};border-radius:999px;">
                        <a href="${u}" style="display:inline-block;padding:14px 32px;font-family:${SANS};font-size:12px;font-weight:600;letter-spacing:1.5px;text-transform:uppercase;color:${C.boton_texto};text-decoration:none;border-radius:999px;">${t}</a>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>`;
    // `mailto:` y `wa.me` no se repiten en claro: ya están en el cuerpo del aviso
    if (/^http/i.test(ctaUrl)) {
      enClaroHtml = '<p style="margin:0 0 14px;word-break:break-all;">'
        + 'Si el botón no funciona, copia esta dirección en tu navegador &middot; '
        + 'If the button does not work, paste this address into your browser:<br>'
        + '<a href="' + u + '" style="color:' + C.pie_enlace + ';">' + u + '</a></p>';
    }
  }

  // ── barra superior: rótulo y fecha ──────────────────────────────────────
  const hoyTxt = hoy.getUTCDate() + ' ' + MESES[hoy.getUTCMonth()] + ' ' + hoy.getUTCFullYear();
  const rotulo = esc(phpTrim(etiqueta) !== '' ? phpTrim(etiqueta) : 'Lawang Properties');
  const anio = String(hoy.getUTCFullYear());
  // Contacto del pie (owner, 23-sep-2026): admin@ por defecto (todo lo que sale de la intranet); sales@ solo si quien llama lo pide.
  const mail = (m.contacto === 'sales' ? 'sales' : 'admin') + '@' + esc(m.dominio);
  const dominio = esc(m.dominio);
  const logo = LOGO_URL, grano = GRANO_URL, granoBase = GRANO_BASE;

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light only">
<meta name="supported-color-schemes" content="light only">
<style>
:root{color-scheme:light only;supported-color-schemes:light only;}
@media only screen and (max-width:480px){.lw-px{padding-left:20px!important;padding-right:20px!important;}}
@font-face{font-family:'Neue Kabel';src:url('https://lawangproperties.com/assets/fonts/correo/NeueKabel-Regular.woff') format('woff');font-weight:400;font-style:normal;}
@font-face{font-family:'Neue Kabel';src:url('https://lawangproperties.com/assets/fonts/correo/NeueKabel-Medium.woff') format('woff');font-weight:500;font-style:normal;}
@font-face{font-family:'Neue Kabel';src:url('https://lawangproperties.com/assets/fonts/correo/NeueKabel-Bold.woff') format('woff');font-weight:600 700;font-style:normal;}
</style>
</head>
<body>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${C.fondo};margin:0;padding:32px 12px;">
  <tr>
    <td align="center">
      <!-- bgcolor (lino) es lo que pinta Outlook de escritorio, que no carga fondos;
           el resto usa la base del grano + la capa, que juntas dan el grano de siempre -->
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${C.tarjeta}" background="${grano}" style="max-width:760px;background-color:${granoBase};background-image:url('${grano}');background-repeat:repeat;background-position:0 0;background-size:256px 256px;border:1px solid ${C.linea};border-radius:16px;overflow:hidden;">

        <!-- barra superior -->
        <tr>
          <td class="lw-px" style="padding:18px 40px 16px;background:${C.barra_fondo};border-bottom:1px solid ${C.barra_linea};font-family:${SANS};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:${C.barra_texto};">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
              <td style="font-family:${SANS};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:${C.barra_texto};"><span style="display:inline-block;width:6px;height:6px;border-radius:3px;background:${C.barra_punto};vertical-align:middle;margin-right:8px;"></span>${rotulo}</td>
              <td align="right" style="font-family:${SANS};font-size:11px;letter-spacing:1.8px;text-transform:uppercase;color:${C.barra_texto};">${hoyTxt}</td>
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
          <td align="center" style="padding:27px 40px 8px;">
            <!-- 210×38 = el logo de 200×28 con 5 px de halo alrededor: el relleno de la
                 celda (32→27) y el margen del filete (18→13) lo descuentan -->
            <img src="${logo}" width="210" height="38" alt="LAWANG"
                 style="display:block;width:210px;height:38px;border:0;margin:0 auto;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:360px;margin:13px auto 0;"><tr>
              <td valign="middle"><div style="height:1px;background:${C.linea};font-size:0;line-height:0;">&nbsp;</div></td>
              <td valign="middle" style="width:1%;white-space:nowrap;padding:0 14px;font-family:${SERIF};font-size:11px;letter-spacing:3px;text-transform:uppercase;color:${C.rotulo_logo};">Properties</td>
              <td valign="middle"><div style="height:1px;background:${C.linea};font-size:0;line-height:0;">&nbsp;</div></td>
            </tr></table>
          </td>
        </tr>

        <!-- cuerpo -->
        <tr>
          <td class="lw-px" style="padding:28px 40px 8px;">
            ${encabezadoHtml}
            ${cuerpoHtml}
          </td>
        </tr>

${accionHtml}
            </table>
          </td>
        </tr>
        <!-- pie -->
        <tr>
          <td style="padding:32px 0 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${C.pie_fondo};border-top:1px solid ${C.pie_linea};">
              <tr>
                <td class="lw-px" style="padding:26px 40px 28px;font-family:${SANS};font-size:11.5px;line-height:18px;color:${C.pie_texto};">
                  ${enClaroHtml}
                  <p style="margin:0 0 6px;font-family:${SERIF};font-size:12px;font-weight:600;letter-spacing:2.5px;text-transform:uppercase;color:${C.pie_marca};">Lawang Tropical Properties</p>
                  <p style="margin:0;"><a href="mailto:${mail}" style="color:${C.pie_enlace};text-decoration:none;">${mail}</a> &middot; <a href="https://${dominio}" style="color:${C.pie_enlace};text-decoration:none;">${dominio}</a></p>
                  <p style="margin:14px 0 0;font-size:10.5px;color:${C.pie_suave};">&copy; ${anio} Lawang Tropical Properties</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
}

/** Parte de texto plano del MISMO correo (multipart/alternative): sale de los mismos datos, no del HTML montado, para que
 *  las dos versiones digan lo mismo (Hostinger bloqueó el SMTP de admin@ por «Content Spam» el 24-sep-2026). */
export function plantillaTexto(mensaje: string, encabezado: string, cta: Cta, m: Marca): string {
  const partes: string[] = [];
  if (phpTrim(encabezado) !== '') partes.push(phpTrim(encabezado));
  partes.push(phpTrim(mensaje.replace(/\r\n/g, '\n')));
  const ctaUrl = cta ? phpTrim(cta.url) : '', ctaTexto = cta ? phpTrim(cta.texto) : '';
  if (ctaUrl !== '' && ctaTexto !== '') partes.push(ctaTexto + ': ' + ctaUrl.replace(/^mailto:/i, ''));
  const mail = (m.contacto === 'sales' ? 'sales' : 'admin') + '@' + m.dominio;
  partes.push('--\nLawang Tropical Properties\n' + mail + ' - https://' + m.dominio);
  return partes.join('\n\n') + '\n';
}
