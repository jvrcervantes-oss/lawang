-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- BUSQUEDA SIN TILDES EN EL SERVIDOR (15-oct-2026, sesion busqueda-tildes; owner: «que no haga falta poner la tilde en
-- los buscadores de Lawang y en todo lo que hagamos»). Regla: contexto/patrones_tecnicos.md de la agencia -> «Busqueda sin tildes».
--
-- QUE HACE. Los tres buscadores que buscan en el SERVIDOR comparan con ilike y no encuentran «José» tecleando «jose»
-- (el 15-oct, 51 de las 228 fichas de cliente llevaban letras no ASCII):
--   1. public.normaliza_busqueda(text): LA pieza del servidor. Aplica EXACTAMENTE el algoritmo de lwNormaliza
--      (contracts/assets/vocabulario.js), paso a paso; no unaccent: Idiomas midio 827 de sus 1.650 reglas distintas de
--      NFD (revision previa #361). Paridad medida el 15-oct en solo lectura con la expresion de abajo: 0 diferencias en
--      83 casos y en los 543 nombres reales (clients.full_name + contratos.comprador_nombre). IMMUTABLE porque todo lo que
--      llama (normalize, regexp_replace, lower, replace, translate, btrim) es IMMUTABLE en pg_catalog (medido); si un dia
--      se le pone un indice de expresion y cambia el algoritmo, ese indice se reconstruye (REINDEX) en la misma migracion.
--   2. comprador_buscar(p_q) (aviso de duplicados del alta, contracts/app.html): compara nombre y correo con
--      strpos(normaliza_busqueda(col), normaliza_busqueda(p_q)) > 0 en vez de ilike. Pasaporte (igualdad exacta y solo en
--      el alcance) y el resto, IDENTICOS a la viva (md5 bd0230e91ad793e198ab687f18552c8f, precondicion abajo). De paso un
--      «%» o «_» tecleado deja de ser comodin (con ilike, «%%%» devolvia 8 fichas cualesquiera).
--   3. contratos_busca(p_q) (buscador de ventas del asistente de contrato, contracts/assets/asistente-contrato.js): NUEVA.
--      Hoy la pantalla pide contratos_equipo() (select * de contratos, VOLATILE) y filtra con .or(numero.ilike,
--      comprador_nombre.ilike). INVOKER: la RLS de contratos es el predicado de visibilidad (no se copia a mano); los 12
--      campos que pinta la pantalla, sin datos ni datos_fields enteros; busca tambien por el nombre de la FICHA unida por
--      adq1_client_id (Base de datos: 46 contratos con la copia del nombre distinta de su ficha el 15-oct). Lo de hoy se
--      conserva: numero no nulo, created_at desc, 10 filas, y con menos de 2 letras las 10 ultimas.
--   4. clientes_busca(p_q) (edge asistente-peticiones, rama «por nombre o pasaporte»): NUEVA, INVOKER: la RLS de clients
--      decide que ve quien pide (el asistente no debe proponer editar o borrar una ficha que la persona no ve; por eso no
--      se usa comprador_buscar, que es el directorio global). Mismas columnas que pedia la edge (id, full_name, email,
--      phone), 6 filas, minimo 2 letras.
-- Volumen (15-oct): 228 clientes y 315 contratos, sin indice (seq scan). Umbral para poner un GIN pg_trgm sobre
-- normaliza_busqueda(col): >20.000 filas o >50 ms en EXPLAIN ANALYZE. Sin limite de uso ni registro propio a proposito:
-- lecturas acotadas por la RLS, 10/8/6 filas, y la pantalla espera 280 ms entre teclas (asistente-contrato.js).
-- PERMISOS: lo nuevo nace cerrado: revoke de PUBLIC y anon, grant execute solo a authenticated (llamadores con nombre:
-- asistente-contrato.js -> contratos_busca; edge asistente-peticiones con el JWT de quien pide -> clientes_busca; las tres
-- INVOKER y comprador_buscar (DEFINER, dueño postgres) -> normaliza_busqueda).
-- ORDEN DE PUBLICACION: esta migracion ANTES que el front (asistente-contrato.js) y la edge que la llaman. Por eso van en un
-- commit APARTE que no se aterriza hasta verla aplicada en vivo (revisor, 15-oct: el orden no puede vivir solo en un mensaje).
-- PRUEBA (solo en rama, fixture propio): supabase/pruebas/busqueda_sin_tildes.sql: la tabla de casos de
-- contracts/busqueda_casos.json y, con el rol real, un caso que entra y otro que se niega por cada funcion (C: comprador_buscar,
-- K: contratos_busca, L: clientes_busca; anon y quien no es del equipo, nada).
--   python erp/rama_prueba.py lawang --lawang <copia> --aplica 20261015130000_busqueda_sin_tildes.sql --prueba busqueda_sin_tildes.sql
-- REVERTIR: supabase/reversion_busqueda_sin_tildes/REVERSION.sql (orden inverso: front y edge viejos primero).
-- destructivo-ok: crea 3 funciones y reemplaza comprador_buscar con el MISMO tipo de retorno; no toca tablas ni datos
set local lock_timeout = '5s';

do $pre$
begin
  if md5(pg_get_functiondef('public.comprador_buscar(text)'::regprocedure)) <> 'bd0230e91ad793e198ab687f18552c8f' then
    raise exception 'comprador_buscar viva no es la medida el 15-oct (md5 bd0230e9…): alguien la cambio; rehacer esta migracion sobre la viva';
  end if;
end $pre$;

-- 1 · la pieza: el MISMO algoritmo que lwNormaliza, paso a paso (si se toca uno, se toca el otro y la tabla de casos)
create or replace function public.normaliza_busqueda(p_texto text)
 returns text
 language plpgsql
 immutable parallel safe
 set search_path = ''
as $f$
declare
  s text := coalesce(p_texto, '');
begin
  -- 1. NFD y fuera los combinantes (tildes, dieresis, la virgulilla de la enye)
  s := pg_catalog.regexp_replace(pg_catalog.normalize(s, 'NFD'), '[̀-ͯ]', '', 'g');
  -- 2. minusculas
  s := pg_catalog.lower(s);
  -- 3. letras que NFD no descompone (minuscula y mayuscula: no depende de la collation de la base)
  s := pg_catalog.replace(s, 'æ', 'ae');  s := pg_catalog.replace(s, 'Æ', 'ae');
  s := pg_catalog.replace(s, 'œ', 'oe');  s := pg_catalog.replace(s, 'Œ', 'oe');
  s := pg_catalog.replace(s, 'þ', 'th');  s := pg_catalog.replace(s, 'Þ', 'th');
  s := pg_catalog.replace(s, 'ĳ', 'ij');  s := pg_catalog.replace(s, 'Ĳ', 'ij');
  s := pg_catalog.replace(s, 'ß', 'ss');  s := pg_catalog.replace(s, 'ẞ', 'ss');
  s := pg_catalog.translate(s, 'øØłŁđĐðÐħĦŀĿŋŊŧŦſıªº', 'oollddddhhllnnttsiao');
  -- 4. fuera apostrofos y el punto volado
  s := pg_catalog.translate(s, '''’‘ʼ`´·', '');
  -- 5. guiones y rachas de espacios (tambien U+00A0 y U+202F) a un solo espacio; recorte
  s := pg_catalog.regexp_replace(s, '[-‐‑–— \t\n\r  ]+', ' ', 'g');
  return pg_catalog.btrim(s);
end $f$;
comment on function public.normaliza_busqueda(text) is
  'Busqueda sin tildes (15-oct-2026): el mismo algoritmo que lwNormaliza (contracts/assets/vocabulario.js). Solo para COMPARAR en un buscador: strpos(normaliza_busqueda(col), normaliza_busqueda(p_q)) > 0.';
revoke all on function public.normaliza_busqueda(text) from public, anon;
grant execute on function public.normaliza_busqueda(text) to authenticated;

-- 2 · comprador_buscar: la viva (md5 bd0230e9…) con la comparacion de nombre y correo cambiada; nada mas
create or replace function public.comprador_buscar(p_q text)
 returns table(id uuid, full_name text, email text, passport_hint text, tipo text, propietario text)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_q text;
begin
  if not public.es_agente() then return; end if;
  if length(btrim(coalesce(p_q,''))) < 3 then return; end if;
  v_q := public.normaliza_busqueda(left(p_q, 200));   -- el servidor normaliza lo que llega: no se fia de que la pantalla lo hiciera
  -- el minimo de 3 se mide YA NORMALIZADO: «a''» pasaba el de arriba y, plegado a «a», devolvia 8 fichas cualesquiera
  if char_length(v_q) < 3 then return; end if;
  return query
    select c.id, c.full_name, c.email, case when c.passport_number is null then null else '…' || right(c.passport_number, 4) end,
           c.tipo, c.propietario
      from public.clients c
     where (strpos(public.normaliza_busqueda(c.full_name), v_q) > 0 or strpos(public.normaliza_busqueda(c.email), v_q) > 0
            or (lower(c.passport_number) = lower(btrim(p_q))
                and (not (select public.alcance_restringido()) or public.cliente_visible(c.propietario, c.id))))
     limit 8;
end $function$;

-- 3 · contratos_busca: buscador de ventas del asistente de contrato (INVOKER: la RLS de contratos y de clients manda)
create or replace function public.contratos_busca(p_q text)
 returns table(id uuid, numero text, tipo text, comprador_nombre text, proyecto_nombre text, parcela_codigo text,
               bloqueado boolean, liberado_en timestamptz, fecha_firma date, created_at timestamptz,
               contrato_padre_id uuid, rev03 text)
 language sql
 stable
 set search_path = ''
as $f$
  with q as (select public.normaliza_busqueda(left(p_q, 200)) as v)   -- tope en el servidor: la pantalla corta a 120, el servidor no se fia
  select c.id, c.numero, c.tipo, c.comprador_nombre, c.proyecto_nombre, c.parcela_codigo,
         c.bloqueado, c.liberado_en, c.fecha_firma, c.created_at,
         c.contrato_padre_id, c.datos_fields->>'clausulas_negociadas'
    from public.contratos c
    cross join q
    left join public.clients k on k.id = c.adq1_client_id   -- el nombre de HOY de la ficha, ademas de la copia del contrato
   where public.es_agente()
     and c.numero is not null
     and (char_length(q.v) < 2
          or strpos(public.normaliza_busqueda(c.numero), q.v) > 0
          or strpos(public.normaliza_busqueda(c.comprador_nombre), q.v) > 0
          or strpos(public.normaliza_busqueda(k.full_name), q.v) > 0)
   order by c.created_at desc
   limit 10
$f$;
comment on function public.contratos_busca(text) is
  'Busqueda sin tildes (15-oct-2026): ventas para el asistente de contrato (asistente-contrato.js). INVOKER: la RLS decide que se ve. Menos de 2 letras = las 10 ultimas.';
revoke all on function public.contratos_busca(text) from public, anon;
grant execute on function public.contratos_busca(text) to authenticated;

-- 4 · clientes_busca: rama «por nombre o pasaporte» de la edge asistente-peticiones (INVOKER: la RLS de clients manda)
create or replace function public.clientes_busca(p_q text)
 returns table(id uuid, full_name text, email text, phone text)
 language sql
 stable
 set search_path = ''
as $f$
  with q as (select public.normaliza_busqueda(left(p_q, 200)) as v)   -- tope en el servidor (la edge corta a 120)
  select c.id, c.full_name, c.email, c.phone
    from public.clients c
    cross join q
   where public.es_agente()
     and char_length(q.v) >= 2
     and (strpos(public.normaliza_busqueda(c.full_name), q.v) > 0
          or lower(c.passport_number) = lower(btrim(p_q)))
   limit 6
$f$;
comment on function public.clientes_busca(text) is
  'Busqueda sin tildes (15-oct-2026): clientes por nombre o pasaporte para la edge asistente-peticiones, con la RLS de quien pide.';
revoke all on function public.clientes_busca(text) from public, anon;
grant execute on function public.clientes_busca(text) to authenticated;
