-- Comprador compartido entre closers — 22-sep-2026, decisión del owner
-- ----------------------------------------------------------------------------
-- CASO: un comprador que ya compró con el closer A vuelve y cierra con el
-- closer B. Hoy B no podía: el generador de contratos buscaba la ficha en
-- `clients`, cuya RLS (11-sep) solo enseña a un agente las fichas que él dio
-- de alta, y sin ficha enlazada el contrato no se guarda. La salida "fácil"
-- era dar de alta a la persona otra vez (clients ya no tiene UNIQUE de email
-- ni de pasaporte) y partirla en dos.
--
-- MODELO: la PERSONA es del equipo (identidad, sin `notes`, por
-- compradores_directorio(), como el directorio desde el 14-sep); el CONTRATO y
-- SU DINERO siguen siendo de quien lo hace, o de su manager, o de un admin.
-- La ficha del comprador dice lo que no enseña: «tiene 3 contratos, ves 2».
--
-- Lo que la revisión previa de Seguridad encontró y esta migración cierra:
--  1. contrato_cobrado(uuid) era DEFINER con gate es_agente() a secas y
--     contratos_del_mismo_comprador() no tenía gate: con un contrato con el
--     comprador de A, B tenía el cobrado del contrato de A en dos llamadas.
--     Este cambio convertía esa precondición en el caso habitual.
--  2. contrato_compradores se escribía con es_agente() a secas: cualquiera
--     podía desenlazar al comprador de un contrato ajeno, y la ficha mentiría
--     para todos justo cuando pasa a apoyarse en esos enlaces.
--  3. «este contrato lo veo» estaba escrito dos veces (policy y RPC nuevo):
--     una sola función, contrato_visible(), y la policy la usa.

-- 1. UNA sola definición de «este contrato lo veo».
--    es_suyo() ya incluye es_admin(); es_manager_de() también.
create or replace function public.contrato_visible(p_autor text, p_proyecto_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.es_suyo(p_autor) or public.es_manager_de(p_proyecto_id)
$$;
revoke all on function public.contrato_visible(text, uuid) from public, anon;
grant execute on function public.contrato_visible(text, uuid) to authenticated, service_role;

alter policy "agentes leen sus contratos" on public.contratos
  using (public.es_agente() and public.contrato_visible(creado_por, proyecto_id));

-- 2. contrato_compradores: se enlaza/desenlaza solo sobre un contrato que se ve.
--    La app no escribe aquí (lo hace el trigger sincronizar_compradores, que es
--    DEFINER y no pasa por estas policies); esto cierra la vía directa por REST.
-- destructivo-ok: se reemplazan 3 policies de contrato_compradores por versiones
--    más estrictas (ningún dato se toca; hallazgo MEDIA de la revisión previa #44)
drop policy if exists "agentes crean contrato_compradores" on public.contrato_compradores;
drop policy if exists "agentes actualizan contrato_compradores" on public.contrato_compradores;
drop policy if exists "agentes borran contrato_compradores" on public.contrato_compradores;

create policy "se enlaza un comprador a un contrato que se ve" on public.contrato_compradores
  for insert to authenticated with check (
    public.es_agente() and exists (
      select 1 from public.contratos c
       where c.id = contrato_id and public.contrato_visible(c.creado_por, c.proyecto_id)));

create policy "se cambia el enlace de un contrato que se ve" on public.contrato_compradores
  for update to authenticated
  using (
    public.es_agente() and exists (
      select 1 from public.contratos c
       where c.id = contrato_id and public.contrato_visible(c.creado_por, c.proyecto_id)))
  with check (
    public.es_agente() and exists (
      select 1 from public.contratos c
       where c.id = contrato_id and public.contrato_visible(c.creado_por, c.proyecto_id)));

create policy "se desenlaza un comprador de un contrato que se ve" on public.contrato_compradores
  for delete to authenticated using (
    public.es_agente() and exists (
      select 1 from public.contratos c
       where c.id = contrato_id and public.contrato_visible(c.creado_por, c.proyecto_id)));

-- 3. contrato_cobrado() es un ORÁCULO INTERNO: lo llaman nueve funciones
--    DEFINER (portal_situacion, crm_ranking_closers, obra_datos_cobro,
--    unidad_parte_cobrada_*, carta_cobrado_calcula…) que ya tienen su propio
--    gate y necesitan la cifra de contratos ajenos (un ranking suma a todos).
--    Por eso el filtro NO va dentro: va en la puerta. El navegador deja de
--    poder llamarlo; el único camino con sesión es contratos_cobrado_equipo(),
--    que filtra con la misma expresión que la policy de contratos.
revoke execute on function public.contrato_cobrado(uuid) from public, anon, authenticated;

create or replace function public.contratos_cobrado_equipo()
returns table(contrato_id uuid, cobrado numeric)
language sql stable security definer set search_path = ''
as $$
  select c.id, public.contrato_cobrado(c.id)
    from public.contratos c
   where public.es_agente() and public.contrato_visible(c.creado_por, c.proyecto_id)
$$;
revoke all on function public.contratos_cobrado_equipo() from public, anon;
grant execute on function public.contratos_cobrado_equipo() to authenticated, service_role;

-- 4. Los hermanos por comprador: solo los que quien pregunta puede ver.
--    (Facturas y el editor v4 lo usan para ACOTAR una lista que ya sale de
--    contratos bajo RLS, así que no pierden nada que pudieran abrir.)
create or replace function public.contratos_del_mismo_comprador(p_contrato_id uuid)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select p_contrato_id
  union
  select cc2.contrato_id
    from public.contrato_compradores cc1
    join public.contrato_compradores cc2 on cc2.client_id = cc1.client_id
    join public.contratos c on c.id = cc2.contrato_id
   where cc1.contrato_id = p_contrato_id
     and public.es_agente()
     and public.contrato_visible(c.creado_por, c.proyecto_id)
$$;
revoke all on function public.contratos_del_mismo_comprador(uuid) from public, anon;
grant execute on function public.contratos_del_mismo_comprador(uuid) to authenticated, service_role;

-- 5. Lo que la ficha del comprador puede decir de TODOS sus contratos, vea o
--    no cada uno: tipo, proyecto, autor y si está firmado. Sin importes, sin
--    número y sin `datos` (jsonb TOAST: no se nombra). `contrato_id` solo
--    viaja cuando el contrato es visible: una fila sin enlace no lo necesita y
--    así el RPC no reparte identificadores de contratos ajenos.
create or replace function public.comprador_contratos_resumen(p_client_id uuid)
returns table(contrato_id uuid, rol text, tipo text, proyecto_nombre text,
              autor text, bloqueado boolean, visible boolean)
language sql stable security definer set search_path = ''
as $$
  select case when v.visible then c.id end,
         cc.rol, c.tipo, c.proyecto_nombre, c.creado_por,
         coalesce(c.bloqueado, false), v.visible
    from public.contrato_compradores cc
    join public.contratos c on c.id = cc.contrato_id
    cross join lateral (
      select public.contrato_visible(c.creado_por, c.proyecto_id) as visible) v
   where public.es_agente() and cc.client_id = p_client_id
   order by c.created_at
$$;
revoke all on function public.comprador_contratos_resumen(uuid) from public, anon;
grant execute on function public.comprador_contratos_resumen(uuid) to authenticated, service_role;
