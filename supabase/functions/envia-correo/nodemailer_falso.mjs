// Doble de nodemailer para el arnés de pruebas (arnes.mjs). NO abre ningún socket: apunta lo que se le
// pediría enviar en `globalThis.__arnesCorreo.correos` y, si hay un fallo armado, lo lanza.
export default {
  createTransport(opciones) {
    const a = globalThis.__arnesCorreo;
    a.transportes.push({ host: opciones.host, port: opciones.port, secure: opciones.secure });
    return {
      async sendMail(mensaje) {
        if (a.falloSmtp) throw a.falloSmtp;
        a.correos.push(mensaje);
        return { messageId: 'falso' };
      },
      close() {},
    };
  },
};
