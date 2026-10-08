// smtp.ts — pruebas SIN RED (F3.1, 7-oct-2026): el servidor que escribe el super admin y el remitente con el que sale el correo.
//   npx --yes deno test erp/funciones/envia-correo/smtp_test.ts      ·      node erp/funciones/envia-correo/corre_deno.test.js
import { normalizaHost, validaServidor, esServidorMalo, esIpPublica, remitenteEfectivo, replyToEfectivo, buzonAvisoValido } from './smtp.ts';

function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }

Deno.test('normalizaHost: un nombre público; nunca IP, puerto, ruta ni red interna', () => {
  ok(normalizaHost('  SMTP.Proveedor.COM ') === 'smtp.proveedor.com', 'minúsculas y espacios');
  ok(normalizaHost('mail.dominio.co.id') === 'mail.dominio.co.id', 'varias etiquetas');
  ok(normalizaHost('smtp.bücher.example') === '', 'Unicode sin punycode no pasa (y .example tampoco)');
  ok(normalizaHost('smtp.xn--bcher-kva.de') === 'smtp.xn--bcher-kva.de', 'punycode sí');
  for (const s of ['', 'smtp', 'localhost', '127.0.0.1', '10.0.0.5', '1.2.3.4', '2130706433', '127.1', '0x7f.1', '[::1]', '::1', 'a.b',
    'smtp.internal', 'mail.local', 'srv.corp', 'x.lan', 'x.home', 'x.intranet', 'x.localdomain', 'x.invalid', 'x.test', 'x.example', 'x.onion', '1.0.0.127.in-addr.arpa',
    'smtp.proveedor.com:465', 'smtp.proveedor.com/x', 'smtp..proveedor.com', '-a.proveedor.com', 'a-.proveedor.com', 'a_b.proveedor.com', 'a b.proveedor.com',
    'smtp.proveedor.com.', 'smtp.prove\nedor.com', 'x'.repeat(64) + '.com', ('a.'.repeat(130)) + 'com']) ok(normalizaHost(s) === '', 'no debería valer: ' + JSON.stringify(s));
  ok(normalizaHost(null) === '' && normalizaHost(5) === '' && normalizaHost({}) === '', 'no texto');
});

Deno.test('validaServidor: puerto 465 fijo y campos limpios', () => {
  const b = { host: 'smtp.proveedor.com', port: 465, user: 'buzon@proveedor.com', pass: 'secreto', nombre: 'Acme' };
  const v = validaServidor(b);
  ok(!esServidorMalo(v) && v.host === 'smtp.proveedor.com' && v.port === 465 && v.nombre === 'Acme', 'bueno');
  ok(!esServidorMalo(validaServidor({ ...b, nombre: undefined })), 'sin nombre vale');
  const malos: [Record<string, unknown>, string][] = [
    [{ host: '127.0.0.1' }, 'host_no_valido'], [{ host: 'localhost' }, 'host_no_valido'], [{ host: undefined }, 'host_no_valido'],
    [{ port: 25 }, 'puerto_no_valido'], [{ port: 587 }, 'puerto_no_valido'], [{ port: '465' }, 'puerto_no_valido'], [{ port: undefined }, 'puerto_no_valido'],
    [{ user: '' }, 'usuario_no_valido'], [{ user: 'a@x.com\r\nBcc: v@y.com' }, 'usuario_no_valido'], [{ user: 'x'.repeat(255) }, 'usuario_no_valido'], [{ user: 5 }, 'usuario_no_valido'],
    [{ pass: '' }, 'clave_no_valida'], [{ pass: 'a\nb' }, 'clave_no_valida'], [{ pass: 'x'.repeat(201) }, 'clave_no_valida'], [{ pass: null }, 'clave_no_valida'],
    [{ nombre: 'Acme <b>' }, 'nombre_no_valido'], [{ nombre: 'x\ny' }, 'nombre_no_valido'], [{ nombre: 'x'.repeat(61) }, 'nombre_no_valido'], [{ nombre: 5 }, 'nombre_no_valido'],
  ];
  for (const [parche, codigo] of malos) {
    const r = validaServidor({ ...b, ...parche });
    ok(esServidorMalo(r) && r.codigo === codigo, JSON.stringify(parche) + ' debería dar ' + codigo + ' y dio ' + JSON.stringify(r));
  }
  ok(!esServidorMalo(validaServidor({ ...b, pass: ' con espacios ' })), 'la contraseña puede llevar espacios (no se recorta)');
  const r = validaServidor({ ...b, pass: ' con espacios ' });
  ok(!esServidorMalo(r) && r.pass === ' con espacios ', 'y se guarda tal cual');
});

Deno.test('esIpPublica: solo lo enrutable; lo que no se entiende no es público', () => {
  for (const s of ['8.8.8.8', '74.125.1.1', '185.70.40.1', '2a00:1450:4001:81b::200e', '2606:4700::1111', '::ffff:8.8.8.8']) ok(esIpPublica(s), 'debería ser pública: ' + s);
  for (const s of ['127.0.0.1', '0.0.0.0', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254', '100.64.0.1', '192.0.0.8', '192.0.2.1',
    '198.18.0.1', '198.51.100.7', '203.0.113.9', '224.0.0.1', '255.255.255.255', '240.0.0.1',
    '::', '::1', 'fe80::1', 'fc00::1', 'fd12:3456::1', 'ff02::1', '2001:db8::1', '::ffff:127.0.0.1', '::ffff:10.0.0.1', '::ffff:7f00:1', '64:ff9b::7f00:1', '2002:7f00:1::1', 'fec0::1',
    '', 'abc', '1.2.3', '1.2.3.4.5', '256.1.1.1', '08.8.8.8x', '1::2::3', ':::', 'gggg::1', '1:2:3:4:5:6:7:8:9']) ok(!esIpPublica(s), 'no debería ser pública: ' + JSON.stringify(s));
  ok(!esIpPublica(null) && !esIpPublica(8) && !esIpPublica(undefined), 'no texto');
});

Deno.test('remitenteEfectivo: email_from solo si su dominio es del buzón, del usuario SMTP o de la instancia', () => {
  const D = 'ejemplo.com';
  const r = (o: Record<string, unknown>) => remitenteEfectivo({ emailFrom: '', buzon: 'buzon@proveedor.com', usuario: 'buzon@proveedor.com', dominioWeb: D, ...o });
  ok(r({}).from === 'buzon@proveedor.com' && r({}).motivo === '', 'sin email_from: el buzón');
  ok(r({ emailFrom: 'ventas@ejemplo.com' }).from === 'ventas@ejemplo.com', 'del dominio de la instancia');
  ok(r({ emailFrom: 'ventas@mail.ejemplo.com' }).from === 'ventas@mail.ejemplo.com', 'de un subdominio de la instancia');
  ok(r({ emailFrom: 'otro@proveedor.com' }).from === 'otro@proveedor.com', 'del dominio del buzón');
  ok(r({ emailFrom: ' Ventas@Ejemplo.COM ' }).from === 'Ventas@Ejemplo.COM', 'recortado y sin tocar mayúsculas');
  const ajeno = r({ emailFrom: 'ceo@banco.com' });
  ok(ajeno.from === 'buzon@proveedor.com' && ajeno.motivo === 'dominio_distinto', 'dominio ajeno → el buzón y el motivo');
  ok(r({ emailFrom: 'ventas@ejemplo.com.fraude.ru' }).motivo === 'dominio_distinto', 'sufijo falso');
  ok(r({ emailFrom: 'ventas@fraudeejemplo.com' }).motivo === 'dominio_distinto', 'prefijo falso');
  for (const m of ['no-es-correo', 'a@x.com, b@ejemplo.com', 'Ana <a@ejemplo.com>', 'a@ejemplo.com\r\nBcc: v@y.com', 'a@ejem\nplo.com']) {
    const x = r({ emailFrom: m });
    ok(x.from === 'buzon@proveedor.com' && x.motivo === 'no_valido', 'no válido: ' + JSON.stringify(m) + ' → ' + JSON.stringify(x));
  }
  ok(r({ emailFrom: 5 }).motivo === 'no_valido', 'no texto');
  // el usuario SMTP puede no ser un correo (un login suelto): el dominio de la instancia sigue valiendo
  ok(remitenteEfectivo({ emailFrom: 'ventas@ejemplo.com', buzon: 'noreply@proveedor.com', usuario: 'login-suelto', dominioWeb: D }).from === 'ventas@ejemplo.com', 'usuario que no es correo');
  // sin buzón no hay con qué enviar: from vacío y se dice
  const sin = remitenteEfectivo({ emailFrom: '', buzon: '', usuario: 'login', dominioWeb: D });
  ok(sin.from === '' && sin.motivo === 'sin_remitente', 'sin buzón');
  ok(remitenteEfectivo({ emailFrom: 'a@otro.com', buzon: '', dominioWeb: D }).from === '', 'dominio ajeno y sin buzón: nada');
  ok(remitenteEfectivo({ emailFrom: 'ventas@ejemplo.com', buzon: '', dominioWeb: D }).from === 'ventas@ejemplo.com', 'propio y sin buzón: sirve el propio');
  ok(remitenteEfectivo({ emailFrom: 'ventas@ejemplo.com', buzon: 'b@p.com', dominioWeb: '' }).motivo === 'dominio_distinto', 'sin dominio_web no se da por propio');
});

Deno.test('replyToEfectivo: un correo válido o nada', () => {
  ok(replyToEfectivo(' a@ejemplo.com ') === 'a@ejemplo.com', 'válido');
  for (const s of ['', 'x', 'a@x.com, b@x.com', 'a@x.com\r\nBcc: v@y.com', null, undefined, 5]) ok(replyToEfectivo(s) === '', 'no debería valer: ' + JSON.stringify(s));
});

Deno.test('buzonAvisoValido: dominio de la instancia, de email_from o del usuario SMTP', () => {
  const D = 'ejemplo.com', o = { dominio: D, emailFrom: 'ventas@desde.com', usuarioSmtp: 'buzon@vault.com' };
  ok(buzonAvisoValido('a@ejemplo.com', o), 'instancia'); ok(buzonAvisoValido('a@mail.ejemplo.com', o), 'subdominio de la instancia');
  ok(buzonAvisoValido('A@DESDE.com', o), 'email_from, sin importar mayúsculas'); ok(buzonAvisoValido('a@vault.com', o), 'usuario SMTP');
  ok(!buzonAvisoValido('a@sub.vault.com', o), 'del servidor/email_from solo el dominio exacto'); ok(!buzonAvisoValido('a@ajeno.com', o), 'ajeno');
  ok(!buzonAvisoValido('a@vault.com.fraude.ru', o), 'sufijo falso'); ok(!buzonAvisoValido('a@vault.com\nBcc: x@y.com', o), 'con salto de línea');
  ok(!buzonAvisoValido('a@vault.com', { dominio: D }), 'sin email_from ni servidor conocidos solo vale la instancia');
});
