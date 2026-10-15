-- LAW-610 · CC00040 lleva 44.000 € — 15-oct-2026, sesión lawang-cola-2 (orquestador agencia-c0). Cambio de DATOS, una fila.
--
-- Qué pasa: el contrato de construcción CC00040 (venta RP00079, parcela SH-3 de Sumba Hills) no tiene precio, y sin precio no
-- hay tope de facturación. INV00071 (69.000 €, sin enviar, sin cobros) se le facturó entera: 69.000 = suelo 25.000 (RP00079) +
-- obra 44.000 de SH-3.
-- Decisión del owner (15-oct, vía agencia-c0): «CC00040 lleva 44.000 €… prepáralo como migración… antes de aplicar, comprueba
-- que SH-3 sigue en 69.000». Con 69.000 la obra subiría de 44.000 a 69.000 y la unidad a 94.000 (trg_unidad_precio_suma).
-- INV00071 NO se toca: 25.000 de esa factura son de la parcela (RP00079); el tope de la venta es 25.000 + 44.000 = 69.000.
--
-- Qué escribe: contratos.precio_total = 44000 de CC00040 y, si su papel no trae precio y no está en firma, también
-- datos.fields.precio_total = '44000' (contrato_guarda recalcula precio_total desde ese campo en cada guardado de un contrato
-- sin firmar: sin él, el próximo guardado lo volvería a dejar sin precio). Si el papel ya trae OTRO precio, PARA.
-- Guardas: el contrato por id exacto, su número, su padre, sin precio, EUR y sin liberar; SH-3 a 69.000 = 25.000 + 44.000
-- antes y después, y su estado sin cambiar; las comisiones de la venta (comisiones_devengadas) sin un cambio. Cualquier
-- desajuste PARA y no escribe nada (es un solo bloque).
-- Efecto que se ve: por contrato, CC00040 queda con 69.000 facturados sobre 44.000 de precio (25.000 de más, que son de la
-- parcela); el tope de la VENTA cuadra (69.000 de 69.000). El ensayo lo enseña con _cadena_saldo_en.
-- Lo prueba el ensayo deshecho contracts/sql/ensayo_law610_612_viva.sql (lanza_ensayo_viva.py, marca «RES LAW610-612»).
-- Reversión: update public.contratos set precio_total = null (y, si se escribió, datos #- '{fields,precio_total}') where id =
-- '93d557dc-814b-48df-b127-adc34f6f191e'.
do $law610$
declare
  c_contrato constant uuid := '93d557dc-814b-48df-b127-adc34f6f191e';   -- CC00040
  c_raiz     constant uuid := '637f9a44-cd31-47eb-a636-5fe33255eab3';   -- RP00079
  c_precio   constant numeric := 44000;
  v_c record; v_u record; v_u2 record; v_n int; v_campo text; v_firmas int; v_obra numeric;
  v_com_antes text; v_com_despues text;
begin
  select c.id, c.numero, c.contrato_padre_id, c.precio_total, c.moneda, c.liberado_en, c.datos->'fields'->>'precio_total' as campo
    into v_c from public.contratos c where c.id = c_contrato for update;
  if not found or v_c.numero <> 'CC00040' or v_c.contrato_padre_id is distinct from c_raiz or v_c.precio_total is not null
     or v_c.moneda is distinct from 'EUR' or v_c.liberado_en is not null then
    raise exception 'PARADA LAW-610: CC00040 no está como se midió el 15-oct (numero %, padre %, precio %, moneda %, liberado %)',
      v_c.numero, v_c.contrato_padre_id, v_c.precio_total, v_c.moneda, v_c.liberado_en;
  end if;
  v_campo := nullif(btrim(coalesce(v_c.campo, '')), '');
  if v_campo is not null and public.lw_parse_importe(v_campo) is distinct from c_precio then
    raise exception 'PARADA LAW-610: el papel de CC00040 ya dice otro precio («%»)', v_campo;
  end if;

  select count(*) into v_n from public.unidades u where u.contrato_id = c_raiz;
  select u.id, u.codigo, u.estado, u.precio, u.precio_suelo, u.precio_construccion into v_u
    from public.unidades u where u.contrato_id = c_raiz;
  if v_n <> 1 or v_u.codigo <> 'SH-3' or v_u.precio <> 69000 or v_u.precio_suelo <> 25000 or v_u.precio_construccion <> 44000 then
    raise exception 'PARADA LAW-610: SH-3 no está en 69.000 = 25.000 + 44.000 (unidades %, código %, precio %, suelo %, obra %)',
      v_n, v_u.codigo, v_u.precio, v_u.precio_suelo, v_u.precio_construccion;
  end if;

  -- el cambio de precio dispara la reconciliación de comisiones de la venta: no tiene que mover ninguna
  select coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '') into v_com_antes
    from public.comisiones_devengadas d where d.contrato_raiz_id in (c_raiz, c_contrato);

  select count(*) into v_firmas from public.contrato_firmas f where f.contrato_id = c_contrato and f.estado in ('pendiente', 'firmado');
  if v_campo is null and v_firmas = 0 then
    update public.contratos c
       set precio_total = c_precio,
           datos = jsonb_set(c.datos, '{fields,precio_total}', to_jsonb(c_precio::text), true)
     where c.id = c_contrato;
  else
    update public.contratos c set precio_total = c_precio where c.id = c_contrato;
  end if;

  select u.estado, u.precio, u.precio_suelo, u.precio_construccion into v_u2 from public.unidades u where u.id = v_u.id;
  select x.obra_precio into v_obra from public._unidad_cobro_cascada(v_u.id) x;
  if v_u2.precio <> 69000 or v_u2.precio_construccion <> 44000 or v_u2.estado is distinct from v_u.estado
     or v_obra is distinct from c_precio then
    raise exception 'PARADA LAW-610: tras el cambio SH-3 queda en precio %, obra %, estado % (antes %), obra de la cascada %',
      v_u2.precio, v_u2.precio_construccion, v_u2.estado, v_u.estado, v_obra;
  end if;
  select coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '') into v_com_despues
    from public.comisiones_devengadas d where d.contrato_raiz_id in (c_raiz, c_contrato);
  if v_com_despues is distinct from v_com_antes then
    raise exception 'PARADA LAW-610: cambian las comisiones de la venta RP00079. Antes: %. Después: %',
      left(v_com_antes, 900), left(v_com_despues, 900);
  end if;
  raise notice 'LAW-610 ok: CC00040 precio_total 44000 (papel %), SH-3 % en 69000, obra de la cascada %',
    case when v_campo is null and v_firmas = 0 then 'escrito' when v_campo is not null then 'ya lo traía' else 'en firma, sin tocar' end,
    v_u2.estado, v_obra;
end $law610$;
