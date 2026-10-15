-- LAW-612 · INV00173 y REC00130 pasan a colgar de CC00088 — 15-oct-2026, sesión lawang-cola-2 (orquestador agencia-c0).
-- Cambio de DATOS, dos filas de facturas.
--
-- Qué pasa: INV00173 (factura) y REC00130 (recibí, ENVIADO el 27-sep) son 10.625 € de la obra (su papel dice «CC00088», el
-- contrato de construcción de la venta RP00026), pero cuelgan de RP00026, el Bloqueo de la parcela.
-- Decisión del owner (15-oct, vía agencia-c0): opción (a), colgarlas de CC00088, con tres condiciones: «el primer dinero va al
-- suelo siempre»; D4 sigue con 15.625 cobrados del suelo y «vendida»; la comisión de 5.900 € no se toca. «Si al moverlos baja
-- lo cobrado del suelo, NO los muevas.»
--
-- Medido antes (20261015101833_precio_cadena_vigente.sql): la cascada (_unidad_cobro_cascada_v2) junta en una BOLSA todo lo
-- cobrado de la venta (raíz + hijos, cuelgue de donde cuelgue) y llena primero el suelo: suelo = least(precio del Bloqueo,
-- bolsa). La bolsa de RP00026 es 15.625 (REC00017 5.000 + REC00130 10.625) antes y después: el suelo de D4 sigue en 15.625. El
-- reparto por contrato (_venta_cobro_atribuido) da el resto de la bolsa a la raíz, así que tampoco cambia.
-- REC00130 está enviado: trg_factura_enviada_no_cambia_emisor solo frena sociedad y número, que no se tocan. El cliente no se
-- vuelve a heredar (client_id ya viene puesto). contrato_numero pasa a 'CC00088', lo que ya dice su papel.
--
-- Guardas (todo antes de escribir): las dos filas por id exacto, con su número, tipo, total, moneda, sociedad, sin anular y
-- colgando de RP00026; la aplicación única REC00130 -> INV00173 por 10.625; CC00088 hijo de RP00026, EUR, sin liberar, de la
-- misma sociedad y del mismo comprador; D4 «vendida» con 15.625 de suelo cobrado y cumpliendo «vendida».
-- Después: D4 igual (suelo cobrado 15.625, cumple «vendida», sigue «vendida»), el reparto por contrato igual, la base de
-- comisión del 1-nov (_comisiones_bases_firmadas) igual, y las comisiones de la venta (comisiones_devengadas) y las de
-- administración del recibí (comision_admin_lineas) sin un solo cambio. Si algo cambia, PARA y no queda nada escrito.
-- La línea de comisión de administración de REC00130 guarda su contrato_id del día del devengo (RP00026) y no se toca: es la
-- foto del devengo (como recibi_numero); comision_admin_descuadres no mira el contrato. Decisión por defecto, reversible.
-- Lo prueba el ensayo deshecho contracts/sql/ensayo_law610_612_viva.sql (marca «RES LAW610-612»).
-- Reversión: update public.facturas set contrato_id = 'f0d47af2-5749-46eb-ad82-00415a95ef4d' (y contrato_numero al valor de
-- antes, que da el NOTICE) where id in (las dos de abajo).
do $law612$
declare
  c_raiz constant uuid := 'f0d47af2-5749-46eb-ad82-00415a95ef4d';   -- RP00026
  c_obra constant uuid := '54030d81-972f-4da1-9e16-643d033c5fe8';   -- CC00088
  c_inv  constant uuid := '9c69f301-566f-4c6c-9c60-5d87e60f97fd';   -- INV00173
  c_rec  constant uuid := 'c0babc5f-7dea-47b4-8cdf-65dad9a0e9e3';   -- REC00130
  c_apl  constant uuid := 'a9e95477-7b7c-42ae-980f-4663494d34cc';   -- REC00130 -> INV00173
  v_inv record; v_rec record; v_obra record; v_n int; v_u record; v_cli uuid; v_soc_obra text;
  v_cas_antes record; v_cas_despues record; v_estado text;
  v_com_antes text; v_com_despues text; v_adm_antes text; v_adm_despues text; v_atr_antes text; v_atr_despues text;
  v_bas_antes text; v_bas_despues text;
begin
  select f.numero, f.tipo, f.total, f.moneda, f.sociedad, f.contrato_id, f.contrato_numero, f.client_id,
         coalesce(f.anulada, false) as anulada
    into v_inv from public.facturas f where f.id = c_inv for update;
  select f.numero, f.tipo, f.total, f.moneda, f.sociedad, f.contrato_id, f.contrato_numero, f.client_id,
         coalesce(f.anulada, false) as anulada, coalesce(f.enviada, false) as enviada
    into v_rec from public.facturas f where f.id = c_rec for update;
  if v_inv.numero is distinct from 'INV00173' or v_inv.tipo <> 'factura' or v_inv.total <> 10625 or v_inv.moneda is distinct from 'EUR'
     or v_inv.anulada or v_inv.contrato_id is distinct from c_raiz
     or v_rec.numero is distinct from 'REC00130' or v_rec.tipo <> 'recibi' or v_rec.total <> 10625 or v_rec.moneda is distinct from 'EUR'
     or v_rec.anulada or v_rec.contrato_id is distinct from c_raiz or v_rec.sociedad is distinct from v_inv.sociedad then
    raise exception 'PARADA LAW-612: INV00173/REC00130 no están como se midió el 15-oct (% % % %, % % % %)',
      v_inv.numero, v_inv.total, v_inv.contrato_id, v_inv.anulada, v_rec.numero, v_rec.total, v_rec.contrato_id, v_rec.anulada;
  end if;
  select count(*) into v_n from public.recibi_aplicaciones ra where ra.recibi_id = c_rec;
  if v_n <> 1 or not exists (select 1 from public.recibi_aplicaciones ra
                              where ra.id = c_apl and ra.recibi_id = c_rec and ra.factura_id = c_inv and ra.importe_aplicado = 10625) then
    raise exception 'PARADA LAW-612: REC00130 no tiene la única aplicación a INV00173 por 10.625 (aplicaciones: %)', v_n;
  end if;

  select c.numero, c.contrato_padre_id, c.moneda, c.liberado_en,
         nullif(btrim(coalesce(c.datos_fields->>'sociedad_firmante', '')), '') as sociedad
    into v_obra from public.contratos c where c.id = c_obra;
  if v_obra.numero is distinct from 'CC00088' or v_obra.contrato_padre_id is distinct from c_raiz or v_obra.moneda is distinct from 'EUR'
     or v_obra.liberado_en is not null or (v_obra.sociedad is not null and v_obra.sociedad <> v_inv.sociedad) then
    raise exception 'PARADA LAW-612: CC00088 no sirve de destino (numero %, padre %, moneda %, liberado %, sociedad % frente a %)',
      v_obra.numero, v_obra.contrato_padre_id, v_obra.moneda, v_obra.liberado_en, v_obra.sociedad, v_inv.sociedad;
  end if;
  select cc.client_id into v_cli from public.contrato_compradores cc where cc.contrato_id = c_obra and cc.rol = 'adquiriente_1';
  if v_cli is not null and (v_inv.client_id is distinct from v_cli or v_rec.client_id is distinct from v_cli) then
    raise exception 'PARADA LAW-612: el comprador de CC00088 no es el de INV00173/REC00130';
  end if;

  select count(*) into v_n from public.unidades u where u.contrato_id = c_raiz;
  select u.id, u.codigo, u.estado, u.precio, u.precio_suelo into v_u from public.unidades u where u.contrato_id = c_raiz;
  select x.cobrado_suelo, x.cobrado_obra into v_cas_antes from public._unidad_cobro_cascada(v_u.id) x;
  if v_n <> 1 or v_u.codigo <> 'W3.1. - D4' or v_u.estado <> 'vendida' or v_cas_antes.cobrado_suelo <> 15625
     or not public.unidad_cumple_estado(v_u.id, 'vendida', v_u.precio, v_u.precio_suelo) then
    raise exception 'PARADA LAW-612: D4 no está vendida con 15.625 de suelo cobrado (unidades %, código %, estado %, suelo cobrado %)',
      v_n, v_u.codigo, v_u.estado, v_cas_antes.cobrado_suelo;
  end if;

  select coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '') into v_com_antes
    from public.comisiones_devengadas d where d.contrato_raiz_id in (c_raiz, c_obra);
  select coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '') into v_adm_antes
    from public.comision_admin_lineas l where l.recibi_id = c_rec;
  select coalesce(string_agg(a.contrato_id::text || '=' || a.cobrado_regla::text, '|' order by a.contrato_id), '') into v_atr_antes
    from public._venta_cobro_atribuido(c_raiz) a;
  -- bases de comisión de la regla del 1-nov: también juntan lo cobrado y llenan primero el suelo (least(suelo, todo)); las
  -- columnas «directo» son solo trazabilidad y sí cambian (5.000 / 10.625)
  select b.cobrado_suelo_firmado::text || '/' || b.cobrado_obra_firmada::text into v_bas_antes
    from public._comisiones_bases_firmadas(c_raiz) b;

  update public.facturas f set contrato_id = c_obra, contrato_numero = 'CC00088' where f.id in (c_inv, c_rec);

  select x.cobrado_suelo, x.cobrado_obra into v_cas_despues from public._unidad_cobro_cascada(v_u.id) x;
  select u.estado into v_estado from public.unidades u where u.id = v_u.id;
  if v_cas_despues.cobrado_suelo <> 15625 or v_estado <> 'vendida'
     or not public.unidad_cumple_estado(v_u.id, 'vendida', v_u.precio, v_u.precio_suelo) then
    raise exception 'PARADA LAW-612 (regla del owner: si baja lo cobrado del suelo, no se mueven): D4 queda con suelo cobrado %, estado %',
      v_cas_despues.cobrado_suelo, v_estado;
  end if;
  select coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '') into v_com_despues
    from public.comisiones_devengadas d where d.contrato_raiz_id in (c_raiz, c_obra);
  if v_com_despues is distinct from v_com_antes then
    raise exception 'PARADA LAW-612: cambian las comisiones de la venta. Antes: %. Después: %', left(v_com_antes, 900), left(v_com_despues, 900);
  end if;
  select coalesce(string_agg(to_jsonb(l)::text, '|' order by l.id), '') into v_adm_despues
    from public.comision_admin_lineas l where l.recibi_id = c_rec;
  if v_adm_despues is distinct from v_adm_antes then
    raise exception 'PARADA LAW-612: cambian las líneas de comisión de administración de REC00130';
  end if;
  select coalesce(string_agg(a.contrato_id::text || '=' || a.cobrado_regla::text, '|' order by a.contrato_id), '') into v_atr_despues
    from public._venta_cobro_atribuido(c_raiz) a;
  if v_atr_despues is distinct from v_atr_antes then
    raise exception 'PARADA LAW-612: cambia el reparto del cobro por contrato. Antes: %. Después: %', v_atr_antes, v_atr_despues;
  end if;
  select b.cobrado_suelo_firmado::text || '/' || b.cobrado_obra_firmada::text into v_bas_despues
    from public._comisiones_bases_firmadas(c_raiz) b;
  if v_bas_despues is distinct from v_bas_antes then
    raise exception 'PARADA LAW-612: cambia la base de comisión del 1-nov (suelo/obra cobrados firmados). Antes: %. Después: %',
      v_bas_antes, v_bas_despues;
  end if;
  raise notice 'LAW-612 ok: INV00173 y REC00130 cuelgan de CC00088 (contrato_numero antes: % y %); D4 vendida con suelo cobrado % (obra % -> %); comisiones y reparto sin cambios',
    v_inv.contrato_numero, v_rec.contrato_numero, v_cas_despues.cobrado_suelo, v_cas_antes.cobrado_obra, v_cas_despues.cobrado_obra;
end $law612$;
