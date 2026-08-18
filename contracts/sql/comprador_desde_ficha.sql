-- ════════════════════════════════════════════════════════════════════════════
-- EL COMPRADOR SALE DE SU FICHA, NO DEL TEXTO — 18-ago-2026, encargo del owner
-- ════════════════════════════════════════════════════════════════════════════
-- CÓMO ERA. `sincronizar_compradores` cogía el pasaporte y el email escritos en
-- el contrato, buscaba una ficha que coincidiera y, si no la encontraba, CREABA
-- UNA PERSONA NUEVA. La identidad de un cliente la decidía lo que alguien
-- tecleaba, y de ahí salieron las dos cosas que ya costaron dinero y tiempo:
--   · los compradores DUPLICADOS (el owner pidió el 18-ago poder borrarlos);
--   · CR00025, con un email en el contrato distinto del de la ficha — el
--     contrato «se envió» a un dominio que no existe;
--   · y RP00043, 165.800 €, con un email metido en el campo del NOMBRE: por eso
--     nunca tuvo ficha.
--
-- CÓMO ES AHORA, y el orden importa:
--   1. Si el contrato trae el ENLACE explícito (`datos.adq1_client_id` para el
--      adquiriente I, `client_id` en cada fila de `datos.compradores`), se usa
--      ese y no se adivina nada. Es lo que manda la app desde hoy.
--   2. Si no lo trae (contrato viejo, o guardado desde una pestaña sin
--      recargar), se sigue buscando por pasaporte o email como siempre — eso no
--      inventa a nadie, solo reconoce.
--   3. Y si no aparece: NO SE CREA. Se devuelve en `sin_ficha` y ahí se queda.
--      La app ya no deja guardar un comprador sin ficha, así que este caso solo
--      lo alcanzan las pestañas viejas y las escrituras a mano por SQL.
--
-- ⚠️ LA OTRA MITAD DE LA REGLA vive en `contracts/app.html` (buscar / «Crear
-- ficha de cliente nuevo» / «Corregir ficha», y el freno al guardar). Si cambia
-- una, cambia la otra: sin la app, esto deja contratos sin comprador enlazado;
-- sin esto, la base volvería a inventar personas a partir de una errata.
-- LAW-51: al tocar esta función se relee TODO consumidor — hoy el trigger
-- `trg_compradores_desde_datos` y la llamada suelta desde /compradores/.

create or replace function public.sincronizar_compradores(p_contrato uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text; v_cid text;
  v_client uuid;
  v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_ficha text[] := '{}';
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
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));
    v_cid  := nullif(btrim(coalesce(p->>'client_id','')), '');

    v_client := null;

    -- 1) el enlace explícito manda: ni se mira el texto
    if v_cid is not null then
      begin
        select id into v_client from public.clients where id = v_cid::uuid;
      exception when invalid_text_representation then
        v_client := null;   -- un id corrupto no revienta el guardado del contrato
      end;
    end if;

    -- 2) sin enlace, se RECONOCE por pasaporte o email (no se inventa)
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
        select id into v_client from public.clients where lower(email) = v_mail limit 1;
      end if;
    end if;

    -- 3) y si no hay ficha, NO se crea una. Aquí estaba el insert que convertía
    --    una errata en una persona nueva.
    if v_client is null then
      v_sin_ficha := v_sin_ficha || v_nombre;
      continue;
    end if;

    insert into public.contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  -- `altas` se conserva en la respuesta y siempre vale 0: quien la lea seguirá
  -- funcionando, y el cero dice por sí solo que esta función ya no da altas.
  return jsonb_build_object('altas', 0, 'enlaces', v_enlaces,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'sin_ficha',         to_jsonb(v_sin_ficha));
end $$;

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select prosrc from pg_proc where proname='sincronizar_compradores';
--     → NO debe aparecer ningún `insert into public.clients`
--   select count(*) from public.clients;   → antes y después de guardar un
--     contrato con un comprador inventado: la misma cifra.
-- Y la de comportamiento: DO con rollback — contrato con adq1_client_id enlaza
-- esa ficha; sin él pero con email conocido, la reconoce; con datos que no
-- existen, devuelve `sin_ficha` y no crea a nadie.
