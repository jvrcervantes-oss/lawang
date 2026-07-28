-- Lawang · firma en cadena (varios firmantes, un solo documento)
-- 28-jul-2026 · diseño en contracts/FIRMA_EN_CADENA.md
--
-- Ejecutar en Lawang BD:
--   https://supabase.com/dashboard/project/vtulllundrfennhjddhc/sql/new
-- Idempotente. Solo añade columnas y cierra tokens huérfanos: no borra nada.

-- ── 1. CONTENCIÓN (hacer aunque no se implemente la cadena) ───────────
-- 5 enlaces `pendiente` y no caducados sobre contratos ya `bloqueado=true`
-- (CR00004: 1 · RP00015: 4), todos rol adquiriente_1 = regeneraciones, no
-- multi-firmante. Quien conserve uno puede producir un SEGUNDO documento
-- "firmado" del mismo contrato con otra fecha e IP: doble instrumento sobre un
-- PPJB cerrado. No toca ningún PDF ni ninguna firma ya completada.
update public.contrato_firmas f
set estado = 'anulado'
from public.contratos c
where c.id = f.contrato_id
  and c.bloqueado = true
  and f.estado = 'pendiente';

-- ── 1b. Enlaces DUPLICADOS del mismo rol, aunque el contrato siga abierto ──
-- Medido: 12 pendientes en total, con 3 grupos duplicados (CR00005 x4,
-- RP00015 x4, RP00016 x2). En los tres casos **el destinatario es el mismo
-- email**: son regeneraciones y dobles clics, no firmantes distintos. Por eso
-- quedarse con el más reciente es seguro.
-- Se hace ANTES del índice único porque si no, el índice no se puede crear.
-- ⚠️ Consecuencia: si a alguien se le mandó un enlace ANTERIOR, deja de
-- funcionar. Hay que reenviarle el vigente. Tras esto quedan 3 vivos:
--   CC00007 · Juan Ramón Sánchez García
--   CR00005 · Rubén Carrasco
--   RP00016 · Juan Ramón Sánchez García
update public.contrato_firmas f
set estado = 'anulado'
where f.estado = 'pendiente'
  and exists (
    select 1 from public.contrato_firmas g
    where g.contrato_id = f.contrato_id
      and g.firmante_rol = f.firmante_rol
      and g.estado = 'pendiente'
      and (g.creado_en > f.creado_en
           or (g.creado_en = f.creado_en and g.id > f.id))   -- desempate estable
  );

-- ── 2. Columnas para la cadena ────────────────────────────────────────
-- `orden`: posición del firmante. Se podría deducir parseando el rol, pero un
-- entero ordena sin depender del formato del texto y deja sitio a roles que no
-- sean adquiriente_N (representante, avalista).
alter table public.contrato_firmas
  add column if not exists orden int not null default 1;

-- `pdf_path`: la que ya estaba pendiente en multifirmante_pdf_path.sql. En la
-- cadena solo la rellena el ÚLTIMO firmante, que es quien produce el PDF; las
-- firmas intermedias no generan documento.
alter table public.contrato_firmas
  add column if not exists pdf_path text;

comment on column public.contrato_firmas.orden is
  'Posicion en la cadena de firma. El enlace de N+1 no se genera hasta que N ha firmado.';
comment on column public.contrato_firmas.pdf_path is
  'PDF de esta firma. Solo lo rellena el ultimo firmante: antes no hay documento completo.';

-- ── 3. Un token vivo por contrato y rol ───────────────────────────────
-- Impide de raíz lo que provocó los 4 enlaces duplicados de RP00015: dos
-- tokens `pendiente` para el mismo rol del mismo contrato. Regenerar un enlace
-- pasa a exigir anular el anterior, que es justo lo que se quiere.
-- ⚠️ La columna es `firmante_rol`, NO `rol`: `rol` es la de
-- `contrato_compradores`. Son tablas distintas y se llaman distinto.
create unique index if not exists contrato_firmas_un_pendiente_por_rol
  on public.contrato_firmas (contrato_id, firmante_rol)
  where estado = 'pendiente';

-- ── COMPROBACIÓN ──────────────────────────────────────────────────────
select
  (select count(*) from public.contrato_firmas f join public.contratos c on c.id=f.contrato_id
     where c.bloqueado = true and f.estado = 'pendiente')                     as enlaces_vivos_sobre_firmados,
  (select count(*) from public.contrato_firmas where estado='pendiente')      as enlaces_vivos_total,
  (select count(*) from information_schema.columns
     where table_name='contrato_firmas' and column_name in ('orden','pdf_path')) as columnas_nuevas,
  (select count(*) from pg_indexes where indexname='contrato_firmas_un_pendiente_por_rol') as indice;
-- esperado: 0 · 3 · 2 · 1
