-- 22-sep-2026 — techo «Ulin» automático para modelos sin variantes de techo.
-- Revisión previa #39 (Legal + Datos). Decisión del owner: "haz un techo
-- estándar automático pero llámalo Ulin".
--
-- POR QUÉ. Desde el 16-sep el precio de Construcción sale de techo+extras y, desde
-- el 22-sep, el servidor lo exige (precio_construccion_cuadra_con_techo.sql). Pero
-- 10 de 15 modelos activos no tienen filas en modelo_techos, así que en sus
-- contratos no había fórmula: precio a mano y sin descuento comercial.
--
-- QUÉ HACE. Solo cuando el modelo NO tiene ninguna variante, la función devuelve
-- una única opción sintética «Ulin» con el precio base de construcción del modelo
-- para ese proyecto (la misma cifra que ya calcula la CTE `base`: modelos_villa
-- si hay precio propio, si no modelos). No se escribe ninguna fila: el precio
-- sigue teniendo un solo dueño. Se reconoce porque techo_id = modelo_id (no
-- existe en modelo_techos): el editor la marca `sintetico` y NO imprime «(por
-- defecto)» — con una sola opción no hubo elección (Legal).
--
-- REGLAS (Datos): precio y moneda de la MISMA fila (coalesce mv.moneda,
-- m.moneda); si el precio base es NULL, CERO filas (nunca una fila con precio
-- NULL: el editor la preseleccionaría y el trigger no tendría nada que
-- comprobar); `not exists` con esquema (search_path vacío); la rama existente
-- entre paréntesis para conservar su `order by`.
--
-- DIVERGENCIA ASUMIDA, no bug: la web pública (modelo/datos.php) sigue
-- ocultando del configurador los modelos sin sirap+bambu; el editor de contratos
-- sí les enseña «Ulin». Son dos consumidores distintos de dos fuentes distintas.
create or replace function public.modelo_techos_opciones(p_modelo_id uuid, p_proyecto_id uuid default null)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language sql
stable
security definer
set search_path to ''
as $$
  with base as (
    select m.precio_construccion as catalogo, m.moneda as m_moneda,
           mv.precio_construccion as propio, mv.moneda as mv_moneda,
           coalesce(mv.precio_construccion, m.precio_construccion) as efectivo,
           case when mv.precio_construccion is not null then coalesce(mv.moneda, m.moneda) else m.moneda end as moneda
      from public.modelos m
      left join public.modelos_villa mv
        on mv.modelo_id = m.id and mv.proyecto_id = p_proyecto_id and mv.precio_construccion is not null
     where m.id = p_modelo_id
  ), tramo as (select public.catalogo_tramo_activo() as t)
  (
    select th.id, th.clave, th.nombre,
           (case when tramo.t = '2026' then th.precio_ahora else th.precio_2027 end)
             + coalesce(base.efectivo - base.catalogo, 0) as precio,
           base.m_moneda, tramo.t
      from public.modelo_techos th, base, tramo
     where th.modelo_id = p_modelo_id
     order by th.orden nulls last, th.nombre
  )
  union all
  (
    select p_modelo_id, 'ulin'::text, 'Ulin'::text, base.efectivo, base.moneda, tramo.t
      from base, tramo
     where base.efectivo is not null
       and not exists (select 1 from public.modelo_techos th where th.modelo_id = p_modelo_id)
  )
$$;

comment on function public.modelo_techos_opciones(uuid, uuid) is
  'Variantes de techo de un modelo con precio YA resuelto (tramo por reloj del servidor + delta proyecto−catálogo). Desde el 22-sep-2026, un modelo SIN variantes devuelve una única opción sintética «Ulin» (techo_id = modelo_id, precio = base de construcción del modelo para el proyecto; cero filas si ese precio es NULL). Solo authenticated; la consume el editor de contratos.';
revoke all on function public.modelo_techos_opciones(uuid, uuid) from public, anon;
grant execute on function public.modelo_techos_opciones(uuid, uuid) to authenticated;
