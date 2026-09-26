-- Frontera frontend/backend — GASTOS por el servidor (26-sep-2026, LAW-336 pieza 3).
-- Máxima del owner: «no te creas NADA del front-end». SOLO AÑADE; el revoke va después.
-- Lo que la base ya garantizaba (se queda): total GENERADO (base + impuesto), CHECKs de importes
-- y retención, _gastos_antes (anulado inmutable, autor, no pagar desde escrow ni cuenta ajena).
-- Lo que decidía la PANTALLA y ya no:
-- · la lista `justificantes` la escribía el cliente (cualquier ruta, exista o no): ahora la
--   entrada la construye el servidor y exige que el fichero EXISTA en el bucket, en la carpeta
--   del gasto;
-- · los pasos eran cambios libres de columnas: cada uno tiene su RPC con solo sus datos, y
--   «marcar pagado» exige que esté pendiente; `estado` no se cambia desde la edición.
-- Permiso = policies de hoy: es_admin() y puede('gastos').
-- Aplicada por MCP el 26-sep y probada (10 casos: agente, fichero inexistente, carpeta ajena,
-- doble pago, retención inexistente, anular sin motivo) sin dejar rastro.

create or replace function public._gasto_puede() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.es_admin() and public.puede('gastos')
$$;
revoke all on function public._gasto_puede() from public, anon, authenticated;

create or replace function public._gasto_importe(v jsonb) returns numeric
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(v) = 'number' then round((v #>> '{}')::numeric, 2)
              when v is null or jsonb_typeof(v) = 'null' or btrim(v #>> '{}') = '' then null
              else round(public.lw_parse_importe(v #>> '{}'), 2) end
$$;
revoke all on function public._gasto_importe(jsonb) from public, anon, authenticated;

create or replace function public.gasto_guarda(p_id uuid, p_datos jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_estado text;
  v_base numeric := public._gasto_importe(p_datos->'base');
  v_imp numeric := coalesce(public._gasto_importe(p_datos->'impuesto'), 0);
  v_pph numeric := coalesce(public._gasto_importe(p_datos->'pph_retenido'), 0);
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if v_base is null then raise exception 'La base no es un importe válido' using errcode = '22023'; end if;
  if p_id is null then
    v_estado := case when p_datos->>'estado' = 'pagado' then 'pagado' else 'pendiente' end;
    insert into public.gastos as g (sociedad, proyecto_id, proveedor_id, categoria, concepto, referencia, moneda,
        fecha, vence_el, base, impuesto, pph_tipo, pph_retenido, notas, estado, pagado_el, cuenta_pago)
    values (p_datos->>'sociedad', nullif(p_datos->>'proyecto_id', '')::uuid, nullif(p_datos->>'proveedor_id', '')::uuid,
        p_datos->>'categoria', p_datos->>'concepto', nullif(p_datos->>'referencia', ''), coalesce(nullif(p_datos->>'moneda', ''), 'EUR'),
        nullif(p_datos->>'fecha', '')::date, nullif(p_datos->>'vence_el', '')::date, v_base, v_imp,
        nullif(p_datos->>'pph_tipo', ''), v_pph, nullif(p_datos->>'notas', ''), v_estado,
        case when v_estado = 'pagado' then coalesce(nullif(p_datos->>'pagado_el', '')::date, current_date) end,
        case when v_estado = 'pagado' then nullif(p_datos->>'cuenta_pago', '') end)
    returning g.id into v_id;
    return v_id;
  end if;
  -- Edición: los datos del gasto; NUNCA estado, pago, justificantes ni anulación (tienen su RPC).
  update public.gastos g set
    sociedad = p_datos->>'sociedad', proyecto_id = nullif(p_datos->>'proyecto_id', '')::uuid,
    proveedor_id = nullif(p_datos->>'proveedor_id', '')::uuid, categoria = p_datos->>'categoria',
    concepto = p_datos->>'concepto', referencia = nullif(p_datos->>'referencia', ''),
    moneda = coalesce(nullif(p_datos->>'moneda', ''), 'EUR'), fecha = nullif(p_datos->>'fecha', '')::date,
    vence_el = nullif(p_datos->>'vence_el', '')::date, base = v_base, impuesto = v_imp,
    pph_tipo = nullif(p_datos->>'pph_tipo', ''), pph_retenido = v_pph, notas = nullif(p_datos->>'notas', '')
  where g.id = p_id
  returning g.id into v_id;
  if v_id is null then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
  return v_id;
end $$;

create or replace function public.gasto_marca_pagado(p_id uuid, p_pagado_el date, p_cuenta text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_estado text;
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  select estado into v_estado from public.gastos where id = p_id for update;
  if not found then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
  if v_estado <> 'pendiente' then raise exception 'Solo se marca pagado un gasto pendiente (este está %)', v_estado using errcode = '22023'; end if;
  if p_pagado_el is null then raise exception 'Falta la fecha de pago' using errcode = '22023'; end if;
  update public.gastos set estado = 'pagado', pagado_el = p_pagado_el, cuenta_pago = nullif(btrim(coalesce(p_cuenta, '')), '') where id = p_id;
end $$;

create or replace function public.gasto_pph_ingresado(p_id uuid, p_fecha date)
returns void language plpgsql security definer set search_path = '' as $$
declare v_pph numeric;
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  select pph_retenido into v_pph from public.gastos where id = p_id for update;
  if not found then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
  if coalesce(v_pph, 0) <= 0 then raise exception 'Este gasto no tiene retención que ingresar' using errcode = '22023'; end if;
  if p_fecha is null then raise exception 'Falta la fecha del ingreso' using errcode = '22023'; end if;
  update public.gastos set pph_ingresado_el = p_fecha where id = p_id;
end $$;

create or replace function public.gasto_anula(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then raise exception 'Anular un gasto exige un motivo' using errcode = '22023'; end if;
  update public.gastos set estado = 'anulado', anulado_motivo = btrim(p_motivo) where id = p_id;
  if not found then raise exception 'Ese gasto ya no existe' using errcode = 'P0002'; end if;
end $$;

-- El fichero lo sube la pantalla al bucket (la policy de storage ya exige admin+gastos y la
-- carpeta de un gasto vivo); lo que ya NO decide la pantalla es la entrada de la lista: el
-- servidor comprueba que el objeto existe en ESA carpeta y apunta él la fecha.
create or replace function public.gasto_anade_justificante(p_id uuid, p_ruta text, p_nombre text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public._gasto_puede() then raise exception 'Gastos exige ser administrador con la herramienta «Gastos»' using errcode = '42501'; end if;
  if p_ruta is null or split_part(p_ruta, '/', 1) <> p_id::text then
    raise exception 'Ese justificante no es de este gasto' using errcode = '42501';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'gastos' and o.name = p_ruta) then
    raise exception 'El fichero no se ha subido: vuelve a intentarlo' using errcode = 'P0002';
  end if;
  update public.gastos g set justificantes = g.justificantes || jsonb_build_array(jsonb_build_object(
      'path', p_ruta, 'nombre', left(coalesce(nullif(btrim(p_nombre), ''), split_part(p_ruta, '/', 2)), 200), 'subido_en', now()))
  where g.id = p_id and not (g.justificantes @> jsonb_build_array(jsonb_build_object('path', p_ruta)));
end $$;

revoke all on function public.gasto_guarda(uuid, jsonb), public.gasto_marca_pagado(uuid, date, text),
  public.gasto_pph_ingresado(uuid, date), public.gasto_anula(uuid, text), public.gasto_anade_justificante(uuid, text, text)
  from public, anon;
grant execute on function public.gasto_guarda(uuid, jsonb), public.gasto_marca_pagado(uuid, date, text),
  public.gasto_pph_ingresado(uuid, date), public.gasto_anula(uuid, text), public.gasto_anade_justificante(uuid, text, text)
  to authenticated;
