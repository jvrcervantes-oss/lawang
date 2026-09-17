-- Decision del owner (17-sep), con los numeros reales delante: para el umbral de inicio de obra,
-- una parcela BLOQUEADA cuenta como vendida -- un Bloqueo de Parcela es un contrato de compraventa
-- firmado, no una intencion. Una RESERVADA no cuenta: la senal de una Carta de Reserva todavia
-- puede caerse.
--
-- OJO, divergencia deliberada y no un bug: el KPI "vendidas" de la intranet v4
-- (assets/datos.js:1636) sigue contando solo vendida+cobrada, y debe seguir asi. Son dos
-- preguntas distintas: aquel responde "cuantas ventas hemos consumado", este responde "hay
-- compromiso contractual suficiente para levantar la obra". Si algun dia se unifican, que sea
-- a proposito y en los dos sitios a la vez.
--
-- Con este criterio (verificado el 17-sep): Soka Village W2 95,7%, Bonian Village 34,5% -- ambos
-- por encima del 33% por defecto; Sumba Hills 1,8%, muy por debajo.
create or replace function public.proyecto_pct_vendido(p_proyecto_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(*) = 0 then 0
              else round(100.0 * count(*) filter (
                     where u.estado in ('vendida','cobrada','bloqueada')
                   ) / count(*), 2)
         end
    from public.unidades u
   where u.proyecto_id = p_proyecto_id;
$$;

revoke all on function public.proyecto_pct_vendido(uuid) from public, anon;
grant execute on function public.proyecto_pct_vendido(uuid) to authenticated;

comment on function public.proyecto_pct_vendido(uuid) is
  'Porcentaje de unidades con compromiso contractual firme (vendida, cobrada o bloqueada) sobre el total del proyecto. Gobierna el umbral de inicio de obra (proyectos.pct_minimo_inicio). NO es el mismo numero que el KPI "vendidas" de la intranet, que cuenta solo ventas consumadas -- ver el comentario de la migracion.';
