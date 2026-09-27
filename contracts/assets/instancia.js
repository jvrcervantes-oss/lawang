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
    inicio: '/intranet/v4/home/',                                // portada tras entrar (27-sep-2026, corte de la clásica,
                                                                 // LAW-257/S19): /intranet/ sigue siendo la PUERTA (login),
                                                                 // pero con sesión manda aquí. El hub clásico solo se pinta
                                                                 // ya para enseñar «?sin_permiso=» (guard.js rebota ahí)
    firma_correo: 'Lawang Tropical Properties',                  // firma de los correos: la MARCA, nunca la sociedad
                                                                 // emisora (owner, 8-sep-2026: cada factura la emite una distinta)
    // F3 lote 3 (27-sep-2026): lo que antes decidía el código con NOMBRES de proyecto de este cliente.
    // Clave = proyectos.nombre tal cual (el mismo texto que unidades.proyecto). Sin entrada, sin plano/sin campos.
    masterplans: Object.freeze({                                 // vista «Plano» de /intranet/v4/proyectos/: qué proyecto
      'Palm Field W5': '/investor-deck/masterplan/palmfield.json',  // tiene masterplan y qué fichero pinta (los MISMOS
      'Sumba Hills': '/investor-deck/masterplan/sumbahills.json'    // .json que usan los investor decks)
    }),
    proyectos_con_fases: Object.freeze(['Sumba Hills'])          // proyectos cuyas unidades llevan fase/zona de masterplan
                                                                 // (editores.js: «Nueva unidad» y «Editar unidad» las piden)
  });
  try { Object.defineProperty(window, 'LW_INSTANCIA', { value: ficha, writable: false, configurable: false, enumerable: true }); }
  catch (e) { /* cargado dos veces: la primera ya fijó la misma ficha */ }
})();
