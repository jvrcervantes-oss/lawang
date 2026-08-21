/* ═══════════════════════════════════════════════════════════════════════════
   QUÉ PARCELA SE VENDE — inventario, traspaso y precios que vienen de él
   Sale de contracts/app.html el 21-ago-2026. Se carga ANTES que el <script> de
   la página, que es lo que hace que sus nombres estén disponibles cuando corre.
   ═══════════════════════════════════════════════════════════════════════════
   Aquí vive todo lo que decide qué parcela puede coger un contrato: leer el
   inventario del proyecto, saber quién ocupa cada unidad, si el ocupante es el
   MISMO comprador (y por tanto se puede traspasar la parcela de una Carta a su
   Bloqueo), y traer el precio desde la unidad en vez de dejarlo a mano.

   Está junto y no repartido porque son una sola pregunta: el trigger de la base
   (sql/parcelas_multiples.sql) valida al guardar, y esto existe para no ofrecer
   siquiera lo que fallaría. Cuando las dos mitades se separan, la pantalla
   ofrece algo que la base rechaza y el usuario no entiende por qué.
   ═══════════════════════════════════════════════════════════════════════════ */
/* ---------- la subparcela sale del inventario ----------
   Si el proyecto elegido tiene unidades dadas de alta en /proyectos/, el código
   de parcela deja de ser texto libre y pasa a ser un desplegable con las que
   hay, su modelo y su precio. Las que ya tiene otro contrato salen marcadas y
   no se pueden elegir: la base también lo impide (trigger
   `sincroniza_unidad_contrato`), pero enseñar una opción que va a fallar al
   guardar es hacerle perder el rato a quien la elige.
   Si el proyecto NO tiene unidades, se queda como estaba —texto libre— por la
   misma regla de siempre: el sistema no frena una venta esperando a que alguien
   dé de alta el inventario. */
let UNIDADES_PROY = { proyecto:null, lista:[], fallo:null };   // `fallo`: no se ha podido leer el inventario (≠ no hay inventario)
// Firma de los identificadores del comprador con los que se pintó el selector.
// Vive junto a UNIDADES_PROY, que es el otro estado que lee el mismo hook.
let ID_PINTADO = null;
/* Tipos que CEDEN una parcela al Bloqueo de Parcela (14-ago-2026, petición del
   owner; caso real: A4 de Bonian Village). Es la secuencia normal de una venta,
   la misma que describe el orden de TEMPLATES: se reserva, se bloquea la
   parcela y se firma la obra. Hasta hoy el segundo paso estaba prohibido —
   había que ir a /proyectos/ a soltar la parcela a mano antes de poder emitir
   el Bloqueo, y el error que salía ("ya está asignada al contrato CR000xx")
   parecía un choque con otra venta cuando era la SUYA PROPIA.
   Solo las Cartas de Reserva y solo hacia un Bloqueo: dos Bloqueos sobre la
   misma parcela, o una Carta sobre una parcela ya bloqueada, siguen chocando.
   Y desde LAW-51 (mismo día), solo si es el MISMO comprador — ver
   estadoTraspaso() e `identificadoresDelFormulario` aquí abajo, y
   sql/traspaso_mismo_comprador_y_enlace.sql en la base.
   La regla vive por duplicado a propósito — aquí para no enseñar deshabilitado
   lo que sí se puede elegir, y en el trigger de Postgres porque es el único
   sitio que de verdad lo impide. Si cambia una, cambia la otra. */
const TIPOS_CEDEN_PARCELA = ['carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa'];

/* Los MISMOS identificadores con los que la base decide si dos contratos son
   del mismo comprador: pasaporte y email, en minúsculas y sin espacios, del
   Adquiriente I y de los adicionales. Réplica de
   `public.contrato_identificadores` (sql/traspaso_mismo_comprador_y_enlace.sql).
   Se comparan estos y no el nombre porque el nombre es texto libre: una tilde o
   un segundo apellido darían un bloqueo falso. Es también lo que usa
   `sincronizar_compradores` para crear o reconocer la ficha de `clients`, así
   que "mismo comprador" significa aquí exactamente lo mismo que en Compradores.
   ⚠️ Tercera copia de la regla del traspaso, con las otras dos: si cambia una,
   cambian las tres. */
const normId = v => String(v == null ? '' : v).trim().toLowerCase();
const unicos = arr => [...new Set(arr.filter(Boolean))];
function identificadoresOcupante(c){
  const out = [normId(c && c.adq1_pasaporte), normId(c && c.adq1_email)];
  (Array.isArray(c && c.extras) ? c.extras : []).forEach(e => {
    out.push(normId(e && e.pasaporte), normId(e && e.email));
  });
  return unicos(out);
}
function identificadoresDelFormulario(){
  const out = [];
  compradoresDelFormulario().lista.forEach(p => { out.push(normId(p.pasaporte), normId(p.email)); });
  return unicos(out);
}
/* Cuatro respuestas y no un sí/no: el desplegable tiene que poder decir POR QUÉ
   una parcela no se puede coger. 'otro' y 'sin_datos' salían antes como
   traspasables y reventaban al guardar, que es justo lo que este selector
   existe para evitar (LAW-51, 14-ago-2026). */
function estadoTraspaso(u){
  if(CONTRACT_TIPO[CURRENT.slug] !== 'reserva_parcela') return 'no';
  if(!u.ocupante || !TIPOS_CEDEN_PARCELA.includes(u.ocupante.tipo)) return 'no';
  const mios = identificadoresDelFormulario(), suyos = identificadoresOcupante(u.ocupante);
  if(!mios.length || !suyos.length) return 'sin_datos';
  return mios.some(v => suyos.includes(v)) ? 'ok' : 'otro';
}
function puedeTraspasarParcela(u){ return estadoTraspaso(u) === 'ok'; }
async function cargarUnidadesDelProyecto(proyecto){
  if(!sb || !proyecto || UNIDADES_PROY.proyecto === proyecto) return;
  UNIDADES_PROY = { proyecto, lista:[], fallo:null };
  try{
    const { data, error } = await sb.from('unidades')
      .select('codigo, modelo, superficie_m2, precio_suelo, precio, moneda, estado, contrato_id')
      .eq('proyecto', proyecto).order('codigo');
    /* 21-ago-2026: el error se GUARDA. Antes se descartaba con un `if(!error)` y
       el catch de abajo estaba vacío, así que un inventario ilegible dejaba la
       lista a cero — y una lista a cero significa «este proyecto no tiene
       inventario», que es lo que hace caer el campo a texto libre. Las dos
       situaciones se veían igual en pantalla y solo una es segura. */
    if(error) UNIDADES_PROY.fallo = error.message || 'no se ha podido leer';
    else UNIDADES_PROY.lista = data || [];
    /* Quién ocupa cada parcela: tipo y número del contrato que la tiene. Hace
       falta para saber si se puede traspasar — una parcela reservada por una
       Carta de Reserva sí puede pasar a su Bloqueo de Parcela (ver
       TIPOS_CEDEN_PARCELA y sql/parcela_traspaso_carta_a_bloqueo.sql).
       Consulta APARTE y no un embebido `contratos(...)` de PostgREST: eso
       depende del nombre de la clave ajena de `unidades.contrato_id`, que no
       se crea en este repo (la columna es anterior). Si el nombre no fuera el
       esperado, el embebido devuelve error, la lista se queda vacía y el
       selector de parcela cae a texto libre SIN avisar — un fallo mudo justo
       en el campo que decide qué parcela se vende.
       Si esta segunda consulta falla, se pierde el traspaso pero no el
       inventario: las parcelas ocupadas salen bloqueadas, como hasta hoy. */
    const ids = [...new Set(UNIDADES_PROY.lista.map(u=>u.contrato_id).filter(Boolean))];
    if(ids.length){
      // pasaporte/email del ocupante: hacen falta para saber si el traspaso es
      // al MISMO comprador (estadoTraspaso). Sin esto el selector ofrecería
      // parcelas de otro cliente que el trigger rechaza al guardar.
      const { data: cs } = await sb.from('contratos')
        .select('id,tipo,numero,adq1_pasaporte:datos->fields->>adq1_pasaporte,'
              + 'adq1_email:datos->fields->>adq1_email,extras:datos->compradores').in('id', ids);
      const porId = Object.fromEntries((cs||[]).map(c=>[c.id, c]));
      UNIDADES_PROY.lista.forEach(u=>{ u.ocupante = u.contrato_id ? porId[u.contrato_id] || null : null; });
    }
  }catch(e){ UNIDADES_PROY.fallo = UNIDADES_PROY.fallo || (e && e.message) || 'no se ha podido leer'; }
  pintarSelectorParcela();
}
function pintarSelectorParcela(){
  /* MULTI-PARCELA — 18-ago-2026 (encargo del owner): un mismo Bloqueo o una
     misma Carta pueden llevar VARIAS parcelas. El valor sigue siendo el campo
     `parcela_codigo` de siempre, ahora como lista separada por comas («A4, A5»):
     las plantillas la imprimen tal cual, y un contrato viejo con un código es
     una lista de uno — cero migración. El patrón de UI es el del teléfono:
     el dato real vive en un input OCULTO con name=, y lo visible (chips + el
     desplegable de añadir) no lleva name para que collect() siga viendo un
     único elemento por campo. El trigger de la base ya valida por parcela
     (sql/parcelas_multiples.sql): esto solo evita ofrecer lo que fallaría. */
  const caja = document.querySelector('.field[data-key="parcela_codigo"]');
  if(!caja) return;
  const campo = caja.querySelector('[name="parcela_codigo"]');
  const valor = campo ? campo.value : '';
  const elegidas = valor.split(',').map(x=>x.trim()).filter(Boolean);
  const libres = UNIDADES_PROY.lista;

  if(!libres.length){
    // sin inventario: texto libre de siempre (se pueden teclear comas a mano)
    if(!campo || campo.type === 'hidden' || campo.tagName === 'SELECT'){
      caja.querySelector('.parcelas-multi')?.remove();
      caja.querySelector('.hint-unidades')?.remove();
      if(campo) campo.outerHTML = `<input name="parcela_codigo" type="text" value="${escAttr(valor)}" autocomplete="off">`;
      wireCampoParcela();
    }
    /* Texto libre por no PODER mirar no es lo mismo que texto libre por no haber
       nada que mirar: en el primer caso el campo que decide qué parcela se vende
       ha perdido su única comprobación —ocupada, de otro comprador, traspasable—
       y quien escribe no tiene forma de saberlo. Se dice, y se dice aquí. */
    caja.querySelector('.hint-unidades')?.remove();
    caja.insertAdjacentHTML('beforeend', UNIDADES_PROY.fallo
      ? `<p class="hint-unidades" style="font-size:11.5px;color:#C8791F;margin:6px 0 0">
           <b>No se ha podido leer el inventario de este proyecto</b>, así que la parcela va a
           mano y sin comprobar si está libre. Recarga la página antes de guardar.</p>`
      : `<p class="hint-unidades" style="font-size:11.5px;color:var(--muted);margin:6px 0 0">
           Este proyecto no tiene unidades cargadas en el inventario: la parcela se escribe a mano.</p>`);
    return;
  }
  const mio = SAVED_CONTRACT && SAVED_CONTRACT.id;
  const ops = libres.filter(u => !elegidas.includes(u.codigo)).map(u => {
    const tomada = u.contrato_id && u.contrato_id !== mio;
    const modo = tomada ? estadoTraspaso(u) : 'no';
    const traspaso = modo === 'ok';
    const suNum = (u.ocupante && u.ocupante.numero) || 'una Carta de Reserva';
    const nota = traspaso        ? 'reservada en ' + suNum + ' · se traspasa a este contrato'
               : modo === 'otro' ? 'reservada en ' + suNum + ' · de otro comprador'
               : modo === 'sin_datos' ? 'reservada en ' + suNum + ' · falta pasaporte o email para traspasarla'
               : tomada ? 'ya asignada' : (u.estado !== 'disponible' ? u.estado : '');
    const partes = [u.codigo, u.modelo, u.superficie_m2 ? u.superficie_m2 + ' m²' : '',
                    u.precio ? fmtImporte(Number(u.precio)) + ' ' + (u.moneda||'EUR') : '', nota];
    return `<option value="${escAttr(u.codigo)}" ${tomada&&!traspaso?'disabled':''}>${
      escAttr(partes.filter(Boolean).join(' · '))}</option>`;
  }).join('');

  // chips de lo elegido (la ✕ quita esa parcela) + añadidor sin name
  const chips = elegidas.map(cod => {
    const u = libres.find(x => x.codigo === cod);
    const detalle = u ? [u.modelo, u.superficie_m2 ? u.superficie_m2 + ' m²' : ''].filter(Boolean).join(' · ')
                      : 'fuera del inventario';
    return `<span class="parcela-chip">${esc(cod)}${detalle ? ` <i>${esc(detalle)}</i>` : ''}
      <button type="button" data-quitar-parcela="${escAttr(cod)}" aria-label="Quitar la parcela ${escAttr(cod)}">✕</button></span>`;
  }).join('');
  const html =
    `<input type="hidden" name="parcela_codigo" value="${escAttr(elegidas.join(', '))}">
     <div class="parcelas-multi">
       ${chips ? `<div class="parcela-chips">${chips}</div>` : ''}
       <select class="parcela-add" aria-label="Añadir parcela">
         <option value="">— ${elegidas.length ? 'añadir otra parcela' : 'elegir parcela'} —</option>${ops}
       </select>
     </div>`;
  if(campo){ campo.outerHTML = html; caja.querySelector('.parcelas-multi + .parcelas-multi')?.remove(); }
  else caja.insertAdjacentHTML('beforeend', html);
  // si el reemplazo dejó un bloque visible viejo, fuera (el nuevo va pegado al hidden)
  const bloques = caja.querySelectorAll('.parcelas-multi');
  for(let i=0;i<bloques.length-1;i++) bloques[i].remove();

  caja.querySelector('.hint-unidades')?.remove();
  {
    const libresN = libres.filter(u => !u.contrato_id && u.estado === 'disponible' && !elegidas.includes(u.codigo)).length;
    const traspN = libres.filter(u => u.contrato_id && u.contrato_id !== mio && puedeTraspasarParcela(u)).length;
    caja.insertAdjacentHTML('beforeend',
      `<p class="hint-unidades" style="font-size:11.5px;color:var(--muted);margin:6px 0 0">
         ${libres.length} unidades en el inventario · <b>${libresN} libres</b>${
           traspN ? ` · <b>${traspN}</b> reservadas con Carta que este contrato puede traspasar` : ''}.
         Se pueden elegir varias; al guardar, las elegidas quedan reservadas en Unidades.</p>`);
  }
  wireCampoParcela();
}
/* El campo se rehace en el DOM: se le devuelven sus oyentes. El dato vive en el
   OCULTO; chips y añadidor solo lo reescriben y disparan `input` sobre él, que
   es donde escuchan sync/preview (patrón del teléfono). */
function wireCampoParcela(){
  const caja = document.querySelector('.field[data-key="parcela_codigo"]');
  if(!caja) return;
  const oculto = caja.querySelector('input[type="hidden"][name="parcela_codigo"], input[type="text"][name="parcela_codigo"]');
  if(oculto && !oculto._wired){
    oculto._wired = true;
    oculto.addEventListener('input',  ()=>{ syncDatosDeUnidad(); aplicarReglasCampos(); renderDebounced(); });
    oculto.addEventListener('change', ()=>{ syncDatosDeUnidad(); aplicarReglasCampos(); render(); });
  }
  if(caja._multiWired) return;
  caja._multiWired = true;
  caja.addEventListener('change', e => {
    const add = e.target.closest('.parcela-add');
    if(!add || !add.value) return;
    const el = caja.querySelector('input[name="parcela_codigo"]');
    const lista = el.value.split(',').map(x=>x.trim()).filter(Boolean);
    if(!lista.includes(add.value)) lista.push(add.value);
    el.value = lista.join(', ');
    el.dispatchEvent(new Event('input', { bubbles:true }));
    pintarSelectorParcela();
    el.dispatchEvent(new Event('change', { bubbles:true }));
  });
  caja.addEventListener('click', e => {
    const q = e.target.closest('[data-quitar-parcela]');
    if(!q) return;
    const el = caja.querySelector('input[name="parcela_codigo"]');
    el.value = el.value.split(',').map(x=>x.trim()).filter(x => x && x !== q.dataset.quitarParcela).join(', ');
    el.dispatchEvent(new Event('input', { bubbles:true }));
    pintarSelectorParcela();
    el.dispatchEvent(new Event('change', { bubbles:true }));
  });
}

/* ---------- la parcela elegida trae sus datos ----------
   Superficie, precio por m², precio total y modelo de villa están en el
   inventario: volver a teclearlos es teclear dos veces el mismo dato, y la
   segunda vez es cuando se equivoca uno. Se rellenan al elegir la parcela y
   QUEDAN EDITABLES: el inventario es el punto de partida de una negociación,
   no su resultado.
   Solo se toca lo que está vacío o lo que puso este mismo automatismo — si el
   comercial pactó otro precio, no se le pisa. */
const AUTO_UNIDAD = {};
/* Aviso de precio forzado desde el inventario — 14-ago-2026, petición del owner.
   Usa `lwConfirmar` (assets/dialogo.js), el diálogo único de la suite: hasta el
   15-ago esto tenía su PROPIO modal pegado en el HTML de esta página, que es
   justo lo que la capa compartida existe para evitar. No es un toast a
   propósito — un aviso que se va solo en 4 segundos no vale para algo que cambia
   una cifra de dinero en un contrato.
   El botón de confirmar NO va en tono peligro: aquí no se destruye nada, se
   corrige. El rojo se reserva para lo que no se deshace. */
async function avisaPrecioForzado({ antes, nuevo, tipoDoc, unidad, suelo, villa, el, queEsTexto }){
  const mon = unidad.moneda || 'EUR';
  const im = n => fmtImporte(n) + ' ' + mon;
  const queEs = queEsTexto || (tipoDoc === 'reserva_parcela'
    ? `el <b>suelo</b> de ${escAttr(unidad.codigo)}`
    : `la <b>obra</b> de ${escAttr(unidad.codigo)} (la villa entera ${im(villa)} menos el suelo ${im(suelo)})`);
  const ok = await lwConfirmar({
    titulo: 'He corregido el precio',
    cuerpo:
      `<p>Este documento traía <b>${escAttr(antes)} ${mon}</b> y lo he cambiado a <b>${escAttr(nuevo)} ${mon}</b>, que es ${queEs} según el inventario.</p>`
      + `<p>La venta va partida en dos contratos: el <b>Bloqueo de Parcela</b> cobra el suelo y el <b>Contrato de Construcción</b> la obra. Si los dos llevan el precio de la villa completa, el cliente aparece debiendo el doble.</p>`
      + `<p>Si el precio de esta operación está negociado, deja el que tenías y edítalo a mano.</p>`,
    confirmar: 'Dejar ' + nuevo + ' ' + mon,
    cancelar:  'Dejar ' + antes + ' ' + mon,
  });
  if(!ok){
    el.value = antes; AUTO_UNIDAD['precio_total'] = antes;
    el.dispatchEvent(new Event('input', { bubbles:true }));   // que la vista previa se entere
    toast('Precio devuelto a ' + antes + ' ' + mon);
  }
}
/* Precio de la OBRA desde el Bloqueo vinculado — 15-ago-2026.
   La Construccion NO tiene selector de parcela: `ppjb_construccion.html` no
   lleva `parcela_codigo` (verificado), asi que `syncDatosDeUnidad` no corre
   nunca aqui y el precio de la obra no lo precargaba nadie. Resultado: la
   Construccion se quedaba con el precio de la villa ENTERA que arrastrara el
   formulario, y sumada a su Bloqueo daba el doble -- CC00021 de Juan Jose
   Carbajo Pinal, 164.000 cuando la obra son 95.600.
   El Bloqueo si sabe su parcela, y la parcela sabe villa y suelo. Al elegir el
   contrato vinculado se deduce la obra (villa - suelo) y se avisa igual que en
   el Bloqueo, con la opcion de dejar el precio que hubiera: puede estar
   negociado. */
let OBRA_VINCULO_HECHO = null;   // numero del Bloqueo ya resuelto, para no repreguntar en cada tecla
async function syncPrecioObraVinculada(){
  if(CONTRACT_TIPO[CURRENT.slug] !== 'construccion' || !sb) return;
  const sel = document.querySelector('[name="num_reserva_vinculada"]');
  const el  = document.querySelector('[name="precio_total"]');
  if(!sel || !el) return;
  if(!sel.value){ OBRA_VINCULO_HECHO = null; return; }
  if(sel.value === OBRA_VINCULO_HECHO) return;
  OBRA_VINCULO_HECHO = sel.value;                    // se marca ANTES de esperar, o dos teclas seguidas lanzan dos avisos
  const padre = (VINCULABLES||[]).find(c => c.numero === sel.value);
  if(!padre || !padre.parcela_codigo || !padre.proyecto_nombre) return;
  /* El Bloqueo vinculado puede llevar VARIAS parcelas (18-ago): se suman las
     obras (villa − suelo) de todas. Si alguna no está en el inventario o le
     faltan precios, mejor no tocar nada que precargar una obra a medias. */
  const codsPadre = String(padre.parcela_codigo).split(',').map(x=>x.trim()).filter(Boolean);
  const { data:us, error } = await sb.from('unidades')
    .select('codigo,precio,precio_suelo,moneda')
    .eq('proyecto', padre.proyecto_nombre).in('codigo', codsPadre);
  if(error || !us || us.length !== codsPadre.length
     || us.some(x => x.precio == null || x.precio_suelo == null)) return;
  const u = { codigo: codsPadre.join(' + '), moneda: us[0].moneda,
              precio: us.reduce((t,x)=>t+Number(x.precio),0),
              precio_suelo: us.reduce((t,x)=>t+Number(x.precio_suelo),0) };
  const obra = u.precio - u.precio_suelo;
  if(!(obra > 0)) return;                            // datos raros: mejor no tocar nada
  const nuevo = fmtImporte(obra), antes = String(el.value||'').trim();
  if(antes && parseImporte(antes) === obra) return;  // ya cuadra
  if(!antes){ el.value = nuevo; AUTO_UNIDAD['precio_total'] = nuevo; return; }
  el.value = nuevo; AUTO_UNIDAD['precio_total'] = nuevo;
  const mon = u.moneda || 'EUR';
  avisaPrecioForzado({ antes, nuevo, tipoDoc:'construccion', unidad:u, el,
    queEsTexto: `la <b>obra</b> de ${escAttr(u.codigo)} seg\u00fan ${escAttr(sel.value)}: `
              + `la villa entera ${fmtImporte(Number(u.precio))} ${mon} menos el suelo `
              + `${fmtImporte(Number(u.precio_suelo))} ${mon}` });
}
function syncDatosDeUnidad(){
  const sel = document.querySelector('[name="parcela_codigo"]');
  if(!sel) return;
  /* MULTI-PARCELA (18-ago-2026): el campo puede llevar «A4, A5». Se suman los
     datos de TODAS las conocidas del inventario — superficie, suelo y villa —
     y el precio según tipo se calcula sobre las sumas. Si algún código no está
     en el inventario, se precarga solo con lo que sí se conoce y no se fuerza
     nada: forzar un precio calculado a medias sería peor que no tocarlo. */
  const cods = String(sel.value||'').split(',').map(x=>x.trim()).filter(Boolean);
  if(!cods.length) return;
  const us = cods.map(c => (UNIDADES_PROY.lista || []).find(x => x.codigo === c)).filter(Boolean);
  if(!us.length) return;
  const completas = us.length === cods.length;   // ¿conocemos TODAS las elegidas?
  const suma = campo => us.every(u => u[campo] != null) ? us.reduce((t,u)=>t+Number(u[campo]),0) : null;
  const m2    = suma('superficie_m2');
  const suelo = suma('precio_suelo');
  const villa = suma('precio');
  const poner = (campo, valor) => {
    const el = document.querySelector(`[name="${campo}"]`);
    if(!el || valor == null || valor === '') return;
    const actual = String(el.value || '').trim();
    if(actual && actual !== AUTO_UNIDAD[campo]) return;   // escrito a mano: intocable
    el.value = valor;
    AUTO_UNIDAD[campo] = valor;
  };
  poner('tipologia_villa', m2 != null ? String(m2) : null);
  poner('precio_m2', (m2 && suelo != null) ? fmtImporte(suelo / m2) : null);
  /* El precio según tipo, sobre las SUMAS (la regla del 14-ago intacta: Bloqueo
     cobra suelo, Construcción obra, la Carta la villa entera). El forzado con
     aviso solo cuando conocemos TODAS las parcelas elegidas: con una fuera del
     inventario la suma está incompleta y forzar sería imponer una cifra mal. */
  const tipoDoc = CONTRACT_TIPO[CURRENT.slug];
  const precioSegunTipo =
      tipoDoc === 'reserva_parcela' ? suelo
    : tipoDoc === 'construccion'    ? ((villa != null && suelo != null) ? villa - suelo : null)
    : villa;
  const forzar = completas && (tipoDoc === 'reserva_parcela' || tipoDoc === 'construccion');
  const elPrecio = document.querySelector('[name="precio_total"]');
  if(forzar && precioSegunTipo != null && elPrecio){
    const antes = String(elPrecio.value || '').trim();
    const nuevo = fmtImporte(precioSegunTipo);
    if(antes && parseImporte(antes) !== precioSegunTipo){
      elPrecio.value = nuevo; AUTO_UNIDAD['precio_total'] = nuevo;
      const etiqueta = cods.join(' + ');
      avisaPrecioForzado({ antes, nuevo, tipoDoc,
        unidad:{ codigo: etiqueta, moneda: us[0].moneda }, suelo, villa, el: elPrecio,
        queEsTexto: tipoDoc === 'reserva_parcela'
          ? `el <b>suelo</b> de ${escAttr(etiqueta)}${us.length>1 ? ' (las ' + us.length + ' parcelas sumadas)' : ''}`
          : `la <b>obra</b> de ${escAttr(etiqueta)} (villa ${fmtImporte(villa)} menos suelo ${fmtImporte(suelo)})` });
    } else {
      poner('precio_total', nuevo);
    }
  } else {
    poner('precio_total', precioSegunTipo != null ? fmtImporte(precioSegunTipo) : null);
  }
  const modelos = [...new Set(us.map(u=>u.modelo).filter(Boolean))].join(', ');
  poner('villa_nombre', modelos || null);
  poner('tipologia_construccion', modelos || null);
  if(us[0].moneda){
    const mon = document.querySelector('[name="moneda"]');
    if(mon && !mon.value) mon.value = us[0].moneda;
  }
}
function buildForm(){
  if(EDITING){ EDITING=false; editBtnIdle(); }   // salir de edición al cambiar de plantilla/idioma
  const form = $('#form');
  const anexosAlFinal = FORM_ORDER.includes('anexos');
  // El panel de Cláusulas solo si la plantilla las imprime: sin el marcador, lo
  // que el agente escribiera ahí desaparecía sin decir nada (mismo criterio que
  // el panel de Compradores, que ya iba condicionado).
  // "Adquirientes adicionales" ya no se antepone aquí: se inyecta dentro del
  // recuadro de la sección 'comprador' (Adquiriente I), ver más abajo.
  const compradorExtraHTML = templateHTML.includes('<!--compradores-extra-->') ? buildCompradorPanel() : '';
  let html = buildDesignPanel() + (anexosAlFinal ? '' : buildAnnexPanel())
    + (templateHTML.includes('<!--extra-clauses-->') ? buildClausePanel() : '');
  // un rótulo por tier la PRIMERA vez que aparece: con FORM_ORDER los tiers ya
  // no son contiguos y comparar solo con el anterior repetía el mismo rótulo.
  const seenTiers = new Set(); let idx=0;
  SECTIONS.forEach(s=>{
    idx++;
    if(!seenTiers.has(s.tier)){ html += `<div class="tier-label ${seenTiers.size?'':'first'}">${L(TIERS[s.tier]||{es:s.tier})}</div>`; seenTiers.add(s.tier); }
    if(s.special==='hitos'){
      html += `<section class="section" data-sec="pagos" data-tier="${s.tier}">
        <header data-acc><span class="num">${idx}</span><h2>${L(s.title)}</h2><span class="chev">▾</span></header>
        <div class="body">${hitosBodyHTML()}</div></section>`;
      return;
    }
    const optional = s.optional ? `<div class="opt-toggle">${L({es:'añadir',en:'add',id:'tambah'})}<label class="switch"><input type="checkbox" data-opt="${s.id}"><span class="slider"></span></label></div>` : '';
    const cls = s.optional ? 'optional off' : '';
    const grid = ['comprador','sociedad','dinero','gestion','otros'].includes(s.id);
    const body = s.fields.map(fieldHTML).join('');
    const note = (s.id==='firmas' && TOKENS && TOKENS.bloqueado && TOKENS.bloqueado.length)
      ? `<div class="note-blocked"><b>Boilerplate bloqueado</b> — texto legal fijo en la plantilla, no editable aquí:
          <ul>${TOKENS.bloqueado.slice(0,6).map(x=>`<li>${x}</li>`).join('')}<li>…</li></ul></div>` : '';
    // buscador de cliente ya registrado: solo en Adquiriente I, precarga desde
    // `clients` en vez de teclear otra vez a alguien que ya tenemos fichado
    // El hueco lo rellena pintarFichaComprador() al final de buildForm(): o el
    // buscador + «crear ficha» (sin enlazar), o el chip de la ficha (enlazada).
    const clienteBuscadorHTML = s.id==='comprador' ? '<div id="cliFicha"></div>' : '';
    html += `<section class="section ${cls}" data-sec="${s.id}" data-tier="${s.tier}">
      <header data-acc><span class="num">${idx}</span><h2>${L(s.title)}</h2>${optional}<span class="chev">▾</span></header>
      <div class="body">${clienteBuscadorHTML}<div class="${grid?'grid2':''}">${body}</div>${note}${s.id==='comprador' ? compradorExtraHTML : ''}</div></section>`;
  });
  if(anexosAlFinal) html += buildAnnexPanel();
  form.innerHTML = html;

  // hitos: delegación (una sola vez; el form persiste entre rebuilds)
  if(!form._hitosWired){ form._hitosWired = true;
    form.addEventListener('input', e=>{ const el=e.target.closest('[data-hkey]'); if(!el) return;
      const h=HITOS[+el.dataset.hi]; if(h){ h[el.dataset.hkey]=el.value; renderDebounced(); } });
    form.addEventListener('click', e=>{
      const del=e.target.closest('[data-hdel]');
      if(del){ HITOS.splice(+del.dataset.hdel,1); refreshHitos(); render(); return; }
      if(e.target.closest('#hitoAdd')){ HITOS.push({pct:'',monto:'',timing:'',es:'',en:'',id:'',fecha:''}); refreshHitos(); render(); }
    });
  }
  // flecha de salto: clic en la etiqueta de un campo → ese punto del contrato
  // en la vista previa (form persiste entre rebuilds, delegación una sola vez)
  if(!form._saltoWired){ form._saltoWired = true;
    form.addEventListener('click', e=>{
      const lbl = e.target.closest('.field > label'); if(!lbl) return;
      const key = lbl.closest('.field').dataset.key; if(key) saltarACampo(key);
    });
  }
  // Campos de teléfono (prefijo+número, 12-ago): los dos inputs visibles no
  // llevan name= (collect() exige un único elemento por key) — se combinan
  // en el input oculto con name="${key}" y se dispara un 'input' sobre él,
  // que ya tiene enganchado el listener genérico de más abajo
  // (aplicarReglasCampos/renderDebounced/updateSaveButton). Delegado y una
  // sola vez, mismo patrón que hitos/salto.
  if(!form._telWired){ form._telWired = true;
    form.addEventListener('input', e=>{
      const sub = e.target.closest('.tel-prefijo, .tel-numero'); if(!sub) return;
      const caja = sub.closest('.field-tel'); if(!caja) return;
      const pre = caja.querySelector('.tel-prefijo').value.trim();
      const num = caja.querySelector('.tel-numero').value.trim();
      const oculto = caja.querySelector('input[type="hidden"][name]'); if(!oculto) return;
      oculto.value = num ? (pre ? pre+' '+num : num) : '';
      oculto.dispatchEvent(new Event('input', { bubbles:true }));
    });
  }

  wireDesignPanel();
  wireAnnexPanel();
  wireClausePanel();
  wireCompradorPanel();
  // pintarFichaComprador() ya llama a wireClienteBuscador() cuando toca pintar
  // el buscador; si hay ficha enlazada no hay buscador que cablear
  pintarFichaComprador();
  wireAccordions();
  form.querySelectorAll('[data-opt]').forEach(chk=>{
    chk.addEventListener('change', ()=>{ const sec=form.querySelector(`[data-sec="${chk.dataset.opt}"]`);
      sec.classList.toggle('off', !chk.checked); if(chk.checked) ensurePads(sec); render();
      // apagar una sección cambia activeKeys(), y con ella si la plantilla exige
      // ficha: sin esto el candado se quedaría con la respuesta de antes
      aplicarBloqueoComprador(); });
  });
  form.querySelectorAll('[data-clear]').forEach(b=>b.addEventListener('click',()=>{ clearPad(b.dataset.clear); render(); }));
  form.querySelectorAll('input[name],textarea[name],select[name]').forEach(el=> el.addEventListener('input', ()=>{ aplicarReglasCampos(); renderDebounced(); updateSaveButton(); }));
  form.querySelectorAll('select[name]').forEach(el=> el.addEventListener('change', ()=>{ aplicarReglasCampos(); render(); updateSaveButton(); }));
  aplicarReglasCampos();   // estado inicial de los campos condicionados
  ensurePads(form);   // secciones visibles al arrancar
  updateSaveButton(); // muestra/oculta "Guardar en base de datos" según la plantilla
  editBtnIdle();      // enseña "↺ Original" si esta plantilla trae ediciones a mano
  wirePickers();      // prefijo y nacionalidad: modal con buscador, no <datalist>
  render();
}
