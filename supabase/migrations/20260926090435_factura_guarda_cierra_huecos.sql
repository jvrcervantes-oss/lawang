-- factura_guarda v2 (26-sep-2026) — capa 1 de deploy sobre LAW-336 (Seguridad + Administración):
-- 1. `justificantes` ya no se acepta: `agente_ve_justificante` da acceso a un fichero de storage
--    si su ruta aparece en una factura que el agente ve, así que meter la ruta ajena en tu
--    propia factura te abría el justificante de otro. Facturas y proformas no usan justificantes
--    (0 de 353, medido); los recibís van por guardar_recibi.
-- 2. `client_id` con contrato: tiene que ser comprador de ESE contrato o un cliente visible para
--    quien emite (antes el cliente solo se comprobaba sin contrato; 1 de 342 facturas actuales
--    cae fuera del contrato y sigue editable por la segunda condición).
-- 3. El total que ve la pantalla es OBLIGATORIO: todas las pantallas lo mandan, y sin él no hay
--    con qué comparar (Administración).
-- Aplicada por MCP el 26-sep y probada (alta con su comprador, sin total, cliente ajeno,
-- justificantes ignorados) en un DO que restaura la numeración antes del rollback.
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
  v_tot jsonb; v_total numeric; v_id uuid; v_num text; v_proy uuid; v_autor text; n int;
begin
  if (select auth.uid()) is null then
    raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501';
  end if;
  if v_tipo = 'recibi' then
    raise exception 'Un recibí se guarda con guardar_recibi, no aquí' using errcode = '22023';
  end if;
  if v_tipo not in ('factura', 'proforma') then
    raise exception 'Tipo de documento desconocido: %', v_tipo using errcode = '22023';
  end if;
  if not (public.es_super_admin() or (public.es_agente() and public.puede('facturas'))) then
    raise exception 'Emitir o editar facturas exige la herramienta «Facturas»' using errcode = '42501';
  end if;
  if v_contrato is not null then
    if not exists (select 1 from public.contratos c
                    where c.id = v_contrato and public.contrato_visible(c.creado_por, c.proyecto_id)) then
      raise exception 'No puedes emitir un documento sobre un contrato que no ves' using errcode = '42501';
    end if;
  end if;
  if v_client is not null then
    if not (
         (v_contrato is not null and exists (select 1 from public.contrato_compradores cc
                                              where cc.contrato_id = v_contrato and cc.client_id = v_client))
      or exists (select 1 from public.clients k
                  where k.id = v_client and public.cliente_visible(k.propietario, k.id))) then
      raise exception 'Ese cliente no es comprador de este contrato ni un cliente que veas' using errcode = '42501';
    end if;
  end if;

  v_tot := public.factura_totales(v_datos->'lineas', v_moneda, v_datos->'fields'->>'imp_pct');
  v_total := (v_tot->>'total')::numeric;
  if (v_tot->>'pct')::numeric not between 0 and 100 then
    raise exception 'El impuesto tiene que estar entre 0 y 100 %%' using errcode = '22023';
  end if;
  if (v_tot->>'subtotal')::numeric <= 0 then
    raise exception 'El documento no tiene importe (un total negativo es una rectificativa, no una factura)'
      using errcode = '22023';
  end if;
  if v_pantalla is null then
    raise exception 'Falta el total que se ve en pantalla: recarga la página y vuelve a guardar' using errcode = '22023';
  end if;
  if v_pantalla <> v_total then
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
       v_datos, '[]'::jsonb)
    returning f.id, f.numero into v_id, v_num;
  else
    select * into v_old from public.facturas f where f.id = p_id for update;
    if not found then
      raise exception 'Ese documento ya no existe' using errcode = 'P0002';
    end if;
    if v_old.tipo = 'recibi' then
      raise exception 'Un recibí se edita con guardar_recibi, no aquí' using errcode = '22023';
    end if;
    if not public._factura_puede_editar(v_old) then
      raise exception 'No puedes editar este documento (anulado, o no es tuyo ni de tu proyecto)' using errcode = '42501';
    end if;
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
      fecha_emision = nullif(p_factura->>'fecha_emision', '')::date, datos = v_datos
    where f.id = p_id
    returning f.id, f.numero, f.proyecto_id, f.creado_por into v_id, v_num, v_proy, v_autor;
    get diagnostics n = row_count;
    if n <> 1 then
      raise exception 'No se ha guardado (0 filas)' using errcode = 'P0002';
    end if;
    if not (public.es_super_admin()
            or (public.es_agente() and public.puede('facturas')
                and (public.es_suyo(v_autor) or public.es_manager_de(v_proy)))) then
      raise exception 'Con ese contrato el documento dejaría de ser tuyo o de tu proyecto' using errcode = '42501';
    end if;
  end if;
  return query select v_id, v_num, v_total;
end $$;
