create or replace function public.contrato_no_editable_en_firma()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  n_vivas    int;
  n_firmadas int;
begin
  if new.datos is not distinct from old.datos then
    return new;
  end if;

  select count(*) filter (where cf.estado = 'pendiente'),
         count(*) filter (where cf.estado = 'firmado')
    into n_vivas, n_firmadas
    from public.contrato_firmas cf
   where cf.contrato_id = new.id;

  if coalesce(n_vivas, 0) = 0 and coalesce(n_firmadas, 0) = 0 then
    return new;
  end if;

  raise exception
    'Este contrato esta enviado a firma (% enlace(s) sin usar, % firma(s) ya recogida(s)) y no se puede editar. Para cambiarlo hay que anular la firma: al guardar, la app te lo ofrece. Anular invalida lo ya firmado y el comprador tendra que firmar de nuevo.',
    coalesce(n_vivas, 0), coalesce(n_firmadas, 0)
    using errcode = '23514';
end $$;

drop trigger if exists trg_contrato_no_editable_en_firma on public.contratos;
create trigger trg_contrato_no_editable_en_firma
  before update on public.contratos
  for each row execute function public.contrato_no_editable_en_firma();;
