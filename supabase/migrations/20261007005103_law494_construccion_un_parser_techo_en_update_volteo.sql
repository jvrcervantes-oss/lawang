-- LAW-494 (7-oct-2026): tres agujeros de dinero en el trigger de Construcción de Lawang.
-- Solo sustituye UNA función (`descuento_comercial_construccion_valido`); no cambia ninguna fila, ni grants, ni el
-- trigger que la engancha (trg_descuento_comercial_construccion, BEFORE INSERT OR UPDATE ON contratos).
--
-- Versión anterior: 20260930023239_techos_alta_y_alcance_por_proyecto.sql (bloque 5). Arreglo de referencia escrito y
-- probado para el ERP maestro el 1-oct (erp/migraciones/20261001160700_techos_alcance_y_suplemento.sql, bloques 8.bis
-- y 9, copia sin aterrizar `1001-1202-porta-techos-maestro`, allí LAW-492). Norma de arreglo compartido (29-sep):
-- lo que se arregló en el maestro se arregla también aquí.
--
-- LOS TRES AGUJEROS (comprobados vivos en la base el 7-oct; camino real de navegador: `contrato_guarda`, con grant a
-- authenticated, escribe el `tipo` y el `precio_total` que manda la pantalla, y `precio_total` lo leen factura y
-- comisiones):
--   1. DOS PARSERS para el mismo importe. El contraste contra Modelos usaba `lw_importe(techo.precio)` y la base del
--      cuadre `techo.precio::numeric`. `lw_importe('120.000')` = 120000; `'120.000'::numeric` = 120. Un techo real de
--      120.000 enviado como cadena "120.000" con precio_total 120 pasaba el contraste Y el cuadre.
--   2. Techo obligatorio solo en INSERT. Un UPDATE que quitaba el techo dejaba la base NULL: sin cuadre y sin tope del
--      15 %, y el total quedaba libre.
--   3. No se miraba el cambio de `tipo`. Alta como otro tipo (el trigger sale en la 1ª línea y no mira nada) con
--      techo a 1, y luego un UPDATE que solo cambia `tipo` a 'construccion': ni contraste ni cuadre.
--
-- CÓMO SE CIERRAN:
--   1. La base del cuadre ya no parsea la cadena del navegador cuando el contraste ha corrido: es la SUMA de los
--      precios que acaban de resolverse contra Modelos (techo + cada extra). Cuando no ha corrido (contrato congelado:
--      no cambian techo, extras ni proyecto), la base son las cifras del propio contrato leídas con el MISMO parser
--      del contraste (`lw_importe`), nunca `::numeric`. `contrato_guarda` lee el total con `lw_parse_importe`, que da
--      lo mismo que `lw_importe` en '68.000', '68,000', '68.000,50', '68000' y '120.000' (medido el 7-oct).
--      Por qué no usar SIEMPRE la base viva de Modelos (lección del maestro, 1-oct): un techo o extra RETIRADO es
--      operación normal; en un contrato congelado el catálogo no devolvería fila, la base saldría NULL y se saltarían
--      el cuadre y el tope. Y «hay techo pero no se resuelve» levanta, nunca se sigue sin comprobar.
--      Y lo comprobado es lo que se GUARDA (revisor-codigo, 7-oct): tras el contraste, `datos.techo.precio` y cada
--      `datos.extras[i].precio` se reescriben con el número de Modelos. Si no, un "48.000" (o el número JSON 48.000,
--      que jsonb guarda con su escala) entraba, y al reabrir el contrato la pantalla lo lee con Number() = 48, calcula
--      un total de 48 y el contrato queda atascado; el bot de agentes y el anexo verían la misma cifra ambigua. En el
--      flujo normal no cambia nada: la pantalla ya manda ese número.
--      Sin función auxiliar nueva (el maestro creó `_construccion_base_modelos`): la suma se acumula en el bucle que
--      ya resolvía cada pieza. Una RPC menos expuesta.
--   2. En UPDATE con sesión, si el contrato YA traía techo, quitarlo se rechaza. Se mira el techo que traía la fila,
--      no el catálogo: los 78 contratos de Construcción antiguos que nunca tuvieron techo (todos creados ≤16-sep,
--      medido el 7-oct) se siguen pudiendo editar.
--   3. «Alta» = INSERT **o** cambio de `tipo`. Un contrato que se vuelve de Construcción pasa contraste, techo
--      obligatorio, tope y cuadre como si se diera de alta.
--   Cuando el contraste corre (alta, o cambian techo, extras o proyecto) también se revisan siempre el tope del 15 % y el
--   cuadre: los precios acaban de reescribirse y «no ha cambiado» ya no se puede deducir comparando datos.
--
-- PRUEBAS: supabase/pruebas/law494_construccion.sql — 15/15 ok el 7-oct con la función creada dentro de la transacción
-- deshecha (0 rastro, hashes de los contratos tocados iguales antes y después). Contra la versión anterior los casos de
-- ataque T5/T5b/T6/T6b/T7 PASABAN: los tres agujeros eran reales.
--
-- SE CONSERVA DE LAWANG (no se porta del maestro): la exención de super_admin al tope del 15 % (20260929154600,
-- decisión del owner del 29-sep) y la regla «un contrato de Construcción lleva SIEMPRE techo» en el alta, sin el
-- `exists(modelo_techos)` del maestro (Lawang tiene catálogo: 12 techos el 7-oct).
--
-- SIN SESIÓN (service_role, MCP, arnés): igual que antes, no se contrasta contra Modelos, pero sí se cuadra contra las
-- cifras del propio contrato con el parser único, también al voltear el tipo.
--
-- Datos medidos el 7-oct antes de aplicar (98 contratos de Construcción): 0 con separador en el precio del techo o de
-- un extra, 0 con precio de techo sin techo_id, 0 de otro tipo con techo. 1 no cuadra: CC00107 (66.000 frente a
-- 68.000), el precio tecleado del 22-sep que ya es LAW-267 (owner); este trigger lo deja congelado igual que antes.

create or replace function public.descuento_comercial_construccion_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento   numeric;
  v_base        numeric;
  v_esperado    numeric;
  v_cambia      boolean;
  v_dc_cambia   boolean;
  v_super       boolean;
  v_alta        boolean;
  v_contrastado boolean;
  v_tid         text;
  v_modelo      uuid;
  v_ok          numeric;
  v_nombre      text;
  v_x           jsonb;
  v_extras      jsonb;
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;

  -- «Alta» no es solo el INSERT: también el contrato que acaba de volverse de Construcción. Mientras era de otro tipo
  -- la línea de arriba hizo que este trigger no mirara nada, así que sus cifras no se contrastaron nunca (LAW-494 #3).
  v_alta := tg_op = 'INSERT' or new.tipo is distinct from old.tipo;

  -- Techo y extras se comprueban CONTRA MODELOS, con sesión, en el alta o si cambian techo, extras o proyecto. Un
  -- contrato guardado que no toca nada de eso conserva su precio congelado aunque el techo se retire o cambie de
  -- precio. Sin sesión no se contrasta (mismo criterio que el resto de candados de rol).
  v_contrastado := (select auth.uid()) is not null and (
       v_alta
       or new.datos->'techo' is distinct from old.datos->'techo'
       or new.datos->'extras' is distinct from old.datos->'extras'
       or new.proyecto_id is distinct from old.proyecto_id);

  if v_contrastado then
    v_tid := nullif(btrim(coalesce(new.datos->'techo'->>'techo_id', '')), '');
    if v_tid is null then
      -- LAW-494 #2: en UPDATE, quitar el techo que el contrato YA traía tampoco vale (sin techo la base queda NULL y
      -- se saltan tope y cuadre). Un contrato antiguo que nunca tuvo techo se sigue pudiendo editar.
      if v_alta
         or nullif(btrim(coalesce(old.datos->'techo'->>'techo_id', '')), '') is not null then
        raise exception 'Un contrato de Construcción lleva siempre techo: elige la tipología y el techo.' using errcode = '22023';
      end if;
      if jsonb_array_length(coalesce(new.datos->'extras', '[]'::jsonb)) > 0 then
        raise exception 'Los extras necesitan un techo elegido.' using errcode = '22023';
      end if;
    else
      -- uuid con su forma exacta: '-'×36 cumplía el patrón viejo y reventaba con 22P02 en el cast
      if v_tid !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        raise exception 'El techo elegido no es válido: vuelve a elegirlo.' using errcode = '22023';
      end if;
      select th.modelo_id into v_modelo from public.modelo_techos th where th.id = v_tid::uuid;
      if v_modelo is null then
        select m.id into v_modelo from public.modelos m where m.id = v_tid::uuid;   -- «Ulin» sintético: techo_id = modelo_id
      end if;
      if v_modelo is null then
        raise exception 'El techo elegido no existe en Modelos: vuelve a elegirlo.' using errcode = '22023';
      end if;
      select o.precio, o.nombre into v_ok, v_nombre
        from public._modelo_techos_opciones(v_modelo, new.proyecto_id) o where o.techo_id = v_tid::uuid;
      if v_ok is null then
        raise exception 'El techo «%» no se ofrece para este proyecto (retirado o fuera de su alcance): elige otro.',
          coalesce(new.datos->'techo'->>'nombre', '?') using errcode = '22023';
      end if;
      if abs(v_ok - coalesce(public.lw_importe(new.datos->'techo'->>'precio'), -1)) > 0.01 then
        raise exception 'El precio del techo «%» es % en Modelos, no %: vuelve a elegir el techo para refrescarlo.',
          v_nombre, v_ok, new.datos->'techo'->>'precio' using errcode = '22023';
      end if;
      -- LAW-494 #1: la base del cuadre es lo que Modelos acaba de dar, no la cadena del navegador, y eso mismo es lo
      -- que se guarda en el contrato (más abajo)
      v_base := v_ok;
      new.datos := jsonb_set(new.datos, '{techo,precio}', to_jsonb(v_ok));
      v_extras := '[]'::jsonb;
      for v_x in select * from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) loop
        v_ok := null;
        if coalesce(v_x->>'extra_id', '') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          select me.precio into v_ok
            from public.modelo_extras me join public.extras e on e.id = me.extra_id
           where me.modelo_id = v_modelo and me.extra_id = (v_x->>'extra_id')::uuid
             and me.disponible and e.activo and me.precio is not null;
        end if;
        if v_ok is null then
          raise exception 'El extra «%» no se ofrece para este modelo: quítalo.', coalesce(v_x->>'nombre', '?') using errcode = '22023';
        end if;
        if abs(v_ok - coalesce(public.lw_importe(v_x->>'precio'), -1)) > 0.01 then
          raise exception 'El precio del extra «%» es % en Modelos, no %: desmárcalo y vuelve a marcarlo.',
            coalesce(v_x->>'nombre', '?'), v_ok, v_x->>'precio' using errcode = '22023';
        end if;
        v_base := v_base + v_ok;
        v_extras := v_extras || jsonb_build_array(jsonb_set(v_x, '{precio}', to_jsonb(v_ok)));
      end loop;
      if jsonb_typeof(new.datos->'extras') = 'array' then
        new.datos := jsonb_set(new.datos, '{extras}', v_extras);
      end if;
    end if;
  elsif nullif(btrim(coalesce(new.datos->'techo'->>'techo_id', '')), '') is not null then
    -- Contrato congelado (o escritura sin sesión): las cifras del propio contrato, con el MISMO parser del contraste.
    select coalesce(public.lw_importe(new.datos->'techo'->>'precio'), 0)
           + coalesce(sum(coalesce(public.lw_importe(x->>'precio'), 0)), 0)
      into v_base
      from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) x;
  end if;

  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);
  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;
  if v_descuento > 0 then
    v_dc_cambia := v_alta or v_contrastado
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial')
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras';
    if v_dc_cambia and v_base > 0 and v_descuento > round(v_base * 0.15, 2) then
      -- exención del super_admin: decisión del owner del 29-sep (20260929154600), se conserva
      select exists (select 1 from public.usuarios u
                      where u.user_id = (select auth.uid()) and u.activo and u.rol = 'super_admin')
        into v_super;
      if not coalesce(v_super, false) then
        raise exception 'El descuento comercial (%) supera el 15%% del precio de techo+extras (%).',
          v_descuento, v_base;
      end if;
    end if;
    if coalesce(new.precio_total, 0) <= 0 then
      raise exception 'precio_total no puede quedar en cero o negativo al aplicar un descuento comercial.';
    end if;
  end if;
  if v_base is not null and v_base > 0 then
    v_cambia := v_alta or v_contrastado
      or new.precio_total is distinct from old.precio_total
      or new.datos->'techo' is distinct from old.datos->'techo'
      or new.datos->'extras' is distinct from old.datos->'extras'
      or (new.datos->'fields'->>'descuento_comercial') is distinct from (old.datos->'fields'->>'descuento_comercial');
    if v_cambia then
      v_esperado := v_base - v_descuento;
      if new.precio_total is null or abs(new.precio_total - v_esperado) > 0.01 then
        raise exception 'precio_total (%) no cuadra con techo + extras − descuento comercial (% = % − %): el precio de Construcción con techo elegido lo calcula la intranet, no se teclea.',
          new.precio_total, v_esperado, v_base, v_descuento using errcode = '22023';
      end if;
    end if;
  end if;
  return new;
end;
$$;
