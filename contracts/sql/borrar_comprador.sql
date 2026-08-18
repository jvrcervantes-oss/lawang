-- ════════════════════════════════════════════════════════════════════════════
-- BORRAR_COMPRADOR — solo super_admin, para los duplicados — 18-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Encargo del owner: hay fichas de comprador duplicadas y hay que poder
-- borrarlas. Hasta hoy era IMPOSIBLE desde la app: `clients` no tiene policy de
-- DELETE (verificado en pg_policies: SELECT/INSERT/UPDATE y nada más), y eso era
-- correcto — borrar una ficha con KYC de una persona real no puede ser un gesto
-- más de la interfaz.
--
-- No se añade una policy de DELETE: se hace por RPC, como borrar_operacion y
-- borrar_proyecto, porque el borrado necesita COMPROBACIONES que una policy no
-- sabe hacer. La regla LAW-51 aplicada a esta tabla: antes de reutilizar (aquí,
-- destruir) una fila, se audita a quién le importa. A `clients` la referencian
-- CUATRO tablas (leído de information_schema, no de memoria):
--
--   · contrato_compradores — el vínculo con contratos REALES. Si existe, se
--     BLOQUEA con los números de contrato: borrar esa ficha dejaría un contrato
--     apuntando a un comprador que no existe. El duplicado bueno de borrar es el
--     que no está vinculado a nada.
--   · portal_accesos — la ficha tiene (o tuvo) acceso al portal. Se BLOQUEA:
--     primero se revoca el acceso desde la propia ficha, luego se borra.
--   · documents — el KYC del duplicado. Se BORRAN las filas y se DEVUELVEN las
--     rutas del bucket: los ficheros los quita la interfaz con la sesión del
--     super_admin (mismo patrón que borrarOperacion en /operaciones/, que quita
--     los PDF tras el RPC). Un pasaporte duplicado en un bucket privado no es
--     una fuga, pero es PII que ya no respalda a nadie: fuera.
--   · reservations — tabla del esquema viejo, sin policies. Si tuviera filas,
--     se bloquea y se mira a mano: no se destruye lo que no se entiende.
--
-- SECURITY DEFINER con search_path vacío, EXECUTE revocado a anon (la puerta
-- real es es_super_admin(), dentro), y devuelve un resumen de lo que hizo.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.borrar_comprador(p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_nombre     text;
  v_contratos  text;
  v_portal     int;
  v_reservas   int;
  v_rutas      text[];
  v_docs       int;
begin
  if not public.es_super_admin() then
    raise exception 'Solo un super admin puede borrar una ficha de comprador' using errcode = '42501';
  end if;

  select c.full_name into v_nombre from public.clients c where c.id = p_client_id;
  if v_nombre is null and not exists (select 1 from public.clients c2 where c2.id = p_client_id) then
    raise exception 'Esa ficha de comprador no existe';
  end if;

  -- ── los bloqueos, cada uno con su porqué en el mensaje ──────────────────
  select string_agg(distinct coalesce(ct.numero, 'sin nº'), ', ') into v_contratos
    from public.contrato_compradores cc
    join public.contratos ct on ct.id = cc.contrato_id
   where cc.client_id = p_client_id;
  if v_contratos is not null then
    raise exception 'La ficha de % está vinculada a los contratos % — no se borra una ficha con contratos. Si es el duplicado, desvincúlalo primero desde el contrato; si dudas, es que no es el duplicado.',
      coalesce(v_nombre, 'este comprador'), v_contratos using errcode = '23503';
  end if;

  select count(*) into v_portal from public.portal_accesos pa where pa.client_id = p_client_id;
  if v_portal > 0 then
    raise exception 'La ficha de % tiene acceso al portal (%). Revócaselo desde la propia ficha y vuelve a intentarlo.',
      coalesce(v_nombre, 'este comprador'), v_portal using errcode = '23503';
  end if;

  select count(*) into v_reservas from public.reservations r where r.client_id = p_client_id;
  if v_reservas > 0 then
    raise exception 'La ficha de % tiene % fila(s) en reservations (esquema antiguo) — se mira a mano antes de borrar.',
      coalesce(v_nombre, 'este comprador'), v_reservas using errcode = '23503';
  end if;

  -- ── el borrado: documentos primero (y sus rutas para el bucket), la ficha después
  select array_agg(d.storage_path) filter (where d.storage_path is not null), count(*)
    into v_rutas, v_docs
    from public.documents d where d.client_id = p_client_id;
  delete from public.documents where client_id = p_client_id;
  delete from public.clients   where id = p_client_id;

  return jsonb_build_object(
    'borrado', true,
    'nombre', v_nombre,
    'documentos', coalesce(v_docs, 0),
    'rutas_kyc', coalesce(to_jsonb(v_rutas), '[]'::jsonb),
    'por', (select auth.email())
  );
end;
$$;

revoke execute on function public.borrar_comprador(uuid) from public, anon;
grant execute on function public.borrar_comprador(uuid) to authenticated;
-- `authenticated` puede LLAMARLA pero la función corta con es_super_admin():
-- el mismo reparto que borrar_proyecto. Revocar a authenticated rompería la
-- llamada desde la app (supabase-js llama con ese rol).

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
--   select proname, prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and proname='borrar_comprador';
-- Y la de comportamiento: el bloque DO de prueba (con rollback) que se corrió
-- al aplicar esto — ficha suelta se borra, ficha con contrato se bloquea.
