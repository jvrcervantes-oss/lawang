-- Tope del descuento comercial de Construcción, en el SERVIDOR — 21-sep-2026,
-- revisión previa #33 (Legal + Administración + Seguridad).
-- ════════════════════════════════════════════════════════════════════════════
-- QUÉ RESUELVE. `contracts/app.html` deja aplicar un `descuento_comercial` al
-- precio de techo+extras de un Contrato de Construcción, con dos candados de
-- PANTALLA: solo super_admin/admin lo tocan (ROLES_HITOS_FIJOS/
-- puedeHitosFijos, reutilizado), y no se guarda si supera el 15% de
-- techo+extras o si falta el motivo con descuento>0 (guardarContrato()).
--
-- ⚠️ HALLAZGO DE SEGURIDAD ANTES DE ESCRIBIR ESTO (verificado, no supuesto):
-- ambos candados son SOLO de pantalla. `contratos.precio_total` no tiene
-- ningún CHECK, y la RLS de `contratos` no mira el rol de quien escribe ni el
-- contenido de `datos` — quien llame a PostgREST/al RPC directamente (o abra
-- la consola del navegador) salta los dos sin que nada en el servidor se
-- entere. Mismo patrón de deuda que ya documentaba el candado de
-- `validez_dias`/FIJOS_ESTUDIO, ahora aplicado a un descuento sobre dinero.
--
-- QUÉ CUBRE ESTE TRIGGER Y QUÉ NO (dicho explícito, no se infla el alcance):
--   · SÍ valida el TOPE del 15% cuando el techo elegido viaja en `datos.techo`
--     con forma reconocible (número en `precio`) — que es como lo escribe
--     `contractPayload()` hoy siempre que hay techo elegido.
--   · SÍ valida que `descuento_comercial` nunca sea negativo.
--   · SÍ es el cinturón final CUANDO HAY DESCUENTO (`v_descuento > 0`), tanto
--     si el 15% se pudo calcular como si no (formato inesperado en
--     `datos.techo`/`datos.extras`): `precio_total` (columna propia, ya
--     numérica) no puede quedar en cero ni negativo por culpa de ese
--     descuento. ⚠️ CORREGIDO el mismo día (migración
--     …_fix_precio_total_incondicional, hallado por autorrevisión antes de
--     cerrar la tarea): la primera versión de este cinturón NO estaba
--     condicionada a que hubiera descuento, así que bloqueaba CUALQUIER
--     UPDATE de un contrato tipo=construccion — y hay contratos reales
--     (CC00040/CC00076/CC00086) con `precio_total` NULL sin ningún descuento,
--     que habrían quedado inguardables para cualquier otra edición.
--   · NO valida el ROL de quien escribe — igual que `validez_dias`/
--     FIJOS_ESTUDIO, comprobar "qué rol tiene la sesión que hizo este UPDATE"
--     no es un dato que un trigger de fila pueda leer sin más infraestructura
--     (una tabla de sesión→rol o un claim de JWT propio, que hoy no existe
--     para este propósito) — igual que el resto de candados de rol de esta
--     suite, sigue siendo de pantalla. Dicho aquí para que quede escrito, no
--     escondido: quien tenga acceso directo a la API con la sesión de un
--     sales_manager puede seguir poniendo el descuento él mismo saltándose
--     app.html. Cerrar ESO es un encargo aparte (rol real en servidor), fuera
--     del alcance de esta tarea.
--   · NO exige el motivo cuando hay descuento — eso tampoco es un hueco de
--     seguridad (no protege dinero), solo higiene de datos, y ya lo cubre la
--     pantalla.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.descuento_comercial_construccion_valido()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_descuento numeric;
  v_techo     numeric;
  v_base      numeric;
begin
  if new.tipo <> 'construccion' then
    return new;
  end if;

  -- Mismo parser que ya usa `carta_cobrado_al_bloquear()` para leer un campo
  -- de dinero tecleado en pantalla (formato canónico "44.000", coma decimal).
  v_descuento := coalesce(public.lw_importe(new.datos->'fields'->>'descuento_comercial'), 0);

  if v_descuento < 0 then
    raise exception 'El descuento comercial no puede ser negativo.';
  end if;

  if v_descuento > 0 then
    -- Techo congelado: TECHO_ELEGIDO viaja como {..., precio:<number>, ...},
    -- un número JSON crudo (nunca pasó por el formateador de pantalla) — se
    -- castea directo, sin lw_importe(). Si no hay techo con esa forma (nulo,
    -- o `precio` no numérico), v_techo sale NULL y el tope del 15% no se
    -- puede calcular aquí: se deja pasar a la comprobación final de abajo.
    v_techo := nullif(new.datos->'techo'->>'precio', '')::numeric;
    if v_techo is not null then
      select v_techo + coalesce(sum(nullif(x->>'precio','')::numeric), 0)
        into v_base
        from jsonb_array_elements(coalesce(new.datos->'extras', '[]'::jsonb)) x;

      if v_base > 0 and v_descuento > round(v_base * 0.15, 2) then
        raise exception 'El descuento comercial (%) supera el 15%% del precio de techo+extras (%).',
          v_descuento, v_base;
      end if;
    end if;

    -- Cinturón final, condicionado a `v_descuento > 0` — CORREGIDO EL MISMO
    -- DÍA (migración …_fix_precio_total_incondicional, hallado por
    -- autorrevisión antes de cerrar la tarea, no en producción): la primera
    -- versión de este cinturón vivía FUERA del `if v_descuento > 0`, así que
    -- corría en CUALQUIER UPDATE de un contrato tipo=construccion — y hay
    -- contratos reales (CC00040/CC00076/CC00086) con `precio_total` NULL sin
    -- ningún descuento, que habrían quedado inguardables para cualquier otra
    -- edición. `precio_total` es columna propia ya numérica (la resuelve
    -- `parseImporte()` en el navegador) — este cinturón solo exige que no
    -- quede en cero o negativa CUANDO hay un descuento que podría haberla
    -- dejado así.
    if coalesce(new.precio_total, 0) <= 0 then
      raise exception 'precio_total no puede quedar en cero o negativo al aplicar un descuento comercial.';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.descuento_comercial_construccion_valido() from public, anon, authenticated;

-- destructivo-ok: DROP defensivo de un trigger que hoy NO existe en producción
-- (comprobado con list_migrations antes de escribir esto) — solo por si esta
-- migración se reaplica alguna vez; no borra nada que exista.
drop trigger if exists trg_descuento_comercial_construccion on public.contratos;
create trigger trg_descuento_comercial_construccion
  before insert or update on public.contratos
  for each row execute function public.descuento_comercial_construccion_valido();

comment on function public.descuento_comercial_construccion_valido() is
  'BEFORE INSERT OR UPDATE en contratos, solo tipo=construccion: bloquea un descuento_comercial negativo o por encima del 15% de techo+extras (cuando esa forma es calculable), y --SOLO cuando hay descuento (v_descuento>0)-- que precio_total no quede en cero o negativo. NO valida el rol de quien escribe (ver comentario de cabecera) — ese candado sigue siendo de pantalla. 21-sep-2026, revisión previa #33; corregido el mismo día (autorrevisión) para no bloquear ediciones de contratos sin descuento y con precio_total ya en null/0.';

-- ── comprobación tras aplicar ────────────────────────────────────────────────
--   select tgname, tgtype from pg_trigger
--    where tgrelid = 'public.contratos'::regclass and tgname = 'trg_descuento_comercial_construccion';
--   -- tgtype impar (BEFORE), INSERT+UPDATE.
--   select proname from pg_proc where proname = 'descuento_comercial_construccion_valido';

-- ─── 22-sep-2026 ─────────────────────────────────────────────────────────────
-- SUSTITUIDA por contracts/sql/precio_construccion_cuadra_con_techo.sql (migración
-- 20260922160000): misma función, añade la comprobación precio_total = techo +
-- Σextras − descuento cuando datos.techo trae precio. Este fichero queda como
-- historia del porqué; la versión vigente de la función es la de aquel.
