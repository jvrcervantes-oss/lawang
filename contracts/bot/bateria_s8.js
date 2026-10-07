#!/usr/bin/env node
/* Batería viva de S8 («plantillas por empresa», 7-oct-2026): 10 preguntas por empresa contra la edge DESPLEGADA.
   NO está en el gate: llama a bot-agentes de verdad (gasta crédito del modelo, 1 llamada por pregunta) y necesita el JWT
   de un agente con la casilla «Asistente» que vea contratos de ESA empresa.
   Uso:  JWT=<jwt> node bateria_s8.js --empresa sandal_woods --contratos id1,id2,... --otra "frase de la otra empresa|otra frase"
   Pasa si, en las 10 respuestas: (a) `fuentes` cita plantillas_contrato con campo «… · <empresa> · <version_id>» de la empresa pedida
   o, para contratos sin versión, plantilla_web; (b) el borrador no contiene NINGUNA de las frases de --otra
   (texto que solo aparece en el cuerpo de la otra empresa); (c) ninguna respuesta pasa a ser «Sin artículo aplicable» por
   culpa de una orden metida en el cuerpo. Sale con 1 si algo falla. Solo imprime números y ids, nunca el borrador. */
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const EMPRESA = arg('--empresa', null);
const CONTRATOS = (arg('--contratos', '') || '').split(',').filter(Boolean);
const OTRA = (arg('--otra', '') || '').split('|').map((s) => s.trim()).filter(Boolean);
const URL = arg('--url', 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/bot-agentes');
const JWT = process.env.JWT;
if (!EMPRESA || !CONTRATOS.length || !JWT) { console.error('falta --empresa, --contratos o JWT'); process.exit(2); }
const PREGUNTAS = [
  '¿Cuál es el plazo de ejecución según el contrato?', '¿Qué dice el contrato si hay retraso en la entrega?', '¿Cómo se paga el precio y en qué hitos?',
  '¿Qué pasa si el comprador desiste?', '¿Quién es la parte vendedora y cómo se identifica?', '¿Qué ley aplica y dónde se resuelven las disputas?',
  '¿Hay garantía o período de defectos? ¿Cuánto dura?', '¿Qué anexos lleva este contrato?', '¿Se puede ceder el contrato a un tercero?', '¿Qué dice sobre impuestos y gastos notariales?',
];
(async () => {
  let fallos = 0, hechas = 0;
  for (let i = 0; i < PREGUNTAS.length; i++) {
    const contrato_id = CONTRATOS[i % CONTRATOS.length];
    const r = await fetch(URL, { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + JWT },
      body: JSON.stringify({ contrato_id, pregunta: PREGUNTAS[i] }) });
    const j = await r.json().catch(() => ({}));
    hechas++;
    const borrador = String(j.borrador || '');
    const fuentesPl = (j.fuentes || []).filter((f) => /^plantilla/.test(f.tabla));
    const deEmpresa = fuentesPl.every((f) => f.tabla === 'plantilla_web' || String(f.campo || '').includes(' · ' + EMPRESA + ' · '));
    const mezcla = OTRA.filter((f) => borrador.toLowerCase().includes(f.toLowerCase()));
    const ok = r.status === 200 && fuentesPl.length > 0 && deEmpresa && mezcla.length === 0;
    if (!ok) fallos++;
    console.log((ok ? 'OK    ' : 'FALLA ') + (i + 1) + ' http=' + r.status + ' contrato=' + contrato_id.slice(0, 8) + ' fuentes_plantilla=' + fuentesPl.map((f) => f.tabla).join(',') + ' frases_de_la_otra=' + mezcla.length);
  }
  console.log(hechas + ' preguntas, ' + fallos + ' fallo(s)');
  process.exit(fallos ? 1 : 0);
})();
