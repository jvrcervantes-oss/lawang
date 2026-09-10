-- Dos correcciones que salen de la revision previa del CRM de leads (9-sep-2026).

-- 1. "FIRMO" ES `bloqueado`, NO `fecha_firma` -------------------------------------
-- La vista que sugiere mover un lead a Reserva/Contrato cruzaba por `fecha_firma`, que
-- se rellena al CREAR el contrato: 137 de los 178 la llevan por el alta de historico
-- que el cliente esta haciendo estos dias, y solo 33 estan firmados de verdad. Hoy los
-- 4 leads que cruzan estan ademas bloqueados, asi que el resultado no cambia -- pero en
-- cuanto uno de esos 137 cruce con un lead, el tablero diria que firmo alguien que no
-- ha firmado. El criterio de la casa esta escrito en contexto/suite_lawang.md (26-ago).
create or replace view public.lead_sugerencia
with (security_invoker = on) as
  select l.id as lead_id,
         case when bool_or(e.etapa = 'contrato') then 'contrato'
              when bool_or(e.etapa = 'reserva')  then 'reserva' end as etapa,
         min(c.numero) as contrato_numero
    from public.leads l
    join public.contratos c on coalesce(c.bloqueado, false) = true
    join lateral unnest(public.contrato_identificadores(c.datos)) ident(ident) on true
    join public.contrato_tipo_etapa e on e.tipo = c.tipo and e.etapa <> 'ninguna'
   where nullif(btrim(l.email), '') is not null
     and lower(btrim(ident.ident)) = lower(btrim(l.email))
   group by l.id;

-- 2. `puede()` YA NO ADIVINA CUANDO FALTA LA FICHA ---------------------------------
-- La rama final devolvia el claim `app_metadata.agente` del token cuando el usuario no
-- tenia ficha en `usuarios`. Como la edge de altas pone ese claim a todos, borrar la
-- ficha de alguien convertia su sesion en un pase para CUALQUIER herramienta, incluida
-- esta, que sirve datos de contacto de 101 personas. guard.js cierra esa puerta en el
-- navegador desde el 8-sep, pero guard.js no esta en el camino de PostgREST: con la
-- clave publicable y un token vivo se lee igual.
-- Medido antes de tocarlo: 22 cuentas llevan el claim y las 22 tienen ficha; las 21 del
-- portal no lo llevan. Cero cuentas dependen hoy de esa rama.
-- `es_agente()` conserva la suya: aqui solo se cierra la puerta de las herramientas.
create or replace function public.puede(herramienta text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
    when public.es_super_admin() then true
    else exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo
                    and herramienta = any(u.herramientas))
  end
$function$;;
