-- erp-ok: el maestro (axisworks-demo, bbm) trae bot_pendientes y bot_temas_resumen desde la línea base del 24-sep; su cierre va en la migración del ERP 20261016140000_bot_sin_llamador (16-oct). bot_faq_aprobar, bot_faq_retirar y bot_respuesta_copiada no salieron en la sonda de la demo.
-- Cuatro funciones del bot YA NO LAS EJECUTA service_role: nadie las llama con ese rol — 16-oct-2026 (Deploy + Seguridad, sonda viva de
-- bot_*, alcance A de BOT-S1; fila «sonda viva de proacl para bot_*» de contexto/seguridad_2026.md §7 de la agencia).
--
-- MEDIDO el 16-oct en la base de Lawang, en solo lectura (erp/sql.py lawang, con permiso del owner), con la consulta del bloque `bot`: las
-- cuatro salen ejecutables por service_role, que ninguna migración les dio (las de 20260927150000 y 20260927171000 conceden solo a
-- authenticated): viene de los permisos por defecto del esquema al crearlas.
--
-- POR QUÉ NO TIENEN LLAMADOR CON service_role (búsqueda del 16-oct en Lawang, el ERP, AxisWorks y todas las ramas de bot-whatsapp):
--   · bot_faq_aprobar y bot_faq_retirar: solo la edge bot-agentes, con el JWT del usuario (createClient(URL_SB, ANON, Authorization: Bearer
--     jwt), index.ts ~434), es decir authenticated; el cliente `admin` de esa edge (clave de servicio) no las llama.
--   · bot_respuesta_copiada y bot_temas_resumen: solo intranet/v4/asistente-correos (sb.rpc con la sesión del usuario: authenticated).
--   · contracts/bot/arnes_faq.sql las prueba con `set local role authenticated`, no con service_role.
-- La propia prueba del bot (supabase/pruebas/bot_s3.sql) ya decía «service_role sin EXECUTE en las funciones del bot (solo bot_lawang)», y estas
-- cuatro y bot_pendientes estaban en su lista de excepciones; con esto salen de ella (las funciones trigger se quedan).
-- «Reducir la exposición»: sin llamador con nombre, se revoca. authenticated NO se toca: es su llamador. Cierra acceso, no abre nada ni borra datos.
-- Vuelta atrás: `grant execute on function <firma> to service_role` de cada una.
revoke execute on function public.bot_faq_aprobar(uuid, text, uuid, text, text, text, uuid) from service_role;
revoke execute on function public.bot_faq_retirar(uuid) from service_role;
revoke execute on function public.bot_respuesta_copiada(uuid, text) from service_role;
revoke execute on function public.bot_temas_resumen(integer) from service_role;

do $comprueba$
declare f text;
begin
  foreach f in array array['public.bot_faq_aprobar(uuid, text, uuid, text, text, text, uuid)', 'public.bot_faq_retirar(uuid)',
                           'public.bot_respuesta_copiada(uuid, text)', 'public.bot_temas_resumen(integer)'] loop
    if has_function_privilege('service_role', f::regprocedure, 'execute') then
      raise exception '% sigue ejecutable por service_role (¿lo da PUBLIC o un rol del que es miembro?)', f;
    end if;
    if not has_function_privilege('authenticated', f::regprocedure, 'execute') then
      raise exception '% ya no la ejecuta authenticated: la pantalla o la edge que la llama se quedaría sin ella', f;
    end if;
  end loop;
end
$comprueba$;
