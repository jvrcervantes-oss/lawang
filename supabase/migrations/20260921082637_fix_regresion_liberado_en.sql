-- ════════════════════════════════════════════════════════════════════════════
-- FIX URGENTE: LAS DOS MIGRACIONES DE HOY BORRARON EL BLINDAJE DE liberado_en
-- 21-sep-2026 · encontrado por advisor antes de dar la tarea por cerrada
-- ════════════════════════════════════════════════════════════════════════════
-- QUÉ PASÓ. Las migraciones `enlace_por_id_y_law73_reabierta` (08:09) y
-- `law73_reabierta_ambito_por_codigo` (08:17) de HOY se escribieron a partir
-- de `contracts/sql/exige_parcela_al_guardar.sql` (14/17-sep) — la copia
-- legible que se supone es la fuente de la función. Esa copia estaba
-- DESACTUALIZADA: la migración `20260921060542_libera_reservas_vencidas`
-- (aplicada esta misma mañana, otra sesión, antes que las mías) ya había
-- modificado `sincroniza_unidad_contrato()` para añadir el blindaje de
-- `liberado_en` (`libera_reserva()`, el RPC que libera una reserva vencida o
-- desistida) y nadie refrescó la copia legible tras aplicarla. Mis dos
-- `create or replace function` de hoy sobrescribieron esa función SIN esas
-- dos piezas:
--   1. La guarda de entrada `if new.liberado_en is not null then return new;
--      end if;` — sin ella, el propio `update contratos set liberado_en =
--      now()` que hace `libera_reserva()` vuelve a pasar por TODO el cuerpo
--      de la función, incluido mi catch-all nuevo, que hace
--      `update unidades set contrato_id = new.id, estado = 'reservada' ...`
--      sobre la unidad que el mismo `libera_reserva()` acababa de poner
--      `disponible` un instante antes — **la reserva liberada se re-reserva
--      sola**, en la misma transacción, sin ningún error.
--   2. `and c.liberado_en is null` en el lookup de "ocupada" — sin ella, un
--      contrato ya liberado sigue contando como que "ocupa" su parcela vieja,
--      bloqueando una reserva nueva y legítima sobre una unidad ya libre.
-- Ninguna de las dos migraciones de hoy tocó estas líneas A PROPÓSITO — se
-- perdieron por trabajar sobre una copia vieja. Este fichero las restaura
-- TAL CUAL estaban en la migración de esta mañana (`libera_reservas_vencidas`,
-- fuente verificada con `grep` sobre ese fichero) y injerta SOLO las piezas
-- de hoy encima — nada más se reestructura.
--
-- TAMBIÉN SE DESHACE una unificación que nadie revisó: la primera migración
-- de hoy cambió la condición del bloque de desvinculación (arriba del todo)
-- de comparar el TEXTO crudo `(old.datos->'fields'->>'proyecto_nombre') is
-- distinct from (new.datos->'fields'->>'proyecto_nombre')` a comparar
-- `proy_ant is distinct from proy` (con `coalesce` a la columna
-- `proyecto_nombre`) — un cambio semántico real para contratos con ese campo
-- vacío en `datos.fields`, que no formaba parte de ningún hallazgo de la
-- consulta de deploy. Se restaura la comparación original; `proy_ant` se
-- sigue calculando (coalesced) pero SOLO se usa para el guardarraíl nuevo de
-- LAW-73, no para el desvinculado.
--
-- VERIFICACIÓN antes de aplicar (en transacción, con rollback, contra un
-- contrato real): `libera_reserva()` sobre una unidad reservada por una
-- Carta de Reserva no liberada deja la unidad en `disponible`/`contrato_id
-- null` — no vuelve a `reservada`.
--
-- IDEMPOTENTE: `create or replace function`. No toca datos.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.sincroniza_unidad_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  cods_ant text[];
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  proy_ant     text;
  cod          text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  ids_nuevo    text[];
  ids_ocupa    text[];
  traspaso_ok  boolean;
  exige        boolean;
  master       text;
  falta        text;
  existe          boolean;
  hay_inventario  boolean;
  cod_nuevo       boolean;   -- este código concreto es nuevo en el contrato, o cambió el proyecto (LAW-73)
begin
  if new.liberado_en is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cods_ant := (
      select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
        from unnest(string_to_array(coalesce(old.datos->'fields'->>'parcela_codigo',''), ',')) x);
    -- proy_ant (coalesced) se calcula aquí SOLO para el guardarraíl de LAW-73
    -- de más abajo (cod_nuevo). El desvinculado de debajo sigue comparando el
    -- texto crudo de `datos.fields`, como siempre — no se unifican.
    proy_ant := coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre);
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      proy_ant := case when tg_op = 'UPDATE'
                  then coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre)
                  end;
      if tg_op = 'UPDATE'
         and cods_ant is not distinct from cods
         and proy_ant is not distinct from proy then
        return new;
      end if;

      falta := case
                 when proy is null and coalesce(array_length(cods, 1), 0) = 0
                   then 'el proyecto y la parcela'
                 when proy is null then 'el proyecto'
                 else 'la parcela'
               end;

      master := nullif(btrim(coalesce(new.datos->'fields'->>'parcela_master','')), '');

      if master is not null and coalesce(array_length(cods, 1), 0) = 0 then
        raise exception
          'Rellena: %. El código «%» está en «Parcela máster» por error — va en el campo «Parcela».',
          falta, master using errcode = '23514';
      end if;

      raise exception
        'Rellena: %.',
        falta using errcode = '23514';
    end if;

    return new;
  end if;

  ids_nuevo := public.contrato_identificadores(new.datos);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id
       and c.liberado_en is null;

    -- LAW-73 REABIERTA (21-sep-2026, ámbito por CÓDIGO): este código concreto
    -- es nuevo en el contrato (INSERT, o UPDATE donde no estaba ya en
    -- `cods_ant`), o cambió el proyecto. Un código legado que ya estaba y
    -- sigue igual NO se revisa aunque el contrato gane/pierda OTRAS parcelas
    -- en el mismo guardado.
    cod_nuevo := (tg_op = 'INSERT')
              or (proy_ant is distinct from proy)
              or not (cod = any (coalesce(cods_ant, '{}')));

    if ocupada_id is null and cod_nuevo then
      select exists(select 1 from public.unidades u where u.proyecto = proy and u.codigo = cod)
        into existe;
      if not existe then
        select exists(select 1 from public.unidades u where u.proyecto = proy)
          into hay_inventario;
        if hay_inventario then
          raise exception
            'La parcela «%» no está en el inventario de «%». Revisa el código (puede faltar o sobrar un espacio, un punto o una tilde) — este proyecto ya tiene parcelas cargadas.',
            cod, proy using errcode = '23514';
        end if;
      end if;
    end if;

    if ocupada_id is not null then
      if new.tipo like 'carta_reserva%'
         and ocupada_tipo = 'reserva_parcela'
         and ids_nuevo && ids_ocupa then
        continue;
      end if;

      traspaso_ok := new.tipo = 'reserva_parcela'
                 and ocupada_tipo like 'carta_reserva%';

      if not traspaso_ok then
        raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
          using errcode = '23505';
      end if;

      if coalesce(array_length(ids_nuevo, 1), 0) = 0
         or coalesce(array_length(ids_ocupa, 1), 0) = 0 then
        raise exception 'El traspaso de la parcela % de % no se puede comprobar: falta el pasaporte o el email del comprador en % o en el contrato que estás guardando. Complétalo y vuelve a guardar.',
          cod, proy, ocupada using errcode = '23514';
      end if;
      if not (ids_nuevo && ids_ocupa) then
        raise exception 'El traspaso de la parcela % de % no cuadra: % está a nombre de otro comprador. La parcela solo pasa de una Carta de Reserva a su Bloqueo si coincide el pasaporte o el email.',
          cod, proy, ocupada using errcode = '23514';
      end if;
    end if;

    update public.unidades u
       set contrato_id = new.id,
           estado = case
             when u.estado in ('vendida','cobrada') then u.estado
             when u.estado = 'no_disponible' then u.estado
             when u.estado = 'bloqueada' and not exists (
                    select 1 from public.contratos c2
                     where c2.id = u.contrato_id
                       and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                  ) then u.estado
             when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
             when new.tipo = 'construccion' then u.estado
             else 'reservada'
           end
     where u.proyecto = proy and u.codigo = cod;

    if ocupada_id is not null and traspaso_ok then
      update public.contratos c
         set contrato_padre_id = new.id
       where c.id = ocupada_id and c.contrato_padre_id is null;
    end if;

    ocupada_id := null; ocupada := null; ocupada_tipo := null; ids_ocupa := null;
  end loop;

  -- CATCH-ALL POR ID: repasa TODO lo que ya está enlazado por
  -- `unidades.contrato_id = new.id`, pase lo que pase con el texto de
  -- `parcela_codigo` ese día. Nunca se llega aquí si `new.liberado_en` no es
  -- null (guarda de entrada, arriba del todo).
  update public.unidades u
     set estado = case
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           when new.tipo = 'construccion' then u.estado
           else 'reservada'
         end
   where u.contrato_id = new.id;

  return new;
end;
$function$;
