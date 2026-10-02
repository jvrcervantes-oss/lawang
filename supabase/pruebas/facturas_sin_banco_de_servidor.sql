-- Prueba negativa de AXW-45 (2-oct-2026). Se corre como postgres sobre la base viva y se deshace sola (termina en excepcion).
-- Esperado: el mensaje final dice flag=f. Si dice flag=t, la marca llega al papel y un agente puede imprimir su propio IBAN.
do $$
declare i uuid; got jsonb;
begin
  select id into i from public.facturas where tipo = 'recibi' limit 1;
  if i is null then select id into i from public.facturas limit 1; end if;
  update public.facturas
     set datos = jsonb_set(coalesce(datos, '{}'::jsonb), '{fields}',
                           coalesce(datos->'fields', '{}'::jsonb) || '{"banco_de_servidor":true,"banco_cuenta":"X"}'::jsonb)
   where id = i;
  select datos->'fields' into got from public.facturas where id = i;
  raise exception 'RESULTADO(rollback): flag=% (esperado f)', got ? 'banco_de_servidor';
end $$;
