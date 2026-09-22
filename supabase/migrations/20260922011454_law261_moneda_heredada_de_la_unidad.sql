-- ════════════════════════════════════════════════════════════════════════════
-- LAW-261 — moneda heredada de la unidad, no un campo suelto — 22-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- 2ª reincidencia (tools/aprendizaje.py). contratos.moneda es text nullable
-- sin default; el único punto de escritura hoy es contracts/app.html:4460, un
-- insert()/update() genérico compartido por TODOS los tipos de contrato — si
-- ese payload no trae moneda (o trae la equivocada), no hay nada que lo pare.
--
-- Alcance real verificado antes de decidir (execute_sql, no de memoria): de
-- 259 contratos, solo 1 tiene moneda distinta de la de su unidad real —
-- C200003 (tipo ppjb_bonian_c2), moneda NULL, su unidad C2 está en EUR. Sigue
-- siendo un caso aislado: se elige AUTORRELLENAR (heredar), no validar con
-- excepción — la única discrepancia real es un hueco (NULL), no un valor
-- puesto a propósito y distinto; una excepción en INSERT/UPDATE bloquearía
-- guardados legítimos por un campo que el propio dueño del dato (la unidad)
-- ya sabe resolver solo. Además "moneda heredada" es más a prueba de
-- reincidencia: cierra el hueco pase lo que pase el próximo punto de escritura
-- que se le olvide, en vez de exigir que cada uno lo rellene bien.
--
-- Un solo trigger BEFORE INSERT OR UPDATE resuelve la unidad real y hereda su
-- moneda mientras el contrato siga editable (bloqueado=false):
--   1) por la MISMA clave que usa sincroniza_unidad_contrato() para enlazar
--      la unidad — datos->fields.parcela_codigo + proyecto_nombre — la única
--      que existe YA en el INSERT (unidades.contrato_id lo pone un trigger
--      AFTER que en el INSERT todavía no ha corrido);
--   2) si no resuelve, por unidad_id directo (construcción) o por
--      unidades.contrato_id = este contrato (ya enlazado, en una UPDATE
--      posterior);
--   3) si tampoco, hereda la moneda YA resuelta del padre
--      (contrato_padre_id) — una construcción colgada de su reserva_parcela.
-- Solo actúa si resuelve un ÚNICO valor sin ambigüedad; varias parcelas de
-- distinta moneda, o ningún enlace (hak_sewa_notario, poa: sin unidad nunca),
-- se dejan tal cual llega el dato, como hoy.
--
-- CONGELADO una vez firmado (bloqueado=true): un contrato ya firmado no
-- cambia de moneda solo por guardarse de nuevo, ni porque el parcelario
-- cambie después — es un dato que ya se firmó (contexto/patrones_tecnicos.md
-- → "El dato tiene un dueño"). Por eso C200003 (ya bloqueado) NO se corrige
-- solo: se backfillea aquí mismo, una vez, con el único valor real conocido.
--
-- Verificado en transacción ROLLBACK: C200003 (bloqueado=true) no cambia tras
-- un update que no toca moneda; CC00078 (sin firmar, EUR real) con una moneda
-- forzada a IDR se autocorrige a EUR en el mismo guardado; un contrato
-- reasignado a datos.fields.parcela_codigo="RF 1.1"/proyecto_nombre=
-- "Riverfront I" (moneda IDR, sin ningún enlace previo) resuelve IDR solo por
-- la clave de sincroniza_unidad_contrato — la ruta que hace falta para un
-- INSERT nuevo, antes de que exista cualquier FK.
--
-- security definer, set search_path='', y revocado explícito de
-- public/anon/authenticated tras crearlo (super_admin_poderes.sql ya
-- documentó que esto se olvidó dos veces en este mismo repo).
create or replace function public.fn_contrato_moneda_desde_unidad()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_proy    text;
  v_cods    text[];
  v_monedas text[];
begin
  if tg_op = 'UPDATE' and coalesce(old.bloqueado, false) then
    return new;
  end if;

  v_proy := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  v_cods := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo', ''), ',')) x
  );

  -- 1) misma clave que sincroniza_unidad_contrato() -- la unica que existe ya
  --    en el INSERT
  if v_proy is not null and coalesce(array_length(v_cods, 1), 0) > 0 then
    select array_agg(distinct u.moneda) filter (where u.moneda is not null)
      into v_monedas
      from public.unidades u
     where u.proyecto = v_proy and u.codigo = any(v_cods);
  end if;

  -- 2) unidad propia por FK: directa (construccion con unidad_id) o ya
  --    enlazada (una UPDATE posterior a que el AFTER trigger la enlazara)
  if coalesce(array_length(v_monedas, 1), 0) = 0 and new.unidad_id is not null then
    select array_agg(distinct u.moneda) filter (where u.moneda is not null)
      into v_monedas from public.unidades u where u.id = new.unidad_id;
  end if;
  if coalesce(array_length(v_monedas, 1), 0) = 0 then
    select array_agg(distinct u.moneda) filter (where u.moneda is not null)
      into v_monedas from public.unidades u where u.contrato_id = new.id;
  end if;

  -- 3) sin unidad propia resoluble: hereda la moneda YA resuelta del padre
  if coalesce(array_length(v_monedas, 1), 0) = 0 and new.contrato_padre_id is not null then
    select array_agg(distinct padre.moneda) filter (where padre.moneda is not null)
      into v_monedas from public.contratos padre where padre.id = new.contrato_padre_id;
  end if;

  if coalesce(array_length(v_monedas, 1), 0) = 1 then
    new.moneda := v_monedas[1];
  end if;

  return new;
end
$$;

revoke all on function public.fn_contrato_moneda_desde_unidad() from public, anon, authenticated;

-- destructivo-ok: DROP TRIGGER IF EXISTS de un trigger nuevo (no existe hoy),
-- patron estandar de creacion idempotente ya usado en todo el repo.
drop trigger if exists trg_contrato_moneda_desde_unidad on public.contratos;
create trigger trg_contrato_moneda_desde_unidad
  before insert or update on public.contratos
  for each row execute function public.fn_contrato_moneda_desde_unidad();

-- backfill del único caso real conocido (congelado por bloqueado=true, el
-- trigger de arriba nunca lo va a tocar solo): C200003, su unidad C2 es EUR.
update public.contratos set moneda = 'EUR'
 where numero = 'C200003' and moneda is null;
