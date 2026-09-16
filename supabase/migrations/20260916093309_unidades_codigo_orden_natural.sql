-- ORDEN NATURAL DE LAS PARCELAS, EN LA BASE (16-sep-2026) — 2ª reincidencia.
--
-- El 26-ago-2026 el owner vio en Sumba Hills que las parcelas salían SH-1, SH-10,
-- SH-100, SH-101… y la SH-2 cien filas más abajo. Se arregló EN EL CLIENTE
-- (`suiOrdenarPorCodigo`, contracts/assets/suite.js): cada pantalla pedía
-- `.order('codigo')` a Postgres —orden de TEXTO— y reordenaba después en JS.
-- El 16-sep-2026 volvió a pasar en /intranet/v4/proyectos/: la v4 no carga suite.js,
-- así que la corrección no llegaba, y además pedía `.order('codigo').limit(60)` sobre
-- 228 unidades — Postgres devolvía LAS 60 PRIMERAS EN ORDEN DE TEXTO, con lo que
-- ninguna reordenación en el cliente podía recuperar la SH-2: nunca llegaba.
--
-- Arreglo de raíz: el orden lo pone el dueño del dato. `unidades.codigo_orden` es una
-- columna GENERADA (no una copia que alguien tenga que mantener) con la clave natural
-- del código: cada tramo numérico rellenado a 8 dígitos y el texto en minúsculas.
--   'SH-2'      → 'sh-00000002'   < 'sh-00000010' ('SH-10')
--   'W3 - A9'   → 'w00000003 - a00000009'   < 'w00000003.00000001 - a00000000' ('W3.1 - A0')
--   'RF 2.1'    → 'rf 00000002.00000001'
-- Los clientes piden `.order('codigo_orden')` y ya viene bien también con `limit`.
-- Que la clave natural se calcule aquí y no en 9 pantallas es la misma regla de
-- siempre: una lista a mano en dos sitios ES el bug.

create or replace function public.lw_orden_natural(t text)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select string_agg(
           case when r.m[1] ~ '^[0-9]+$' then lpad(r.m[1], 8, '0') else lower(r.m[1]) end,
           '' order by r.ord)
  from regexp_matches(t, '[0-9]+|[^0-9]+', 'g') with ordinality as r(m, ord);
$$;

comment on function public.lw_orden_natural(text) is
  'Clave de orden natural de un código de parcela: tramos numéricos a 8 dígitos, texto en
   minúsculas. Alimenta unidades.codigo_orden (columna generada). IMMUTABLE a propósito:
   una columna generada lo exige.';

-- Las migraciones 20260916042641/042744 revocaron el EXECUTE por defecto a
-- public/anon/authenticated. Una columna generada se evalúa con el rol de QUIEN
-- ESCRIBE la fila, así que sin este grant cada INSERT/UPDATE de unidades desde la
-- intranet moriría con «permission denied for function lw_orden_natural».
revoke execute on function public.lw_orden_natural(text) from public;
grant execute on function public.lw_orden_natural(text) to authenticated, service_role;

alter table public.unidades
  add column if not exists codigo_orden text
  generated always as (public.lw_orden_natural(codigo)) stored;

create index if not exists unidades_proyecto_codigo_orden_idx
  on public.unidades (proyecto, codigo_orden);

comment on column public.unidades.codigo_orden is
  'Clave de orden natural del código (generada, no editable). Los clientes ordenan por
   esta columna, nunca por `codigo` (orden de texto: SH-10 antes que SH-2). Gate:
   contracts/orden_codigo.test.js.';

-- La vista lista sus columnas a mano (no `u.*`): hay que añadir la nueva AL FINAL —
-- CREATE OR REPLACE VIEW solo permite añadir por la cola. Y se re-declara
-- security_invoker=true en la propia sentencia (LAW-42, reincidente 3 veces: sin esto
-- la vista vuelve a correr como el dueño y se salta la RLS de contratos).
create or replace view public.unidades_estado
with (security_invoker = true) as
select
  u.id,
  u.codigo,
  u.proyecto,
  u.tipo,
  u.superficie_m2,
  coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) as precio,
  u.moneda,
  u.estado,
  u.contrato_id,
  u.notas,
  u.created_at,
  u.precio_suelo,
  u.precio_construccion,
  u.modelo,
  u.obra_fase,
  u.obra_fecha_entrega,
  u.obra_actualizado,
  c.numero as contrato_numero,
  c.comprador_nombre,
  c.bloqueado as contrato_firmado,
  cp.cobrado_suelo + cp.cobrado_obra as facturado,
  case
    when cp.cobrado_suelo is null then null
    when coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) > 0
      then round((cp.cobrado_suelo + cp.cobrado_obra)
           / coalesce(u.precio, nullif(coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0), 0)) * 100, 1)
    else null
  end as pct_cobrado,
  u.fase_masterplan,
  u.zona_masterplan,
  u.precio as precio_guardado,
  c.creado_por as contrato_creado_por,
  cp.cobrado_suelo,
  cp.cobrado_obra,
  cp.obra_firmada,
  u.codigo_orden
from public.unidades u
left join public.contratos c on c.id = u.contrato_id
left join lateral public.unidad_parte_cobrada_split(u.id) cp on true;

comment on view public.unidades_estado is
  'Estado en vivo de unidades + su contrato. security_invoker=true a proposito (LAW-42,
   reincidente 3 veces): sin esto, un CREATE OR REPLACE se olvida de re-declararlo y la
   vista vuelve a correr con los privilegios del dueno, saltandose la RLS de contratos
   entera. facturado/pct_cobrado/cobrado_suelo/cobrado_obra/obra_firmada salen NULL
   cuando el contrato de la unidad no es visible para quien consulta -- la decision es
   de unidad_parte_cobrada_split() (LAW-186 mitad B, 15-sep-2026), no de esta vista: no
   se duplica el criterio aqui a proposito, para no tener dos copias de la misma regla
   que puedan divergir. codigo_orden (16-sep-2026): clave de orden natural, ordenar
   SIEMPRE por ella y nunca por codigo.';
