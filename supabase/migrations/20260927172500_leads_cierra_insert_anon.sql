-- destructivo-ok: retira el INSERT directo de anon en `leads` y su policy `with check (true)`; no toca filas.
-- APLICAR tras publicar SumbaHills/api/lead.php, que da de alta por lead_publico_alta (20260927172000).
-- Con esto authenticated/anon no escriben directo en NINGUNA tabla de la base de Lawang.
revoke insert on public.leads from anon, authenticated;
drop policy if exists "anon can insert leads" on public.leads;
do $$
begin
  if has_table_privilege('anon', 'public.leads', 'INSERT') or has_table_privilege('authenticated', 'public.leads', 'INSERT') then
    raise exception 'leads: sigue habiendo INSERT directo';
  end if;
end $$;
