-- ════════════════════════════════════════════════════════════════════════════
-- EL ESTADO SE REFRESCA POR ID, NO SOLO POR TEXTO · LAW-73 REABIERTA CON INVENTARIO
-- 21-sep-2026 · encargo del owner · revisión previa: Datos + Desarrollo (revisión
-- previa #29, folio en CEO/revisiones/estado.json) + advisor (corrigió el plan:
-- el enlace por ID que hacía falta YA EXISTE, es `unidades.contrato_id`)
-- ════════════════════════════════════════════════════════════════════════════
-- POR QUÉ EXISTE. RP00116 (Yolanda Bartolome Gonzalez, Bloqueo de Parcela) se
-- firmó el 27-ago-2026 (`bloqueado=true`, PDF firmado) pero `unidades.estado`
-- se quedó en `reservada` en vez de pasar a `bloqueada`. Causa: el bucle de
-- `sincroniza_unidad_contrato()` ata y mueve el estado de una unidad SOLO
-- cuando `unidades.codigo` casa EXACTO con el texto de
-- `datos.fields.parcela_codigo`. La unidad real es `W3.1. - D5` (con punto);
-- el contrato traía `W3.1 - D5` (sin él) — una corrección manual de este
-- mismo contrato en agosto (`rp00116_corrige_parcela_codigo.sql`, owner:
-- "está vinculado a A5, que está fuera de inventario") se hizo por SQL
-- directo, fuera de `contracts/app.html`, y tecleó el código sin pasarlo por
-- el desplegable — que es justo la vía que `parcela_inventario.js` protege
-- desde LAW-73 para que esto no pueda pasar tecleando a mano.
-- El UPDATE de la firma SÍ disparó el trigger (`trg_sincroniza_unidad` es
-- `AFTER INSERT OR UPDATE` sin `OF`, verificado con `pg_get_triggerdef`), pero
-- el `UPDATE ... WHERE u.codigo = cod` del bucle no encontró ninguna fila —
-- silencioso, cero aviso.
--
-- LA CORRECCIÓN NO ES UNA TABLA NUEVA. La primera versión de este plan
-- proponía una tabla puente `contrato_parcelas`. El enlace por ID que hacía
-- falta ya existe y ya es la fuente de verdad para todo lo demás del sistema
-- (`avanza_unidad_por_cobro`, `libera_reserva`, `unidades_estado`): es
-- `unidades.contrato_id`, y ya apuntaba bien a RP00116 — el texto era lo
-- único desincronizado. Lo único que faltaba era que, además de atar por
-- texto (necesario: así nace el enlace y así se detectan choques/traspasos),
-- la función refrescara el estado de TODO lo que YA está enlazado por ID,
-- pase lo que pase con el texto ese día. Eso es lo que añade el bloque nuevo
-- al final del bucle — ni tabla, ni RLS nueva, ni backfill.
--
-- LAW-73, REABIERTA (decisión del owner, 21-sep-2026, "la opción 2 es mucho
-- mejor que la 1" sobre la revisión previa #29). Hasta hoy un código que no
-- casaba con ninguna unidad se guardaba callado a propósito (`contracts/sql/
-- exige_parcela_al_guardar.sql`, "FUERA DE ALCANCE A PROPÓSITO") para no
-- bloquear un proyecto sin inventario cargado. Ahora, si el PROYECTO ya tiene
-- inventario, un código que no casa con NINGUNA unidad de ese proyecto para
-- el guardado — habría cazado el propio error de agosto en el momento de
-- teclearlo. Si el proyecto no tiene ninguna unidad cargada todavía, se
-- sigue dejando pasar: la regla original de LAW-73 sigue viva para ese caso,
-- textual.
-- Acotado igual que el resto de esta función (comentario de
-- `exige_parcela_al_guardar.sql`, "la regla solo muerde cuando el UPDATE TOCA
-- esos campos"): si el proyecto y los códigos son idénticos a los de OLD, se
-- deja pasar igual que hasta hoy — si no, el legado (37 contratos, 18
-- firmados) se vuelve imposible de tocar por un motivo ajeno al que se está
-- editando.
--
-- LO QUE ESTO NO CIERRA A PROPÓSITO: los 37 contratos legado que YA tienen el
-- texto desincronizado no disparan la excepción nueva mientras nadie toque
-- `parcela_codigo`/`proyecto_nombre` en ellos — y el catch-all por ID de
-- arriba solo arregla el ESTADO, no el texto impreso. Para verlos en un
-- listado (no solo cuando el bucle los cruza) queda la vista
-- `contratos_sin_parcela_vinculada` de más abajo — el "no callar" que pedía
-- Desarrollo en la revisión previa. Wiring visual en la pantalla de
-- Contratos/Operaciones: pendiente, tarea de Desarrollo aparte.
--
-- IDEMPOTENTE: `create or replace function` + `create or replace view`. No
-- toca datos, no backfillea nada, no dispara `trg_registra_edicion_privilegiada`
-- (no hay ningún UPDATE sobre `contratos` en este fichero).
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
  toca_parcela    boolean;   -- INSERT, o UPDATE que cambia código y/o proyecto
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  -- cods_ant/proy_ant se calculan una sola vez aquí (antes solo existían
  -- dentro de la rama "vacío") porque el guardarraíl de LAW-73 de más abajo
  -- también necesita saber si esto es un INSERT o un UPDATE que de verdad
  -- toca parcela/proyecto, no solo la rama de "sin código".
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

    -- LAW-73 REABIERTA (21-sep-2026): un código que no casa con NINGUNA
    -- unidad del proyecto ya no se calla si el proyecto tiene inventario
    -- cargado. Solo muerde cuando el guardado TOCA parcela/proyecto (mismo
    -- criterio que el resto de esta función) — un contrato legado se puede
    -- seguir anulando/cobrando/corrigiendo lo demás sin que esto le salte.
    if ocupada_id is null and toca_parcela then
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

-- ── "NO CALLAR" PARA EL LEGADO (Desarrollo, revisión previa #29) ────────────
-- Los 37 contratos que YA tienen el texto desincronizado (RP00116 incluido,
-- antes de este fichero) no disparan la excepción de arriba mientras nadie
-- toque parcela/proyecto en ellos. Esta vista los hace visibles en vez de que
-- dependan de que alguien vuelva a tropezar con uno.
create or replace view public.contratos_sin_parcela_vinculada as
select c.id, c.numero, c.tipo, c.bloqueado, c.comprador_nombre,
       coalesce(nullif(btrim(c.datos->'fields'->>'proyecto_nombre'), ''), c.proyecto_nombre) as proyecto,
       c.datos->'fields'->>'parcela_codigo' as parcela_codigo_texto
  from public.contratos c
  join public.contrato_tipo_etapa e on e.tipo = c.tipo and e.etapa = 'reserva'
 where c.liberado_en is null
   and not exists (select 1 from public.unidades u where u.contrato_id = c.id);

alter view public.contratos_sin_parcela_vinculada set (security_invoker = true);
grant select on public.contratos_sin_parcela_vinculada to authenticated;
