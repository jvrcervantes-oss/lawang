-- ═══════════════════════════════════════════════════════════════════════════
-- LA CUENTA TAMBIÉN PUEDE DEPENDER DEL PROYECTO — 14-sep-2026
-- ═══════════════════════════════════════════════════════════════════════════
-- Encargo del owner, el mismo día que el reparto por tipo de contrato: «en carta
-- de reserva esta cuenta bancaria pero si seleccionas Palm Field puede ser esta
-- otra».
--
-- POR QUÉ EL DATO LE DA LA RAZÓN. Sobre los 157 contratos que ya tienen cuenta:
-- el NOTARIO es determinista por proyecto (Soka Village W2 → Nyoman Wiryasa en
-- 18 de 18 de sus Bloqueos de Parcela), y sin embargo hoy el comercial elige
-- entre CINCO notarios en ese desplegable. Esa es una cuenta de escrow:
-- equivocarse es mandar el depósito de garantía a la cuenta de otra operación.
--
-- NO ES UNA MATRIZ, ES UNA EXCEPCIÓN. 8 tipos × 29 proyectos son 232 casillas
-- que nadie mantiene y que a los tres meses estarían medio viejas. Aquí el
-- reparto por tipo (`plantilla_cuentas`) sigue siendo la regla general y un
-- proyecto solo declara en qué se sale de ella. Lo que no diga, lo hereda —
-- mismo patrón que la cascada de precios del catálogo de modelos.
--
-- CÓMO SE RESUELVE (y el orden importa): gana ENTERO el nivel más específico
-- que tenga filas, sin fusionar niveles.
--   1. (proyecto, tipo de contrato)  → esas y solo esas
--   2. (proyecto, '*')               → cuentas del proyecto válidas en cualquier tipo
--   3. plantilla_cuentas[tipo]       → la regla general
--   4. todas las activas             → solo si la carga falló (ver entidades_pago.js)
-- «El proyecto no dice nada» (hereda) y «no he podido cargarlo» (ofrece todas)
-- son cosas distintas y no pueden comportarse igual.
create table if not exists public.proyecto_cuentas (
  proyecto_id     uuid not null references public.proyectos(id) on delete cascade,
  -- `'*'` = vale para CUALQUIER tipo de contrato de este proyecto. Se usa un
  -- valor explícito y no NULL: un NULL en la clave primaria no se puede, y
  -- además `on conflict` con NULL se comporta de forma sorprendente.
  -- ⚠️ El nivel '*' es para cuentas de EMPRESA del proyecto. Una cuenta de
  -- notario NUNCA va aquí: solo tiene sentido donde el contrato pacta escrow
  -- notarial (el Bloqueo de Parcela). Puesta en '*' y con la semántica de
  -- restringir, la Carta de Reserva de ese proyecto ofrecería solo el escrow
  -- del notario — dinero a una cuenta de garantía con una cláusula que la
  -- Carta no pacta. Verificado que el riesgo es real y no teórico: en Soka
  -- Village W2 los contratos de construcción cobran en `sandalwoods_dbs_sg`,
  -- no en su notario.
  slug            text not null default '*',
  clave           text not null references public.cuentas_bancarias(clave) on update cascade on delete restrict,
  es_default      boolean not null default false,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid,
  primary key (proyecto_id, slug, clave)
);

-- Un solo default por (proyecto, tipo). Clon del de `plantilla_cuentas` y por el
-- mismo motivo: trigger y no índice único parcial, que no sirve para
-- `ON CONFLICT` (42P10).
create or replace function public.un_solo_default_por_proyecto()
returns trigger language plpgsql security invoker
set search_path = ''
as $$
begin
  if new.es_default then
    update public.proyecto_cuentas
       set es_default = false
     where proyecto_id = new.proyecto_id and slug = new.slug
       and clave <> new.clave and es_default;
  end if;
  new.actualizado_en  := now();
  new.actualizado_por := auth.uid();
  return new;
end $$;

create trigger trg_un_solo_default_proyecto
  before insert or update on public.proyecto_cuentas
  for each row execute function public.un_solo_default_por_proyecto();

-- RLS y privilegios EN LA MISMA MIGRACIÓN, no descubiertos después: las tres
-- lecciones que costaron un ida y vuelta hace un rato en `plantilla_cuentas`.
alter table public.proyecto_cuentas enable row level security;

create policy "cuentas por proyecto: solo con sesion"
  on public.proyecto_cuentas for select to authenticated using (true);

create policy "cuentas por proyecto: solo super admin escribe"
  on public.proyecto_cuentas for all to authenticated
  using (es_super_admin()) with check (es_super_admin());

-- 1) `anon` sin GRANT: así un GET anónimo da 401 y no un `[]` indistinguible de
--    «tabla vacía». El 401 no lo da la policy, lo da la ausencia de grant.
revoke all on table public.proyecto_cuentas from anon;
-- 2) `authenticated` solo con lo que el panel usa: la tabla nace con el
--    `grant all` por defecto de Supabase, TRUNCATE incluido.
revoke all on table public.proyecto_cuentas from authenticated;
grant select, insert, update, delete on table public.proyecto_cuentas to authenticated;;
