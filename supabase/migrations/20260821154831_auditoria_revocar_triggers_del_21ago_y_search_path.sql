-- Auditoría del 21-ago-2026, primer hallazgo y es mío de hace una hora.
--
-- Las DOS funciones de trigger que escribí hoy nacieron ejecutables por `anon`.
-- Puse `revoke execute ... from public`, que no basta: Supabase concede EXECUTE
-- a `anon` y `authenticated` POR SEPARADO, así que quitárselo a PUBLIC no se lo
-- quita a ninguno de los dos. Es exactamente lo que ya está escrito en la
-- migración `execute_solo_authenticated_funciones_permisos` del 29-jul, y en
-- `auditoria_revocar_triggers_de_law71` del 19-ago, donde pasó lo mismo con las
-- dos de LAW-71.
--
-- Tercera vez con la misma piedra. El riesgo práctico sigue siendo bajo —
-- PostgREST no expone una función que devuelve `trigger`, no puede construir el
-- argumento— pero la norma existe para no depender de ese detalle, y que se me
-- haya escapado teniéndola escrita es el argumento para que la vigile una
-- máquina y no yo: por eso se añade también al chequeo de salud.
revoke all on function public.factura_hereda_cliente()             from public, anon, authenticated;
revoke all on function public.factura_anulada_solo_cambia_autor()  from public, anon, authenticated;

-- Y `diferencias_con_ficha` (mía, del 19-ago) se quedó SIN `set search_path`.
-- No es SECURITY DEFINER, así que no es escalada de privilegios; pero un
-- search_path mutable hace que a qué tabla mira dependa de quién la llame, y la
-- norma del estudio es que TODA función lo fije. Se recrea igual, solo con el
-- `set`, para no cambiar lo que hace.
alter function public.diferencias_con_ficha(jsonb, jsonb) set search_path = '';;
