create or replace function public.trg_guarda_antes_de_borrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quien text := (select auth.email());
begin
  insert into public.borrados (tabla, fila_id, numero, fila, quien)
  values (tg_table_name, old.id,
          case when to_jsonb(old) ? 'numero' then to_jsonb(old)->>'numero' end,
          to_jsonb(old), v_quien);

  if tg_table_name = 'facturas' then
    if exists (select 1 from public.recibi_aplicaciones ra
                where ra.factura_id = old.id or ra.recibi_id = old.id) then
      if not public.es_super_admin() then
        raise exception 'esta factura tiene cobros aplicados: solo un super admin puede borrarla, y se lleva sus aplicaciones'
          using errcode = '23503';
      end if;
      insert into public.borrados (tabla, fila_id, numero, fila, quien)
      select 'recibi_aplicaciones', ra.id, null, to_jsonb(ra), v_quien
        from public.recibi_aplicaciones ra
       where ra.factura_id = old.id or ra.recibi_id = old.id;
      delete from public.recibi_aplicaciones ra
       where ra.factura_id = old.id or ra.recibi_id = old.id;
    end if;
  end if;

  return old;
end $$;;
