-- Techos y extras seleccionables en el Contrato de Construccion (16-sep-2026).
-- Resuelve TODO el precio en servidor: el tramo 2026/2027 (mismo corte que modelo/lib.php,
-- LW_CORTE_2027, Asia/Makassar, nunca el reloj del cliente) y el delta que modelos_villa ya
-- aplica por proyecto sobre el precio de catalogo (revision previa de Datos: Sumba Hills ya
-- pisa el catalogo con deltas NO proporcionales por modelo -- Dali +6.000, Temple +13.000,
-- Trinity +8.000 -- y modelo_techos seguia anclado al precio de catalogo puro).
-- El cliente (contracts/app.html) NUNCA decide el tramo ni el delta: solo suma los precios ya
-- resueltos que le devuelven estas dos funciones. Mismo patron de permisos que
-- modelo_precio_construccion: security definer, revocado de anon, solo authenticated.

create or replace function public.catalogo_tramo_activo()
returns text
language sql
stable
set search_path = ''
as $$
  select case when (now() at time zone 'Asia/Makassar') < timestamp '2027-01-01 00:00:00'
              then '2026' else '2027' end
$$;

comment on function public.catalogo_tramo_activo() is
  'Mismo corte que LW_CORTE_2027 de modelo/lib.php (Asia/Makassar, 2027-01-01 00:00:00). Unica fuente de "que tramo esta activo hoy" -- nunca un new Date() de navegador.';

revoke all on function public.catalogo_tramo_activo() from public, anon;
grant execute on function public.catalogo_tramo_activo() to authenticated;

create or replace function public.modelo_techos_opciones(p_modelo_id uuid, p_proyecto_id uuid default null)
returns table(techo_id uuid, clave text, nombre text, precio numeric, moneda text, tramo text)
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select m.precio_construccion as catalogo, m.moneda,
           coalesce(
             (select mv.precio_construccion from public.modelos_villa mv
               where mv.modelo_id = p_modelo_id and mv.proyecto_id = p_proyecto_id
                 and mv.precio_construccion is not null),
             m.precio_construccion
           ) as efectivo
      from public.modelos m
     where m.id = p_modelo_id
  ), tramo as (select public.catalogo_tramo_activo() as t)
  select th.id, th.clave, th.nombre,
         (case when tramo.t = '2026' then th.precio_ahora else th.precio_2027 end)
           + coalesce(base.efectivo - base.catalogo, 0) as precio,
         base.moneda, tramo.t
    from public.modelo_techos th, base, tramo
   where th.modelo_id = p_modelo_id
   order by th.orden nulls last, th.nombre
$$;

comment on function public.modelo_techos_opciones(uuid, uuid) is
  'Techos de un modelo con su precio YA resuelto (tramo activo + delta de modelos_villa para ese proyecto, si el proyecto pisa el precio de catalogo). El delta se prorratea entero sobre el techo (mismo importe, no proporcional) porque modelos_villa tampoco es proporcional -- decision de la revision previa del 16-sep, mas simple que mantener un override de techo por proyecto.';

revoke all on function public.modelo_techos_opciones(uuid, uuid) from public, anon;
grant execute on function public.modelo_techos_opciones(uuid, uuid) to authenticated;

create or replace function public.modelo_extras_opciones(p_modelo_id uuid)
returns table(extra_id uuid, clave text, nombre text, precio numeric, moneda text)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id, e.clave, e.nombre, me.precio, me.moneda
    from public.modelo_extras me
    join public.extras e on e.id = me.extra_id
   where me.modelo_id = p_modelo_id
     and me.disponible and e.activo
     and me.precio is not null
   order by e.orden nulls last, e.nombre
$$;

comment on function public.modelo_extras_opciones(uuid) is
  'Extras ofrecibles de un modelo para Contratos: ya filtra disponible/activo aqui (antes cada pantalla que leia modelo_extras/extras por tabla directa tenia que acordarse de repetir el filtro -- catalogo_publico() ya lo hacia para la web, esta es la misma regla para la intranet).';

revoke all on function public.modelo_extras_opciones(uuid) from public, anon;
grant execute on function public.modelo_extras_opciones(uuid) to authenticated;;
