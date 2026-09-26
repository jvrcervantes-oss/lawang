-- destructivo-ok: el unico DELETE vive DENTRO de factura_borra (replica literal de la policy «borrar facturas»); esta migracion no borra ninguna fila, solo crea funciones.
-- ════════════════════════════════════════════════════════════════════════════
-- Frontera frontend/backend — FACTURAS por el servidor (26-sep-2026, LAW-336)
-- Aplicada por MCP el 26-sep y probada con 16 casos (agente, super admin, sin sesión,
-- anon; total falso, contrato ajeno, recibí, negativo, enviada, anulada) en un DO que
-- restaura las secuencias de numeración antes del rollback.
-- ════════════════════════════════════════════════════════════════════════════
-- Norma del owner: contexto/patrones_tecnicos.md -> «Frontera frontend / backend».
-- Plan y revisión previa #119 (Datos + Seguridad + Administración):
-- encargos/20260926_lawang_frontera_f1_facturas.md
--
-- Esta migración SOLO AÑADE: las pantallas siguen funcionando igual hasta que se
-- pasan a estas RPCs, y el REVOKE de escritura directa va en otra migración, después.
--
-- Por qué SECURITY DEFINER (rev. #119, Datos): tras el revoke, `authenticated` ya no
-- puede escribir en `facturas`; una RPC INVOKER moriría con 42501. Así que cada RPC
-- comprueba A MANO, en su cabecera, exactamente lo que hoy comprueban las policies —
-- y lo que la policy de alta NO miraba (Seguridad): que el contrato o el cliente al que
-- va la factura sea visible para quien la emite. Los triggers no cambian: leen
-- auth.uid()/auth.email() de los claims del JWT, que siguen ahí dentro de un DEFINER.

-- ── 1. Totales en el servidor — port de calcTotales/lwParseImporte ─────────────
-- Paridad con el JS medida el 26-sep: 0 diferencias en 140 importes y 70 facturas
-- (incluidos los formatos reales «63.565»). En numeric exacto y half-up: no se porta
-- el error de coma flotante de Math.round (Administración #119).

create or replace function public.lw_parse_importe(v text)
returns numeric language plpgsql immutable set search_path = '' as $$
declare
  bruto text := coalesce(v, '');
  negativo boolean; s text; sep text; d int; c int; resto text; limpio text;
begin
  -- El signo se mira ANTES de limpiar (como el JS: «-5.000» no es +5000).
  negativo := left(btrim(bruto), 1) = '-' or bruto ~ '^\s*-';
  s := regexp_replace(bruto, '[^0-9.,]', '', 'g');
  if s !~ '[0-9]' then return null; end if;
  d := case when strpos(s, '.') = 0 then 0 else length(s) - strpos(reverse(s), '.') + 1 end;
  c := case when strpos(s, ',') = 0 then 0 else length(s) - strpos(reverse(s), ',') + 1 end;
  sep := case when d > c then '.' when c > d then ',' else '' end;
  if sep <> '' then
    resto := substr(s, (case when sep = '.' then d else c end) + 1);
    -- Más de un separador igual, o exactamente 3 dígitos detrás: era de miles.
    if array_length(string_to_array(s, sep), 1) > 2 or resto ~ '^[0-9]{3}$' then sep := ''; end if;
  end if;
  if sep = '' then
    limpio := regexp_replace(s, '[.,]', '', 'g');
  else
    limpio := replace(regexp_replace(s, case when sep = '.' then '[,]' else '[.]' end, '', 'g'), sep, '.');
  end if;
  limpio := substring(limpio from '^[0-9]*\.?[0-9]*');
  if limpio is null or limpio in ('', '.') then return null; end if;
  return case when negativo then -limpio::numeric else limpio::numeric end;
end $$;

-- Decimales por moneda: espejo de LW_DECIMALES (contracts/assets/dinero.js).
create or replace function public.lw_decimales(moneda text)
returns int language sql immutable set search_path = '' as $$
  select case upper(coalesce(moneda, '')) when 'IDR' then 0 else 2 end
$$;

create or replace function public.factura_totales(lineas jsonb, moneda text, pct text)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  dec int := public.lw_decimales(moneda);
  sub numeric := 0; p numeric; imp numeric := 0; l jsonb;
begin
  if jsonb_typeof(lineas) = 'array' then
    for l in select * from jsonb_array_elements(lineas) loop
      sub := sub + coalesce(public.lw_parse_importe(l->>'importe'), 0);
    end loop;
  end if;
  sub := round(sub, dec);
  p := coalesce(public.lw_parse_importe(pct), 0);
  if p <> 0 then imp := round(sub * p / 100, dec); end if;
  return jsonb_build_object('subtotal', sub, 'pct', p, 'impuesto', imp, 'total', round(sub + imp, dec));
end $$;

revoke all on function public.lw_parse_importe(text), public.lw_decimales(text),
  public.factura_totales(jsonb, text, text) from public, anon, authenticated;

-- ── 2. Permiso de edición — la policy «el autor, su manager, o un admin editan…» ──
-- Una sola definición para las RPCs; si cambia la policy, cambia esto (y al revés).
create or replace function public._factura_puede_editar(f public.facturas)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.es_super_admin()
      or (not f.anulada and public.es_agente() and public.puede('facturas')
          and (public.es_suyo(f.creado_por) or public.es_manager_de(f.proyecto_id)))
$$;
revoke all on function public._factura_puede_editar(public.facturas) from public, anon, authenticated;

-- ── 3. Emitir / editar ─────────────────────────────────────────────────────────
-- Lista blanca (Seguridad #119): de p_factura solo se leen tipo, sociedad, cliente_nombre,
-- proyecto_nombre, contrato_numero, contrato_id, client_id, moneda, fecha_emision, datos,
-- justificantes y el total que VE la pantalla (solo para compararlo). id, numero, total
-- guardado, creado_por, anulada, enviada, fecha_envio y justificante_path NO se aceptan:
-- los ponen los triggers o sus propias RPCs.
create or replace function public.factura_guarda(p_id uuid, p_factura jsonb)
returns table (id uuid, numero text, total numeric)
language plpgsql security definer set search_path = '' as $$
declare
  v_old public.facturas%rowtype;
  v_tipo text := coalesce(nullif(p_factura->>'tipo', ''), 'factura');
  v_contrato uuid := nullif(p_factura->>'contrato_id', '')::uuid;
  v_client uuid := nullif(p_factura->>'client_id', '')::uuid;
  v_moneda text := nullif(p_factura->>'moneda', '');
  v_datos jsonb := coalesce(p_factura->'datos', '{}'::jsonb);
  v_pantalla numeric := public.lw_parse_importe(p_factura->>'total');
  v_just jsonb := case when jsonb_typeof(p_factura->'justificantes') = 'array' then p_factura->'justificantes' end;
  v_tot jsonb; v_total numeric; v_id uuid; v_num text; v_proy uuid; v_autor text; n int;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  -- Los recibís tienen su camino (aplicaciones + justificante en la misma transacción).
  if v_tipo = 'recibi' then
    raise exception 'Un recibí se guarda con guardar_recibi, no aquí' using errcode = '22023';
  end if;
  if v_tipo not in ('factura', 'proforma') then
    raise exception 'Tipo de documento desconocido: %', v_tipo using errcode = '22023';
  end if;
  -- Policy de alta: agente activo con la herramienta «Facturas».
  if not (public.es_super_admin() or (public.es_agente() and public.puede('facturas'))) then
    raise exception 'Emitir o editar facturas exige la herramienta «Facturas»' using errcode = '42501';
  end if;
  -- Lo que la policy de alta NO miraba (Seguridad #119): a qué contrato o cliente va.
  if v_contrato is not null then
    if not exists (select 1 from public.contratos c
                    where c.id = v_contrato and public.contrato_visible(c.creado_por, c.proyecto_id)) then
      raise exception 'No puedes emitir un documento sobre un contrato que no ves' using errcode = '42501';
    end if;
  elsif v_client is not null then
    if not exists (select 1 from public.clients k
                    where k.id = v_client and public.cliente_visible(k.propietario, k.id)) then
      raise exception 'No puedes emitir un documento a un cliente que no ves' using errcode = '42501';
    end if;
  end if;

  -- Totales: los calcula el SERVIDOR. Si la pantalla enseñaba otra cifra, se rechaza en
  -- vez de corregir en silencio (Administración #119): lo que se ve es lo que se guarda.
  v_tot := public.factura_totales(v_datos->'lineas', v_moneda, v_datos->'fields'->>'imp_pct');
  v_total := (v_tot->>'total')::numeric;
  if (v_tot->>'pct')::numeric not between 0 and 100 then
    raise exception 'El impuesto tiene que estar entre 0 y 100 %%' using errcode = '22023';
  end if;
  if (v_tot->>'subtotal')::numeric <= 0 then
    raise exception 'El documento no tiene importe (un total negativo es una rectificativa, no una factura)'
      using errcode = '22023';
  end if;
  if v_pantalla is not null and v_pantalla <> v_total then
    raise exception 'El total no cuadra: la pantalla dice % y las líneas suman %. Recarga la página y vuelve a guardar.',
      v_pantalla, v_total using errcode = '22023';
  end if;
  v_datos := jsonb_set(v_datos, '{totales}', v_tot, true);

  if p_id is null then
    insert into public.facturas as f
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id, client_id,
       total, moneda, fecha_emision, datos, justificantes)
    values
      (v_tipo, p_factura->>'sociedad', nullif(p_factura->>'cliente_nombre', ''),
       nullif(p_factura->>'proyecto_nombre', ''), nullif(p_factura->>'contrato_numero', ''),
       v_contrato, v_client, v_total, v_moneda, nullif(p_factura->>'fecha_emision', '')::date,
       v_datos, coalesce(v_just, '[]'::jsonb))
    returning f.id, f.numero into v_id, v_num;
  else
    select * into v_old from public.facturas f where f.id = p_id for update;
    if not found then
      raise exception 'Ese documento ya no existe' using errcode = 'P0002';
    end if;
    if v_old.tipo = 'recibi' then
      raise exception 'Un recibí se edita con guardar_recibi, no aquí' using errcode = '22023';
    end if;
    -- Policy de edición sobre la fila de ANTES.
    if not public._factura_puede_editar(v_old) then
      raise exception 'No puedes editar este documento (anulado, o no es tuyo ni de tu proyecto)' using errcode = '42501';
    end if;
    -- Una enviada no reescribe sus importes (Administración #119): eso es una rectificativa.
    if v_old.enviada and (v_total is distinct from v_old.total
                          or v_moneda is distinct from v_old.moneda
                          or (v_datos->'lineas') is distinct from (v_old.datos->'lineas')) then
      raise exception 'El documento % ya se envió: sus importes no se cambian, se emite una rectificativa', v_old.numero
        using errcode = '42501';
    end if;
    update public.facturas f set
      tipo = v_tipo, sociedad = p_factura->>'sociedad',
      cliente_nombre = nullif(p_factura->>'cliente_nombre', ''),
      proyecto_nombre = nullif(p_factura->>'proyecto_nombre', ''),
      contrato_numero = nullif(p_factura->>'contrato_numero', ''),
      contrato_id = v_contrato, client_id = v_client, total = v_total, moneda = v_moneda,
      fecha_emision = nullif(p_factura->>'fecha_emision', '')::date, datos = v_datos,
      justificantes = coalesce(v_just, f.justificantes)
    where f.id = p_id
    returning f.id, f.numero, f.proyecto_id, f.creado_por into v_id, v_num, v_proy, v_autor;
    get diagnostics n = row_count;
    if n <> 1 then
      raise exception 'No se ha guardado (0 filas)' using errcode = 'P0002';
    end if;
    -- CHECK de la policy sobre la fila de DESPUÉS (el proyecto lo hereda del contrato).
    if not (public.es_super_admin()
            or (public.es_agente() and public.puede('facturas')
                and (public.es_suyo(v_autor) or public.es_manager_de(v_proy)))) then
      raise exception 'Con ese contrato el documento dejaría de ser tuyo o de tu proyecto' using errcode = '42501';
    end if;
  end if;
  return query select v_id, v_num, v_total;
end $$;

-- ── 4. Anular / reactivar / borrar ─────────────────────────────────────────────
create or replace function public.factura_anula(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if v_old.anulada then raise exception 'El documento % ya está anulado', v_old.numero using errcode = '22023'; end if;
  if not public._factura_puede_editar(v_old) then
    raise exception 'No puedes anular este documento' using errcode = '42501';
  end if;
  update public.facturas f set anulada = true where f.id = p_id;
end $$;

-- Solo toca `anulada` (rev. #119, Datos): el trigger factura_anulada_solo_cambia_autor
-- acepta la reactivación únicamente si NADA más cambia, y exige super_admin y que no
-- se enviara. La RPC lo comprueba antes para dar un mensaje claro; el trigger manda.
create or replace function public.factura_reactiva(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not public.es_super_admin() then
    raise exception 'Solo un super admin puede reactivar un documento anulado' using errcode = '42501';
  end if;
  if not v_old.anulada then raise exception 'El documento % no está anulado', v_old.numero using errcode = '22023'; end if;
  update public.facturas f set anulada = false where f.id = p_id;
end $$;

-- Policy «borrar facturas», literal.
create or replace function public.factura_borra(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not (not coalesce(v_old.enviada, false)
          and (public.es_super_admin()
               or (public.es_admin() and not coalesce(v_old.anulada, false)
                   and not exists (select 1 from public.recibi_aplicaciones ra
                                    where ra.factura_id = v_old.id or ra.recibi_id = v_old.id)))) then
    raise exception 'No puedes borrar este documento (enviado, anulado, con cobros aplicados, o sin permiso). Lo normal es anularlo.'
      using errcode = '42501';
  end if;
  delete from public.facturas f where f.id = p_id;
end $$;

-- ── 5. Marcar como enviada — para la edge send-contract-email (rev. #119, Datos) ──
-- La edge escribía `enviada` con el JWT del usuario; tras el revoke dejaría de marcar
-- sin que nadie lo notara. Misma regla que la policy de edición. La fecha es la del
-- PRIMER envío: un reenvío no la mueve y cuenta como marcada.
create or replace function public.factura_marca_enviada(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then return false; end if;
  if v_old.enviada then return true; end if;
  if not public._factura_puede_editar(v_old) then
    raise exception 'No puedes marcar este documento como enviado' using errcode = '42501';
  end if;
  update public.facturas f set enviada = true, fecha_envio = now() where f.id = p_id;
  return true;
end $$;

revoke all on function public.factura_guarda(uuid, jsonb), public.factura_anula(uuid),
  public.factura_reactiva(uuid), public.factura_borra(uuid), public.factura_marca_enviada(uuid)
  from public, anon;
grant execute on function public.factura_guarda(uuid, jsonb), public.factura_anula(uuid),
  public.factura_reactiva(uuid), public.factura_borra(uuid), public.factura_marca_enviada(uuid)
  to authenticated;
