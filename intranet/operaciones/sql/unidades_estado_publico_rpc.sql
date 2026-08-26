-- Lawang · lectura publica del estado de unidades para el masterplan de la ficha
-- 6-ago-2026 — YA APLICADA (mcp__supabase-lawang__apply_migration)
--
-- La tabla `unidades` solo la leen agentes autenticados (precio, contrato_id,
-- notas son datos operativos). La ficha publica solo necesita saber si una
-- parcela concreta ya esta vendida/reservada para no ofrecerla como
-- disponible en el plano. Se resuelve con una funcion SECURITY DEFINER que
-- filtra explicitamente en el cuerpo (una vista normal NO reaplicaria la RLS
-- de la tabla base) y solo devuelve codigo/estado/superficie_m2 -- nunca
-- precio, contrato_id ni notas.
--
-- p_codigos es obligatorio y acota a los codigos que la propia ficha ya
-- declara (p.masterplanPlots en data.json): sin el filtro, cualquiera podria
-- pedir el proyecto entero y ver fases o parcelas que marketing no ha
-- anunciado todavia (bloqueada/no_disponible incluidas).

create or replace function public.unidades_estado_publico(p_proyecto text, p_codigos text[])
returns table(codigo text, estado text, superficie_m2 numeric)
language sql
security definer
set search_path = public
as $$
  select codigo, estado, superficie_m2
  from public.unidades
  where proyecto = p_proyecto
    and codigo = any(p_codigos)
    and cardinality(p_codigos) > 0
    and cardinality(p_codigos) <= 100;
$$;

-- Postgres concede EXECUTE a PUBLIC por defecto en las funciones nuevas.
-- Se revoca y se concede solo a anon (y de rebote a authenticated, que ya
-- puede leer la tabla entera via es_agente() y no pierde nada con esto).
revoke all on function public.unidades_estado_publico(text, text[]) from public;
grant execute on function public.unidades_estado_publico(text, text[]) to anon, authenticated;

comment on function public.unidades_estado_publico is
  'Lectura publica acotada para el masterplan de la ficha: codigo+estado+superficie_m2 de los codigos pedidos, nunca precio/contrato/notas. SECURITY DEFINER porque una vista no reaplicaria la RLS de unidades.';

-- ═════════════════════════════════════════════════════════════
-- COMPROBACION (verificado con curl anonimo el 6-ago-2026):
--   - con p_codigos=['A1','B17','C8'] -> devuelve exactamente esas 3 filas
--   - con p_codigos=[] -> devuelve []  (nunca "todo el proyecto")
--   - GET directo a /rest/v1/unidades con la publishable key -> 200 []
--     (la tabla base sigue protegida por RLS, esta funcion es la unica via)
-- ═════════════════════════════════════════════════════════════
