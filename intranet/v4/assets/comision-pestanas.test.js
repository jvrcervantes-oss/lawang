// Cada pestaña de la barra tiene su panel y cada panel su pestaña (identificadores PROPIOS, no los del menú lateral).
const fs = require('fs'), assert = require('assert'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '../comision-admin/index.html'), 'utf8');
const botones = [...html.matchAll(/data-lw-ca-pestana="([^"]+)"/g)].map(m => m[1]);
const paneles = new Set([...html.matchAll(/data-lw-ca-panel="([^"]+)"/g)].map(m => m[1]));
assert.ok(botones.length >= 5, 'faltan pestañas');
botones.forEach(b => assert.ok(paneles.has(b), 'la pestaña ' + b + ' no tiene panel'));
paneles.forEach(p => assert.ok(botones.includes(p), 'el panel ' + p + ' no tiene pestaña'));
assert.ok(!/data-lw-pestana=/.test(html), 'data-lw-pestana es del menú lateral (nav.js): no usarlo aquí');
assert.ok(botones.includes('calendario'), 'la pestaña por defecto (calendario) tiene que existir');
console.log('OK comision-pestanas.test.js — ' + botones.length + ' pestañas con su panel');
