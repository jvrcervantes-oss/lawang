-- DAR DE ALTA UN COMPRADOR VUELVE A FUNCIONAR. 11-sep-2026, reportado por el owner:
-- "Hay gente que no puede dar de alta COMPRADORES".
--
-- No era "gente": medido usuario por usuario, **18 de las 21 personas con la herramienta
-- `compradores` no podian crear una ficha**. Solo podian los 3 admin. Los 7 gestores
-- (sales_manager / project_manager) y los 11 agentes, no.
--
-- SON DOS FALLOS QUE SE SUMAN, y por eso hacen falta las dos mitades:
--
-- (1) EL PANEL NUNCA PONE DUENO. `intranet/compradores/index.html` construye `fila` sin
--     `propietario`, la columna no tiene default y no habia trigger: toda ficha nueva nacia
--     con `propietario = NULL`. Y `cliente_visible(NULL, id)` devuelve false para quien no
--     sea admin, porque `coalesce(NULL = auth.email(), false)` es false. Esto es lo que
--     tumbaba a los 11 agentes.
--
-- (2) LA RAMA DEL GESTOR SUSTITUIA EN VEZ DE SUMAR. `cliente_visible` era un `case`: si eres
--     gestor, ves los clientes que cuelgan de un contrato de tu proyecto — y NADA MAS, ni
--     siquiera los tuyos. Un comprador recien creado todavia no tiene contrato, asi que el
--     gestor no podia ver el que acababa de crear. Esto tumbaba a los 7 gestores incluso
--     cuando el dueno venia puesto.
--
-- POR QUE FALLABA EL ALTA Y NO SOLO LA LECTURA, que es lo que despista: el panel hace
-- `insert(fila).select().single()`, y un `INSERT ... RETURNING` **tambien aplica la politica
-- de SELECT** sobre la fila nueva. Si no la puedes leer, el statement entero falla. Postgres
-- lo reporta como «new row violates row-level security policy», que suena a permiso de
-- escritura y manda a mirar donde no es. Comprobado separando los dos casos: el mismo insert
-- SIN `returning` pasa, y CON `returning` falla.
--
-- (1) se arregla con TRIGGER y no con `default`: un default solo salta cuando la columna se
-- omite, y no protege del insert que manda NULL explicito. Se pone en la base y no en el
-- panel a proposito — «el dato tiene un dueno», fuente unica: asi vale para todos los
-- caminos de alta (panel, app de contratos, lo que venga) y no hay que acordarse en cada uno.
create or replace function public.clients_pone_dueno() returns trigger
language plpgsql security definer set search_path to ''
as $$
begin
  -- `nullif(btrim(...),'')` y no solo `is null`: una cadena vacia deja la ficha igual de
  -- huerfana que un NULL, y es lo que manda un formulario con el campo en blanco.
  new.propietario := coalesce(nullif(btrim(new.propietario), ''), (select auth.email()));
  return new;
end $$;

-- destructivo-ok: el DROP es de un trigger que no existe todavia; es la forma idempotente de
-- crearlo (patron `drop if exists` + `create`). No borra datos ni toca ninguna fila.
drop trigger if exists trg_clients_pone_dueno on public.clients;
create trigger trg_clients_pone_dueno
  before insert on public.clients
  for each row execute function public.clients_pone_dueno();

-- (2) La regla pasa a SUMAR, que es la forma que ya usan todas las hermanas de la suite
-- (`contratos`, `facturas`, `contrato_firmas`, `recibi_aplicaciones`, `solicitudes_pago`
-- usan todas `es_suyo(creado_por) OR es_manager_de(proyecto_id)`). `clients` era la unica
-- con la forma excluyente — comprobado, no supuesto: es la unica funcion del esquema que
-- menciona `es_gestor()`.
-- Lo unico que ensancha es "lo mio tambien es mio" para el gestor. Un agente normal no gana
-- visibilidad ninguna: su rama era ya esa y no cambia.
create or replace function public.cliente_visible(p_propietario text, p_client_id uuid)
returns boolean language sql stable security definer set search_path to ''
as $$
  select public.es_admin()
      or coalesce(p_propietario = (select auth.email()), false)
      or (public.es_gestor() and exists (
            select 1
              from public.contrato_compradores cc
              join public.contratos c on c.id = cc.contrato_id
             where cc.client_id = p_client_id
               and public.es_manager_de(c.proyecto_id)));
$$;

-- VERIFICADO antes de aplicar, con las 21 identidades reales y el insert exacto que manda el
-- panel, revirtiendo todo (patron LAW-51):
--   1. alta tal cual el panel .......... pueden 21 / no pueden 0   (antes: 3 / 18)
--   2. un agente ve 0 fichas ajenas .... sin regresion
--   3. un gestor sigue viendo un cliente ajeno de su proyecto .... sin regresion
--
-- QUEDA ABIERTO, y NO se toca aqui porque es decision del owner:
--   · 52 de las 171 fichas (28-jul a 3-sep) tienen `propietario` vacio de antes de este
--     trigger. Hoy solo las ve direccion. Rellenarlas es un UPDATE masivo sobre datos reales
--     de cliente -> LAW-180.
--   · La politica de UPDATE de `clients` sigue siendo solo `es_admin()`: las mismas 18
--     personas pueden ahora CREAR una ficha pero no CORREGIRLA. Puede ser intencionado (KYC),
--     asi que no se ensancha por iniciativa propia -> LAW-181.
--   · La policy de INSERT es `es_agente()` a secas, sin `puede('compradores')`: 3 usuarios
--     activos sin la herramienta podrian insertar igual. Es ANTERIOR a este cambio, salio al
--     revisarlo -> LAW-182.
