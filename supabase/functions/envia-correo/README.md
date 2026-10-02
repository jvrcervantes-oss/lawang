# envia-correo (Lawang)

Edge que envía **todo el correo de la intranet** por el SMTP del buzón de Lawang. Sustituye a `contracts/api/send_email.php` con el mismo contrato (cuerpo, cabeceras, respuestas) — encargo «Ajustes del ERP», S5.0, 30-sep-2026. **En el momento de escribir esto está construida y probada, no desplegada, y ningún llamante apunta a ella**: hasta que se repunten (subtareas 4 y 5 de S5.0) el correo sigue saliendo por el PHP.

## Qué es de quién

| Fichero | Es |
|---|---|
| `index.ts`, `valida.ts` | **Canon**: idénticos byte a byte a los del maestro (`erp/funciones/envia-correo/` en el repo de la agencia). `.canon_hash` guarda su SHA-256 y `canon.test.js` lo comprueba aquí; el que compara los dos repos es `erp/test_canon_envia_correo.py`. Se cambian **en los dos a la vez** (`node canon.test.js --escribe` regenera el hash). El contrato completo (vías, secretos, códigos, desviaciones del PHP) está en el README del maestro |
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

## Secretos que lee (nombres; los valores nunca están en el repo)

`SMTP_HOST`, `SMTP_PORT` (465), `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `SMTP_FROM_NAME`, `ENVIO_CORREO_SECRET`, `ENVIO_AVISO_SECRET`, `RENDER_SECRET`, `PDF_SERVICE_URL`. `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` los pone el runtime.

⚠ **Dos huecos que se cierran con configuración, no con código** (criterio de aceptación de la subtarea 2 de S5.0):
- Si **`ENVIO_CORREO_SECRET` no existe**, la edge acepta como entrada el `RENDER_SECRET` compartido con las demás instancias (el log lo anota como `servicio-render`). En Lawang tiene que existir.
- Si **`ENVIO_AVISO_SECRET` no existe**, la puerta anónima de aviso interno sigue abierta (a los buzones `email_avisos_*`, con freno). En Lawang tiene que existir.

## Lo que lee de `config_instancia`

`dominio_web` y `url_intranet` (sin ellos responde 500 y no envía nada), `marca`, `logo_correo_url` (esta piel no lo usa), `asunto_por_defecto` (para Lawang: `Contrato — Lawang Tropical Properties`, lo que ponía el PHP), `email_avisos_soporte|sistema|reservas`. Hoy la tabla está vacía: **hay que sembrarla antes de repuntar nada**.

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
node corre_deno.test.js    # valida_test.ts y plantilla_test.ts con node (con Deno: deno test)
node plantilla.test.js     # los recursos del correo existen en este repo; `contacto` llega al pie
node dorada.test.js        # plantilla.ts frente a plantilla_correo.php (necesita php; sin él dice NO COMPROBADO)
node plantillas_motor.test.js     # S5: el motor de plantillas con el index.ts real
node plantillas_fabrica.test.js   # S5: fábrica ⇔ catálogo sellado de la migración ⇔ `resuelve`; importe igual que dinero.js
node plantillas_dorada.test.js    # S5: las 8 plantillas == lo que componen hoy los llamantes (y la prueba se rompe a sí misma)
```

Al desplegar por MCP o CLI, **solo** `index.ts`, `valida.ts`, `plantilla.ts` y `plantillas_fabrica.ts` (el resto es de pruebas). Si tocas la piel, tócala también en `plantilla_correo.php` mientras `lead.php` y `booking-notify.php` la usen.
