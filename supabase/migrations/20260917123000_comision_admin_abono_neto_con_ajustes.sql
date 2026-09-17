-- El abono tiene que revertir el NETO, no solo el devengo (17-sep-2026)
-- ============================================================================
-- Cazado en la prueba con rollback de la migracion de hace un rato, antes de que
-- esto viera un solo recibi real:
--
--   devengo 20.000 € -> 100,00 €
--   el recibi sube a 25.000 € cuando la comision ya estaba facturada
--       -> linea de ajuste +25,00 €      (devengado hasta aqui: 125,00 €)
--   el recibi se anula
--       -> abono -100,00 €               (neto: 25,00 €)  ← MAL
--
-- Anular un recibi tiene que dejar el libro a cero para ese recibi. El abono
-- miraba solo `v_linea.importe` (el devengo) e ignoraba las lineas de ajuste que
-- colgaban de el, asi que cada correccion posterior a la facturacion dejaba un
-- resto vivo despues de anular. La forma general: **un abono revierte la suma de
-- lo devengado, no la primera linea de la serie.**
--
-- destructivo-ok: solo hay CREATE OR REPLACE de dos funciones. Ningun DROP,
-- DELETE ni UPDATE de datos.

create or replace function public._comision_admin_cambio_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea      record;
  v_base       numeric;
  v_decimales  integer;
  v_nuevo      numeric;
  v_neto_imp   numeric;
  v_neto_base  numeric;
begin
  if coalesce(new.tipo, '') <> 'recibi' and coalesce(old.tipo, '') <> 'recibi' then
    return new;
  end if;

  select * into v_linea
    from public.comision_admin_lineas l
   where l.recibi_id = new.id and l.tipo_linea = 'devengo'
   limit 1;

  -- Un recibi sin devengo (anterior al corte, o que acaba de cambiar de tipo) NO
  -- nace de un UPDATE. Si el flip factura->recibi fuera legitimo, sale como
  -- «recibi vivo sin linea» en comision_admin_descuadres(): un descuadre visible
  -- en vez de un alta por la puerta de atras.
  if v_linea.id is null then
    return new;
  end if;

  v_decimales := case when upper(coalesce(new.moneda, '')) = 'IDR' then 0 else 2 end;
  v_base      := coalesce((new.datos -> 'totales' ->> 'subtotal')::numeric, new.total, 0);

  -- (a) el recibi se anula -> ABONO por el NETO devengado (devengo + sus ajustes)
  if coalesce(new.anulada, false) and not v_linea.anulada then
    select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
      into v_neto_imp, v_neto_base
      from public.comision_admin_lineas l
     where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
       and l.tipo_linea in ('devengo', 'ajuste');

    if v_neto_imp <> 0 or v_neto_base <> 0 then
      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
        contrato_id, proyecto_id, devengado_el, fecha_recibi,
        base_total, moneda, pct_aplicado, importe, tarifa_id, nota, snapshot
      ) values (
        'abono', v_linea.id, new.id, v_linea.recibi_numero, v_linea.sociedad,
        v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
        - v_neto_base, v_linea.moneda, v_linea.pct_aplicado,
        - v_neto_imp, v_linea.tarifa_id,
        'Abono automatico: el recibi se anulo.',
        jsonb_build_object('motivo', 'recibi_anulado', 'devengo_id', v_linea.id,
                           'neto_revertido', v_neto_imp, 'en', now())
      );
    end if;

    update public.comision_admin_lineas
       set anulada = true, actualizado_en = now()
     where id = v_linea.id or linea_origen_id = v_linea.id;
    return new;
  end if;

  -- (b) un recibi anulado vuelve a la vida: el devengo no se repone solo
  if not coalesce(new.anulada, false) and v_linea.anulada then
    update public.comision_admin_lineas
       set revisar = true, actualizado_en = now(),
           nota = coalesce(nota || ' - ', '') || 'El recibi se desanulo: revisar si procede reponer el devengo.'
     where id = v_linea.id;
    return new;
  end if;

  -- (c) cambia la base
  if v_base is distinct from v_linea.base_total and not v_linea.anulada then
    v_nuevo := round(v_base * v_linea.pct_aplicado / 100, v_decimales);

    if v_linea.estado = 'pendiente'
       and not exists (select 1 from public.comision_admin_lineas a
                        where a.linea_origen_id = v_linea.id) then
      -- nadie la ha facturado y no cuelga nada de ella: se corrige en sitio, con
      -- SU pct congelado (nunca el de hoy)
      update public.comision_admin_lineas
         set base_total = v_base, importe = v_nuevo,
             moneda = coalesce(new.moneda, moneda),
             recibi_numero = coalesce(new.numero, recibi_numero),
             contrato_id = new.contrato_id, proyecto_id = new.proyecto_id,
             fecha_recibi = new.fecha_emision, actualizado_en = now()
       where id = v_linea.id;
    else
      -- ya facturada/cobrada: el dinero emitido no se toca, se anota la
      -- DIFERENCIA contra lo devengado hasta ahora (devengo + ajustes previos)
      select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
        into v_neto_imp, v_neto_base
        from public.comision_admin_lineas l
       where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
         and l.tipo_linea in ('devengo', 'ajuste');

      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_id, recibi_numero, sociedad,
        contrato_id, proyecto_id, devengado_el, fecha_recibi,
        base_total, moneda, pct_aplicado, importe, tarifa_id, revisar, nota, snapshot
      ) values (
        'ajuste', v_linea.id, new.id, coalesce(new.numero, v_linea.recibi_numero), v_linea.sociedad,
        new.contrato_id, new.proyecto_id, current_date, new.fecha_emision,
        v_base - v_neto_base, v_linea.moneda, v_linea.pct_aplicado,
        v_nuevo - v_neto_imp, v_linea.tarifa_id, true,
        'Ajuste automatico: el recibi cambio de importe despues de que la comision dejara de estar pendiente.',
        jsonb_build_object('motivo', 'base_corregida', 'devengo_id', v_linea.id,
                           'base_antes', v_neto_base, 'base_despues', v_base, 'en', now())
      );
      update public.comision_admin_lineas set revisar = true, actualizado_en = now() where id = v_linea.id;
    end if;
  end if;

  return new;
exception when others then
  raise warning 'comision_admin cambio (recibi %): %', new.id, sqlerrm;
  return new;
end;
$function$;

create or replace function public._comision_admin_borrado_recibi()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_linea     record;
  v_neto_imp  numeric;
  v_neto_base numeric;
begin
  if coalesce(old.tipo, '') <> 'recibi' then
    return old;
  end if;

  select * into v_linea
    from public.comision_admin_lineas l
   where l.recibi_id = old.id and l.tipo_linea = 'devengo'
   limit 1;

  if v_linea.id is null then
    return old;
  end if;

  if not v_linea.anulada then
    select coalesce(sum(l.importe), 0), coalesce(sum(l.base_total), 0)
      into v_neto_imp, v_neto_base
      from public.comision_admin_lineas l
     where (l.id = v_linea.id or l.linea_origen_id = v_linea.id)
       and l.tipo_linea in ('devengo', 'ajuste');

    if v_neto_imp <> 0 or v_neto_base <> 0 then
      insert into public.comision_admin_lineas (
        tipo_linea, linea_origen_id, recibi_numero, sociedad, contrato_id, proyecto_id,
        devengado_el, fecha_recibi, base_total, moneda, pct_aplicado, importe,
        tarifa_id, revisar, nota, snapshot
      ) values (
        'abono', v_linea.id, v_linea.recibi_numero, v_linea.sociedad,
        v_linea.contrato_id, v_linea.proyecto_id, current_date, v_linea.fecha_recibi,
        - v_neto_base, v_linea.moneda, v_linea.pct_aplicado, - v_neto_imp,
        v_linea.tarifa_id, true,
        'Abono automatico: el recibi se BORRO de la base.',
        jsonb_build_object('motivo', 'recibi_borrado', 'devengo_id', v_linea.id,
                           'neto_revertido', v_neto_imp, 'en', now())
      );
    end if;
  end if;

  update public.comision_admin_lineas
     set anulada = true, revisar = true, actualizado_en = now(),
         nota = coalesce(nota || ' - ', '') || 'El recibi ya no existe en la base.'
   where id = v_linea.id or linea_origen_id = v_linea.id;

  return old;
exception when others then
  raise warning 'comision_admin borrado (recibi %): %', old.id, sqlerrm;
  return old;
end;
$function$;

revoke all on function public._comision_admin_cambio_recibi()  from public, anon, authenticated;
revoke all on function public._comision_admin_borrado_recibi() from public, anon, authenticated;
