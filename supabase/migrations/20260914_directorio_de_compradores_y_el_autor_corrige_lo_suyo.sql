-- ============================================================================
-- 14-sep-2026 — Dar de alta un comprador volvía a ser un callejón sin salida
-- ----------------------------------------------------------------------------
-- Desde el 11-sep (`20260911031517_equipo_deja_de_saltarse_la_rls`) la RLS de
-- `clients` es «cada uno ve lo que dio de alta». Con 178 fichas repartidas así:
--
--     hello@lawangproperties.com  74   ·  sales@lawangproperties.com  22
--     (sin dueño)                 20   ·  las otras 13 personas      4-14
--
-- un agente ve entre 1 y 14 de 178. Antes buscaba al comprador en la lista y lo
-- reutilizaba; ahora la búsqueda le sale vacía, CREA LA FICHA OTRA VEZ, y la
-- base la rechaza contra una fila que él no puede ver. Ni la encuentra, ni la
-- reutiliza, ni la crea.
--
-- Medido en los logs de Postgres de las 24h previas: 17 altas rechazadas, todas
-- en 18 minutos (02:13-02:31 del 14-sep) — 14 contra `clients_pasaporte_uniq` y
-- 3 contra `clients_email_tipo_key`. Una persona sola, atascada, reintentando.
--
-- Decisión del owner (14-sep): el DIRECTORIO de compradores se abre a todo el
-- equipo — quién es quién, sus datos de identidad — y lo que es del negocio de
-- cada uno (contratos, facturas, cobros, estado de cuentas) NO se toca. Eso
-- último ya estaba bien desde el 11-sep: `clients` no tiene ni una columna de
-- dinero, el dinero vive en `contratos`/`facturas` y sigue filtrado por autor.
--
-- Lo que NO entra en el directorio, y por qué:
--   · `notes` — texto libre comercial («ofrecerle el descuento», «viene de X»).
--     Es la conversación de un agente con SU cliente, no un dato de identidad.
--   · la ficha completa. El directorio dice QUIÉN EXISTE; abrir la ficha,
--     subirle documentos o editarla sigue siendo del autor / manager / admin.
--
-- Se expone `propietario` a propósito: sin él, el agente que choca sabe que la
-- ficha existe pero no a quién pedirle el traspaso, y el callejón sin salida
-- vuelve un piso más arriba.
--
-- RPC y no VISTA a propósito: una vista es justo el objeto que alguien
-- «mejora» con CREATE OR REPLACE, y eso resetea `security_invoker` — ya ha
-- pasado tres veces con `unidades_estado` (10-ago, 2-sep, 11-sep). Columnas
-- escritas una a una y nunca `c.*`: un `*` congela la forma de la tabla del día
-- que se escribió y deja de contar las columnas nuevas.
-- ============================================================================

create or replace function public.compradores_directorio()
returns table (
  id              uuid,
  full_name       text,
  tipo            text,
  email           text,
  phone           text,
  nationality     text,
  passport_number text,
  date_of_birth   date,
  address         text,
  forma_juridica  text,
  registro_num    text,
  rep_nombre      text,
  rep_cargo       text,
  kyc_status      text,
  propietario     text,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path to ''
as $function$
  select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality,
         c.passport_number, c.date_of_birth, c.address,
         c.forma_juridica, c.registro_num, c.rep_nombre, c.rep_cargo,
         c.kyc_status, c.propietario, c.created_at
    from public.clients c
   where public.es_agente()
$function$;

comment on function public.compradores_directorio() is
  'Directorio de identidad de TODOS los compradores, para cualquiera del equipo '
  '(14-sep-2026). No incluye `notes`. Abrir la ficha, editarla o subirle '
  'documentos sigue mandándolo la RLS de `clients`.';

-- `anon` fuera: la función es DEFINER y sin esto la sirve PostgREST sin sesión
-- (mismo gotcha que ya costó una auditoría el 11-ago).
revoke execute on function public.compradores_directorio() from public, anon;
grant  execute on function public.compradores_directorio() to authenticated;


-- ----------------------------------------------------------------------------
-- El autor corrige la ficha que él mismo dio de alta
-- ----------------------------------------------------------------------------
-- Editar una ficha era solo de admin desde el 7-ago (`clients_solo_admin_edita`).
-- Consecuencia que nadie midió: el agente que se equivoca al teclear el correo
-- al CREARLA no puede corregirlo — y el formulario, que sí le deja crear, le
-- devolvía «tu sesión ha caducado» (PGRST116 = 0 filas tras el update), que es
-- falso y manda a buscar el fallo donde no está.
--
-- Decisión del owner (14-sep): sí, la suya, y solo mientras no haya un contrato
-- FIRMADO colgando de ella. Mismo criterio que ya rige los contratos: firmado
-- es inmutable, porque el pasaporte y el domicilio de esa ficha están impresos
-- dentro del documento que el comprador ya firmó.
--
-- `es_suyo(NULL)` es false salvo para admin, así que las 20 fichas sin dueño
-- NO se abren con esto: siguen siendo de admin. Se deja a propósito — ponerles
-- un autor a mano sería inventar una autoría que nadie puede reconstruir.

create or replace function public.cliente_con_contrato_firmado(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.contrato_compradores cc
      join public.contratos c on c.id = cc.contrato_id
     where cc.client_id = p_client_id
       and coalesce(c.bloqueado, false)
  )
$function$;

comment on function public.cliente_con_contrato_firmado(uuid) is
  'true si esta ficha de comprador cuelga de algún contrato ya firmado '
  '(`bloqueado`). DEFINER a propósito: la pregunta es del sistema, no del que '
  'mira — si pasara por la RLS del que mira, el contrato firmado por un '
  'compañero no contaría y la ficha se podría editar por debajo.';

revoke execute on function public.cliente_con_contrato_firmado(uuid) from public, anon;
grant  execute on function public.cliente_con_contrato_firmado(uuid) to authenticated;

-- Sin `drop policy if exists` delante a propósito: `tools/no_destruir.py` lo
-- para (y hace bien — no distingue un DROP de limpieza de uno de verdad), y la
-- policy no existía. Si algún día hay que reescribirla, se borra a mano en una
-- pasada aparte y declarada.
create policy "el autor corrige su ficha mientras no este firmada"
  on public.clients for update to authenticated
  using (
    public.es_agente()
    and public.es_suyo(propietario)
    and not public.cliente_con_contrato_firmado(id)
  )
  with check (
    public.es_agente()
    and public.es_suyo(propietario)
    and not public.cliente_con_contrato_firmado(id)
  );

-- El WITH CHECK repite el predicado sobre la fila NUEVA a propósito: sin él, el
-- autor podría reescribir `propietario` con el correo de otro y regalar (o
-- robar) la ficha en un UPDATE. Con él, la fila resultante tiene que seguir
-- siendo suya.
