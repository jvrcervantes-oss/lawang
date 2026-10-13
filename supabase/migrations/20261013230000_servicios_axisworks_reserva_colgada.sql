-- Servicios de AxisWorks: una reserva colgada SIN ENVIAR deja de pesar a los 10 minutos aunque nadie la caduque (revisor de código, 13-oct-2026).
-- Por qué: solo editor_ia_reserva caduca reservas (_editor_ia_caduca). Cerca del tope, una reserva abandonada antes de llamar al proveedor
-- (hasta 0,352 USD) dejaba la pantalla en «lleno»; en «lleno» la pantalla no pide nada, así que nadie la caducaba hasta el mes siguiente.
-- Ahora _editor_ia_peso la cuenta a 0 pasados 10 minutos (la misma regla que _editor_ia_caduca: lo que no salió no cuesta). Una reserva
-- ENVIADA sigue pesando al peor caso: pudo cobrar y no se sabe cuánto.
-- Solo construye: create or replace con la misma firma; pasa de immutable a stable porque ahora mira la hora (no la usa ningún índice).
-- Vuelta atrás: la versión de 20261013210000 (immutable, sin la primera rama del case).
create or replace function public._editor_ia_peso(u public.editor_ia_uso) returns numeric language sql stable set search_path = '' as $$
  select case
    when u.estado = 'reservado' and u.enviada_en is null and u.fecha < now() - interval '10 minutes' then 0
    when u.estado = 'reservado' then coalesce(u.coste_max_usd, 0)
    when u.enviada_en is null then 0
    when u.estado in ('hecho', 'fallo') then coalesce(u.coste_usd, u.coste_max_usd, 0)
    else coalesce(u.coste_max_usd, 0) end
$$;
revoke all on function public._editor_ia_peso(public.editor_ia_uso) from public, anon, authenticated, service_role;
