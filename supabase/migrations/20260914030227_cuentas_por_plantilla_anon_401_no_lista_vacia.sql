-- Un GET anónimo a las dos tablas nuevas devolvía **200 con `[]`** en vez de 401.
-- No había fuga —la RLS hacía su trabajo, el array venía vacío— pero `[]` es la
-- respuesta ambigua que este proyecto ya decidió no aceptar: es exactamente igual
-- a la de una tabla vacía, así que ni el gate (`tools/check_seguridad.py`, que lo
-- marca como «RLS o tabla vacia -> confirmar con pg_policies») ni una persona
-- pueden distinguir «protegida» de «no me ha dado tiempo a llenarla».
--
-- `cuentas_bancarias` da 401 desde el 6-ago-2026 precisamente por esto, y el 401
-- no lo da la policy: lo da la ausencia de GRANT a nivel de tabla. Se igualan las
-- dos nuevas al mismo estándar que su tabla hermana.
-- `authenticated` no se toca: la suite las sigue leyendo igual.
revoke all on table public.plantillas_pago   from anon;
revoke all on table public.plantilla_cuentas from anon;;
