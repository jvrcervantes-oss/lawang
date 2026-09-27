/* Buscadores del CRM que el navegador no puede rellenar solo — 27-sep-2026.
   ============================================================================
   INCIDENTE. Una sales manager abrió Pipeline y vio el tablero vacío con 132
   leads suyos en la base. El buscador #q llevaba escrito su propio email: lo
   había puesto el gestor de contraseñas de Chrome. La página tenía un campo
   `type="password"` (el token de GoHighLevel de Trazabilidad, oculto para ella)
   y, sin <form>, Chrome junta todos los campos sueltos en un formulario de login
   imaginario y elige como «usuario» el único campo de texto visible: el
   buscador, cuyo placeholder además decía «email». Rellenarlo disparaba el
   `input`, `visibles()` filtraba los nombres por ese email y no quedaba ninguno.
   `autocomplete="off"` no lo evita: Chrome lo ignora cuando cree que es login.

   Los atributos del HTML quitan la causa (token con `new-password`, buscadores
   marcados como no-credencial). Esto es la segunda barrera, por si el navegador
   vuelve a hacerlo por otra vía: un valor que el usuario no ha tecleado NO se
   toma como búsqueda.

   `busquedaAceptable` es pura y va probada en buscador.test.js; `lwBlindarBuscador`
   la conecta a un <input>. */

/* ¿Se puede tomar este valor como texto de búsqueda?
   · vacío → siempre (borrar nunca hace daño);
   · el email de la sesión → nunca: la búsqueda es por nombre, y ese valor solo
     llega ahí por autocompletado (es exactamente el caso del incidente);
   · sin tecleo previo (keydown/paste/drop/composición) y con un `input` que no es
     InputEvent → no: teclear, pegar, IME y dictado generan InputEvent; el
     relleno automático de Blink dispara un Event genérico. */
function busquedaAceptable({ valor, tocado, esInputEvent, emailSesion }){
  const v = String(valor == null ? '' : valor).trim().toLowerCase();
  if(!v) return true;
  const yo = String(emailSesion || '').trim().toLowerCase();
  if(yo && v === yo) return false;
  if(!tocado && !esInputEvent) return false;
  return true;
}

/* Conecta un buscador. `email()` devuelve el email de la sesión (puede ser '' si
   aún no ha llegado); `alCambiar(texto)` recibe SOLO valores aceptados — si el
   valor se rechaza, el campo se vacía y recibe ''. Devuelve `barrer()`, para
   repasar el campo cuando ya se conoce la sesión o al volver con «atrás». */
function lwBlindarBuscador(input, { email, alCambiar }){
  if(!input) return { barrer(){} };
  let tocado = false;
  ['keydown', 'paste', 'drop', 'cut', 'compositionstart'].forEach(t =>
    input.addEventListener(t, () => { tocado = true; }));
  const rechazar = () => { input.value = ''; alCambiar(''); };
  input.addEventListener('input', ev => {
    const ok = busquedaAceptable({ valor: input.value, tocado,
      esInputEvent: typeof InputEvent !== 'undefined' && ev instanceof InputEvent, emailSesion: email() });
    if(ok) alCambiar(input.value); else rechazar();
  });
  /* Relleno sin evento `input`: Chrome marca el campo con :-webkit-autofill, y
     leads.css le pone una animación vacía solo para enterarse aquí. */
  input.addEventListener('animationstart', ev => {
    if(ev.animationName === 'lw-autorrelleno' && !tocado) rechazar();
  });
  return {
    barrer(){
      if(input.value && !busquedaAceptable({ valor: input.value, tocado, esInputEvent: false, emailSesion: email() })) rechazar();
    },
  };
}

if(typeof module !== 'undefined') module.exports = { busquedaAceptable };
