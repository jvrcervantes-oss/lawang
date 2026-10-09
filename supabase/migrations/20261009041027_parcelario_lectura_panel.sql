-- Parcelario del estudio: lectura ACOTADA del inventario para cruzar el masterplan con la base (9-oct-2026).
-- erp-ok: lectura interna para una herramienta del estudio (AI Tools del panel), sin pantalla en el maestro
-- destructivo-ok: solo crea dos funciones de lectura; no toca ninguna fila
--
-- Encargo: encargos/20261009_parcelario_ai_tools.md (repo de la agencia) · revisión previa #242 (Seguridad, Datos).
-- LLAMADOR ÚNICO: el panel del estudio (infraestructura/panel-web/server.py, GET /api/parcelario y
-- /api/parcelario/unidades/<id>), en el servidor y con la service key. Ningún navegador las llama.
--
-- Por qué una RPC y no `unidades_estado?select=...` desde el panel: el panel usa la service key (se salta la RLS)
-- y arma URLs con f-strings. La única barrera sería el texto del `select=`, y un parámetro del navegador mal metido
-- (`x&select=*`) leería comprador y precio. Aquí las columnas son FIJAS: no hay forma de pedir otras.
-- Por qué no reutilizar investor_deck_parcelas: devuelve solo lo publicado en el deck y busca por NOMBRE de
-- proyecto. El cruce tiene que ver TODAS las unidades (LAW-140 son justo 23 unidades que no salen en el deck) y por
-- id (un cambio de nombre no puede dejarlo vacío).
--
-- QUÉ DEVUELVE: código, proyecto, tipo, superficie, estado (la columna real, que mantienen los triggers del contrato:
-- reservada/vendida/cobrada no se ponen a mano), fase y zona de masterplan, y si está publicada en el deck.
-- NUNCA: comprador, contrato, precio, notas ni socio (el reparto por socio es dato de admin, unidad_socio).
-- Solo service_role: revoke a public, anon y authenticated (el permiso de PUBLIC es el que se cuela, §1.ter).

create or replace function public.parcelario_proyectos()
returns table (id uuid, nombre text, parcela_master_m2 numeric, unidades bigint)
language sql stable security definer set search_path = '' as $$
  select p.id, p.nombre, p.parcela_master_m2, count(u.id)
    from public.proyectos p
    join public.unidades u on u.proyecto_id = p.id
   group by p.id, p.nombre, p.parcela_master_m2
   order by p.nombre;
$$;

create or replace function public.parcelario_unidades(p_proyecto_id uuid)
returns table (codigo text, proyecto text, tipo text, superficie_m2 numeric, estado text,
               fase_masterplan text, zona_masterplan text, publicado_investor_deck boolean)
language sql stable security definer set search_path = '' as $$
  select u.codigo, u.proyecto, u.tipo, u.superficie_m2, u.estado,
         u.fase_masterplan, u.zona_masterplan, coalesce(u.publicado_investor_deck, false)
    from public.unidades u
   where u.proyecto_id = p_proyecto_id
   order by u.codigo_orden nulls last, u.codigo;
$$;

revoke all on function public.parcelario_proyectos() from public, anon, authenticated;
revoke all on function public.parcelario_unidades(uuid) from public, anon, authenticated;
grant execute on function public.parcelario_proyectos() to service_role;
grant execute on function public.parcelario_unidades(uuid) to service_role;

comment on function public.parcelario_proyectos() is
  'Parcelario (AI Tools del estudio): proyectos con unidades, para elegir con cuál cruzar. Solo service_role; llamador: panel-web /api/parcelario.';
comment on function public.parcelario_unidades(uuid) is
  'Parcelario (AI Tools del estudio): 8 columnas fijas del inventario de un proyecto (nunca comprador, contrato, precio ni socio). Solo service_role; llamador: panel-web /api/parcelario/unidades/<id>.';
