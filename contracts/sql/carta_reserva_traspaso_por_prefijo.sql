-- La familia de Cartas de Reserva se queda FUERA de una lista a mano — 10-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- SÍNTOMA (caso real, HOLMACA 1970 S.L., Mejan Village S7, CP00002): reservada
-- una parcela con la Carta de Reserva Condicionada (serie CP, tipo
-- `carta_reserva_pma`, alta 7-sep), el Bloqueo de Parcela (`reserva_parcela`)
-- que debería sucederla muere con
--   La parcela B2 de Mejan Village S7 ya esta asignada al contrato CP00002
-- exactamente el mismo síntoma que `parcela_traspaso_carta_a_bloqueo.sql`
-- (14-ago) vino a arreglar — pero para un tipo de Carta que no existía ese día.
--
-- CAUSA: `traspaso_ok` (y su gemelo, la Carta que sigue editable tras perder su
-- parcela) miran `ocupada_tipo in ('carta_reserva', 'carta_reserva_ampliada',
-- 'carta_reserva_hak_sewa')` — una lista escrita a mano el 14-ago con las TRES
-- Cartas que existían entonces. Desde entonces se dieron de alta DOS más
-- (`carta_reserva_pma` 7-sep, `carta_reserva_investor_deck` 10-sep) y ninguna
-- entró en esta lista: es el patrón LAW-48 ("al alta de un tipo le faltan
-- sitios"), y esta lista concreta ya lleva DOS altas seguidas sin acordarse de
-- ella — la 2ª reincidencia que la escalera de aprendizaje manda promocionar
-- (`tools/aprendizaje.py log`), no volver a parchear con dos strings más.
--
-- ARREGLO — se generaliza al criterio que ya existe, en vez de ampliar la
-- lista una tercera vez: TODOS los tipos de Carta de Reserva llevan el prefijo
-- `carta_reserva_` por diseño deliberado (ver el comentario de cada alta en
-- `contracts/app.html` — "tipo PROPIO... mismo motivo que las otras Cartas"),
-- así que `like 'carta_reserva%'` cubre las cinco de hoy y cualquiera que se
-- dé de alta mañana sin tocar este trigger otra vez. Nada más cambia: mismo
-- guardarrail de mismo-comprador (LAW-51), mismo enlace Carta->Bloqueo
-- (LAW-50), misma escalera de estados, mismo bucle multi-parcela
-- (`parcelas_multiples.sql`, 18-ago — este fichero es su continuación, no un
-- reemplazo del resto de reglas que trae).
--
-- ✅ Comprobado antes de escribir: `prosrc` de producción == la última versión
-- del repo (`parcelas_multiples.sql`), sin deriva. Caso real que lo prueba:
-- CP00002/HOLMACA reserva B2,B3,B4,B6,B7 de Mejan Village S7, las 5 en
-- `reservada` — el Bloqueo de cualquiera de ellas es justo el caso que hoy
-- revienta y que este cambio deja pasar.

create or replace function public.sincroniza_unidad_contrato()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  cods_ant text[];
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod          text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  ids_nuevo    text[];
  ids_ocupa    text[];
  traspaso_ok  boolean;
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

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then return new; end if;

  ids_nuevo := public.contrato_identificadores(new.datos);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

    if ocupada_id is not null then
      -- la Carta (cualquiera de las cinco) que perdió ESTA parcela a manos del
      -- Bloqueo de su comprador sigue editable: se salta, el resto sigue.
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
$$;
revoke execute on function public.sincroniza_unidad_contrato() from public, anon, authenticated;

-- ── Comprobación ─────────────────────────────────────────────────────────────
--   select prosrc from pg_proc where proname = 'sincroniza_unidad_contrato';
--   -- debe contener "like 'carta_reserva%'" y ya NO la lista de tres strings.
--   select u.codigo, u.estado, c.numero, c.tipo
--     from public.unidades u left join public.contratos c on c.id = u.contrato_id
--    where u.proyecto = 'Mejan Village S7' and u.codigo in ('B2','B3','B4','B6','B7');
--   -- antes de guardar el Bloqueo: las 5 con CP00002. Después de guardarlo la
--   -- que se bloquea pasa a RP0000x y CP00002 se cuelga de ella (contrato_padre_id).
