-- Lawang · tamanos de parcela DISPONIBLES para /palmfield (landing publica de venta)
-- 14-sep-2026
--
-- /palmfield/index.php publicaba una lista de tamanos escrita a mano el 4-sep-2026
-- (project_lawang_palmfield_landing_4sep), con su fecha en LW_PF_PARCELAS_FECHA. Hoy
-- esa lista ya diverge de la realidad: los tamanos realmente disponibles de
-- "Palm Field W5" son [250, 255, 295, 310], no los [250, 255, 310, 330, 355] escritos
-- el 4-sep -- 330 y 355 ya no estan disponibles, y 295 no estaba en la lista.
--
-- Esta funcion es el hermano de `investor_deck_parcelas` (20260910025145), MISMA fila,
-- mismo filtro -- no una copia que diverja: solo columnas distintas (aqui, una sola:
-- superficie_m2, sin codigo/precio/cuota_reserva). Revision previa de Seguridad
-- (14-sep-2026, plan): la primera version de este plan filtraba unicamente por
-- `proyecto = p_proyecto and estado = 'disponible'`, SIN el opt-in
-- `publicado_investor_deck` -- eso habria hecho de esta funcion un oraculo del
-- inventario de los otros 13 proyectos de `unidades` en cuanto alguien la llamara
-- por REST con otro nombre de proyecto. Como en `investor_deck_parcelas`, el filtro
-- vive FILA A FILA sobre `unidades` (no via `deck_proyecto_abierto`, que gatea por
-- TABLAS SIN opt-in propio como `deck_fotos`/`modelos`; `unidades` SI lo tiene, y es
-- el origen de la regla, no una copia suya).
--
-- Nunca devuelve codigo, precio ni recuento agregado: decision del owner del 4-sep de
-- NO publicar cuantas parcelas quedan en trafico de pago (se descarto el "Only 4 Plots
-- Left" del mockup del investor deck). Solo los TAMANOS, que cambian mucho mas despacio.
--
-- Prima hermana de `unidades_estado_publico` (20260806, gatea por lista de codigos
-- conocidos de antemano, no por proyecto agregado) -- no la sustituye, cubre un caso
-- distinto (agregado por proyecto sin conocer codigos). Se deja aqui la referencia
-- cruzada para no acabar con tres familias de "lectura publica redactada de unidades"
-- sin relacion entre si (hallazgo de Datos en la revision previa).

create or replace function public.parcelas_tamanos_disponibles(p_proyecto text)
returns table(superficie_m2 numeric)
language sql
security definer
stable
set search_path = public
as $$
  select distinct superficie_m2
    from public.unidades
   where proyecto = p_proyecto
     and estado = 'disponible'
     and publicado_investor_deck = true
   order by superficie_m2;
$$;

revoke all on function public.parcelas_tamanos_disponibles(text) from public;
grant execute on function public.parcelas_tamanos_disponibles(text) to anon, authenticated;

comment on function public.parcelas_tamanos_disponibles is
  'Lectura publica y acotada para /palmfield (landing de venta): solo los tamanos de parcela DISPONIBLES de un proyecto abierto (publicado_investor_deck fila a fila, mismo opt-in que investor_deck_parcelas). Nunca codigo, precio ni recuento -- decision del owner de no publicar cuantas quedan.';
