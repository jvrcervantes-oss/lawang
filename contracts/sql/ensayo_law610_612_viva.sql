-- ENSAYO DESHECHO de LAW-610, LAW-611 y LAW-612 en la viva de Lawang (15-oct-2026, lawang-cola-2).
-- GENERADO por contracts/sql/genera_ensayo_law610_612.py: no se edita a mano.
-- Se lanza con tools/lanza_ensayo_viva.py (begin … rollback, nunca confirma), marca «RES LAW610-612».

-- Foto de las comisiones de la venta RP00079 (devengos, sus diferencias y el último error del recálculo automático): la
-- reconciliación que dispara LAW-610 es DIFERIDA, así que se compara antes y después de forzarla en el resumen (revisor, 15-oct).
create or replace function pg_temp.e612_comisiones_rp00079() returns text language sql as $f$
  select coalesce((select string_agg(to_jsonb(d)::text, '|' order by d.id) from public.comisiones_devengadas d
                    where d.contrato_raiz_id in ('637f9a44-cd31-47eb-a636-5fe33255eab3', '93d557dc-814b-48df-b127-adc34f6f191e')), '')
      || ' # ' || coalesce((select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.comisiones_diferencias x
                            join public.comisiones_devengadas d on d.id = x.devengo_id
                           where d.contrato_raiz_id = '637f9a44-cd31-47eb-a636-5fe33255eab3'), '')
      || ' # ' || coalesce((select string_agg(coalesce(i.ultimo_error_en::text, '-'), ',') from public.comisiones_interruptor i), '')
$f$;

-- ── ANTES (solo lee; lo guarda en una variable de la transacción para el resumen) ───────────────────────────────────────
do $antes$
declare v text;
begin
  select format('CC00040 por contrato: precio %s, sin precio %s, facturado %s', s.precio, s.sin_precio, s.facturado) into v
    from public._cadena_saldo_en('93d557dc-814b-48df-b127-adc34f6f191e', 'EUR') s;
  v := v || ' · bases 1-nov RP00026 (suelo/obra cobrados firmados · directo suelo/obra): ' ||
       (select b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada || ' · ' || b.cobrado_directo_suelo || '/' || b.cobrado_directo_obra
          from public._comisiones_bases_firmadas('f0d47af2-5749-46eb-ad82-00415a95ef4d') b);
  perform set_config('ensayo_law610_612.antes', v, true);
  perform set_config('ensayo_law610_612.com79', pg_temp.e612_comisiones_rp00079(), true);
end $antes$;
-- ── 20261015210000_law610_cc00040_precio.sql · sha256 bb15a22c49db31c8135f936d585c1a1532bd4867e2b8d434adedfa98ddf32137 ──
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
-- antes y después, y su estado sin cambiar; CC00040 SIN FIRMAR (si no, su precio entraría en la base de comisión de la venta:
-- ver el bloque). Cualquier desajuste PARA y no escribe nada (es un solo bloque). El ensayo fuerza la reconciliación diferida
-- de comisiones y enseña las de RP00079 antes y después.
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

  -- Comisiones (revisor, 15-oct): el cambio de precio dispara zz_comisiones_reconcilia_cambio, DIFERIDO (corre al confirmar,
  -- fuera de este bloque) y que se traga sus errores: una foto antes/después aquí no vería nada. La base de comisión solo suma
  -- contratos FIRMADOS (_comisiones_bases_firmadas, _comisiones_precio_total): con CC00040 sin firmar, su precio no entra en
  -- ninguna base y la reconciliación no tiene nada que mover. Por eso se exige sin firmar; firmado, PARA (y se decide aparte).
  if exists (select 1 from public.contratos c where c.id = c_contrato and coalesce(c.bloqueado, false)) then
    raise exception 'PARADA LAW-610: CC00040 está firmado: su precio entraría en la base de comisión de RP00079';
  end if;

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
  raise notice 'LAW-610 ok: CC00040 precio_total 44000 (papel %), SH-3 % en 69000, obra de la cascada %',
    case when v_campo is null and v_firmas = 0 then 'escrito' when v_campo is not null then 'ya lo traía' else 'en firma, sin tocar' end,
    v_u2.estado, v_obra;
end $law610$;
-- ── 20261015210100_law611_w3c3_bloqueada.sql · sha256 920a4e1fddecd3f2cd59999df0c5e549f55edf81fc3289285c1d009586988661 ──
-- LAW-611 · W3 - C3 (RP00070) pasa de «vendida» a «bloqueada» — 15-oct-2026, sesión lawang-cola-2 (orquestador agencia-c0).
-- Cambio de DATOS, una fila de unidades y su fila de historial.
--
-- Qué pasa: la parcela W3 - C3 figura «vendida» con el Bloqueo RP00070 SIN firmar y el suelo cobrado al 67 % (22.250 de 33.250).
-- Con la regla de hoy no lo estaría, y la bajada automática (avanza_unidad_por_cobro) solo baja con el Bloqueo firmado.
-- Decisión del owner: opción (a), pasarla a «bloqueada» a mano. La regla para las demás no cambia.
--
-- Medido antes (migraciones 20261007035823, 20261007051946, 20260921060542 y 20261014032925):
--   · trg_unidad_vendida_exige_cobro solo frena al ENTRAR en vendida/cobrada: bajar a bloqueada no lo dispara; no hace falta la
--     excepción app.unidad_estado_excepcion (y no se usa: su historial diría «excepcion decidida por el owner» sin el porqué).
--   · trg_protege_liberado_contrato es de contratos (que no se toque liberado_en fuera de libera_reserva): aquí no se toca ningún
--     contrato.
--   · trg_unidad_estado_al_historial (diferido: corre al confirmar) no escribe su fila si ya hay una de esta transacción
--     (mismo en = now(), mismo antes y después): la fila con el motivo de LAW-611 se escribe aquí, tras el update y con la
--     fila tal como queda, y la suya se omite (corre después, al confirmar). El ensayo
--     lo comprueba forzando los diferidos (set constraints all immediate) antes de contar.
--   · avanza_unidad_por_cobro deja una «bloqueada» como está mientras su Bloqueo no esté firmado: no la vuelve a subir.
--   · trg_unidad_estado_aviso_manager avisa a los managers del proyecto («Unidad W3 - C3 — bloqueada»): es el aviso interno de
--     siempre en un cambio de estado.
-- 89.000 frente a 95.000: la unidad tiene construcción 89.000 de catálogo; el contrato de obra CC00032 (borrador) dice 95.000.
-- La cascada ya usa el del contrato (owner 14-oct: «manda el contrato»), y unidad_cumple_estado('cobrada') toma el mayor. No es
-- otro fallo ni se toca aquí.
-- Guardas: la unidad por el id del contrato, su código, «vendida», el Bloqueo sin firmar y sin liberar, y que hoy NO cumple
-- vendida. Cualquier desajuste PARA y no escribe nada.
-- Lo prueba el ensayo deshecho contracts/sql/ensayo_law610_612_viva.sql (marca «RES LAW610-612»).
-- Reversión: update public.unidades set estado = 'vendida' where id = <la de W3 - C3> con
-- set_config('app.unidad_estado_excepcion', 'on', true) (subir a vendida sin el suelo cobrado es la excepción del owner).
do $law611$
declare
  c_raiz constant uuid := '40f7bd40-52e5-431e-a7ab-0f8f3752ff52';   -- RP00070
  v_r record; v_u public.unidades; v_n int; v_despues jsonb; v_estado text;
begin
  select c.numero, c.tipo, coalesce(c.bloqueado, false) as firmado, c.liberado_en into v_r
    from public.contratos c where c.id = c_raiz;
  if not found or v_r.numero <> 'RP00070' or v_r.tipo <> 'reserva_parcela' or v_r.firmado or v_r.liberado_en is not null then
    raise exception 'PARADA LAW-611: RP00070 no está como se midió (numero %, tipo %, firmado %, liberado %)',
      v_r.numero, v_r.tipo, v_r.firmado, v_r.liberado_en;
  end if;
  select count(*) into v_n from public.unidades u where u.contrato_id = c_raiz;
  select * into v_u from public.unidades u where u.contrato_id = c_raiz for update;
  if v_n <> 1 or v_u.codigo <> 'W3 - C3' or v_u.estado <> 'vendida' then
    raise exception 'PARADA LAW-611: la parcela de RP00070 no es W3 - C3 vendida (unidades %, código %, estado %)',
      v_n, v_u.codigo, v_u.estado;
  end if;
  if public.unidad_cumple_estado(v_u.id, 'vendida', v_u.precio, v_u.precio_suelo) then
    raise exception 'PARADA LAW-611: W3 - C3 ya cumple «vendida» (el suelo está cobrado): no se baja';
  end if;

  update public.unidades u set estado = 'bloqueada' where u.id = v_u.id;
  -- «después» = la fila tal como queda (tras los disparadores BEFORE de unidades), no una copia armada a mano
  select to_jsonb(u), u.estado into v_despues, v_estado from public.unidades u where u.id = v_u.id;
  insert into public.unidades_log (unidad_id, antes, despues, motivo, via, por)
  values (v_u.id, to_jsonb(v_u), v_despues,
          'LAW-611: vuelve a bloqueada por decisión del owner (15-oct-2026): figuraba vendida con el Bloqueo RP00070 sin firmar '
          || 'y el suelo sin cobrar entero',
          'sql directo', 'migración LAW-611');

  if v_estado is distinct from 'bloqueada' then
    raise exception 'PARADA LAW-611: tras el cambio W3 - C3 queda en «%»', v_estado;
  end if;
  raise notice 'LAW-611 ok: W3 - C3 vendida -> bloqueada, con su fila de historial';
end $law611$;
-- ── 20261015210200_law612_inv00173_rec00130_a_cc00088.sql · sha256 a31f80e506f72bc6239d68e84fb27f695f184789309421c1926be45c0c735199 ──
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

-- ── RESUMEN (solo lee) ──────────────────────────────────────────────────────────────────────────────────────────────────
do $res$
declare
  v text := '';
  r record;
begin
  -- los disparadores diferidos (historial de unidades) corren aquí y no al confirmar, que en un ensayo no llega
  execute 'set constraints all immediate';
  v := 'ANTES · ' || current_setting('ensayo_law610_612.antes', true) || E'\n';
  -- LAW-610
  select c.precio_total, c.datos->'fields'->>'precio_total' as campo,
         (select count(*) from public.contrato_vencimientos v where v.contrato_id = c.id) as venc
    into r from public.contratos c where c.id = '93d557dc-814b-48df-b127-adc34f6f191e';
  v := v || format('610 · CC00040 precio_total %s · papel %s · vencimientos %s', r.precio_total, coalesce(r.campo, '(vacío)'), r.venc);
  select u.estado, u.precio, u.precio_suelo, u.precio_construccion, x.obra_precio, x.obra_de_contrato into r
    from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
   where u.contrato_id = '637f9a44-cd31-47eb-a636-5fe33255eab3';
  v := v || format(' · SH-3 %s precio %s = %s + %s · obra cascada %s (de contrato %s)', r.estado, r.precio, r.precio_suelo,
                   r.precio_construccion, r.obra_precio, r.obra_de_contrato);
  v := v || (select format(' · por contrato: precio %s, sin precio %s, facturado %s (cadena %s)', s.precio, s.sin_precio,
                           s.facturado, s.raiz_numero)
               from public._cadena_saldo_en('93d557dc-814b-48df-b127-adc34f6f191e', 'EUR') s);
  v := v || ' · comisiones RP00079 (devengos, diferencias, error del recálculo) tras forzar la reconciliación: '
         || case when pg_temp.e612_comisiones_rp00079() = current_setting('ensayo_law610_612.com79', true) then 'IGUALES'
                 else 'CAMBIAN (FALLA): antes «' || left(current_setting('ensayo_law610_612.com79', true), 400)
                      || '» después «' || left(pg_temp.e612_comisiones_rp00079(), 400) || '»' end;
  -- LAW-611
  select u.id, u.estado, x.cobrado_suelo, x.suelo_precio into r
    from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
   where u.contrato_id = '40f7bd40-52e5-431e-a7ab-0f8f3752ff52';
  v := v || format(E'\n611 · W3 - C3 %s (suelo cobrado %s de %s) · historial de hoy: %s', r.estado, r.cobrado_suelo, r.suelo_precio,
                   (select string_agg(coalesce(l.motivo, '(sin motivo)') || ' [' || coalesce(l.via, '') || ']', ' | ')
                      from public.unidades_log l where l.unidad_id = r.id and l.en = now()));
  -- LAW-612
  select u.estado, x.cobrado_suelo, x.cobrado_obra, x.suelo_precio,
         public.unidad_cumple_estado(u.id, 'vendida', u.precio, u.precio_suelo) as cumple into r
    from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
   where u.contrato_id = 'f0d47af2-5749-46eb-ad82-00415a95ef4d';
  v := v || format(E'\n612 · D4 %s · suelo cobrado %s de %s · obra cobrada %s · cumple vendida %s', r.estado, r.cobrado_suelo,
                   r.suelo_precio, r.cobrado_obra, r.cumple);
  v := v || ' · docs: ' || (select string_agg(f.numero || '→' || c.numero || ' (' || coalesce(f.contrato_numero, '') || ')', ', ' order by f.numero)
                             from public.facturas f join public.contratos c on c.id = f.contrato_id
                            where f.id in ('9c69f301-566f-4c6c-9c60-5d87e60f97fd', 'c0babc5f-7dea-47b4-8cdf-65dad9a0e9e3'));
  v := v || ' · cobrado por contrato: ' || (select string_agg(c.numero || ' ' || public._contrato_cobrado_interno(c.id), ', ' order by c.numero)
                                             from public.contratos c
                                            where c.id in ('f0d47af2-5749-46eb-ad82-00415a95ef4d', '54030d81-972f-4da1-9e16-643d033c5fe8'));
  v := v || ' · bases 1-nov: ' ||
       (select b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada || ' · ' || b.cobrado_directo_suelo || '/' || b.cobrado_directo_obra
          from public._comisiones_bases_firmadas('f0d47af2-5749-46eb-ad82-00415a95ef4d') b);
  v := v || ' · línea admin de REC00130: ' ||
       coalesce((select string_agg(l.tipo_linea || ' ' || l.importe || ' contrato ' || coalesce(c.numero, '?') || case when l.anulada then ' anulada' else '' end, ', ')
                   from public.comision_admin_lineas l left join public.contratos c on c.id = l.contrato_id
                  where l.recibi_id = 'c0babc5f-7dea-47b4-8cdf-65dad9a0e9e3'), '(ninguna)');
  v := v || ' · comisiones: ' || coalesce((select string_agg(d.nivel || ' ' || d.estado || ' ' || d.importe || ' ' || d.moneda, ', ')
                                            from public.comisiones_devengadas d
                                           where d.contrato_raiz_id = 'f0d47af2-5749-46eb-ad82-00415a95ef4d'), '(ninguna)');
  raise exception E'RES LAW610-612 · las tres aplicadas y deshechas\n%', v;
end $res$;
