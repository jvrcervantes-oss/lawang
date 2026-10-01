// Prueba SIN RED del validador (la plantilla, que es de cada cliente, tiene su plantilla_test.ts):
//   npx --yes deno test erp/funciones/envia-correo/valida_test.ts
import {
  esEmail, tieneControl, ctaPermitida, esDominioPropio, limpiaNombreFichero, decodificaBase64, esPdf,
  igualSeguro, leePeticion, validaEnvio, validaTextos, deduceCta, esFallo, LIMITES, type Peticion,
  TEXTO_PAUSA, saneaLlamante, viaServicio, viaAviso, describeFalloSmtp,
} from './valida.ts';

function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }
const D = 'ejemplo.com';
const base = (o: Record<string, unknown> = {}) => leePeticion({ to: 'ana@cliente.es', message: 'Hola', attach: false, ...o }) as Peticion;

Deno.test('esEmail: una dirección, sin listas ni inyección', () => {
  for (const s of ['ana@cliente.es', 'a.b+c@sub.dominio.co', "o'neil@x.io"]) ok(esEmail(s), 'debería valer: ' + s);
  for (const s of ['', 'ana', 'ana@', '@x.com', 'ana@x', 'a@b.c', '.a@x.com', 'a..b@x.com', 'a@-x.com',
    'a@x.com, b@y.com', 'Ana <a@x.com>', 'a@x.com\r\nBcc: v@y.com', 'a b@x.com', 'a@x.com\n']) ok(!esEmail(s), 'no debería valer: ' + JSON.stringify(s));
});

Deno.test('tieneControl caza CR/LF/NUL/TAB', () => {
  ok(tieneControl('Hola\r\nBcc: x@y.z'), 'CRLF'); ok(tieneControl('a\u0000'), 'NUL'); ok(tieneControl('a\tb'), 'TAB');
  ok(!tieneControl('Factura Nº 12 — José'), 'texto normal');
});

Deno.test('ctaPermitida: host completo, no substring', () => {
  ok(ctaPermitida('https://ejemplo.com/portal/', D), 'dominio');
  ok(ctaPermitida('https://erp.ejemplo.com/intranet/', D), 'subdominio');
  ok(ctaPermitida('mailto:ana@cliente.es', D), 'mailto');
  ok(ctaPermitida('https://wa.me/34600111222', D), 'wa.me');
  for (const u of ['https://ejemplo.com.fraude.ru/', 'https://fraude-ejemplo.com/', 'http://ejemplo.com/',
    'https://ejemplo.com@fraude.ru/', 'https://user:pw@ejemplo.com/', 'javascript:alert(1)', 'https://wa.me/34abc',
    'mailto:a@x.com,b@y.com', 'https://ejemplo.com/\r\nX: y']) ok(!ctaPermitida(u, D), 'no debería valer: ' + u);
  ok(!ctaPermitida('https://ejemplo.com/', ''), 'sin dominio configurado no pasa nada');
});

Deno.test('esDominioPropio', () => {
  ok(esDominioPropio('avisos@ejemplo.com', D), 'propio'); ok(esDominioPropio('a@mail.EJEMPLO.com', D), 'subdominio y mayúsculas');
  ok(!esDominioPropio('a@ejemplo.com.fraude.ru', D), 'sufijo falso'); ok(!esDominioPropio('a@otroejemplo.com', D), 'prefijo falso');
});

Deno.test('limpiaNombreFichero: Unicode sí, separadores de ruta y comillas no', () => {
  ok(limpiaNombreFichero('Contrato José+García.pdf') === 'Contrato_José+García.pdf', 'tildes y +');
  ok(limpiaNombreFichero('../../etc/"x".pdf') === '.._.._etc__x_.pdf', 'ruta y comillas');
  ok(limpiaNombreFichero('a\r\nb.pdf') === 'a__b.pdf', 'saltos');
  ok(limpiaNombreFichero('..') === 'documento.pdf', 'solo puntos');
  ok(limpiaNombreFichero('x'.repeat(400)).length === LIMITES.nombreFichero, 'tope');
});

Deno.test('base64 estricto y cabecera %PDF', () => {
  ok(esPdf(decodificaBase64(btoa('%PDF-1.7 hola'))), 'pdf válido');
  ok(esPdf(decodificaBase64(btoa('%PDF-1.7 hola').replace(/(.{4})/g, '$1\n'))), 'con saltos de línea');
  ok(!esPdf(decodificaBase64(btoa('<html>'))), 'no es pdf');
  ok(decodificaBase64('no es base64!') === null, 'basura'); ok(decodificaBase64('') === null, 'vacío');
});

Deno.test('igualSeguro', () => {
  ok(igualSeguro('abc', 'abc'), 'iguales'); ok(!igualSeguro('abc', 'abd'), 'distintos');
  ok(!igualSeguro('abc', 'abcd'), 'largo'); ok(!igualSeguro('', ''), 'vacío nunca autoriza');
});

Deno.test('leePeticion: valores por defecto del PHP', () => {
  ok(esFallo(leePeticion(null)) && esFallo(leePeticion([])) && esFallo(leePeticion('x')), 'no-objeto');
  const p = leePeticion({ to: ' a@b.co ' }) as Peticion;
  ok(p.to === 'a@b.co' && p.attach === true && p.filename === 'contrato.pdf' && p.preview === false && p.contacto === null, 'defaults');
  ok((leePeticion({ attach: 0 }) as Peticion).attach === true, 'solo false literal desactiva el adjunto');
  ok((leePeticion({ preview: 'true' }) as Peticion).preview === false, 'solo true literal activa preview');
});

Deno.test('validaEnvio: orden y límites', () => {
  ok(validaEnvio(base()) === null, 'válido');
  ok(validaEnvio(base({ to: 'x' }))?.error === 'Destinatario no válido', 'to');
  ok(validaEnvio(base({ subject: 'Hola\r\nBcc: v@y.z' }))?.status === 400, 'asunto con CRLF');
  ok(validaEnvio(base({ subject: 'a'.repeat(201) }))?.error === 'Asunto demasiado largo', 'asunto largo');
  ok(validaEnvio(base({ subject: 'ñ'.repeat(200) })) === null, 'cuenta caracteres, no bytes');
  ok(validaEnvio(base({ message: '' }))?.error === 'Un correo sin adjunto necesita mensaje', 'sin mensaje');
  ok(validaEnvio(base({ attach: true }))?.error === 'Falta el PDF o el HTML a renderizar', 'adjunto sin pdf');
  ok(validaEnvio(base({ attach: true, pdf_base64: 'A'.repeat(LIMITES.pdfBase64 + 4) }))?.error === 'El PDF es demasiado grande', 'pdf grande');
  ok(validaTextos(base({ encabezado: 'x'.repeat(121) }))?.status === 400, 'encabezado');
  ok(validaTextos(base({ etiqueta: 'x'.repeat(41) }))?.status === 400, 'etiqueta');
});

Deno.test('deduceCta: mismo orden que el PHP', () => {
  const portal = 'https://erp.ejemplo.com/portal/';
  const c1 = deduceCta(base({ cta_url: 'https://erp.ejemplo.com/x', cta_texto: 'Ir' }), D, portal, false);
  ok(!esFallo(c1) && c1.url === 'https://erp.ejemplo.com/x', 'impuesta');
  ok(esFallo(deduceCta(base({ cta_url: 'https://fraude.ru/', cta_texto: 'Ir' }), D, portal, false)), 'impuesta fuera de lista → error');
  ok(esFallo(deduceCta(base({ cta_url: 'https://ejemplo.com/' }), D, portal, false)), 'url sin texto → error');
  const f = deduceCta(base({ message: 'Firma: https://erp.ejemplo.com/contracts/firmar.html?t=abc.1-2 gracias' }), D, portal, false);
  ok(!esFallo(f) && f.texto === 'Firmar el documento' && f.url.endsWith('t=abc.1-2'), 'firma');
  const fx = deduceCta(base({ message: 'https://fraude.ru/contracts/firmar.html?t=x' }), D, portal, false);
  ok(!esFallo(fx) && fx.url === portal, 'firma de otro dominio → portal');
  const i = deduceCta(base({ message: 'Responder desde: https://erp.ejemplo.com/intranet/compradores/?id=9' }), D, portal, true);
  ok(!esFallo(i) && i.texto === 'Abrir en la intranet', 'intranet a interno');
  const e = deduceCta(base({ message: 'Responder desde: https://erp.ejemplo.com/intranet/compradores/?id=9' }), D, portal, false);
  ok(!esFallo(e) && e.url === portal, 'intranet a externo → portal (los clientes nunca a /intranet/)');
  // URLs limpias (AXW-140): enlace nuevo a la raíz de la instancia
  const I = 'https://erp.ejemplo.com/';
  const n = deduceCta(base({ message: 'Responder desde: https://erp.ejemplo.com/compradores/?id=9' }), D, portal, true, I);
  ok(!esFallo(n) && n.texto === 'Abrir en la intranet' && n.url === 'https://erp.ejemplo.com/compradores/?id=9', 'enlace limpio a interno');
  const ne = deduceCta(base({ message: 'Responder desde: https://erp.ejemplo.com/compradores/?id=9' }), D, portal, false, I);
  ok(!esFallo(ne) && ne.url === portal, 'enlace limpio a externo → portal');
  const np = deduceCta(base({ message: 'Mira https://erp.ejemplo.com/portal/ y luego https://erp.ejemplo.com/home/' }), D, portal, true, I);
  ok(!esFallo(np) && np.url === 'https://erp.ejemplo.com/home/', 'el /portal/ no es la intranet: se salta');
  const nf = deduceCta(base({ message: 'https://fraude.ru/home/' }), D, portal, true, I);
  ok(!esFallo(nf) && nf.url === portal, 'enlace limpio de otro origen → portal');
  const ns = deduceCta(base({ message: 'https://erp.ejemplo.com/home/' }), D, portal, true, '');
  ok(!esFallo(ns) && ns.url === portal, 'sin url_intranet válida no hay enlace nuevo');
  const nlw = deduceCta(base({ message: 'Web: https://erp.ejemplo.com/propiedades/' }), D, portal, true, 'https://erp.ejemplo.com/intranet/');
  ok(!esFallo(nlw) && nlw.url === portal, 'url_intranet con /intranet/ (Lawang): la rama nueva no existe, cero cambio');
  const nl = deduceCta(base({ message: 'https://erp.ejemplo.com/intranet/v4/home/' }), D, portal, true, I);
  ok(!esFallo(nl) && nl.url === 'https://erp.ejemplo.com/intranet/v4/home/', 'el enlace viejo sigue valiendo (legado)');
});

Deno.test('TEXTO_PAUSA: el texto exacto que buscan los crons', () => {
  ok(TEXTO_PAUSA === 'Los envíos de correo están en pausa (modo mantenimiento). No se ha enviado nada.', 'texto');
  ok(/en pausa \(modo mantenimiento\)/i.test(TEXTO_PAUSA), 'casa con EN_PAUSA de avisos-manager');
});

Deno.test('saneaLlamante: solo atribuye, recortado y sin caracteres raros', () => {
  ok(saneaLlamante('firma-submit') === 'firma-submit', 'normal');
  ok(saneaLlamante(' pg_net:soporte ') === 'pg_net:soporte', 'recorta espacios');
  ok(saneaLlamante('a<b>"c"\r\nd') === 'a_b__c___d', 'raros a guion bajo: ' + saneaLlamante('a<b>"c"\r\nd'));
  ok(saneaLlamante('x'.repeat(100)).length === 40, 'tope 40');
  ok(saneaLlamante(null) === '' && saneaLlamante(undefined) === '', 'vacío');
});

Deno.test('viaServicio: ENVIO_CORREO_SECRET manda; sin él, RENDER_SECRET', () => {
  ok(viaServicio('e1', 'e1', 'r1') === 'servicio', 'secreto de envío');
  ok(viaServicio('r1', 'e1', 'r1') === '', 'con secreto de envío definido, el de render no vale');
  ok(viaServicio('r1', '', 'r1') === 'servicio-render', 'fallback');
  ok(viaServicio('x', '', 'r1') === '' && viaServicio('', 'e1', 'r1') === '' && viaServicio('', '', '') === '', 'cabecera mala o vacía');
  ok(viaServicio('x', '', '') === '', 'sin ningún secreto configurado nunca autoriza');
});

Deno.test('viaAviso: solo texto a los buzones de aviso; con secreto, sin puerta anónima', () => {
  const av = ['soporte@x.com'];
  const o = (d: Record<string, unknown> = {}) => ({ secretoEnv: '', cabecera: '', attach: false, to: 'soporte@x.com', avisos: av, ...d });
  ok(viaAviso(o()) === 'aviso-interno', 'sin secreto: puerta anónima de siempre');
  ok(viaAviso(o({ to: 'SOPORTE@X.COM' })) === 'aviso-interno', 'mayúsculas');
  ok(viaAviso(o({ to: 'otro@x.com' })) === null, 'buzón que no es de aviso');
  ok(viaAviso(o({ attach: true })) === null, 'con adjunto nunca');
  ok(viaAviso(o({ secretoEnv: 's', cabecera: 's' })) === 'aviso', 'con secreto y cabecera');
  ok(viaAviso(o({ secretoEnv: 's', cabecera: '' })) === null, 'con secreto definido, sin cabecera: cerrada');
  ok(viaAviso(o({ secretoEnv: 's', cabecera: 't' })) === null, 'cabecera mala');
  ok(viaAviso(o({ secretoEnv: 's', cabecera: 's', to: 'otro@x.com' })) === null, 'el secreto no abre otros buzones');
});

Deno.test('describeFalloSmtp: 554 / 5.7.1 en el texto, el texto libre del servidor fuera', () => {
  const f = describeFalloSmtp({ code: 'EENVELOPE', responseCode: 554, response: '554 5.7.1 Outbound sending is disabled for a@b.co (id 99)' });
  ok(/\b554\b/.test(f.texto) && f.texto.includes('5.7.1') && f.texto.includes('Outbound sending is disabled'), 'texto: ' + f.texto);
  ok(!f.texto.includes('a@b.co') && !f.texto.includes('id 99'), 'no copia la línea libre');
  ok(f.smtp_code === 'EENVELOPE' && f.smtp_response_code === 554, 'campos');
  ok(!f.log.includes('Outbound') && !f.log.includes('a@b.co') && f.log.includes('554'), 'log: ' + f.log);
  const g = describeFalloSmtp({ code: 'EAUTH', response: '535 5.7.8 Error: authentication failed for user@x.com' });
  ok(g.smtp_response_code === 535 && g.texto === 'No se pudo enviar por SMTP (535, 5.7.8, EAUTH)', 'número sacado de la respuesta: ' + g.texto);
  ok(describeFalloSmtp({ code: 'ETIMEDOUT' }).texto === 'No se pudo enviar por SMTP (ETIMEDOUT)', 'solo código');
  ok(describeFalloSmtp(null).texto === 'No se pudo enviar por SMTP (desconocido)', 'nada');
  ok(describeFalloSmtp({ code: 'con espacios <b>' }).smtp_code === 'desconocido', 'un code raro no se copia');
  ok(describeFalloSmtp({ responseCode: 99999 }).smtp_response_code === null, 'número fuera de rango');
  ok(describeFalloSmtp({ code: 'X', response: '250 2.0.0 Ok: queued as 4.10.1' }).texto === 'No se pudo enviar por SMTP (250, 2.0.0, X)', 'solo el estado tras el código');
  ok(describeFalloSmtp({ code: 'X', response: 'version 10.5.7.1234 raro' }).texto === 'No se pudo enviar por SMTP (X)', 'un 5.7.1 dentro de otro número no cuenta');
});
