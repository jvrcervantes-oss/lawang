-- ============================================================================
-- Rastro que Legal pidió el 19-sep-2026 (revisión previa #27 del encargo de
-- paridad v4) y que no se llegó a aplicar — verificado contra la base el
-- 23-sep: `borrar_comprador()` no escribía en `borrados`, y `sociedades` no
-- sabía quién dio de alta una entidad emisora.
-- ----------------------------------------------------------------------------
-- 1) Ficha de comprador y documentos KYC borrados → `borrados`.
--    Motivo (Legal): RGPD art. 5.2/30 y UU PDP — hay que poder demostrar qué
--    se borró, cuándo y quién; conservación fiscal/AML. En vez de tocar
--    `borrar_comprador()`, se cuelga de `clients` y `documents` el MISMO
--    trigger genérico que ya guardan contratos, facturas, comisiones y
--    solicitudes (`trg_guarda_antes_de_borrar`): así queda también el
--    borrado suelto de un documento KYC desde la pantalla, que Legal pedía
--    aparte, y cualquier camino futuro. `borrados` solo lo lee el super admin
--    (policy «super admin lee borrados»): la copia de la ficha no se abre a
--    nadie más.
-- 2) `sociedades`: `creado_por` y alta en el registro.
--    La columna la fija el trigger en cada alta con `auth.email()` — no el
--    navegador: el INSERT de `authenticated` es de tabla y un valor enviado
--    a mano se podría falsear. El registro (`sociedades_log`) cubría UPDATE y
--    DELETE; ahora también INSERT (accion='insert', `antes` = la fila nueva).
-- Sin DROP: `create or replace trigger` (PG14+).
-- ============================================================================

create or replace trigger trg_guarda_antes_de_borrar
  before delete on public.clients
  for each row execute function public.trg_guarda_antes_de_borrar();

create or replace trigger trg_guarda_antes_de_borrar
  before delete on public.documents
  for each row execute function public.trg_guarda_antes_de_borrar();

alter table public.sociedades add column if not exists creado_por text;

-- El registro solo admitía 'update'|'delete' (CHECK): se AMPLÍA a 'insert'.
-- Cazado ensayando esta migración con ROLLBACK antes de aplicarla — habría
-- reventado la primera alta de sociedad.
-- destructivo-ok: se sustituye un CHECK por otro más ancho; ninguna fila se toca
alter table public.sociedades_log drop constraint if exists sociedades_log_accion_check;
alter table public.sociedades_log add constraint sociedades_log_accion_check
  check (accion = any (array['insert'::text, 'update'::text, 'delete'::text]));

create or replace function public._sociedades_log()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    new.creado_por := (select auth.email());
    insert into public.sociedades_log (clave, antes, accion)
    values (new.clave, to_jsonb(new), 'insert');
    return new;
  end if;
  insert into public.sociedades_log (clave, antes, accion)
  values (old.clave, to_jsonb(old), lower(tg_op));
  return case when tg_op = 'DELETE' then old else new end;
end; $function$;

create or replace trigger trg_sociedades_log
  before insert or update or delete on public.sociedades
  for each row execute function public._sociedades_log();
