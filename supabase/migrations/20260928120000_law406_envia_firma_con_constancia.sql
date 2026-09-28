-- destructivo-ok: sustituye la firma de contrato_envia_firma (drop de la de 6 argumentos + create con 7, para no dejar dos sobrecargas); no borra ni cambia ninguna fila.
-- LAW-406 (28-sep-2026): el envío a firma y su constancia «sin anexo» van en UNA transacción.
--
-- QUÉ PASABA. «Enviar igualmente» sin un documento del modelo (owner, 28-sep-2026) deja constancia en el
-- historial del contrato (evento `envio_sin_anexo_confirmado`). La edge `ficheros-contrato` lo hacía con DOS
-- llamadas: primero contrato_envia_firma (anula el enlace vivo y crea el nuevo) y después
-- contrato_envio_sin_anexo. Si la segunda fallaba, el envío ya había salido sin constancia y solo quedaba un
-- aviso rojo en pantalla y una línea de log: justo lo que la constancia existe para impedir.
--
-- QUÉ CAMBIA. contrato_envia_firma recibe `p_sin_anexo` (jsonb, por defecto null) y, si viene, apunta el
-- evento en la MISMA transacción que el envío: o sale el enlace con su constancia, o no sale nada (el enlace
-- anterior sigue vivo). La validación es la de antes (motivo ninguno|sin_apendice_a|fallo, `faltan` ≤ 20
-- textos, sin caracteres de control ni < >, 200 caracteres cada uno) y se hace ANTES de anular nada.
--   · QUIÉN lo declaró lo pone la base con la sesión (`auth.email()`, lo mismo que `anulado_por`), no un
--     parámetro: la edge llama con el JWT del usuario.
--   · El evento lleva el id de la firma creada: la constancia apunta al envío concreto.
--   · Firma nueva con el 7º argumento por defecto: una edge VIEJA (6 argumentos por nombre) sigue resolviendo
--     esta función mientras se despliega la nueva, y su segunda llamada sigue funcionando porque
--     contrato_envio_sin_anexo NO se retira aquí.
--
-- ORDEN DE DESPLIEGUE (revisión de código, 28-sep): 1) esta migración; 2) la edge ficheros-contrato; 3) la
-- migración supabase/migrations_diferidas/20260928122000_law406_retira_envio_sin_anexo (FUERA de migrations/ para que
-- no se aplique en lote por accidente; reducir la exposición: su único llamador era la
-- segunda llamada de la edge vieja). Retirarla aquí dejaba, entre 1 y 2, envíos «sin anexo» sin constancia.
-- La edge nueva NO puede ir antes que esta migración: con p_sin_anexo la llamada no encuentra la función.
--
-- PERMISOS: solo authenticated (nada para public/anon/service_role). El único llamador es la edge con el JWT
-- del usuario; el permiso sobre el contrato lo decide contrato_firma_estado. En producción tenía también
-- service_role, sin llamador (con service_role auth.email() es null: anulado_por y quien saldrían vacíos), así
-- que la firma nueva nace sin él. El create de una firma nueva no hereda la ACL de la vieja: se pone explícita.
--
-- ERP maestro: contrato_envia_firma es del núcleo (erp/modulos.json); este cambio queda como deuda del maestro
-- (erp/pendiente_maestro.jsonl) hasta que se porte a erp/migraciones/.

drop function if exists public.contrato_envia_firma(uuid, text, text, text, integer, text);

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
  v_motivo text;
  v_faltan jsonb := '[]';
  x        jsonb;
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

  -- «Enviar igualmente» sin un anexo del modelo: se valida ANTES de tocar nada.
  -- ninguno: no salió ningún documento del modelo; sin_apendice_a: salieron informativos pero no el plano que el
  -- contrato cita (el único apéndice vinculante, Legal 28-sep); fallo: uno marcado no se pudo adjuntar.
  -- Lo que falta lo DECLARA la pantalla (el servidor no reconstruye el documento): se guarda como declaración,
  -- acotado y sin HTML.
  if p_sin_anexo is not null and jsonb_typeof(p_sin_anexo) <> 'null' then
    if jsonb_typeof(p_sin_anexo) <> 'object' then raise exception 'Constancia de envío sin anexo no válida' using errcode = '22023'; end if;
    v_motivo := p_sin_anexo->>'motivo';
    if v_motivo is null or v_motivo not in ('ninguno', 'sin_apendice_a', 'fallo') then
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
        v_faltan := v_faltan || to_jsonb(left(regexp_replace(x #>> '{}', '[[:cntrl:]<>]', '', 'g'), 200));
      end loop;
    end if;
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

  -- La constancia, en la MISMA transacción: si no se puede apuntar, no sale el envío (y el enlace anterior sigue).
  if v_motivo is not null then
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (p_contrato, 'envio_sin_anexo_confirmado',
            jsonb_build_object('motivo', v_motivo, 'faltan', v_faltan, 'declarado_por', 'pantalla', 'firma_id', v_firma),
            left(nullif(btrim(coalesce((select auth.email()), '')), ''), 200));
  end if;

  return jsonb_build_object('link', v_link, 'anulados', v_anul);
end $$;
revoke all on function public.contrato_envia_firma(uuid, text, text, text, integer, text, jsonb) from public, anon, service_role;
grant execute on function public.contrato_envia_firma(uuid, text, text, text, integer, text, jsonb) to authenticated;
