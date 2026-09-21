-- ════════════════════════════════════════════════════════════════════════════
-- LAW-73 REABIERTA: EL ÁMBITO ES POR CÓDIGO, NO POR CONTRATO — 21-sep-2026
-- Fix-forward sobre `enlace_por_id_y_law73_reabierta.sql` (mismo día, consulta
-- de deploy capa 1, hallazgo ALTA de Desarrollo).
-- ════════════════════════════════════════════════════════════════════════════
-- EL BUG. La migración anterior gateaba la excepción nueva con `toca_parcela`,
-- una bandera de TODO el contrato: true si el array `cods` entero cambiaba
-- respecto a OLD. Caso real encontrado por Desarrollo: RP00126 (Java Sunset
-- S2) tiene `parcela_codigo = "PLOT 6, S1 - H6"` — "PLOT 6" está en el
-- inventario, "S1 - H6" no (legado, chip sin ✕, no se puede tocar desde la
-- UI). El flujo normal y SOPORTADO de "añadir otra parcela"
-- (`pintarSelectorParcela`/`parcela_inventario.js`) cambia el array `cods` al
-- añadir una tercera parcela válida → `toca_parcela = true` para TODO el
-- contrato → el bucle volvía a evaluar "S1 - H6", que nadie estaba tocando, y
-- reventaba con la excepción de LAW-73. Un guardado legítimo bloqueado por un
-- código que ni siquiera aparecía en el formulario que se estaba editando.
--
-- LA CORRECCIÓN. El guardarraíl de LAW-73 se mueve de "¿tocó el contrato
-- parcela o proyecto?" a "¿es ESTE código concreto nuevo en el contrato, o
-- cambió el proyecto?" — por código, dentro del propio FOREACH, no por
-- contrato. Un código que YA estaba en `cods_ant` y sigue en `cods` tal cual
-- no se revalida aunque el contrato gane o pierda OTRAS parcelas en el mismo
-- guardado. Si cambia el proyecto, sí se revalidan todos — un código válido
-- en el proyecto viejo no tiene por qué existir en el nuevo.
--
-- `toca_parcela` (a nivel de contrato) se queda intacta para lo que ya hacía
-- bien: soltar unidades que dejaron de estar en `cods` (bloque de arriba) y
-- la salida temprana del legado "sin código" (rama vacía). Solo el guardarraíl
-- de LAW-73 pasa a mirar el código, no el contrato entero.
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
  toca_parcela    boolean;   -- INSERT, o UPDATE que cambia código y/o proyecto (a nivel de CONTRATO)
  cod_nuevo       boolean;   -- este código concreto es nuevo aquí, o cambió el proyecto (a nivel de CÓDIGO)
begin
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
    proy_ant := coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre);
    toca_parcela := (cods_ant is distinct from cods) or (proy_ant is distinct from proy);
    if toca_parcela then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  else
    toca_parcela := true;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      if tg_op = 'UPDATE' and not toca_parcela then
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
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

    -- LAW-73 REABIERTA (21-sep-2026, ámbito por CÓDIGO — fix-forward mismo
    -- día, hallazgo Desarrollo): este código concreto es nuevo en el contrato
    -- (INSERT, o UPDATE donde no estaba ya en `cods_ant`), o cambió el
    -- proyecto (entonces se revalida todo). Un código legado que ya estaba
    -- y sigue igual NO se revisa aunque el contrato gane/pierda OTRAS
    -- parcelas en el mismo guardado — así no bloquea el flujo normal de
    -- "añadir otra parcela" sobre un contrato con un código legado sin tocar.
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
  -- `parcela_codigo` ese día. Es lo que le faltaba a RP00116 — misma CASE que
  -- el bucle de arriba, así que es idempotente donde el texto sí casaba.
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
