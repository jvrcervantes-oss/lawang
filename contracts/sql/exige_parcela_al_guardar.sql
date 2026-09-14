-- ════════════════════════════════════════════════════════════════════════════
-- UN CONTRATO QUE RESERVA PARCELA NO SE GUARDA SIN PROYECTO Y SIN PARCELA
-- 14-sep-2026 · encargo del owner · revisión previa: Datos + Desarrollo
-- ════════════════════════════════════════════════════════════════════════════
-- POR QUÉ EXISTE. RP00164 (54.204 €) se guardó sin proyecto y con el código de
-- la subparcela ("C3") escrito en `parcela_master` —el código del terreno
-- entero— en vez de en `parcela_codigo`. Como la plantilla imprime cada campo
-- en una frase distinta, el PDF que firmaron las dos partes dice «parcela
-- máster C3» y deja EN BLANCO el número de la parcela que se cede. Y como
-- `sincroniza_unidad_contrato()` lee `parcela_codigo` para atar la unidad, la
-- parcela C3 se quedó `disponible` con el contrato firmado y 27.102 € cobrados:
-- vendible dos veces, sin que nada avisara.
--
-- El agujero por el que salió está escrito literalmente aquí abajo, en esta
-- misma función: un `return new` mudo. Este fichero lo convierte en un error.
--
-- POR QUÉ SE MODIFICA ESTA FUNCIÓN Y NO SE AÑADE UN TRIGGER HERMANO.
-- Un `trg_exige_parcela` aparte serían dos triggers razonando sobre los mismos
-- dos campos, con orden de disparo por nombre alfabético y con la lista de
-- tipos duplicada — la familia de fallo que este repo ya paga tres veces. El
-- sitio donde la falta de parcela YA se detecta es este `if`; lo único que le
-- faltaba era hablar.
--
-- LA LISTA DE TIPOS NO SE ESCRIBE A MANO. Sale de `contrato_tipo_etapa`
-- (`etapa = 'reserva'`), que es donde el estudio ya declara qué tipos reservan
-- una parcela: reserva_parcela, carta_reserva, carta_reserva_ampliada,
-- carta_reserva_hak_sewa y carta_reserva_pma. Un tipo nuevo de reserva hereda
-- el guardarraíl el día que se le pone su etapa, sin tocar este fichero.
-- `construccion` queda fuera sola y por el motivo correcto: su etapa es
-- 'contrato', y además se vincula por `unidad_id`, no por código de parcela.
--
-- LA SALIDA PARA EL LEGADO, QUE TAMBIÉN PROTEGE LAS ALTAS NUEVAS.
-- Hay 37 contratos ya guardados que no cumplirían la regla, 18 de ellos
-- firmados. Rechazar todo UPDATE los dejaría imposibles de anular y de
-- corregir — incluido RP00164, que es justo al que hay que ir. Peor: esta
-- misma función hace `update public.contratos set contrato_padre_id` sobre el
-- contrato VIEJO en el traspaso carta→bloqueo, así que guardar un contrato
-- nuevo y perfectamente válido abortaría por culpa de un legado ajeno, con un
-- mensaje hablando de otro contrato.
-- Por eso la regla solo muerde cuando el UPDATE TOCA esos campos: si el
-- proyecto y los códigos son idénticos a los de OLD, se deja pasar. Se puede
-- anular, cobrar y corregir lo demás; lo que no se puede es dejarlos mal
-- habiéndolos tocado.
--
-- FUERA DE ALCANCE A PROPÓSITO: que el código EXISTA en `unidades`. Cerraría
-- también los 23 códigos huérfanos que LAW-73 dejó vivos, pero bloquea guardar
-- en un proyecto cuyas unidades aún no están cargadas. Es una decisión del
-- owner, no un detalle de implementación — va anotada aparte.
--
-- IDEMPOTENTE: es un `create or replace` de la función. Correrlo dos veces
-- deja lo mismo. No toca datos, no toca la tabla, no borra nada.
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
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  -- ── EL GUARDARRAÍL (14-sep-2026) ──────────────────────────────────────────
  -- Antes esto era `if ... then return new; end if;` a secas: sin proyecto o
  -- sin códigos, la función se callaba y el contrato se guardaba suelto.
  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      -- El legado sigue siendo editable y anulable mientras no se toquen estos
      -- dos campos. Ver la cabecera: sin esto, el traspaso interno de esta
      -- misma función aborta altas nuevas y válidas.
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
          'Este contrato reserva una parcela y no dice cuál: falta %. Ojo, parece que el código se ha escrito en el campo equivocado — «%» está puesto en «Parcela máster», que es el terreno entero del proyecto (S7, W5…), no la parcela que se vende. El número de la parcela va en «Parcela», y el contrato lo imprime en «ceder los derechos sobre la parcela nº …»: si se deja vacío, el documento firmado no dice qué se vende.',
          falta, master using errcode = '23514';
      end if;

      raise exception
        'Este contrato reserva una parcela y no se puede guardar sin %. El contrato lo imprime literalmente («ceder los derechos sobre la parcela nº …»), así que sin ese dato el documento firmado no dice qué se vende, y la parcela sigue figurando libre para otro comprador.',
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

  return new;
end;
$function$;
