drop policy if exists "el autor o un admin editan contratos no bloqueados" on public.contratos;
create policy "el autor o un admin editan contratos no bloqueados" on public.contratos
  for update
  using (
    public.es_super_admin()
    or ((bloqueado = false) and public.es_agente() and public.puede('contratos')
        and public.es_suyo(creado_por) and public.puede_proyecto_de(datos, proyecto_nombre))
  )
  with check (
    public.es_super_admin()
    or (public.es_agente() and public.puede('contratos') and public.puede_proyecto_de(datos, proyecto_nombre))
  );

create or replace function public.trg_registra_edicion_privilegiada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(old.bloqueado, false) then
    perform public.registra_privilegio(new.id,
      case when coalesce(new.bloqueado, false) then 'editado_estando_firmado' else 'desbloqueado' end,
      jsonb_build_object('numero', old.numero, 'bloqueado_antes', old.bloqueado,
                         'bloqueado_despues', new.bloqueado));
  end if;
  return new;
end $$;

drop trigger if exists trg_registra_edicion_privilegiada on public.contratos;
create trigger trg_registra_edicion_privilegiada after update on public.contratos
  for each row when (coalesce(old.bloqueado, false)) execute function public.trg_registra_edicion_privilegiada();

drop policy if exists "borrar facturas" on public.facturas;
create policy "borrar facturas" on public.facturas
  for delete using (
    public.es_super_admin()
    or (public.es_admin()
        and coalesce(anulada, false) = false
        and not exists (select 1 from public.recibi_aplicaciones ra
                         where ra.factura_id = facturas.id or ra.recibi_id = facturas.id))
  );;
