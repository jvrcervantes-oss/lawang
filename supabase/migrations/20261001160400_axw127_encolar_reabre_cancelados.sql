-- AXW-127 — revisión de Datos (1-oct-2026): encolar reabre también filas 'cancelado' y 'obsoleto' con el mismo (contrato, email, sha)
-- (contrato liberado y vuelto a firmar con un PDF idéntico): antes quedaban sin enviar y sin aviso. Solo create or replace; no toca datos.

create or replace function public.copia_firmada_encolar(p_contrato uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  c       record;
  d       record;
  v_bytes bigint;
  v_modo  text;
  v_estado text;
  v_out   jsonb := '[]'::jsonb;
  v_encolo boolean := false;
  v_max   constant bigint := 18000000;
begin
  select ct.id, ct.numero, ct.bloqueado, ct.liberado_en,
         ct.pdf_firmado_path as ruta, ct.pdf_firmado_hash as sha
    into c from public.contratos ct where ct.id = p_contrato;
  if not found then
    raise exception 'contrato_inexistente' using errcode = 'P0002';
  end if;
  if not c.bloqueado or c.liberado_en is not null or c.ruta is null or c.sha is null then
    raise exception 'contrato_sin_pdf_firmado' using errcode = '22023';
  end if;
  select (o.metadata->>'size')::bigint into v_bytes
    from storage.objects o where o.bucket_id = 'contratos-firmados' and o.name = c.ruta;
  if v_bytes is null then
    raise exception 'pdf_no_encontrado' using errcode = 'P0002';
  end if;

  for d in select * from public.copias_firmadas_destinos(p_contrato) loop
    if d.elegible then v_modo := 'portal';
    elsif v_bytes <= v_max then v_modo := 'cola';
    elsif d.estudio or d.equipo then v_modo := 'intranet';
    else v_modo := 'error';
    end if;

    v_estado := null;
    if v_modo in ('cola', 'error') then
      insert into public.copias_firmadas_envios
             (contrato_id, email, nombre, pdf_sha256, pdf_bytes, estado, error)
      values (p_contrato, lower(btrim(d.email)), left(d.nombre, 120), c.sha, v_bytes::int,
              case when v_modo = 'cola' then 'pendiente' else 'error' end,
              case when v_modo = 'error' then 'pdf_demasiado_grande_para_adjuntar' else null end)
      on conflict (contrato_id, email, pdf_sha256) do update
         set estado = 'pendiente', intentos = 0, error = null, reclamado_en = null, encolado_en = now(), avisado = false
       where public.copias_firmadas_envios.estado in ('error', 'cancelado', 'obsoleto') and excluded.estado = 'pendiente'
      returning estado into v_estado;
      if v_estado is null then
        select e.estado into v_estado from public.copias_firmadas_envios e
         where e.contrato_id = p_contrato and e.email = lower(btrim(d.email)) and e.pdf_sha256 = c.sha;
      end if;
      if v_modo = 'cola' and v_estado = 'pendiente' then v_encolo := true; end if;
    end if;

    v_out := v_out || jsonb_build_object(
      'email', d.email, 'nombre', d.nombre, 'estudio', d.estudio, 'equipo', d.equipo,
      'modo', v_modo, 'estado', v_estado);
  end loop;

  if v_encolo then perform public._copias_firmadas_despierta(); end if;
  return jsonb_build_object('numero', c.numero, 'bytes', v_bytes, 'max_adjunto', v_max, 'destinos', v_out);
end $$;

revoke execute on function public.copia_firmada_encolar(uuid) from public, anon, authenticated;
grant  execute on function public.copia_firmada_encolar(uuid) to service_role;
