/* Reasignar el autor de un documento — 30-jul-2026.
   Compartido por /contracts (contratos) y /facturas (facturas, proformas y
   recibís): las dos tablas guardan el autor en la misma columna `creado_por`.

   POR QUÉ EXISTE: `creado_por` no es un adorno, es la identidad con la que la
   RLS decide quién puede editar su propio documento (`es_suyo()` compara con
   `auth.email()`). Si un agente crea el documento de otro, o alguien deja el
   equipo, el documento queda atribuido a quien no le toca y editable por quien
   no debe. Hasta hoy solo se podía arreglar en el SQL Editor.

   QUIÉN: solo `super_admin`. La RLS deja UPDATE a cualquier admin, pero
   reatribuir un documento es un acto de administración de personas, no de
   documentos, así que el botón se le muestra a un rol y no a dos.

   RASTRO: cada cambio escribe una fila en `correcciones_datos` ANTES de tocar
   la tabla (esa es la convención de la tabla: el rastro sobrevive aunque el
   update se caiga a medias). Si el update falla se escribe una segunda fila que
   anula la primera — un rastro que miente es peor que no tenerlo.

   LÍMITE HEREDADO DE LA RLS, no de este código: la policy de UPDATE exige
   `bloqueado = false` (contratos) y `anulada = false` (facturas). Un contrato
   ya firmado o una factura anulada NO se pueden reatribuir sin ampliar la
   policy — ver `contracts/sql/reasignar_autor_bloqueados.sql`, que está escrito
   y SIN aplicar porque toca la inmutabilidad de lo firmado y eso lo decide el
   dueño. Aquí se dice por qué no se puede, en vez de dejar un botón que falla. */
(function () {
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }[c]));

  let EQUIPO = null;   // [{email, nombre, activo}] — se pide una vez por sesión

  async function equipo(sb) {
    if (EQUIPO) return EQUIPO;
    const { data } = await sb.from('usuarios').select('email, nombre, activo').order('email');
    EQUIPO = data || [];
    return EQUIPO;
  }

  /* Último movimiento de este campo, para que el panel diga quién reasignó y
     cuándo. Sin esto la reasignación es invisible en cuanto se cierra. */
  async function ultimoCambio(sb, tabla, filaId) {
    const { data } = await sb.from('correcciones_datos')
      .select('valor_anterior, valor_nuevo, motivo, corregido_en, corregido_por')
      .eq('tabla', tabla).eq('fila_id', filaId).eq('campo', 'creado_por')
      .order('corregido_en', { ascending: false }).limit(1).maybeSingle();
    return data || null;
  }

  async function reasignar(sb, { tabla, filaId, actual, nuevo, motivo }) {
    if (!nuevo) return { error: 'Falta el nuevo autor.' };
    if (nuevo === actual) return { error: 'Ese ya es el autor.' };
    if (!motivo || motivo.trim().length < 3) return { error: 'Escribe el motivo: es lo que explica el cambio dentro de un año.' };

    const traza = { tabla, fila_id: filaId, campo: 'creado_por',
                    valor_anterior: actual || null, valor_nuevo: nuevo, motivo: motivo.trim() };
    const { error: eTraza } = await sb.from('correcciones_datos').insert(traza);
    if (eTraza) return { error: 'No se pudo dejar rastro del cambio, así que no se cambia nada: ' + eTraza.message };

    const { data, error } = await sb.from(tabla).update({ creado_por: nuevo }).eq('id', filaId).select('id').maybeSingle();
    if (error || !data) {
      await sb.from('correcciones_datos').insert({ ...traza, valor_anterior: nuevo, valor_nuevo: actual || null,
        motivo: 'ANULA la corrección anterior: el update no se aplicó (' + ((error && error.message) || 'sin filas afectadas, probablemente la RLS') + ')' });
      return { error: 'La base de datos rechazó el cambio: ' + ((error && error.message) || 'la RLS no dejó actualizar esta fila') };
    }
    return { ok: true };
  }

  /* Pinta el control dentro del `slot` que le da el anfitrión.
     `editable` = false cuando la fila está bloqueada/anulada: se explica, no se
     ofrece un botón que la RLS va a rechazar. */
  async function montar(slot, { sb, ficha, tabla, filaId, actual, editable, motivoNoEditable, onCambio }) {
    if (!slot || !sb) return;
    if (!ficha || ficha.rol !== 'super_admin') return;   // el resto no ve nada

    slot.classList.add('lw-autoria');
    slot.innerHTML = '<button type="button" class="lw-autoria-abrir">Reasignar autor</button>';
    const abrir = slot.querySelector('button');

    abrir.onclick = async (ev) => {
      ev.stopPropagation();                       // las filas de las dos listas abren el documento al hacer clic
      if (slot.querySelector('.lw-autoria-caja')) { cerrar(); return; }
      abrir.disabled = true;
      const [lista, ultimo] = await Promise.all([equipo(sb), ultimoCambio(sb, tabla, filaId)]);
      abrir.disabled = false;

      const opciones = lista.filter(u => u.email !== actual)
        .map(u => `<option value="${esc(u.email)}">${esc(u.nombre || u.email)}${u.activo ? '' : ' (desactivado)'}</option>`).join('');

      const caja = document.createElement('div');
      caja.className = 'lw-autoria-caja';
      caja.innerHTML = `
        <p class="lw-autoria-actual">Autor actual: <b>${esc(actual || 'sin autor')}</b></p>
        ${ultimo ? `<p class="lw-autoria-hist">Ya se reasignó el ${esc(String(ultimo.corregido_en).slice(0,10))}
            por ${esc(ultimo.corregido_por || '—')}: ${esc(ultimo.valor_anterior || '—')} → ${esc(ultimo.valor_nuevo || '—')}</p>` : ''}
        ${editable ? `
          <label>Nuevo autor
            <select class="lw-autoria-quien">${opciones || '<option value="">No hay nadie más en el equipo</option>'}</select>
          </label>
          <label>Motivo
            <input class="lw-autoria-motivo" type="text" maxlength="180" placeholder="Ej. lo creó Ana con mi cuenta por error">
          </label>
          <div class="lw-autoria-pie">
            <button type="button" class="lw-autoria-ok">Reasignar</button>
            <button type="button" class="lw-autoria-no">Cancelar</button>
          </div>
          <p class="lw-autoria-aviso" hidden></p>`
        : `<p class="lw-autoria-hist">${esc(motivoNoEditable || 'Esta fila no admite cambios.')}</p>`}`;
      slot.appendChild(caja);
      caja.onclick = e => e.stopPropagation();

      const $ = s => caja.querySelector(s);
      if (!editable) return;
      $('.lw-autoria-quien').focus();
      $('.lw-autoria-no').onclick = cerrar;
      $('.lw-autoria-ok').onclick = async () => {
        const aviso = $('.lw-autoria-aviso');
        const boton = $('.lw-autoria-ok');
        boton.disabled = true; boton.textContent = 'Reasignando…';
        const nuevo = $('.lw-autoria-quien').value;
        const r = await reasignar(sb, { tabla, filaId, actual, nuevo, motivo: $('.lw-autoria-motivo').value });
        boton.disabled = false; boton.textContent = 'Reasignar';
        if (r.error) { aviso.hidden = false; aviso.textContent = r.error; return; }
        cerrar();
        if (typeof onCambio === 'function') onCambio(nuevo);
      };
    };

    function cerrar() {
      const c = slot.querySelector('.lw-autoria-caja');
      if (c) c.remove();
    }
  }

  /* El estilo viaja con el módulo: son los mismos controles en dos herramientas
     con hojas de estilo distintas, y duplicarlo en las dos es cómo se separan.
     Hereda tipografía y color del anfitrión, no impone paleta. */
  const css = `
  .lw-autoria{ position:relative; display:inline-block; }
  .lw-autoria-abrir{ font:inherit; font-size:11.5px; letter-spacing:.04em; color:inherit; opacity:.75;
    background:none; border:1px solid currentColor; border-radius:999px; padding:3px 9px; cursor:pointer; }
  .lw-autoria-abrir:hover{ opacity:1; }
  .lw-autoria-abrir:disabled{ opacity:.4; cursor:default; }
  .lw-autoria-caja{ position:absolute; right:0; top:calc(100% + 6px); z-index:80; width:290px; text-align:left;
    background:#fff; color:#22282A; border:1px solid #E2DACA; border-radius:12px; padding:13px 14px;
    box-shadow:0 12px 30px -14px rgba(46,52,55,.4); font-size:12.5px; }
  .lw-autoria-caja label{ display:block; margin:9px 0 0; font-size:11px; letter-spacing:.06em;
    text-transform:uppercase; color:#4A5052; }
  .lw-autoria-caja select, .lw-autoria-caja input{ width:100%; font:inherit; font-size:12.5px; margin-top:4px;
    padding:6px 8px; border:1px solid #E2DACA; border-radius:8px; background:#fff; color:#22282A; }
  .lw-autoria-actual{ margin:0; }
  .lw-autoria-hist{ margin:6px 0 0; color:#4A5052; line-height:1.45; }
  .lw-autoria-pie{ display:flex; gap:8px; margin-top:11px; }
  .lw-autoria-pie button{ font:inherit; font-size:12px; border-radius:999px; padding:6px 13px; cursor:pointer;
    border:1px solid #485B37; }
  .lw-autoria-ok{ background:#485B37; color:#fff; }
  .lw-autoria-no{ background:none; color:#4A5052; border-color:#E2DACA; }
  .lw-autoria-aviso{ margin:9px 0 0; color:#8A2E22; line-height:1.45; }`;
  const hoja = document.createElement('style');
  hoja.textContent = css;
  document.head.appendChild(hoja);

  window.LW_AUTORIA = { montar, reasignar, equipo, ultimoCambio,
    puede: ficha => !!ficha && ficha.rol === 'super_admin' };
})();
