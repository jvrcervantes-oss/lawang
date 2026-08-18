-- ════════════════════════════════════════════════════════════════════════════
-- UN CONTRATO, VARIAS PARCELAS — 18-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del owner (no del cliente): un comprador puede querer MÁS DE UNA
-- parcela en el mismo Bloqueo o la misma Carta de Reserva. El dato sigue siendo
-- `datos->fields->>parcela_codigo`, ahora admitiendo una LISTA separada por
-- comas («A4, A5, C7»): así las plantillas la imprimen tal cual, los listados
-- la enseñan tal cual, y un contrato viejo con un solo código es el caso
-- particular de una lista de uno — cero migración.
--
-- La relación de la base YA era N:1 (unidades.contrato_id apunta al contrato):
-- lo que asumía «una» era el TRIGGER. Esta es su reescritura, con las reglas de
-- siempre aplicadas POR PARCELA — y dos arreglos de minas que la multi-parcela
-- habría pisado en `avanza_unidad_por_cobro` (abajo, con su porqué).
--
-- Reglas conservadas del original, una a una (LAW-51: al tocar este trigger se
-- relee TODO consumidor):
--   · parcela ocupada por OTRO comprador → excepción nombrando el contrato;
--   · traspaso Carta→Bloqueo del MISMO comprador (pasaporte o email, los mismos
--     identificadores que crean la ficha) → la parcela pasa y la Carta se
--     cuelga del Bloqueo — ahora por parcela: un Bloqueo puede recoger A4 de
--     una Carta y A5 de otra, y cada Carta se re-cuelga;
--   · la Carta que PERDIÓ su parcela sigue editable: si al guardarla su código
--     está en manos del Bloqueo del mismo comprador, ese código SE SALTA en vez
--     de reventar (el early-exit del original, llevado al bucle);
--   · la escalera de estados de la unidad no cambia ni una regla.
-- Y una mejora de paso: al editar la lista solo se LIBERAN las parcelas que
-- salen — el original soltaba todas y reasignaba, y ese suelta-y-recoge pasaba
-- por 'disponible' un instante sin necesidad.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.sincroniza_unidad_contrato()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  -- la lista: partida por comas, recortada, sin vacíos ni repetidos, en orden
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
    -- solo se sueltan las que SALEN de la lista (o todas, si cambió el proyecto):
    -- soltar y volver a coger la misma pasaba por 'disponible' sin motivo.
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then return new; end if;

  -- los identificadores del comprador de ESTE contrato, una sola vez
  ids_nuevo := public.contrato_identificadores(new.datos);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

    if ocupada_id is not null then
      -- la Carta que perdió ESTA parcela a manos del Bloqueo de su comprador
      -- sigue editable: el código se salta, el resto de la lista sigue.
      if new.tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa')
         and ocupada_tipo = 'reserva_parcela'
         and ids_nuevo && ids_ocupa then
        continue;
      end if;

      traspaso_ok := new.tipo = 'reserva_parcela'
                 and ocupada_tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa');

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

    -- la escalera de estados, intacta del original
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

-- ════════════════════════════════════════════════════════════════════════════
-- Las dos minas de avanza_unidad_por_cobro, cazadas al auditar la multi-parcela
-- ════════════════════════════════════════════════════════════════════════════
-- 1. La subconsulta de moneda `(select u.moneda from unidades where contrato_id=…)`
--    devuelve VARIAS filas en cuanto un contrato tenga dos unidades → «more than
--    one row returned by a subquery» y el recibí ENTERO falla al guardarse. No
--    era teórico con este cambio: era el primer recibí de la primera venta doble.
-- 2. `v_cobrado >= u.precio` comparaba el cobrado TOTAL del contrato contra el
--    precio de CADA unidad: con dos parcelas de 68.000 y 70.000 cobrados, las
--    DOS salían 'cobrada' habiendo pagado una. Ahora compara contra la SUMA de
--    los precios de las unidades del contrato: 'cobrada' solo con todo pagado.
create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raiz_id uuid;
  v_cobrado numeric;
  v_mezcla  boolean;
  v_mon     text;
  v_nmon    int;
  v_precio_unidades numeric;
begin
  if p_contrato_id is null then return; end if;

  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  -- la moneda de las unidades del contrato: si entre ellas ya hay mezcla,
  -- se deja para una persona (mismo criterio que la mezcla de recibís)
  select min(u.moneda), count(distinct u.moneda)
    into v_mon, v_nmon
    from public.unidades u where u.contrato_id = v_raiz_id;
  if coalesce(v_nmon, 0) > 1 then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from v_mon
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from v_mon
  ) into v_mezcla;
  if v_mezcla then return; end if;

  v_cobrado := coalesce(public.contrato_cobrado(v_raiz_id), 0);
  select v_cobrado + coalesce(sum(public.contrato_cobrado(hijo.id)), 0)
    into v_cobrado
    from public.contratos hijo
   where hijo.contrato_padre_id = v_raiz_id;

  select sum(u.precio) into v_precio_unidades
    from public.unidades u where u.contrato_id = v_raiz_id;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when coalesce(v_precio_unidades, 0) > 0 and v_cobrado >= v_precio_unidades then 'cobrada'
           when v_cobrado > 0 then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end;
$$;
revoke execute on function public.avanza_unidad_por_cobro(uuid) from public, anon, authenticated;

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
--   select proname, prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and proname in ('sincroniza_unidad_contrato','avanza_unidad_por_cobro');
--   select prosrc from pg_proc … — el cuerpo debe llevar `foreach cod in array cods`.
-- Y la de comportamiento: el bloque DO con rollback que cubre alta multi,
-- edición que quita una, ocupada por otro, traspaso doble, carta editable tras
-- perder su parcela y contrato viejo de un solo código.
