-- La clave de una sociedad: RECHAZAR, no ajustar en silencio.
--
-- La primera version hacia `new.clave := old.clave`, asi que un intento de
-- renombrarla no fallaba: simplemente no pasaba nada, y el log registraba un
-- update sin cambios. El estandar de Seguridad en esta suite es rechazar, nunca
-- ajustar por debajo — un guardado que dice que fue bien y no hizo lo que se le
-- pidio es peor que un error.
create or replace function public._sociedades_autoria() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.clave is distinct from old.clave then
    raise exception 'La clave de una sociedad no se cambia: va dentro de cada contrato y cada factura ya emitidos. Da de alta otra si hace falta.';
  end if;
  new.actualizado_por := auth.email();
  new.actualizado_en := now();
  return new;
end; $$;

revoke execute on function public._sociedades_autoria() from anon, authenticated;
