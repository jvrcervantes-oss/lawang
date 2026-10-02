-- AXW-45 (Seguridad, 2-oct-2026): `banco_de_servidor` solo lo escribe el servidor (ERP maestro, B1). El papel de la factura
-- (intranet/facturas/documento.js) imprime banco_* tal cual cuando esa marca es true, asi que en Lawang un agente podia
-- mandar `banco_de_servidor:true` + su IBAN en datos.fields y el PDF lo imprimia sin que se vea en el editor.
-- Lawang NO escribe nunca esa marca (la cuenta se resuelve en el navegador contra el catalogo; «otros» se ve en el editor),
-- asi que factura_guarda la quita siempre. Es la misma resta que hace B1 en el maestro. Solo anade ese bloque: el resto
-- del cuerpo es el vivo de 2-oct-2026.
create or replace function public.factura_guarda(p_id uuid, p_factura jsonb)
 returns table(id uuid, numero text, total numeric)
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
                    where c.id = v_contrato and public.puede_ver_contrato(c.id)) then
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

  -- AXW-45: la marca de «cuenta resuelta por el servidor» no viene nunca del navegador.
  if jsonb_typeof(v_datos->'fields') = 'object' then
    v_datos := jsonb_set(v_datos, '{fields}', (v_datos->'fields') - 'banco_de_servidor');
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
  if abs(v_pantalla - v_total) > power(10::numeric, -public.lw_decimales(v_moneda)) then
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
    if v_old.enviada and v_old.tipo = 'factura' then
      raise exception 'La factura % ya se envió: no se edita (ni cliente, ni empresa, ni fecha, ni importes). Se corrige con una rectificativa.', v_old.numero
        using errcode = '42501';
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
                and (public.es_suyo(v_autor) or public.es_manager_de(v_proy) or public._sm_ve_venta(v_contrato)))) then
      raise exception 'Con ese contrato el documento dejaría de ser tuyo o de tu proyecto' using errcode = '42501';
    end if;
  end if;
  return query select v_id, v_num, v_total;
end $function$;
