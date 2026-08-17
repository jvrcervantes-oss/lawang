-- ════════════════════════════════════════════════════════════════════════════
-- CONTRATO_VENCIMIENTOS — el calendario de pagos OPERATIVO — 18-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del cliente: controlar CUÁNDO debe entrar cada pago (dashboard de
-- vencimientos). Los hitos ya viven en `contratos.datos->hitos`, así que la
-- primera pregunta es por qué esto no es la duplicación que la suite prohíbe.
--
-- PORQUE SON DOS DATOS CON DOS VIDAS, y se comprobó antes de decidir:
-- `contrato_no_editable_en_firma` (leído del catálogo, no del repo) bloquea
-- cualquier cambio de `datos` en cuanto el contrato tiene una firma viva o
-- recogida. O sea: lo que dice el DOCUMENTO —"50% a la firma, 50% a los 3
-- meses"— queda congelado al firmar, y ESO ES CORRECTO, es un documento firmado.
-- Pero la fecha REAL en que se espera el dinero es operativa: se pacta un
-- aplazamiento, se corrige un descuadre, y eso pasa DESPUÉS de firmar. Meterla
-- en `datos` la congelaría junto al documento; el equipo no podría gestionar
-- vencimientos justo en los contratos que más importan (los firmados: 46 hoy).
--
--   · datos->hitos           = el término CONTRACTUAL (congela al firmar)
--   · contrato_vencimientos  = el calendario OPERATIVO (vive siempre)
--
-- La regla anti-divergencia sigue en pie, resuelta por dirección única: mientras
-- el contrato es BORRADOR, esta tabla es un espejo derivado (el trigger la
-- reescribe desde datos->hitos en cada guardado y aquí no se edita); cuando está
-- FIRMADO, datos ya no cambia, el trigger ya no pisa, y la edición pasa a la
-- herramienta de Vencimientos, que marca `ajustado`. Nunca hay dos sitios
-- editables a la vez.
--
-- PCT Y MONTO SE GUARDAN CRUDOS (texto), NO PARSEADOS. `monto` es lo que tecleó
-- el agente ("50.000", "1,500.50") y la ÚNICA forma de leer eso es
-- `lwParseImporte` (assets/dinero.js) — escribir su equivalente en plpgsql sería
-- la CUARTA implementación de leer un importe, el mismo pecado que se acaba de
-- pagar unificando las otras tres (17-ago). El importe en euros lo resuelve el
-- cliente con la función compartida; esta tabla aporta lo que SQL sí debe
-- aportar: la FECHA consultable e indexable.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.contrato_vencimientos (
  id             uuid primary key default gen_random_uuid(),
  contrato_id    uuid not null references public.contratos(id) on delete cascade,
  orden          int  not null,
  descripcion    text,                       -- el texto ES del hito ("Fase de obra 1")
  pct            text,                       -- crudo del hito; puede ir vacío
  monto          text,                       -- crudo del hito; lo lee lwParseImporte
  fecha          date,                       -- NULL = sin fecha: se enseña como hueco, nunca se inventa
  ajustado       boolean not null default false,  -- true = lo tocó una persona; el trigger no lo pisa
  nota           text,                       -- "aplazado por el comprador, ver email 12-ago"
  actualizado_por text,
  actualizado_en  timestamptz,
  creado_en       timestamptz not null default now(),
  unique (contrato_id, orden)
);

-- La consulta del dashboard es "qué vence en esta ventana": la fecha manda.
create index if not exists contrato_vencimientos_fecha_idx
  on public.contrato_vencimientos (fecha) where fecha is not null;
create index if not exists contrato_vencimientos_contrato_idx
  on public.contrato_vencimientos (contrato_id);

alter table public.contrato_vencimientos enable row level security;

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- SELECT para todo el equipo: los vencimientos son la vista de dinero de la
-- EMPRESA (mismo criterio que Operaciones, que existe para cruzar lo de todos).
-- Un comprador del portal no pasa: es_agente() lo deja fuera.
drop policy if exists vencimientos_select on public.contrato_vencimientos;
create policy vencimientos_select on public.contrato_vencimientos
  for select to authenticated using (public.es_agente());

-- UPDATE solo con la herramienta de operaciones en la ficha. Qué columnas puede
-- tocar NO lo decide la policy (RLS no sabe de columnas): lo decide el GRANT de
-- columna de aquí abajo — fecha, nota y ajustado. El resto (contrato_id, orden,
-- pct, monto, descripcion) solo lo escribe el trigger: cambiar el porcentaje de
-- un hito ES cambiar el contrato, y eso se hace en Contratos, no aquí.
drop policy if exists vencimientos_update on public.contrato_vencimientos;
create policy vencimientos_update on public.contrato_vencimientos
  for update to authenticated
  using (public.es_agente() and public.puede('operaciones'))
  with check (public.es_agente() and public.puede('operaciones'));

-- Sin policy de INSERT ni DELETE a propósito: las filas nacen y mueren con su
-- contrato, por el trigger. Un vencimiento suelto sin hito detrás sería dinero
-- que ningún documento respalda.

revoke all on public.contrato_vencimientos from anon;
revoke insert, delete, update on public.contrato_vencimientos from authenticated;
grant select on public.contrato_vencimientos to authenticated;
grant update (fecha, nota, ajustado, actualizado_por, actualizado_en)
  on public.contrato_vencimientos to authenticated;

-- ── El trigger que deriva las filas del contrato ────────────────────────────
-- AFTER y no BEFORE: escribe en OTRA tabla, no toca la fila de contratos.
-- SECURITY DEFINER porque quien guarda un contrato no tiene (ni debe tener)
-- INSERT sobre esta tabla — es la misma razón y el mismo patrón que
-- sincroniza_unidad_contrato. Con search_path vacío y el EXECUTE revocado al
-- final, como el resto de funciones de trigger desde el 17-ago.
create or replace function public.sincroniza_vencimientos()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  hitos jsonb := coalesce(new.datos->'hitos', '[]'::jsonb);
begin
  -- Solo si los hitos CAMBIARON: cada guardado de la app reescribe datos entero
  -- (anexos incluidos, ver LAW-71) y regenerar esta tabla en cada retoque de un
  -- campo de texto sería ruido — y pisaría actualizado_en sin motivo.
  if tg_op = 'UPDATE' and new.datos->'hitos' is not distinct from old.datos->'hitos' then
    return new;
  end if;

  -- Se rehacen las filas NO ajustadas. Las ajustadas (tocadas por una persona
  -- en Vencimientos) sobreviven: en la práctica solo existen en contratos
  -- firmados, cuyo datos ya no cambia — este delete es para los borradores,
  -- donde la tabla es un espejo y el espejo se regenera entero.
  delete from public.contrato_vencimientos v
   where v.contrato_id = new.id and not v.ajustado;

  insert into public.contrato_vencimientos
         (contrato_id, orden, descripcion, pct, monto, fecha)
  select new.id,
         h.ordinality,
         nullif(btrim(coalesce(h.value->>'es', h.value->>'en', h.value->>'id', '')), ''),
         nullif(btrim(coalesce(h.value->>'pct',   '')), ''),
         nullif(btrim(coalesce(h.value->>'monto', '')), ''),
         case when h.value->>'fecha' ~ '^\d{4}-\d{2}-\d{2}$'
              then (h.value->>'fecha')::date end
    from jsonb_array_elements(hitos) with ordinality h
   where not exists (select 1 from public.contrato_vencimientos v2
                      where v2.contrato_id = new.id and v2.orden = h.ordinality)
  on conflict (contrato_id, orden) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_sincroniza_vencimientos on public.contratos;
create trigger trg_sincroniza_vencimientos
  after insert or update of datos on public.contratos
  for each row execute function public.sincroniza_vencimientos();

-- La regla del 17-ago: una función de trigger no es un endpoint. Probado ese
-- día que el trigger dispara igual sin EXECUTE.
revoke execute on function public.sincroniza_vencimientos() from public, anon, authenticated;

-- Y el sello de la edición: quién y cuándo, puesto por la base y no por el
-- cliente (un cliente puede mentir sobre la hora; auth.email() no).
create or replace function public.sella_vencimiento()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  -- email si el token lo trae; si no, el uid — nunca null con sesión. La primera
  -- versión usaba solo auth.email() y el test del bloque DO la cazó: un JWT sin
  -- email dejaba el sello a medias, y un vencimiento editado sin saber por quién
  -- es justo lo que este sello evita.
  new.actualizado_por := coalesce((select auth.email()), (select auth.uid())::text);
  new.actualizado_en  := now();
  return new;
end;
$$;

drop trigger if exists trg_sella_vencimiento on public.contrato_vencimientos;
create trigger trg_sella_vencimiento
  before update on public.contrato_vencimientos
  for each row execute function public.sella_vencimiento();

revoke execute on function public.sella_vencimiento() from public, anon, authenticated;

-- ── Siembra de los contratos existentes ─────────────────────────────────────
-- INSERT directo, NUNCA un `update contratos set datos = datos` para disparar
-- el trigger: eso dispararía TODOS los triggers de contratos sobre 73 filas —
-- sincroniza_unidad_contrato revalidaría parcelas (y el caso LAW-51 enseñó que
-- una fila que perdió su parcela muere con "ya está asignada" al tocarla) y
-- contrato_no_editable_en_firma rechazaría los firmados. Los hitos de estas
-- filas no traen fecha (el campo nace hoy): quedan a NULL y el dashboard los
-- enseña como "sin fecha" — el equipo las pone; inventarlas sería mentir.
insert into public.contrato_vencimientos (contrato_id, orden, descripcion, pct, monto, fecha)
select c.id,
       h.ordinality,
       nullif(btrim(coalesce(h.value->>'es', h.value->>'en', h.value->>'id', '')), ''),
       nullif(btrim(coalesce(h.value->>'pct',   '')), ''),
       nullif(btrim(coalesce(h.value->>'monto', '')), ''),
       case when h.value->>'fecha' ~ '^\d{4}-\d{2}-\d{2}$' then (h.value->>'fecha')::date end
  from public.contratos c,
       jsonb_array_elements(coalesce(c.datos->'hitos', '[]'::jsonb)) with ordinality h
on conflict (contrato_id, orden) do nothing;

-- ── Comprobación (la del catálogo, no la de que alguien lo corriera) ────────
--   select count(*) filter (where fecha is null) as sin_fecha, count(*) as filas,
--          count(distinct contrato_id) as contratos
--     from public.contrato_vencimientos;
--   select tgname from pg_trigger where tgrelid='public.contratos'::regclass and not tgisinternal;
-- Y como anónimo, la tabla tiene que dar 0 filas o 401 — nunca datos.
