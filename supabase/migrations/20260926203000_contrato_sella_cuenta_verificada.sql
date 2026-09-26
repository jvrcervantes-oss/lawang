-- LAW-342, cierre del hueco que marcó Seguridad (26-sep-2026, MEDIA): un contrato podía guardarse
-- apuntando a una cuenta aún NO verificada (el valor de `datos.fields.cuenta_bancaria` lo pone el
-- navegador); luego se cambiaba el número, se activaba, y el contrato reimprimía el número nuevo.
-- Ahora, en cuanto un contrato usa una cuenta, esa cuenta queda verificada (y con ello congelado lo
-- que imprime). Se sella en vez de rechazar: rechazar pararía el guardado de un contrato por una regla
-- de otra tabla, y sellar deja la misma garantía sin romper a nadie.
-- `sella_cuenta_bancaria` deja de apuntar como «último editor» a quien solo provocó el sello: si lo
-- único que cambia es `verificada_en`, se conservan `actualizado_en/por` (el log sí lo registra).
create or replace function public._contrato_sella_cuenta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_cl text := nullif(new.datos->'fields'->>'cuenta_bancaria', '');
begin
  if v_cl is not null and (tg_op = 'INSERT' or v_cl is distinct from nullif(old.datos->'fields'->>'cuenta_bancaria', '')) then
    update public.cuentas_bancarias set verificada_en = now() where clave = v_cl and verificada_en is null;
  end if;
  return null;
end $$;
revoke all on function public._contrato_sella_cuenta() from public, anon, authenticated;
create trigger trg_contrato_sella_cuenta after insert or update of datos on public.contratos
  for each row execute function public._contrato_sella_cuenta();

create or replace function public.sella_cuenta_bancaria() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'verificada_en' - 'actualizado_en' - 'actualizado_por')
                         = (to_jsonb(old) - 'verificada_en' - 'actualizado_en' - 'actualizado_por') then
    new.actualizado_en  := old.actualizado_en;
    new.actualizado_por := old.actualizado_por;
    return new;
  end if;
  new.actualizado_en  := now();
  new.actualizado_por := auth.uid();
  return new;
end $$;
