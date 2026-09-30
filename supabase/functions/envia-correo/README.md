# envia-correo (Lawang)

Edge que envía **todo el correo de la intranet** por el SMTP del buzón de Lawang. Sustituye a `contracts/api/send_email.php` con el mismo contrato (cuerpo, cabeceras, respuestas) — encargo «Ajustes del ERP», S5.0, 30-sep-2026. **En el momento de escribir esto está construida y probada, no desplegada, y ningún llamante apunta a ella**: hasta que se repunten (subtareas 4 y 5 de S5.0) el correo sigue saliendo por el PHP.

## Qué es de quién

| Fichero | Es |
|---|---|
| `index.ts`, `valida.ts` | **Canon**: idénticos byte a byte a los del maestro (`erp/funciones/envia-correo/` en el repo de la agencia). `.canon_hash` guarda su SHA-256 y `canon.test.js` lo comprueba aquí; el que compara los dos repos es `erp/test_canon_envia_correo.py`. Se cambian **en los dos a la vez** (`node canon.test.js --escribe` regenera el hash). El contrato completo (vías, secretos, códigos, desviaciones del PHP) está en el README del maestro |
| `plantilla.ts` | **De Lawang**: la piel portada de `contracts/api/lib/plantilla_correo.php` (paleta canopy, Neue Kabel por `@font-face`, grano, marca de agua «moanito», logo con halo, `color-scheme: light only`). Mismas firmas exportadas que la del maestro. `dorada.test.js` la compara con el PHP byte a byte |

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
```

Al desplegar por MCP o CLI, **solo** `index.ts`, `valida.ts` y `plantilla.ts` (el resto es de pruebas). Si tocas la piel, tócala también en `plantilla_correo.php` mientras `lead.php` y `booking-notify.php` la usen.
