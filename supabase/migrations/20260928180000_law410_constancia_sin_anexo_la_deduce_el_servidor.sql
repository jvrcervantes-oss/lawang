-- LAW-410 (28-sep-2026, owner: «Sí, la escribe el servidor»): la constancia de envío a firma SIN un anexo del
-- modelo la deduce la base, no la pantalla. Máxima del owner: no te creas nada del front-end.
--
-- QUÉ PASABA. Desde LAW-406 (20260928120000) contrato_envia_firma apunta el evento `envio_sin_anexo_confirmado`
-- en la misma transacción que el envío, pero SOLO si la pantalla manda `p_sin_anexo`. Un navegador manipulado (o
-- una pantalla vieja) que no lo mandara sacaba a firma un contrato de obra sin su Apéndice A y sin rastro.
--
-- QUÉ CAMBIA. Misma función, misma firma de 7 argumentos (la edge ficheros-contrato v6 la llama por nombre y no
-- cambia). Antes de anular nada, si el contrato es de OBRA calcula ella qué falta, con el contrato GUARDADO:
--   · De obra = `datos.fields.tipologia_construccion` no vacío: la misma condición que `tipSel` en app.html y
--     que el trigger _contrato_anexos_con_paginas (hoy: tipo construccion y cc00014_timon). Los demás contratos
--     no llevan documentos del modelo: no se deduce nada.
--   · Esperados = la regla de docs_contrato.js → entran() y del trigger de LAW-400 (20260928121000): documentos
--     del modelo (resuelto por nombre entre los ACTIVOS, UNO) con en_contrato, tipo en plano|calidades|ficha|render|otro (nunca el
--     dosier), path no vacío (el `d.path` de documentosDelContrato) y techo NULL o el del contrato (ninguno si el
--     techo es «sintético»).
--   · Presentes = los esperados con ficha `axauto-<id>` en datos.annexes y `on` distinto de false (ausente =
--     incluido, como `g.on !== false`). La ficha vieja `axauto` (contratos de antes del 27-sep) cuenta como el
--     plano del techo o, si no hay, el genérico: lo mismo que fichaGuardadaDe() de documento_anexos.js.
--   · Motivo (los tres de siempre, que ya pinta el registro):
--       ninguno ........ el modelo no tiene nada marcado para este techo, o no se ha podido resolver (0 o 2+
--                        modelos con ese nombre: `nota` lo dice, para que no se lea como «no había nada»);
--       sin_apendice_a . no va el plano que el contrato cita (Apéndice A, el único vinculante: Legal, 28-sep);
--       fallo .......... va el plano pero falta o está apagado otro documento marcado.
--     `faltan` es la lista REAL (plano primero, luego por tipo y orden de Modelos), no un texto de la pantalla.
--
-- `p_sin_anexo` SE QUEDA, y solo puede SUMAR (decisión de esta migración). El servidor no ve las páginas de un
-- anexo automático, solo su ficha: si el navegador no pudo descargar o convertir un PDF marcado, conserva su
-- ficha guardada con `on` y aquí parecería presente. Eso solo lo sabe la pantalla. Así que:
--   · se valida igual que antes (22023 si viene mal formada, ANTES de tocar nada);
--   · su lista se UNE a la del servidor (sin repetir, tope 20) y su motivo se guarda como `motivo_pantalla`;
--   · si el servidor deduce una falta, el evento se escribe AUNQUE la pantalla no mande nada o mande otra cosa:
--     no hay forma de ocultar una falta desde el navegador;
--   · `declarado_por` = servidor | pantalla | ambos.
--
-- LO QUE NO PRUEBA. Se juzga el contrato guardado, no el HTML que se sube a firmar: si el agente cambió los anexos
-- en pantalla sin guardar, la constancia describe lo guardado. Tampoco qué versión del PDF se imprimió (eso es
-- el `sha` de la ficha, que sigue siendo lo que declara el navegador: ver 20260928121000).
--
-- PERMISOS: solo authenticated, explícitos aunque create or replace conserve la ACL (P2 del test lo mide).
-- ERP maestro: contrato_envia_firma es del núcleo (erp/modulos.json); queda como deuda del maestro
-- (erp/pendiente_maestro.jsonl) hasta que se porte a erp/migraciones/.
-- Pruebas: contracts/tools/envio_y_fichas_rpc_test.py C (rol real, ROLLBACK).

create or replace function public.contrato_envia_firma(p_contrato uuid, p_nombre text, p_email text, p_rol text,
                                                       p_orden integer, p_snapshot_hash text,
                                                       p_sin_anexo jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_email  text := btrim(coalesce(p_email, ''));
  v_rol    text := btrim(coalesce(p_rol, ''));
  v_token  text;
  v_link   text;
  v_anul   int;
  v_firma  uuid;
  x        jsonb;
  -- lo que declara la pantalla
  v_pmotivo text;
  v_pfaltan jsonb := '[]';
  -- lo que deduce el servidor
  v_tip     text;
  v_techo_j jsonb;
  v_anx     jsonb;
  v_techo   text;
  v_modelo  uuid;
  v_n       int;
  v_on      uuid[];
  v_vieja   boolean;
  v_vieja_id uuid;
  v_esper   int := 0;
  v_plano   boolean := false;
  v_smotivo text;
  v_sfaltan jsonb := '[]';
  v_nota    text;
  -- la constancia final
  v_motivo  text;
  v_faltan  jsonb := '[]';
  v_det     jsonb;
begin
  perform public.contrato_firma_estado(p_contrato);
  if length(v_nombre) < 2 then raise exception 'Pon el nombre del comprador' using errcode = '22023'; end if;
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Pon un email válido del comprador' using errcode = '22023'; end if;
  if v_rol !~ '^adquiriente_[0-9]+$' then raise exception 'Firmante no válido' using errcode = '22023'; end if;
  if coalesce(p_orden, 0) < 1 then raise exception 'Orden de firma no válido' using errcode = '22023'; end if;
  if coalesce(p_snapshot_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'Falta el documento a firmar' using errcode = '22023'; end if;
  if exists (select 1 from public.contrato_firmas f
              where f.contrato_id = p_contrato and f.firmante_rol = v_rol and f.estado = 'firmado') then
    raise exception 'Ese firmante ya ha firmado este contrato' using errcode = '23505';
  end if;

  -- 1) Lo que declara la pantalla («Enviar igualmente»): se valida igual que en LAW-406, ANTES de tocar nada.
  if p_sin_anexo is not null and jsonb_typeof(p_sin_anexo) <> 'null' then
    if jsonb_typeof(p_sin_anexo) <> 'object' then raise exception 'Constancia de envío sin anexo no válida' using errcode = '22023'; end if;
    v_pmotivo := p_sin_anexo->>'motivo';
    if v_pmotivo is null or v_pmotivo not in ('ninguno', 'sin_apendice_a', 'fallo') then
      raise exception 'Constancia de envío sin anexo no válida: motivo' using errcode = '22023';
    end if;
    if p_sin_anexo ? 'faltan' then
      if jsonb_typeof(p_sin_anexo->'faltan') is distinct from 'array' or jsonb_array_length(p_sin_anexo->'faltan') > 20 then
        raise exception 'Constancia de envío sin anexo no válida: lista de lo que falta' using errcode = '22023';
      end if;
      for x in select * from jsonb_array_elements(p_sin_anexo->'faltan') loop
        if jsonb_typeof(x) is distinct from 'string' then
          raise exception 'Constancia de envío sin anexo no válida: lista de lo que falta' using errcode = '22023';
        end if;
        v_pfaltan := v_pfaltan || to_jsonb(left(regexp_replace(x #>> '{}', '[[:cntrl:]<>]', '', 'g'), 200));
      end loop;
    end if;
  end if;

  -- 2) Lo que deduce el servidor, del contrato GUARDADO (solo contratos de obra).
  select nullif(lower(btrim(coalesce(c.datos->'fields'->>'tipologia_construccion', ''))), ''), c.datos->'techo', c.datos->'annexes'
    into v_tip, v_techo_j, v_anx
    from public.contratos c where c.id = p_contrato;
  if v_tip is not null then
    v_techo := case when jsonb_typeof(v_techo_j) = 'object' and (v_techo_j->>'sintetico') is distinct from 'true'
                    then nullif(btrim(coalesce(v_techo_j->>'clave', '')), '') end;
    -- solo modelos ACTIVOS, como el catálogo de la pantalla (modelos_catalogo.js, `.eq('activo', true)`): un modelo
    -- retirado con el mismo nombre no puede convertir cada envío en un «modelo repetido» (code-review 28-sep).
    select min(m.id::text)::uuid, count(*) into v_modelo, v_n from public.modelos m where lower(btrim(m.nombre)) = v_tip and m.activo;
    if v_n <> 1 then
      v_smotivo := 'ninguno';
      v_nota := case when v_n = 0 then 'modelo_no_encontrado' else 'modelo_repetido' end;
      v_sfaltan := jsonb_build_array('Apéndice A – Planos Arquitectónicos');
    else
      if jsonb_typeof(v_anx) is distinct from 'array' then v_anx := '[]'; end if;
      v_on := array(select substr(a->>'id', 8)::uuid from jsonb_array_elements(v_anx) a
                     where jsonb_typeof(a) = 'object' and jsonb_typeof(a->'auto') = 'string' and btrim(a->>'auto') <> ''
                       and a->>'id' ~ '^axauto-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                       and (a->'on') is distinct from 'false'::jsonb);
      v_vieja := exists (select 1 from jsonb_array_elements(v_anx) a
                          where jsonb_typeof(a) = 'object' and jsonb_typeof(a->'auto') = 'string' and btrim(a->>'auto') <> ''
                            and a->>'id' = 'axauto' and (a->'on') is distinct from 'false'::jsonb);
      if v_vieja then
        select d.id into v_vieja_id from public.modelo_documentos d
         where d.modelo_id = v_modelo and d.en_contrato and d.tipo = 'plano' and d.path <> ''
           and (d.techo_clave is null or d.techo_clave = v_techo)
         order by (d.techo_clave is null), d.orden, d.subido_en, d.id limit 1;
      end if;
      with esp as (
        select d.id, d.tipo, d.nombre, d.orden, d.subido_en,
               (d.id = any(v_on) or d.id is not distinct from v_vieja_id) as esta,
               array_position(array['plano', 'calidades', 'ficha', 'render', 'otro'], d.tipo) as grupo
          from public.modelo_documentos d
         where d.modelo_id = v_modelo and d.en_contrato and d.path <> ''
           and d.tipo in ('plano', 'calidades', 'ficha', 'render', 'otro')
           and (d.techo_clave is null or d.techo_clave = v_techo))
      select count(*), coalesce(bool_or(esta and tipo = 'plano'), false),
             coalesce(jsonb_agg(case tipo when 'plano' then 'Apéndice A – Planos Arquitectónicos'
                                          when 'calidades' then 'Memoria de calidades'
                                          when 'ficha' then 'Ficha' when 'render' then 'Render' else 'Otro' end
                                || ' «' || left(nombre, 120) || '»'
                                order by grupo, orden, subido_en, id) filter (where not esta), '[]')
        into v_esper, v_plano, v_sfaltan
        from esp;
      if v_esper = 0 then
        v_smotivo := 'ninguno';
        v_sfaltan := jsonb_build_array('Apéndice A – Planos Arquitectónicos');
      elsif not v_plano then
        v_smotivo := 'sin_apendice_a';
        -- el modelo no tiene plano marcado para este techo: el Apéndice A falta igual, y se nombra
        if not exists (select 1 from jsonb_array_elements_text(v_sfaltan) t where t like 'Apéndice A%') then
          v_sfaltan := jsonb_build_array('Apéndice A – Planos Arquitectónicos') || v_sfaltan;
        end if;
      elsif jsonb_array_length(v_sfaltan) > 0 then
        v_smotivo := 'fallo';
      end if;
    end if;
  end if;

  -- 3) La constancia: manda lo deducido; lo declarado por la pantalla solo suma.
  v_motivo := coalesce(v_smotivo, v_pmotivo);
  if v_motivo is not null then
    for x in select * from jsonb_array_elements(v_sfaltan || v_pfaltan) loop
      exit when jsonb_array_length(v_faltan) >= 20;
      if not v_faltan @> jsonb_build_array(x) then v_faltan := v_faltan || jsonb_build_array(x); end if;
    end loop;
    v_det := jsonb_build_object('motivo', v_motivo, 'faltan', v_faltan,
               'declarado_por', case when v_smotivo is not null and v_pmotivo is not null then 'ambos'
                                     when v_smotivo is not null then 'servidor' else 'pantalla' end);
    if v_pmotivo is not null and v_pmotivo is distinct from v_motivo then v_det := v_det || jsonb_build_object('motivo_pantalla', v_pmotivo); end if;
    if v_nota is not null then v_det := v_det || jsonb_build_object('nota', v_nota); end if;
  end if;

  update public.contrato_firmas f
     set estado = 'anulado', anulado_en = now(), anulado_por = (select auth.email()), anulado_motivo = 'nuevo_enlace'
   where f.contrato_id = p_contrato and f.estado = 'pendiente';
  get diagnostics v_anul = row_count;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_link  := 'https://lawangproperties.com/contracts/firmar.html?t=' || v_token;
  insert into public.contrato_firmas (contrato_id, token_hash, firmante_nombre, firmante_email, firmante_rol,
                                      orden, snapshot_path, snapshot_hash, enlace_firma)
  values (p_contrato, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_nombre, v_email, v_rol,
          p_orden, 'pendientes/' || p_contrato::text || '.html', p_snapshot_hash, v_link)
  returning id into v_firma;

  -- En la MISMA transacción: si no se puede apuntar, no sale el envío (y el enlace anterior sigue).
  if v_det is not null then
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (p_contrato, 'envio_sin_anexo_confirmado', v_det || jsonb_build_object('firma_id', v_firma),
            left(nullif(btrim(coalesce((select auth.email()), '')), ''), 200));
  end if;

  return jsonb_build_object('link', v_link, 'anulados', v_anul);
end $$;
revoke all on function public.contrato_envia_firma(uuid, text, text, text, integer, text, jsonb) from public, anon, service_role;
grant execute on function public.contrato_envia_firma(uuid, text, text, text, integer, text, jsonb) to authenticated;
