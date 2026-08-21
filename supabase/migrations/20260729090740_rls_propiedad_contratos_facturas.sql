-- Propiedad del documento: quien lo crea es quien lo edita. Un admin puede
-- editar cualquiera (alguien tiene que poder desatascar).
-- Se mantienen los guardas que ya había (bloqueado / anulada) y se añade
-- `puede(...)`: quitarle la herramienta a alguien deja de ser solo cosmético.
-- Las LECTURAS siguen en es_agente() a propósito: Operaciones cruza contratos,
-- facturas y firmas, y filtrar lecturas por herramienta la dejaría vacía.
drop policy if exists "agentes autenticados actualizan contratos no bloqueados" on public.contratos;
create policy "el autor o un admin editan contratos no bloqueados" on public.contratos
  for update to authenticated
  using (bloqueado = false and public.es_agente() and public.puede('contratos') and public.es_suyo(creado_por))
  with check (public.es_agente() and public.puede('contratos'));

drop policy if exists "agentes autenticados insertan contratos" on public.contratos;
create policy "agentes con la herramienta insertan contratos" on public.contratos
  for insert to authenticated
  with check (public.es_agente() and public.puede('contratos'));

drop policy if exists "agentes autenticados actualizan facturas no anuladas" on public.facturas;
create policy "el autor o un admin editan facturas no anuladas" on public.facturas
  for update to authenticated
  using (anulada = false and public.es_agente() and public.puede('facturas') and public.es_suyo(creado_por))
  with check (public.es_agente() and public.puede('facturas'));

drop policy if exists "agentes autenticados insertan facturas" on public.facturas;
create policy "agentes con la herramienta insertan facturas" on public.facturas
  for insert to authenticated
  with check (public.es_agente() and public.puede('facturas'));

-- Unidades y fichas de comprador: escritura por herramienta (no hay autoría
-- por fila — son inventario y personas compartidas, no documentos de alguien).
drop policy if exists "agentes actualizan unidades" on public.unidades;
create policy "agentes con la herramienta actualizan unidades" on public.unidades
  for update to authenticated using (public.es_agente() and public.puede('unidades'))
  with check (public.es_agente() and public.puede('unidades'));
drop policy if exists "agentes crean unidades" on public.unidades;
create policy "agentes con la herramienta crean unidades" on public.unidades
  for insert to authenticated with check (public.es_agente() and public.puede('unidades'));;
