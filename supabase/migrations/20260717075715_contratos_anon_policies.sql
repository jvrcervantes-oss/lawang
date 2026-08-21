-- La app de contratos no tiene login propio (herramienta interna sin auth aún) —
-- se autoriza a anon insertar/leer/actualizar para que app.html pueda guardar y
-- listar contratos con la publishable key. Sin política de DELETE (nadie borra
-- desde el cliente). Ojo: esto expone datos.jsonb (incluye pasaporte, domicilio)
-- a quien tenga la key pública — aceptable mientras la herramienta sea interna,
-- revisar antes de un uso con datos reales de cliente a gran escala.
create policy "anon puede insertar contratos" on public.contratos
  for insert to anon with check (true);

create policy "anon puede leer contratos" on public.contratos
  for select to anon using (true);

create policy "anon puede actualizar contratos" on public.contratos
  for update to anon using (true) with check (true);;
