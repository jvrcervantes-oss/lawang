-- Acción `verificar` del bot (encargo «bot sin Redis», apartado c, 10-oct-2026; aplicada a la base con la version 20261009235701; el repo la nombra 20261010190000 como las demas (se compara por NOMBRE)): el bot pregunta a la edge si la PERSONA que le pide enviar o pausar
-- (su JWT, verificado contra Auth por la edge) tiene la casilla `bot_escribir`. Hoy el bot se fía de la clave de administración y de un `byUser` que pone
-- el proxy: quien robe esa clave escribe a los clientes como cualquiera. Con esto el bot comprueba él mismo, contra la base, quién es y qué puede.
--
-- DATO CON DUEÑO: la regla de permisos del bot es de `public.usuarios` (rol, activo, herramientas, ambito, empresas). Vive en DOS sitios hasta que el proxy
-- (lawang-bot-proxy, `reglaBot`) llame también a esta función: se mantienen iguales con un test de paridad (supabase/functions/bot-api/bot_humano_verificar.test.js
-- + supabase/pruebas/bot_humano_verificar.sql, los mismos casos). Regla: usuario `activo`, `ambito` distinto de 'empresa' y sin `empresas` marcadas (el bot
-- es UNO y mezcla las dos empresas), y (rol = 'super_admin' o la casilla en `herramientas`).
--
-- Dos funciones: `_bot_humano_regla` (pura: sin leer tablas, para poder probar cada caso sin tocar datos) y `bot_humano_verificar` (busca la ficha y la aplica).
-- Solo EXECUTE para bot_lawang en la segunda; nada para PUBLIC/anon/authenticated/service_role (gate BOT-S1). Devuelve el email solo si puede; nunca `herramientas`.
-- Reversión: drop function public.bot_humano_verificar(text, text); drop function public._bot_humano_regla(text, boolean, text, text[], text[], text);

create or replace function public._bot_humano_regla(p_rol text, p_activo boolean, p_ambito text, p_empresas text[], p_herramientas text[], p_permiso text)
returns boolean language sql immutable set search_path = '' as $f$
  select coalesce(p_activo, false)
     and p_ambito is distinct from 'empresa'
     and coalesce(cardinality(p_empresas), 0) = 0
     and (p_rol is not distinct from 'super_admin' or coalesce(p_permiso = any (p_herramientas), false));
$f$;

create or replace function public.bot_humano_verificar(p_usuario text, p_permiso text)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_u public.usuarios%rowtype;
  v_ok boolean;
begin
  if p_permiso is distinct from 'bot_escribir' then return jsonb_build_object('error', 'permiso_invalido'); end if;
  -- p_usuario es el id de Auth (uuid) en texto; lo que no lo sea simplemente no casa con ninguna ficha.
  if p_usuario is null or length(p_usuario) > 120 then return jsonb_build_object('permitido', false, 'email', null); end if;
  select * into v_u from public.usuarios where user_id::text = p_usuario;
  if not found then return jsonb_build_object('permitido', false, 'email', null); end if;
  v_ok := public._bot_humano_regla(v_u.rol, v_u.activo, v_u.ambito, v_u.empresas, v_u.herramientas, p_permiso);
  return jsonb_build_object('permitido', v_ok, 'email', case when v_ok then v_u.email end);
end $f$;

revoke all on function public._bot_humano_regla(text, boolean, text, text[], text[], text) from public, anon, authenticated, service_role;
revoke all on function public.bot_humano_verificar(text, text)                             from public, anon, authenticated, service_role;
grant execute on function public.bot_humano_verificar(text, text) to bot_lawang;
