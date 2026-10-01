-- LAW-437 — precio_lista_suelo lo pone el SERVIDOR, no el navegador — 29-sep-2026.
-- Owner: "backend no se cree al navegador".
-- ════════════════════════════════════════════════════════════════════════════
-- QUÉ PASABA. El tope del 15% del descuento comercial del Bloqueo de Parcela
-- (descuento_comercial_suelo_valido) se medía contra
-- datos.fields.precio_lista_suelo, que calculaba y mandaba app.html. Quien
-- edita el contrato podía mandar una lista inflada (lista 200.000 sobre una
-- parcela de 100.000) y colar un descuento del 30% como si fuera un 15%.
--
-- QUÉ HACE. Este trigger es el ÚNICO dueño de precio_lista_suelo. Lo que
-- mande el navegador en ese campo se pisa siempre:
--   · Contrato nuevo, o cambian las parcelas / el proyecto → la lista sale del
--     inventario: suma de unidades.precio_suelo de las parcelas de
--     datos.fields.parcela_codigo (lista separada por comas) en su proyecto.
--     Si alguna parcela no está en el inventario o no tiene precio de suelo,
--     el campo se quita, y un descuento sin lista lo para el trigger de
--     validación ("necesita el precio de lista").
--   · Mismas parcelas y ya había lista guardada → se conserva la guardada
--     (CONGELADA: es la lista con la que se pactó el descuento; si el
--     inventario cambia después, el contrato no se mueve). Igual que hacía
--     la pantalla con listaSueloVigente().
--   · Un UPDATE que no toca `datos` (bloqueado, pdf, padre…) no se toca:
--     escribir en datos ahí haría saltar el candado de contrato firmado.
--
-- ORDEN. Los BEFORE triggers corren por nombre: trg_contrato_lista_suelo va
-- antes de trg_descuento_comercial_suelo (que la valida) y de
-- zz_contrato_datos_fields (que copia datos->fields). Corre también antes de
-- trg_espejo_proyecto, así que en un INSERT el proyecto se resuelve aquí por
-- nombre, con la misma regla que ese trigger.
--
-- Prueba ejecutable: erp/pruebas/lista_suelo_servidor.sql del maestro (mismo cuerpo de función; Lawang no
-- tiene arnés SQL). Casos probados aquí a mano con rollback el 29-sep.
--
-- Datos existentes: las 13 reservas con lista guardada casan con el
-- inventario (comprobado el 29-sep); no hace falta corregir nada.

create or replace function public.contrato_lista_suelo_servidor()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_cods     text[];
  v_cods_old text[];
  v_proy     uuid;
  v_lista    numeric;
  v_n        int;
  v_con      int;
begin
  if new.tipo <> 'reserva_parcela' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.datos is not distinct from old.datos then
    return new;
  end if;
  if jsonb_typeof(new.datos->'fields') <> 'object' then
    return new;
  end if;

  v_cods := array(select distinct btrim(x)
                    from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo', ''), ',')) x
                   where btrim(x) <> '' order by 1);

  if tg_op = 'UPDATE' and old.tipo = 'reserva_parcela' then
    v_cods_old := array(select distinct btrim(x)
                          from unnest(string_to_array(coalesce(old.datos->'fields'->>'parcela_codigo', ''), ',')) x
                         where btrim(x) <> '' order by 1);
    if v_cods = v_cods_old
       and new.proyecto_id is not distinct from old.proyecto_id
       and coalesce(public.lw_importe(old.datos->'fields'->>'precio_lista_suelo'), 0) > 0 then
      new.datos := jsonb_set(new.datos, '{fields,precio_lista_suelo}', old.datos->'fields'->'precio_lista_suelo');
      return new;
    end if;
  end if;

  v_proy := new.proyecto_id;
  if v_proy is null and nullif(btrim(coalesce(new.proyecto_nombre, '')), '') is not null then
    select p.id into v_proy from public.proyectos p where p.nombre = new.proyecto_nombre;
  end if;

  if cardinality(v_cods) > 0 and v_proy is not null then
    select count(*), count(u.precio_suelo), sum(u.precio_suelo)
      into v_n, v_con, v_lista
      from public.unidades u
     where u.proyecto_id = v_proy and u.codigo = any(v_cods);
    if v_n <> cardinality(v_cods) or v_con <> v_n or not (v_lista > 0) then
      v_lista := null;
    end if;
  end if;

  if v_lista is null then
    new.datos := new.datos #- '{fields,precio_lista_suelo}';
  else
    new.datos := jsonb_set(new.datos, '{fields,precio_lista_suelo}', to_jsonb(public.lw_importe_texto(v_lista)));
  end if;
  return new;
end;
$$;

comment on function public.contrato_lista_suelo_servidor() is
  'LAW-437, 29-sep-2026. BEFORE INSERT OR UPDATE en contratos, solo tipo=reserva_parcela y solo si cambia datos: único dueño de datos.fields.precio_lista_suelo. Nuevo o cambio de parcelas/proyecto → suma de unidades.precio_suelo (o se quita si falta alguna); mismas parcelas con lista guardada → se conserva la guardada. Lo que mande el navegador se ignora.';

revoke all on function public.contrato_lista_suelo_servidor() from public, anon, authenticated;

-- destructivo-ok: DROP defensivo para que la migración se pueda reaplicar (al aplicarla en producción el trigger
-- aún no existía y se omitió); no borra datos.
drop trigger if exists trg_contrato_lista_suelo on public.contratos;
create trigger trg_contrato_lista_suelo
  before insert or update on public.contratos
  for each row execute function public.contrato_lista_suelo_servidor();
