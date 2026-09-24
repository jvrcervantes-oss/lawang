-- CUENTAS PROPIAS FRENTE A CUENTAS DE TERCEROS (24-sep-2026, LAW-305, owner: «a»).
-- cuentas_bancarias mezcla cuentas de la sociedad con las del contratista, los
-- vendedores de suelo y los notarios (donde paga el comprador). Lo que entra en
-- una cuenta de un tercero no es caja de la sociedad. null = SIN MARCAR (lo
-- marca el owner en Cuentas); true = de la sociedad; false = de un tercero.
-- Una cuenta de escrow es de un tercero por definición, la marque o no.
-- Sin GRANT nuevo: `authenticated` tiene UPDATE a nivel de tabla y la policy
-- de escritura sigue siendo es_super_admin().
alter table public.cuentas_bancarias add column if not exists es_propia boolean;
comment on column public.cuentas_bancarias.es_propia is
  'true = cuenta de la sociedad (su caja); false = de un tercero (contratista, vendedor de suelo, notario); null = sin marcar. Lo lee Finanzas para separar la caja real.';

-- Un gasto solo se paga desde una cuenta marcada como PROPIA (y nunca escrow).
-- La comprobación corre solo cuando la cuenta del gasto CAMBIA: re-marcar una
-- cuenta después no bloquea la edición de gastos antiguos.
create or replace function public._gastos_antes()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_escrow boolean; v_propia boolean;
begin
  if tg_op = 'UPDATE' then
    if old.estado = 'anulado' then
      raise exception 'Este gasto está anulado: ya no se puede modificar.' using errcode = '23514';
    end if;
    new.creado_por := old.creado_por;
    new.creado_en  := old.creado_en;
    new.actualizado_por := (select auth.uid());
    new.actualizado_en  := now();
  else
    new.creado_por := coalesce((select auth.uid()), new.creado_por);
    new.creado_en  := now();
    new.actualizado_por := null;
    new.actualizado_en  := null;
  end if;
  if new.cuenta_pago is not null and (tg_op = 'INSERT' or new.cuenta_pago is distinct from old.cuenta_pago) then
    select es_escrow, es_propia into v_escrow, v_propia from public.cuentas_bancarias where clave = new.cuenta_pago;
    if coalesce(v_escrow, false) then
      raise exception 'No se paga un gasto desde una cuenta de depósito en garantía (escrow): ese dinero no es de la sociedad.' using errcode = '23514';
    end if;
    if v_propia is distinct from true then
      raise exception 'Solo se paga un gasto desde una cuenta marcada como propia de la sociedad (Cuentas → editar la cuenta).' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
revoke all on function public._gastos_antes() from public, anon, authenticated;
