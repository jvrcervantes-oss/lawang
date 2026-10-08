// Doble de nodemailer para el arnés de pruebas (arnes.mjs). NO abre ningún socket: apunta lo que se le
// pediría enviar en `globalThis.__arnesCorreo.correos` y, si hay un fallo armado, lo lanza.
// F3.1 (7-oct-2026): añade `verify()` (lo usa ajustes-correo para probar usuario y contraseña) y fallos por servidor
// (`falloVerify`, `falloEnHost[host]`); cada transporte y cada correo anotan el servidor y el usuario con que se abrió.
// Idéntico en Lawang y en el maestro (test_canon_envia_correo.py).
export default {
  createTransport(opciones) {
    const a = globalThis.__arnesCorreo;
    a.transportes.push({ host: opciones.host, port: opciones.port, secure: opciones.secure, user: opciones.auth && opciones.auth.user });
    return {
      async verify() {
        a.verificados = (a.verificados || []);
        a.verificados.push({ host: opciones.host, user: opciones.auth && opciones.auth.user });
        if (a.falloVerify) throw a.falloVerify;
        if (a.falloEnHost && a.falloEnHost[opciones.host]) throw a.falloEnHost[opciones.host];
        return true;
      },
      async sendMail(mensaje) {
        if (a.falloSmtp) throw a.falloSmtp;
        if (a.falloEnHost && a.falloEnHost[opciones.host]) throw a.falloEnHost[opciones.host];
        a.correos.push({ ...mensaje, _host: opciones.host, _user: opciones.auth && opciones.auth.user });
        return { messageId: 'falso' };
      },
      close() {},
    };
  },
};
