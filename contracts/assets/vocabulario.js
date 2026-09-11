/* Vocabulario de negocio de la suite — 14-ago-2026
   ----------------------------------------------------------------------------
   Cómo se LLAMAN las cosas y qué SIGNIFICAN, en un solo sitio.

   Fichero aparte de suite-comun.js a propósito, y no por gusto de separar:
   contracts/app.html define su propio `esc()` —con un segundo parámetro que
   suite-comun.js no tiene, así que no son intercambiables— y dos `const esc` en
   el ámbito global revientan la página entera con «Identifier has already been
   declared». Metiendo esto en un módulo sin colisiones, la herramienta más
   grande de la suite puede usar el vocabulario compartido sin tocar sus 36
   llamadas a `esc`.

   POR QUÉ EXISTE. El nombre de un tipo de contrato estaba escrito en dos sitios
   —`TIPO_ES` en operaciones/ y `TIPO_LABEL` en contracts/app.html— y no decían
   lo mismo. Encontrado el 14-ago comparándolos contra los datos de producción:

     · `reserva_parcela` salía «Bloqueo de Parcela» en Operaciones y «Parcela» en
       Contratos. Son 21 contratos con dos nombres distintos según dónde mires, y
       el bueno es el primero: el cliente pidió ese nombre el 24-jul.
     · `commercial_offer` salía «Oferta Comercial» en una y «Commercial Offer» en
       la otra.
     · `poa` salía «POA (Poder Notarial)» y «Poder Notarial».
     · Y a Operaciones le FALTABAN tres tipos, así que enseñaba la clave cruda de
       la base de datos: `hak_sewa_notario` (3 contratos), `ppjb_bonian_c2` (2) y
       `carta_reserva_hak_sewa` (1). Seis documentos reales enseñando jerga.

   Es el mismo fallo que ya se arregló una vez en app.html («faltaba: el listado
   enseñaba "poa" en crudo») y que volvió en la herramienta de al lado, porque la
   lista estaba copiada. Copiada otra vez, vuelve otra vez.

   AL AÑADIR UN TIPO DE CONTRATO hay que tocar cuatro sitios, no uno: la app
   (`CONTRACT_TIPO`), la numeración (`set_contrato_numero`), la restricción
   `contratos_tipo_check` de Postgres, y este diccionario. Los tres primeros
   rompen ruidosamente; éste no: se limita a enseñar la clave cruda. */

/* Nombre visible de cada tipo de contrato. La clave es el valor real de
   `contratos.tipo`. En español porque es el idioma de trabajo de la suite; la
   versión inglesa la resuelve idioma.js donde haga falta, no este fichero. */
const LW_TIPO_CONTRATO = {
  carta_reserva:          'Carta de Reserva',
  carta_reserva_ampliada: 'Carta de Reserva ampliada',
  carta_reserva_hak_sewa: 'Carta de Reserva (Hak Sewa)',
  carta_reserva_pma:      'Carta de Reserva Condicionada (PT PMA)',
  reserva_parcela:        'Bloqueo de Parcela',
  construccion:           'Construcción',
  contrato_general:       'Contrato General',
  commercial_offer:       'Oferta Comercial',
  acuerdo_comercial:      'Acuerdo Comercial',
  protocolo_operativo:    'Protocolo Operativo',
  ppjb_bonian:            'PPJB Bonian Beach',
  ppjb_bonian_c2:         'PPJB Bonian Beach · Parcela C2',
  hak_sewa_notario:       'Hak Sewa - Notario',
  poa:                    'Poder Notarial',
  cc00014_timon:          'Construcción · CC00014 Timon',
  adenda:                 'Adenda a contrato',
  carta_reserva_investor_deck: 'Carta de Reserva (Investor Deck)',
};
/* Cae a la clave si el tipo es nuevo y nadie lo añadió aquí. Enseñar
   `ppjb_bonian_c2` es feo, pero mentir con el nombre de otro documento es peor:
   el fallback nunca adivina. */
const lwTipoContrato = t => LW_TIPO_CONTRATO[t] || t || '—';

/* ---------------------------------------------------------------------------
   Qué contratos NO suman precio
   ---------------------------------------------------------------------------
   Una Carta de Reserva es un documento PRELIMINAR: reserva la operación mientras
   se hace el due diligence (15 días o un mes) y luego o se sigue o se devuelve el
   dinero. El precio que declara NO es de fiar —unos agentes ponen la villa
   entera, otros solo la parcela— y además es el mismo importe que luego reparten
   el Bloqueo de Parcela (suelo) y la Construcción (obra). Sumarla cuenta la misma
   villa dos veces.

   Vivía SOLO en compradores/ (12-ago: una Carta + Construcción de 76.500 € daba
   153.000 € por la misma villa). El 14-ago la Carta pasó a colgar de su Bloqueo y
   Operaciones —que suma el grupo y no tenía la regla— empezó a dar el doble:
   328.000 € por una villa de 164.000.

   Lo ÚNICO que se hereda de una Carta es cuánto pagó el cliente: el COBRADO sí
   suma todo el grupo, para descontárselo al pasar a Bloqueo sin duplicarlo. */
const LW_TIPOS_PRELIMINARES = ['carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa',
                               'carta_reserva_pma', 'carta_reserva_investor_deck'];
const lwEsPreliminar = t => LW_TIPOS_PRELIMINARES.includes(t);


/* ---------------------------------------------------------------------------
   BUSCAR SIN QUE LAS TILDES ESTORBEN — 8-sep-2026, aviso del owner:
   «todos los buscadores de la suite no filtran si llevan tildes».
   ---------------------------------------------------------------------------
   Los once buscadores de la suite hacian
   `String(v).toLowerCase().includes(q)`. Eso baja las mayusculas pero NO toca
   los acentos, asi que escribir «maria» no encontraba a MARIA (con tilde) y
   escribir «Balí» no encontraba «Bali». En una cartera con nombres espanoles,
   indonesios y franceses el buscador fallaba justo en los que mas se buscan.

   `normalize('NFD')` separa la letra de su acento y el rango de combinantes
   se tira. Se normalizan LOS DOS LADOS en la misma funcion a proposito: con
   dos llamadas separadas siempre acaba habiendo un sitio que normaliza solo
   uno, y ese buscador vuelve a fallar sin que nadie lo note.

   Vive aqui y no en `suite-comun.js` por el mismo motivo que el resto de este
   fichero: `contracts/app.html` NO puede cargar aquel (su `esc()` local
   chocaria), y app.html tambien busca. */
function lwNormaliza(s){
  return String(s == null ? '' : s)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}
/* `q` ya viene normalizado o no: da igual, se normaliza aqui. Vacio = todo pasa,
   que es lo que espera un buscador con el campo en blanco. */
function lwBusca(texto, q){
  const aguja = lwNormaliza(q);
  return !aguja || lwNormaliza(texto).includes(aguja);
}
/* Varios campos de una misma fila: «alguno de estos casa». Evita repetir el
   `.some(...)` en once sitios y, sobre todo, evita que uno de los once se
   escriba sin normalizar. */
function lwBuscaEn(campos, q){
  const aguja = lwNormaliza(q);
  if(!aguja) return true;
  return (campos || []).some(v => lwNormaliza(v).includes(aguja));
}

/* ── ORDEN DE PROYECTOS: W, luego S, luego G, luego los que no llevan código ──
   11-sep-2026, petición del owner para /intranet/proyectos/ y /intranet/v4/proyectos/.

   El código de parcela máster (W5, S1, G2…) es como el owner tiene ordenada la
   cartera en la cabeza y en el parcelario: alfabético puro mezclaba "Bebali G1"
   entre dos W y dejaba los proyectos sin código repartidos por toda la lista.

   DE DÓNDE SALE EL CÓDIGO, en este orden:
     1. La columna `proyectos.parcela_master` — el dato con dueño. Hoy la llevan
        6 de 29 filas, pero es la buena: "Bonian Village" no enseña código en su
        nombre y sin embargo ES la W8, así que aparece entre las W. No es un
        fallo de orden: es el dato real, que el nombre no cuenta.
     2. Si está vacía, el código embebido en el propio nombre ("Palm Field W5",
        "The Cliff - S8", "S3 - S4 Karana" — da igual dónde vaya).
   Sin ninguno de los dos, el proyecto cae al último grupo, alfabético.

   `\b([WSG])(\d{1,2})\b` pegado y en MAYÚSCULA, sin `/i` y sin espacio opcional:
   todos los códigos reales se escriben así, y aflojarlo convertiría cualquier
   "…s 2 dormitorios" o un nombre en minúscula en un código falso.

   Dentro de cada grupo manda el NÚMERO, no el texto: como cadena, "W13" iría
   antes que "W2". Empate (o sin código) se resuelve por nombre. */
const LW_GRUPO_PARCELA = { W:0, S:1, G:2 };
const LW_RE_PARCELA = /\b([WSG])(\d{1,2})\b/;

/* Devuelve [grupo, número, nombre] — la clave por la que se ordena. Se expone
   suelta además del comparador porque una pantalla puede querer agrupar o
   pintar el código, no solo ordenar. */
function lwClaveProyecto(nombre, parcelaMaster){
  const m = LW_RE_PARCELA.exec(String(parcelaMaster || '')) ||
            LW_RE_PARCELA.exec(String(nombre || ''));
  const grupo = m ? LW_GRUPO_PARCELA[m[1]] : 3;
  return [grupo, m ? Number(m[2]) : 0, lwNormaliza(nombre)];
}

/* Comparador para `.sort()`. Fábrica, no función suelta, porque las dos
   pantallas ordenan cosas distintas:
     · /intranet/proyectos/ ordena ARRAYS DE NOMBRES (strings) y tiene las
       parcelas máster aparte → `lwOrdenProyectos(PROYECTOS_FICHA)`, mapa
       nombre → ficha (o → código suelto; se aceptan ambos).
     · /intranet/v4/proyectos/ ordena las FILAS de `proyectos`, que ya traen su
       `parcela_master` dentro → `lwOrdenProyectos()` sin argumento.
   Un solo comparador para las dos: si el criterio cambia, cambia en un sitio. */
function lwOrdenProyectos(master){
  const codigoDe = (x, nombre) => {
    if(x && typeof x === 'object' && x.parcela_master != null) return x.parcela_master;
    const m = master && master[nombre];
    if(m == null) return '';
    return (typeof m === 'object') ? (m.parcela_master || '') : m;
  };
  return (a, b) => {
    const na = (a && typeof a === 'object') ? a.nombre : a;
    const nb = (b && typeof b === 'object') ? b.nombre : b;
    const ka = lwClaveProyecto(na, codigoDe(a, na));
    const kb = lwClaveProyecto(nb, codigoDe(b, nb));
    return (ka[0] - kb[0]) || (ka[1] - kb[1]) || (ka[2] < kb[2] ? -1 : ka[2] > kb[2] ? 1 : 0);
  };
}
