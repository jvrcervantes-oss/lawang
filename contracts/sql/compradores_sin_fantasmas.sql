-- ============================================================================
-- Un comprador que sale del contrato tiene que salir de la tabla — 24-ago-2026
--
-- SÍNTOMA (owner): en Operaciones, C200003 mostraba como compradores a «Aranzazu
-- Bahon Bueno y Carlos Fragua Martinez», que no tienen nada que ver con ese
-- contrato. Sus compradores reales son Xavier Roman y Andrea Köver, y así lo
-- decía `contratos.comprador_nombre`. Los que sobraban vivían en
-- `contrato_compradores`, que es de donde Operaciones pinta esa columna.
--
-- CAUSA: `sincronizar_compradores` solo sabía sumar. Su bucle hace
--   insert ... on conflict (contrato_id, rol) do update
-- y nada más: si el contrato tuvo cuatro adquirientes y se editó dejando dos,
-- los roles `adquiriente_3` y `adquiriente_4` se quedan enlazados para siempre,
-- apuntando a las personas de la versión anterior. No hay error, no hay aviso, y
-- el documento impreso —que sale de `datos`— sigue correcto: la contradicción
-- solo se ve en las pantallas que leen la tabla.
--
-- Medido antes de tocar: de 112 contratos, 3 no cuadran. C200003 (2 en el
-- documento, 4 en la tabla) es el caso del owner. CR00013 tiene el problema
-- INVERSO —2 en el documento, 1 en la tabla— y esa es otra causa distinta (un
-- comprador sin ficha que el bucle salta a propósito, `v_sin_ficha`), así que
-- este arreglo no lo toca ni debe. CO00004 es una Oferta Comercial, que por
-- diseño no exige ficha.
--
-- EL ARREGLO, y por qué así: se borran los roles que YA NO EXISTEN EN EL
-- DOCUMENTO, no «los que no he podido enlazar en esta pasada». La diferencia
-- importa: un comprador que sigue nombrado en el contrato pero cuya ficha no se
-- puede resolver hoy (sin pasaporte ni email todavía) conserva su enlace, que es
-- lo correcto. Solo desaparecen los roles fantasma — los que el documento ya no
-- menciona. Con el criterio fácil («borra lo que no he enlazado») una ficha
-- borrada o un email corregido habrían desenlazado a un comprador de verdad.
-- ============================================================================

-- destructivo-ok: el DELETE es el arreglo, y esta acotado a los roles que el
-- propio documento ya no menciona, dentro de UN contrato. Sin el, la tabla no
-- puede volver a cuadrar con el contrato. Verificado antes de aplicarlo: nada
-- referencia `contrato_compradores` por clave ajena, asi que no arrastra nada.
create or replace function public.sincronizar_compradores(p_contrato uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text; v_cid text;
  v_client uuid;
  v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_ficha text[] := '{}';
  v_roles_vivos text[] := '{}';
  v_borrados int := 0;
begin
  select datos into v_datos from public.contratos where id = p_contrato;
  if v_datos is null then return jsonb_build_object('error', 'contrato inexistente o sin datos'); end if;

  v_gente := jsonb_build_array(jsonb_build_object(
      'rol','adquiriente_1',
      'client_id',    v_datos->>'adq1_client_id',
      'nombre',       v_datos->'fields'->>'adq1_nombre',
      'pasaporte',    v_datos->'fields'->>'adq1_pasaporte',
      'email',        v_datos->'fields'->>'adq1_email',
      'telefono',     v_datos->'fields'->>'adq1_telefono',
      'nacionalidad', v_datos->'fields'->>'adq1_nacionalidad',
      'domicilio',    v_datos->'fields'->>'adq1_domicilio'))
    || coalesce((
      select jsonb_agg(jsonb_build_object(
               'rol','adquiriente_' || (ord + 1),
               'client_id', e->>'client_id',
               'nombre', e->>'nombre', 'pasaporte', e->>'pasaporte', 'email', e->>'email',
               'telefono', e->>'telefono', 'nacionalidad', e->>'nacionalidad',
               'domicilio', e->>'domicilio') order by ord)
      from jsonb_array_elements(
             case when jsonb_typeof(v_datos->'compradores') = 'array'
                  then v_datos->'compradores' else '[]'::jsonb end) with ordinality t(e, ord)
      where ord + 1 <= 9), '[]'::jsonb);

  for p in select value from jsonb_array_elements(v_gente) loop
    v_nombre := btrim(coalesce(p->>'nombre',''));
    continue when v_nombre = '';
    v_rol  := p->>'rol';
    -- Este rol EXISTE en el documento. Se apunta aunque luego no se consiga
    -- enlazar: lo que decide si una fila sobra es el documento, no el enlace.
    v_roles_vivos := v_roles_vivos || v_rol;
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));
    v_cid  := nullif(btrim(coalesce(p->>'client_id','')), '');

    v_client := null;

    if v_cid is not null then
      begin
        select id into v_client from public.clients where id = v_cid::uuid;
      exception when invalid_text_representation then
        v_client := null;
      end;
    end if;

    if v_client is null then
      if v_pas is null and v_mail is null then
        v_sin_id := v_sin_id || v_nombre;
        continue;
      end if;
      if v_pas is not null then
        select id into v_client from public.clients
         where lower(btrim(passport_number)) = lower(v_pas) limit 1;
      end if;
      if v_client is null and v_mail is not null then
        select id into v_client from public.clients
         where lower(email) = v_mail
         order by (tipo = 'persona') desc, created_at
         limit 1;
      end if;
    end if;

    if v_client is null then
      v_sin_ficha := v_sin_ficha || v_nombre;
      continue;
    end if;

    insert into public.contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  /* LOS FANTASMAS. Un contrato que pasó de cuatro compradores a dos dejaba
     `adquiriente_3` y `adquiriente_4` enlazados a las personas de la versión
     anterior, y Operaciones los seguía enseñando como compradores de este
     contrato. Se borran los roles que el documento YA NO NOMBRA.

     ⚠️ Si el documento no nombra a NADIE (`v_roles_vivos` vacío) NO se borra
     nada. Un contrato sin nombres es casi siempre un `datos` a medio escribir o
     una plantilla que aún no los tiene, y vaciar la tabla por eso convertiría un
     guardado intermedio en una pérdida de enlaces. */
  if array_length(v_roles_vivos, 1) is not null then
    delete from public.contrato_compradores
     where contrato_id = p_contrato
       and rol <> all(v_roles_vivos);
    get diagnostics v_borrados = row_count;
  end if;

  return jsonb_build_object('altas', 0, 'enlaces', v_enlaces,
                            'retirados', v_borrados,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'sin_ficha',         to_jsonb(v_sin_ficha));
end $function$;
