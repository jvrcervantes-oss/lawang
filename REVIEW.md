# REVIEW.md — Lawang (intranet, contratos, Supabase)
Lo lee el `revisor-codigo` (y cada `buscador-fallos`) **antes que el diff**: lo que ya ha fallado en ESTE repo y por qué es grave aquí.
No copia normas: cada línea dice qué pasó, cuándo y dónde está la regla (las del estudio viven en el repo de la agencia).
Grave = las 5 clases del revisor. Cuenta como código: quitar una línea pasa por el revisor. Tope 40 líneas. El servidor no lo sirve (`.htaccess`, `.md` → 404).

## El navegador escribe o decide (máxima «el backend jamás se cree el frontend»)
- **Guardar en dos escrituras desde el navegador** (datos): el modelo de contrato quedaba a medias; el autor escribió «no es una transacción» y lo subió. 16-sep, b0ed4ac90e. Regla: `contexto/patrones_tecnicos.md` → «Frontera frontend / backend»; gate `tools/escrituras_front.py`.
- **Estado de dinero marcado desde la pantalla** (dinero): una factura quedaba «enviada» porque lo decía el navegador. 11-ago, a99bf44871.
- **Total o importe que calcula la pantalla** (dinero): la base se creía el total y un agente podía facturar sobre el contrato de otro. 26-sep (`CLAUDE.md` → máximas).
- **Enganchar por rótulo, cabecera o texto** (deja de funcionar): un cambio «solo de texto» dejó tres días muerto un alta. 29-sep. Se engancha por `data-accion`, `data-lw` o el id (`contexto/suite_lawang.md`, `contexto/patrones_tecnicos.md` → «Enganche por identificador estable»).

## Permisos (RLS, GRANT, DEFINER, vistas)
- **Policy que da TRUE con un nulo** (seguridad): `es_suyo(null)` devolvía TRUE en la campana. 4-ago, e4ba169947.
- **Policy sin GRANT, y la pantalla solo mira `r.error`** (deja de funcionar): en cuentas bancarias, la base negaba y la pantalla, que solo miraba `r.error`, no lo contaba. 14-sep, f564054caa.
- **`INSERT … RETURNING` bajo una policy SELECT** (deja de funcionar): con `propietario` NULL la fila nueva no la deja leer la policy, y el RETURNING lo exige. 10-sep, b9e152c507; y 25-sep en storage con upsert (aprendizaje «rls-select-en-insert-returning»).
- **`select=*` sobre una tabla con columnas cerradas** (deja de funcionar): Sociedades devolvía 42501. 12-oct (`CEO/flujos/deploy.md` de la agencia → «Profundidad»).
- **`CREATE OR REPLACE VIEW` pierde `security_invoker`** (seguridad): la vista vuelve a DEFINER en silencio y la RLS deja de aplicar; en `unidades_estado` pasó dos veces. Desde el 10-ago (`contexto/seguridad_2026.md`).
- **Lógica nueva de permisos sin prueba ejecutable** (seguridad): permisos de IA (quitado, revivido, borrado lógico) sin ninguna prueba. 16-oct, CAMBIOS 53b0a0cf3.

## Dinero y contratos
- **Recálculo que deja el calendario de cobros a precio entero** (dinero): `carta_cobrado_recalcula_interno` dejaba el calendario a precio entero. 17-oct, CAMBIOS 1047ea537, 2.ª vuelta (el mismo cambio llegó a la 3.ª, d932b741e).
- **Bloqueo enviado a firma con la parcela aún en una Carta** (dinero + datos): el trigger solo frenaba con la fila «pendiente»; tras rechazar un traspaso pasaba. 16-oct, CAMBIOS 58e122afc.
- **Pedir `contratos` entero en producción** (deja de funcionar): un `json_agg` tumbó Postgres el 25-sep y el respaldo diario por REST lo dejó 5 h caído el 1-oct. Medir con EXPLAIN sobre pocas filas (aprendizaje «respaldo-contratos-pesados»).

## Pruebas y migraciones (`supabase/migrations/`, `supabase/pruebas/`, `reversion_*`)
- **PL/pgSQL `raise exception` con una variable como formato** (seguridad): error de sintaxis al compilar; la prueba de revoke nunca llegaba a su fin. 17-oct, CAMBIOS d7d70213e.
- **Migración que destruye o abre acceso** (datos, seguridad): el DDL que construye se aplica solo; el que borra, desactiva RLS o toca `auth` para (`CLAUDE.md` → Política de autonomía; `departamentos/backend/prompt.md` → Supabase).
- **Ampliar la intranet no es empezar de cero** (deja de funcionar): una herramienta nueva usa el menú, el pie y los assets comunes. `contexto/suite_lawang.md` → Regla 0.
