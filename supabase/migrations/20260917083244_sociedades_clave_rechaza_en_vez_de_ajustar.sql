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

revoke execute on function public._sociedades_autoria() from anon, authenticated;;
