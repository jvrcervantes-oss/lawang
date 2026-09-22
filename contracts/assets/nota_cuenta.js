/* nota_cuenta.js — la «Nota» que una cuenta de cobro imprime dentro del contrato.
 *
 * Nacido el 18-sep-2026 al portar el panel de cuentas a /intranet/v4/cuentas/:
 * las dos pantallas tienen que leer y escribir `cuentas_bancarias.extra` EXACTO
 * IGUAL, y en esta suite un mismo bloque escrito en dos sitios no es deuda de
 * higiene, es el bug (Regla 0 de `contexto/suite_lawang.md`). Si divergen, el
 * resultado no es un aviso: es un contrato que imprime la nota en el idioma
 * equivocado, o que la imprime en español dentro de un documento en inglés.
 *
 * `extra` es JSONB y puede ser DOS cosas, las dos válidas y las dos en la base:
 *   · un texto suelto            → se imprime igual en los tres idiomas
 *   · un objeto {es, en, id}     → cada idioma imprime el suyo
 * Que existan las dos formas no es un descuido: la fila «Nota» se imprime en los
 * tres idiomas del contrato, y donde se había guardado texto plano salía en
 * español aunque el documento estuviera en inglés. El objeto llegó después, y el
 * texto plano se conserva porque el 90 % de las notas son la misma frase en los
 * tres — obligar a tres huecos donde sobra uno es pedirle a quien administra
 * cuentas que copie y pegue tres veces.
 *
 * Ninguna de las dos funciones escribe JSON crudo en pantalla a propósito: quien
 * administra cuentas no tiene por qué saber cerrar un objeto, y un JSON mal
 * cerrado se guardaría como texto y se imprimiría con las llaves dentro.
 */
(function () {
  'use strict';

  window.lwNotaCuenta = {
    /* De lo que hay en la base a los tres huecos del formulario. */
    lee: function (extra) {
      if (extra && typeof extra === 'object') {
        return { es: extra.es || '', en: extra.en || '', id: extra.id || '' };
      }
      return { es: extra == null ? '' : String(extra), en: '', id: '' };
    },

    /* De los tres huecos a lo que se guarda. Las tres ramas importan:
       · nada escrito  → cadena vacía, y la fila «Nota» no se imprime;
       · solo ES       → texto plano, como estaba (no se inventa un objeto);
       · ES + alguno   → objeto, y el inglés que falte cae al español.
       El bahasa (`id`) NUNCA cae al español (LAW-247, decisión del owner
       22-sep-2026: opción b). El bahasa PREVALECE legalmente en estos
       documentos (Ley nº 24/2009) — heredar el texto ES sin que se note es
       imprimir una traducción falsa con apariencia de traducción real. Si
       nadie escribió el bahasa, se queda vacío a propósito: en pantalla y en
       el contrato se ve claramente vacío, nunca disfrazado de traducción. No
       bloquea el guardado — solo dice la verdad sobre lo que hay. */
    aJson: function (n) {
      var es = (n && n.es ? String(n.es) : '').trim();
      var en = (n && n.en ? String(n.en) : '').trim();
      var id = (n && n.id ? String(n.id) : '').trim();
      if (!es && !en && !id) return '';
      if (!en && !id) return es;
      return { es: es, en: en || es, id: id };
    }
  };
})();
