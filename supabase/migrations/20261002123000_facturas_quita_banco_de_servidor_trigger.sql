-- AXW-45 (cierre del revisor, 2-oct-2026): factura_guarda ya quita `banco_de_servidor`, pero guardar_recibi guardaba
-- p_factura->'datos' tal cual y el recibi se imprime con la misma plantilla (documento.js bancoDocHTML). En vez de parchear
-- cada RPC que escribe facturas.datos, la tabla misma descarta la marca: en Lawang NINGUN camino la escribe (la cuenta se
-- resuelve en el navegador contra el catalogo y «otros» se ve en el editor). Solo Lawang: el ERP maestro la escribe
-- legitimamente desde el servidor (B1) y NO lleva este trigger.
create or replace function public.facturas_sin_banco_de_servidor()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if jsonb_typeof(new.datos->'fields') = 'object' and (new.datos->'fields') ? 'banco_de_servidor' then
    new.datos := jsonb_set(new.datos, '{fields}', (new.datos->'fields') - 'banco_de_servidor');
  end if;
  return new;
end $function$;

revoke all on function public.facturas_sin_banco_de_servidor() from public, anon, authenticated;

create trigger facturas_sin_banco_de_servidor
  before insert or update of datos on public.facturas
  for each row execute function public.facturas_sin_banco_de_servidor();
