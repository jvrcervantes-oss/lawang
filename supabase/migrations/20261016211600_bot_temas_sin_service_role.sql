-- erp-ok: el maestro (axisworks-demo, bbm) trae la misma ACL desde la línea base del 24-sep; su revoke va en una migración del ERP aparte (número de agencia-cd, 16-oct)
-- bot_temas_resumen YA NO LA EJECUTA service_role: nadie la llama con ese rol — 16-oct-2026 (Deploy + Seguridad, sonda viva de bot_*,
-- alcance A de BOT-S1; fila «sonda viva de proacl para bot_*» de contexto/seguridad_2026.md §7 de la agencia).
--
-- POR QUÉ. 20260922210000 la concedió «to authenticated, service_role». El único llamador es la pantalla del asistente de correos
-- (intranet/v4/asistente-correos: sb.rpc('bot_temas_resumen') con la sesión del usuario, authenticated). Buscado el 16-oct: ninguna
-- edge, ni el bot (todas las ramas de bot-whatsapp), ni el ERP ni AxisWorks la llaman con service_role. «Reducir la exposición»: sin
-- llamador con nombre, se revoca. bot_pendientes ya perdió service_role en el L5 (20261016063536).
-- authenticated NO se toca: es su llamador. Cierra acceso, no abre nada ni borra datos.
revoke execute on function public.bot_temas_resumen(integer) from service_role;

do $comprueba$
begin
  if has_function_privilege('service_role', 'public.bot_temas_resumen(integer)'::regprocedure, 'execute') then
    raise exception 'bot_temas_resumen(integer) sigue ejecutable por service_role (¿lo da PUBLIC o un rol del que es miembro?)';
  end if;
  if not has_function_privilege('authenticated', 'public.bot_temas_resumen(integer)'::regprocedure, 'execute') then
    raise exception 'bot_temas_resumen(integer) ya no la ejecuta authenticated: el asistente de correos se quedaría sin temas';
  end if;
end
$comprueba$;
