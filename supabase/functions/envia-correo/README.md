# envia-correo (Lawang)

Edge que envía **todo el correo de la intranet** por el SMTP del buzón de Lawang. Sustituye a `contracts/api/send_email.php` con el mismo contrato (cuerpo, cabeceras, respuestas) — encargo «Ajustes del ERP», S5.0, 30-sep-2026. **En el momento de escribir esto está construida y probada, no desplegada, y ningún llamante apunta a ella**: hasta que se repunten (subtareas 4 y 5 de S5.0) el correo sigue saliendo por el PHP.

## Qué es de quién

| Fichero | Es |
|---|---|
| `index.ts`, `valida.ts` | **Canon**: idénticos byte a byte a los del maestro (`erp/funciones/envia-correo/` en el repo de la agencia). `.canon_hash` guarda su SHA-256 y `canon.test.js` lo comprueba aquí; el que compara los dos repos es `erp/test_canon_envia_correo.py`. Se cambian **en los dos a la vez** (`node canon.test.js --escribe` regenera el hash). El contrato completo (vías, secretos, códigos, desviaciones del PHP) está en el README del maestro |
| `smtp.ts`, `smtp_test.ts`, `smtp_fuente.test.js` | **Idénticos al maestro** (F3.1, portados el 8-oct-2026): las reglas del servidor SMTP (nombre DNS público, puerto 465, remitente efectivo, «responder a», buzones de aviso propios) y la prueba de dónde saca el servidor. `index.ts` importa `./smtp.ts`: **al desplegar, `smtp.ts` tiene que ir en la carpeta** (la edge `ajustes-correo` también lo importa, desde `../envia-correo/smtp.ts`, y `valida.ts`) |
| `arnes.mjs`, `nodemailer_falso.mjs` | Idénticos al maestro: el doble de Deno/fetch (ahora contesta `correo_smtp_lee`) y el de nodemailer (con `verify()` y fallos por servidor) |
| `plantillas_fabrica.ts` | **De Lawang, fuera del canon** (S5.2): el texto de fábrica de las 8 plantillas de correo (el que componían los llamantes) y `resuelve`, que lee de la base los datos de cada una a partir de los ids. Misma firma exportada que la del maestro (`test_canon_envia_correo.py`) |
| `plantilla.ts` | **De Lawang**: la piel portada de `contracts/api/lib/plantilla_correo.php` (paleta canopy, Neue Kabel por `@font-face`, grano, marca de agua «moanito», logo con halo, `color-scheme: light only`). Mismas firmas exportadas que la del maestro. `dorada.test.js` la compara con el PHP byte a byte |

## Plantillas de correo (S5, 2-oct-2026) — construido, sin desplegar, ningún llamante repuntado

La petición admite `plantilla` (una de **8 claves cerradas**: `enlace_firma_cadena`, `copia_firmada_comprador`, `copia_firmada_portal`, `copia_firmada_manual`, `aviso_anulacion`, `factura_primer_hito`, `proforma_total`, `factura_vencimiento`; otra → 400) + los ids que pide esa clave (`contrato_id`, `factura_id`, `firma_id`) + `vars`. **El camino libre `subject`/`message` sigue igual** (los otros 19 correos no son plantilla).
- **Los datos los lee la edge** de la base con la clave de servicio (importes, fechas, número de contrato o factura, enlace de firma, motivo de la anulación); del llamante solo se admite `vars.nombre` (con quién saludar) y solo en las claves que lo declaran (`PLANTILLAS` en `valida.ts`). Un id que no cuadra con el destinatario o con el estado del documento → 400.
- **El texto** es el de la fila ACTIVA y válida de `correo_plantillas` (migración `20261002100000`); si está inactiva, es inválida (URL, HTML, variable inexistente, falta una obligatoria…), la tabla no existe o la lectura falla, sale el de **fábrica**, nunca un 500. Un texto de plantilla es texto plano con `{{variable}}`; el catálogo de variables permitidas/obligatorias de cada clave está sellado en la propia fila.
- **Solo vía de servicio o sesión** (la de aviso interno no admite plantillas). `subject`, `message` y el botón que mande el llamante se ignoran. El botón lo pone el servidor: el enlace de firma para `enlace_firma_cadena`, el portal para el resto.
- **La respuesta** lleva `{plantilla, version}` (`v3` = fila editada, `f:ab12cd34` = fábrica) y el log también; el llamante —único escritor de `correos_enviados`— guarda eso en las columnas `plantilla`/`plantilla_version` y **nunca el texto renderizado**.
- Variantes **que no cubre**: la copia firmada por enlace firmado de 30 días (`copia_firmada_comprador`/`_manual` solo cubren «va adjunto»; el enlace sigue por el camino libre mientras exista).
- La edge que guarda el texto es `plantillas-guardar` (solo super admin, `verify_jwt=false` en `config.toml` por el preflight CORS; autoriza dentro).
- Pruebas: `plantillas_motor.test.js` (el index.ts real: cada clave plantilla == camino libre byte a byte, causas de caída a fábrica, doble escape, ids/vars/vías), `plantillas_fabrica.test.js` (fábrica ⇔ catálogo sellado ⇔ lo que `resuelve` produce; importe igual que `dinero.js`), **`plantillas_dorada.test.js` (solo Lawang): las 8 claves contra lo que componen hoy los llamantes y contra las funciones reales de `contracts/app.html`, y se rompe un texto a propósito para exigir ROJO**, y `../plantillas-guardar/plantillas_guardar.test.js`. SQL por perfil: `contracts/sql/prueba_correo_plantillas.sql`.

## De dónde saca el servidor SMTP (F3.1, porte del 8-oct-2026; escrito, **sin aplicar ni desplegar**)

1. **Vault** (`correo_smtp_lee()`, lo escribe el super admin desde Ajustes › Correo por la edge `ajustes-correo`): si HAY servidor, manda ese. La lectura tiene 2,5 s de plazo y se cachea 30 s por isolate; si falla, vale el último valor bueno hasta 10 min y después es un **500 en voz alta** (nunca cae en silencio a los secretos tras un cambio).
2. **Los secretos de entorno `SMTP_*`** (abajo) solo si la base contesta «no hay servidor» (NULL) o la función aún no existe (404 `PGRST202`/`42883`: base sin migrar). **No se borran nunca: son el plan B** (una restauración de la base no recupera Vault). Si cambia la contraseña del buzón, se rota en los dos sitios.
3. `email_from` / `email_reply_to` de Ajustes mandan sobre el remitente y el «responder a» (`remitenteEfectivo`, `replyToEfectivo`): `email_from` solo vale si es del dominio del buzón o de la instancia; `email_reply_to` vacío = no se pone. Hoy ninguna de las dos existe en `config_instancia` de Lawang (medido 8-oct-2026): hasta que alguien las guarde, el remitente es el de siempre.
4. **Rotar la contraseña del buzón** (mismo host y usuario desde Ajustes): hasta 10 min de envíos con la credencial vieja (caché). Cambiarla en el proveedor del buzón después de ese margen.

**Desplegar `envia-correo` antes de la migración es seguro**: sin la función `correo_smtp_lee` la edge sigue con los `SMTP_*` (lo fija `smtp_fuente.test.js`). Orden completo: migración → `envia-correo` → `ajustes-correo` → front.

## Secretos que lee (nombres; los valores nunca están en el repo)

`SMTP_HOST`, `SMTP_PORT` (465), `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_FROM_NAME` (plan B permanente, ver arriba), `ENVIO_CORREO_SECRET`, `ENVIO_AVISO_SECRET`, `RENDER_SECRET`, `PDF_SERVICE_URL`. `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` los pone el runtime. (`CORREO_CODIGO_PEPPER` es de la edge `ajustes-correo`, no de esta.)

⚠ **Dos huecos que se cierran con configuración, no con código** (criterio de aceptación de la subtarea 2 de S5.0):
- Si **`ENVIO_CORREO_SECRET` no existe**, la edge acepta como entrada el `RENDER_SECRET` compartido con las demás instancias (el log lo anota como `servicio-render`). En Lawang tiene que existir.
- Si **`ENVIO_AVISO_SECRET` no existe**, la puerta anónima de aviso interno sigue abierta (a los buzones `email_avisos_*`, con freno). En Lawang tiene que existir.

## Lo que lee de `config_instancia`

`dominio_web` y `url_intranet` (sin ellos responde 500 y no envía nada), `marca`, `logo_correo_url` (esta piel no lo usa), `asunto_por_defecto` (para Lawang: `Contrato — Lawang Tropical Properties`, lo que ponía el PHP), `email_avisos_soporte|sistema|reservas`, `email_from` y `email_reply_to` (F3.1). En la base viva (medido 8-oct-2026) están sembradas `dominio_web`, `asunto_por_defecto`, `email_avisos_soporte` y `email_avisos_sistema`; no existen `email_from`, `email_reply_to`, `email_avisos_reservas` ni `email_avisos_crm` (la edge los trata como vacíos).

## Vías (en este orden)

1. **servicio**: `X-Render-Secret` = `ENVIO_CORREO_SECRET`. Lo usan las edges y el panel de la agencia.
2. **sesión**: `X-Suite-Token` / `Authorization: Bearer` de alguien del equipo (fila activa en `usuarios`). El navegador (vista previa y envío de Comunicación).
3. **aviso**: `X-Aviso-Secret` = `ENVIO_AVISO_SECRET`, solo texto y solo a los buzones de aviso. Lo usan las funciones de la base por `pg_net`.

Cabecera opcional `X-Llamante` (40 caracteres, saneada): se anota en la línea de log para atribuir cada envío.

## `verify_jwt = false`

Declarado en `supabase/config.toml` (`[functions.envia-correo]`). Dos de sus vías no llevan JWT (pg_net y las edges con secreto); la autorización se hace dentro. El despliegue tiene que conservarlo.

## Cómo se prueba (sin Deno, sin red, sin enviar nada)

```
node canon.test.js         # index.ts / valida.ts contra .canon_hash
node index.test.js         # el index.ts REAL con dobles de Deno, nodemailer y fetch (arnes.mjs)
node corre_deno.test.js    # valida_test.ts, smtp_test.ts y plantilla_test.ts con node (con Deno: deno test)
node smtp_fuente.test.js   # F3.1: de dónde sale el servidor SMTP (Vault, entorno, caché, errores) y con qué remitente
node plantilla.test.js     # los recursos del correo existen en este repo; `contacto` llega al pie
node dorada.test.js        # plantilla.ts frente a plantilla_correo.php (necesita php; sin él dice NO COMPROBADO)
node plantillas_motor.test.js     # S5: el motor de plantillas con el index.ts real
node plantillas_fabrica.test.js   # S5: fábrica ⇔ catálogo sellado de la migración ⇔ `resuelve`; importe igual que dinero.js
node plantillas_dorada.test.js    # S5: las 8 plantillas == lo que componen hoy los llamantes (y la prueba se rompe a sí misma)
```

Al desplegar por MCP o CLI, **solo** `index.ts`, `valida.ts`, `plantilla.ts` y `plantillas_fabrica.ts` (el resto es de pruebas). Si tocas la piel, tócala también en `plantilla_correo.php` mientras `lead.php` y `booking-notify.php` la usen.
