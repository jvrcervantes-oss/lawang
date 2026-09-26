-- destructivo-ok: retira todos los permisos de anon/authenticated sobre `leads` y la policy `with check (true)`; no toca filas.
-- APLICAR tras publicar SumbaHills/api/lead.php que da de alta por lead_publico_alta (20260927172000) y comprobar que
-- entra una fila con su lead_estado. Nada del cliente lee `leads` directamente (CRM e intranet van por RPC; Fathom,
-- trazabilidad-ghl y el panel usan service_role): fuera también SELECT/UPDATE/DELETE (Seguridad, 27-sep: el grant es
-- lo que abre la puerta el día que alguien añada una policy permisiva).
revoke all on public.leads from anon, authenticated;
drop policy if exists "anon can insert leads" on public.leads;
do $$
begin
  if has_table_privilege('anon', 'public.leads', 'INSERT') or has_table_privilege('authenticated', 'public.leads', 'INSERT')
     or has_table_privilege('anon', 'public.leads', 'SELECT') or has_table_privilege('authenticated', 'public.leads', 'SELECT') then
    raise exception 'leads: quedan permisos para anon/authenticated';
  end if;
  if not has_function_privilege('anon', 'public.lead_publico_alta(text, text, text, text, text, text)', 'EXECUTE') then
    raise exception 'leads: el formulario público perdería su única puerta (lead_publico_alta)';
  end if;
end $$;
