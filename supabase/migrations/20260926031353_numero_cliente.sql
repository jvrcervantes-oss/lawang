-- Aplicada por MCP el 26-sep-2026 (versión 20260926031353). Copia literal de erp/migraciones/20260926120000_numero_cliente.sql
-- (allí el porqué completo: revisión previa #104, Datos).
-- Por qué: el único identificador de un comprador era su uuid, que nadie puede dictar ni poner en una transferencia;
-- el nombre no sirve (Lawang: 4 repetidos en 203 fichas, sociedades como compradoras, fichas compartidas entre closers).
-- Un número por cliente, nunca por proyecto ni por año: el mismo comprador en dos proyectos sigue siendo UN cliente.
--
-- Revisión previa #104 (Datos), cada punto con su porqué:
--   1. Orden: columna → relleno en UNA sentencia → setval → not null + unique → triggers AL FINAL. Con el trigger
--      de «no se cambia» puesto antes, el paso de null a CLI-00001 cuenta como cambio y el relleno no entra.
--   2. El número lo pone SIEMPRE la base (BEFORE INSERT, nextval): lo que mande una pantalla o un import se ignora.
--   3. Cambiarlo no da error, se ignora en silencio (BEFORE UPDATE, new := old): `authenticated` tiene UPDATE sobre
--      toda la tabla y `resolver_solicitud_cambio` aplica cambios genéricos por clave; un `raise` haría que un
--      formulario que manda el campo vacío ya no pudiera guardar la ficha.
--   4. La secuencia no es de nadie más: el ACL por defecto de public da `w` (setval) a authenticated/anon. El
--      trigger es SECURITY DEFINER, así numera aunque quien inserta no tenga permiso sobre ella.
--   5. La factura NO lo copia: lo lee por client_id (FK sin cascada: un cliente con facturas no se borra, y el
--      número no cambia nunca por el punto 3). Una copia sería un segundo dueño del mismo dato.
-- Avisos aceptados: un insert que falla gasta un número (habrá huecos: no es un número fiscal). El orden del relleno
-- es el de alta EN LA SUITE (created_at, desempate por id), no la antigüedad comercial del cliente.
-- Solo añade: ningún drop, ningún dato existente se reescribe (el relleno escribe una columna recién creada).

alter table public.clients add column numero_cliente text;

create sequence public.clients_numero_cliente_seq as bigint start with 1;
revoke all on sequence public.clients_numero_cliente_seq from public, anon, authenticated;

with orden as (
  select id, row_number() over (order by created_at nulls last, id) as n from public.clients
)
update public.clients c set numero_cliente = 'CLI-' || lpad(o.n::text, 5, '0')
  from orden o where o.id = c.id;

-- is_called = false con 0 filas: el primero será 1; con N filas, el siguiente será N+1.
select setval('public.clients_numero_cliente_seq', greatest((select count(*) from public.clients), 1),
              (select count(*) from public.clients) > 0);

alter table public.clients alter column numero_cliente set not null;
alter table public.clients add constraint clients_numero_cliente_key unique (numero_cliente);

create function public.clients_numero_cliente() returns trigger
  language plpgsql security definer set search_path to ''
  as $$
begin
  if tg_op = 'INSERT' then
    new.numero_cliente := 'CLI-' || lpad(nextval('public.clients_numero_cliente_seq')::text, 5, '0');
  else
    new.numero_cliente := old.numero_cliente;
  end if;
  return new;
end $$;
revoke all on function public.clients_numero_cliente() from public, anon, authenticated;

create trigger trg_clients_numero_cliente before insert or update of numero_cliente on public.clients
  for each row execute function public.clients_numero_cliente();

-- El directorio (`compradores_directorio()`) no se toca: cambiar lo que devuelve exige borrarla y recrearla. Los
-- números de TODAS las fichas salen de aquí, con la misma puerta (es_agente) y sin ningún otro dato del cliente.
create function public.compradores_numeros() returns table (id uuid, numero_cliente text)
  language sql stable security definer set search_path to ''
  as $$ select c.id, c.numero_cliente from public.clients c where public.es_agente() $$;
revoke all on function public.compradores_numeros() from public, anon;
grant execute on function public.compradores_numeros() to authenticated, service_role;
