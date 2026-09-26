-- LAW-342 (26-sep-2026, decisión del owner «bloquear y registrar», tras Legal MEDIA + Seguridad en la
-- consulta de deploy de LAW-336 pieza 4).
-- EL PROBLEMA: los contratos leen la cuenta VIVA al reabrirse o reimprimirse. Cambiar el número, el
-- titular, el banco o el Swift de una cuenta en uso hace que un contrato firmado salga con otro destino
-- de pago del que firmó el comprador — la vía clásica de fraude por transferencia, y un problema de
-- prueba en un litigio. Y no quedaba rastro: `cuentas_bancarias` solo guardaba el último editor.
-- LA REGLA: una cuenta queda VERIFICADA la primera vez que se activa (`verificada_en`), y desde ahí sus
-- datos bancarios no cambian: para otro número, otra cuenta con otra clave. Mientras nunca se activó
-- se corrige libremente — para eso nace desactivada (se comprueba con el justificante y luego se activa).
-- Por qué «activada alguna vez» y no «sale en contratos»: las plantillas de Bonian C2 imprimen cuentas
-- fijas (`<!--cuenta:CLAVE-->`) que no quedan anotadas en el contrato, así que contar contratos se las
-- saltaría; y una lista a mano de esas claves envejecería en silencio.
-- Va en un TRIGGER, no solo en la RPC: vale para cualquier camino que escriba (RPC, service_role, SQL).
-- `direccion`, `label`, la nota, `activa`, `es_escrow`, `es_propia` y `orden` siguen editables.
-- HISTORIAL: cuentas_bancarias_log, como sociedades_log: una fila por alta/cambio/borrado con el antes y
-- el después, quién y cuándo. Solo la lee un super admin; nadie la escribe salvo el trigger.

alter table public.cuentas_bancarias add column if not exists verificada_en timestamptz;
comment on column public.cuentas_bancarias.verificada_en is
  'Primera activación. Desde entonces cuenta/titular/banco/codigo no cambian (LAW-342): otra cuenta, otra clave.';

-- Relleno: las activas hoy, y cualquiera que ya salga en un contrato, cuentan como verificadas.
-- Sin el trigger de sello: si no, `actualizado_por/en` perderían al último editor real.
alter table public.cuentas_bancarias disable trigger trg_sella_cuenta;
update public.cuentas_bancarias c set verificada_en = coalesce(c.actualizado_en, c.creado_en)
 where c.verificada_en is null
   and (c.activa or exists (select 1 from public.contratos ct where ct.datos->'fields'->>'cuenta_bancaria' = c.clave));
alter table public.cuentas_bancarias enable trigger trg_sella_cuenta;

create or replace function public._cuenta_bancaria_blinda() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.verificada_en := coalesce(old.verificada_en, new.verificada_en);   -- no se borra nunca
    if new.clave is distinct from old.clave then
      raise exception 'La clave de una cuenta no se cambia: va dentro de cada contrato y factura emitidos' using errcode = '42501';
    end if;
    if old.verificada_en is not null and (
         new.cuenta  is distinct from old.cuenta  or new.titular is distinct from old.titular or
         new.banco   is distinct from old.banco   or new.codigo  is distinct from old.codigo) then
      raise exception 'Esta cuenta ya se ha usado (verificada el %): su número, titular, banco y Swift no se cambian, porque los contratos firmados la reimprimen. Crea una cuenta nueva con otra clave y cámbiala en el reparto.',
        to_char(old.verificada_en, 'DD-MM-YYYY') using errcode = '42501';
    end if;
  end if;
  if new.activa and new.verificada_en is null then new.verificada_en := now(); end if;
  return new;
end $$;
create trigger trg_cuenta_blinda before insert or update on public.cuentas_bancarias
  for each row execute function public._cuenta_bancaria_blinda();

create table if not exists public.cuentas_bancarias_log (
  id bigint generated always as identity primary key,
  clave text not null,
  accion text not null,
  antes jsonb,
  despues jsonb,
  quien text,
  quien_id uuid,
  cuando timestamptz not null default now()
);
alter table public.cuentas_bancarias_log enable row level security;
revoke all on public.cuentas_bancarias_log from anon, authenticated;
grant select on public.cuentas_bancarias_log to authenticated;
create policy "cuentas_log: leer solo super" on public.cuentas_bancarias_log for select to authenticated
  using ((select public.es_super_admin()));
create index if not exists cuentas_bancarias_log_clave on public.cuentas_bancarias_log (clave, cuando desc);

create or replace function public._cuentas_bancarias_log() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.cuentas_bancarias_log (clave, accion, antes, despues, quien, quien_id)
  values (coalesce(new.clave, old.clave), lower(tg_op),
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          (select auth.email()), (select auth.uid()));
  return null;
end $$;
revoke all on function public._cuentas_bancarias_log() from public, anon, authenticated;
create trigger trg_cuentas_log after insert or update or delete on public.cuentas_bancarias
  for each row execute function public._cuentas_bancarias_log();
