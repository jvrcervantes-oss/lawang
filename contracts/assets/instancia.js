/* Ficha de ESTA instancia del ERP — AxisWorks ERP, F3 (25-sep-2026), encargos/20260924_estudio_erp_modular.md.

   No es código: son los datos que distinguen a este cliente de cualquier otro. El núcleo (guard.js y toda la suite)
   no escribe ninguno de estos valores; los lee de aquí. En cada instancia nueva del ERP el build de AxisWorks genera
   la suya (comercial/demo-erp/build.py --instancia), así que cambiar un valor de este cliente es cambiar este fichero y
   nada más.

   Se carga ANTES de guard.js en cada página de la intranet (y, en las públicas —acceso, portal, firma—, antes de
   crear el cliente de Supabase). Si falta, guard.js se para: sin base no hay nada que enseñar.
   Solo lectura: nadie puede pisarlo después en la misma página. */
(function () {
  var ficha = Object.freeze({
    sb_url: 'https://vtulllundrfennhjddhc.supabase.co',
    sb_key: 'sb_publishable_B_ot_6lNVRLiWiEMtApYOQ_3Ho3xNUg',   // publicable: el candado es la RLS
    marca: 'Lawang',                                             // en frases: «lo paga Lawang»
    cabecera: 'LAWANG',                                          // barra lateral, en grande
    subcabecera: 'PROPERTIES & SUITE',                           // barra lateral, debajo
    titulo: 'Lawang Intranet',                                   // pestaña del navegador: «Facturas — Lawang Intranet»
    firma_correo: 'Lawang Tropical Properties'                   // firma de los correos: la MARCA, nunca la sociedad
                                                                 // emisora (owner, 8-sep-2026: cada factura la emite una distinta)
  });
  try { Object.defineProperty(window, 'LW_INSTANCIA', { value: ficha, writable: false, configurable: false, enumerable: true }); }
  catch (e) { /* cargado dos veces: la primera ya fijó la misma ficha */ }
})();
