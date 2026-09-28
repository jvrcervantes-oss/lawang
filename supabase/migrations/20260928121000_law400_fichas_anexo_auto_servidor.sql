-- LAW-400 (28-sep-2026): el servidor comprueba las fichas de anexo AUTOMÁTICO que guarda un contrato.
--
-- QUÉ PASABA. Desde el 27-sep el contrato de obra adjunta todos los documentos del modelo marcados «va en el
-- contrato» (modelo_documentos.en_contrato) de su techo o sin techo, y guarda por cada uno una FICHA congelada
-- {id: 'axauto-<id del documento>', auto, techo, sha, on} en datos.annexes (migración
-- 20260927230000_modelo_documentos_en_contrato_dosier). La lista la calcula el navegador y la base se la creía:
-- una pantalla manipulada podía guardar la ficha de un documento de OTRO modelo, de otro techo o no marcado
-- (y su `on`/`sha`), y la ficha guardada dejaba de probar qué se anexó. Además el trigger de LAW-78 se saltaba
-- CUALQUIER ficha con `auto`, así que un anexo manual con un `auto` inventado esquivaba la comprobación de
-- que sus páginas están en el archivo.
--
-- QUÉ CAMBIA. El mismo trigger (trg_contrato_anexos_con_paginas, before insert or update of datos), que ya
-- solo juzga cuando CAMBIA la lista de anexos, comprueba también las fichas automáticas:
--   · Automática = `auto` es un texto no vacío (lo mismo que el `if(a.auto)` de documento_anexos.js). Todo lo
--     demás es manual y sigue la regla de LAW-78 (páginas en el archivo o en `pages`).
--   · Su id tiene que ser `axauto-<uuid>` de un documento que HOY esté marcado en_contrato, sea del modelo del
--     contrato (datos.fields.tipologia_construccion, por nombre, como fichaDelModelo() de app.html) y tenga
--     techo NULL o el techo del contrato (datos.techo.clave; ninguno si el techo es «sintético», como
--     techoDelAnexo() de documento_anexos.js). La misma regla que docs_contrato.js → entran().
--   · Compatibilidad: la ficha vieja `axauto` (una sola, sin id de documento; 36 contratos el 28-sep-2026) se
--     acepta SOLO si ya estaba en la lista guardada del contrato (update) y una sola vez: la pantalla actual
--     nunca la escribe (la traduce a `axauto-<doc>` al abrir), así que una `axauto` NUEVA solo puede venir de
--     un navegador manipulado y se saltaría las dos comprobaciones (revisión de código, 28-sep).
--   · El modelo se resuelve por nombre y tiene que ser UNO: `modelos.nombre` no es único (solo el slug) y con
--     dos modelos del mismo nombre un documento del otro pasaría (revisión de código, 28-sep). Hoy no hay
--     nombres repetidos; si llega a haberlos, el guardado lo dice en vez de elegir uno a ciegas.
--   · Un mismo documento no puede aparecer dos veces.
--   · Se lee `datos->'fields'` y no la columna datos_fields: esa la rellena zz_contrato_datos_fields, que corre
--     después por orden de nombre, y no se depende del orden de disparo entre triggers (contexto/suite_lawang.md).
--
-- LO QUE NO CAMBIA. Un contrato firmado o cualquier update que no toca la lista de anexos no se juzga (el
-- trigger sale en la primera línea): renombrar un proyecto o marcar cobrada una carta no abortan por una
-- ficha vieja. Tampoco se exige que estén TODOS los marcados: «Enviar igualmente» sin un anexo es una decisión
-- permitida (owner, 28-sep-2026) que deja su constancia al enviar (LAW-406).
--
-- El texto del error empieza por «El anexo »: app.html lo enseña literal (esFrenoConocido).
--
-- ERP maestro: el trigger es del núcleo de contratos; este cambio queda como deuda del maestro
-- (erp/pendiente_maestro.jsonl) hasta que se porte a erp/migraciones/.

create or replace function public._contrato_anexos_con_paginas() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb; v_id text; v_doc uuid; v_vistos uuid[] := '{}'; v_vieja boolean := false;
  v_ctx boolean := false; v_tip text; v_techo text; v_modelo uuid; v_n int;
begin
  -- Solo juzga a quien CAMBIA la lista de anexos (Datos, consulta de deploy): un update de `datos` que no la toca
  -- —renombrar_proyecto, trg_cliente_actualizado, carta_cobrado_recalcula sobre un contrato ajeno— no se aborta
  -- por el estado de unos anexos que nadie está guardando ahora.
  if tg_op = 'UPDATE' and new.datos->'annexes' is not distinct from old.datos->'annexes' then return new; end if;
  if jsonb_typeof(new.datos->'annexes') is distinct from 'array' then return new; end if;
  for a in select value from jsonb_array_elements(new.datos->'annexes') loop
    continue when jsonb_typeof(a) <> 'object';

    -- ── automática: un documento de Modelos (LAW-400) ──
    if jsonb_typeof(a->'auto') = 'string' and btrim(a->>'auto') <> '' then
      v_id := coalesce(a->>'id', '');
      -- ficha de antes del 27-sep: solo la que ya estaba guardada, y una vez
      if v_id = 'axauto' then
        if v_vieja or tg_op <> 'UPDATE' or jsonb_typeof(old.datos->'annexes') is distinct from 'array'
           or not exists (select 1 from jsonb_array_elements(old.datos->'annexes') o
                           where jsonb_typeof(o) = 'object' and o->>'id' = 'axauto') then
          raise exception 'El anexo «%» es de un formato antiguo que ya no se guarda: recarga la página para que se vuelva a calcular.',
            left(coalesce(a->>'title', v_id), 80) using errcode = '23514';
        end if;
        v_vieja := true;
        continue;
      end if;
      if v_id !~ '^axauto-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'El anexo «%» no es un documento de Modelos: recarga la página para que se vuelva a calcular.',
          left(coalesce(a->>'title', v_id, '?'), 80) using errcode = '23514';
      end if;
      v_doc := substr(v_id, 8)::uuid;
      if v_doc = any(v_vistos) then
        raise exception 'El anexo «%» aparece dos veces: recarga la página para que se vuelva a calcular.',
          left(coalesce(a->>'title', v_id), 80) using errcode = '23514';
      end if;
      v_vistos := v_vistos || v_doc;
      if not v_ctx then
        v_tip := lower(btrim(coalesce(new.datos->'fields'->>'tipologia_construccion', '')));
        v_techo := case when jsonb_typeof(new.datos->'techo') = 'object'
                             and (new.datos->'techo'->>'sintetico') is distinct from 'true'
                        then nullif(btrim(coalesce(new.datos->'techo'->>'clave', '')), '') end;
        select min(m.id::text)::uuid, count(*) into v_modelo, v_n from public.modelos m where lower(btrim(m.nombre)) = v_tip;
        v_ctx := true;
      end if;
      if v_n > 1 then
        raise exception 'El anexo «%» no se puede comprobar: hay % modelos llamados «%». Avisa a administración.',
          left(coalesce(a->>'title', v_id), 80), v_n, v_tip using errcode = '23514';
      end if;
      if v_modelo is null or not exists (
           select 1 from public.modelo_documentos d
            where d.id = v_doc and d.modelo_id = v_modelo and d.en_contrato and d.tipo <> 'dosier'
              and (d.techo_clave is null or d.techo_clave = v_techo)) then
        raise exception 'El anexo «%» no es un documento marcado para el contrato de este modelo y techo (Modelos → Documentos): recarga la página para que se vuelva a calcular.',
          left(coalesce(a->>'title', v_id), 80) using errcode = '23514';
      end if;
      continue;
    end if;

    -- ── manual: sus páginas, en el archivo o en `pages` (LAW-78) ──
    continue when jsonb_typeof(a->'pages') = 'array' and jsonb_array_length(a->'pages') > 0;
    if not exists (select 1 from public.contrato_anexo_paginas p
                    where p.contrato_id = new.id and p.anexo_id = a->>'id') then
      raise exception 'El anexo «%» no tiene sus páginas en el archivo: vuelve a subirlo o quítalo (Anexos → Quitar).',
        left(coalesce(a->>'title', a->>'id', '?'), 80) using errcode = '23514';
    end if;
  end loop;
  return new;
end $$;
revoke all on function public._contrato_anexos_con_paginas() from public, anon, authenticated;
