-- guardar_recibi: barrera de visibilidad (27-sep-2026, parada B del encargo encargos/20260926_estudio_erp_maestro_unico.md).
--
-- Agujero medido en producción (prueba por rol en ROLLBACK, caso A5): la función es SECURITY DEFINER y, con
-- contrato, nunca comprobaba que quien emite VE ese contrato. Un agente con la herramienta Facturas y los uuid de
-- un contrato ajeno y de una de sus facturas creaba un recibí a nombre del comprador de otro, lo aplicaba a la
-- factura ajena (quedaba cobrada) y disparaba los triggers de avance y comisiones de ese contrato.
--
-- Qué cambia (mismo patrón que factura_guarda: 42501 salvo super_admin):
--   1. El contrato del recibí tiene que ser visible (`contrato_visible`), también al EDITAR (cambiar el contrato
--      de un recibí propio a uno ajeno era la misma puerta).
--   2. Cada factura a la que se aplica tiene que ser un documento que quien emite ve (`documento_visible`, el
--      mismo predicado que la policy de lectura de facturas). La pantalla ya solo ofrece esas
--      (`contratos_del_mismo_comprador` filtra por `contrato_visible`); la base ahora lo exige. Cierra la
--      variante «contrato propio del mismo comprador aplicado a la factura del contrato de otro closer»
--      (el contrato y su dinero son de quien lo hace, 22-sep).
-- Resto del cuerpo: idéntico al de producción del 27-sep (LAW-38, mismo comprador, privilegios de super_admin).
-- Las filas existentes no se tocan: solo cambian las llamadas nuevas.
-- destructivo-ok: falso positivo del freno — el único DELETE es el de recibi_aplicaciones DENTRO del cuerpo de
--   guardar_recibi (ya existía: rehace el reparto al editar un recibí). La migración no borra ni reescribe filas.

create or replace function public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificantes jsonb;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
  v_factura_autor text;
  v_factura_proyecto uuid;
begin
  if not (public.es_agente() and public.puede('facturas')) then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;

  -- Barrera (27-sep): el contrato del recibí tiene que ser uno que quien lo emite ve.
  if not public.es_super_admin()
     and not exists (select 1 from public.contratos c
                      where c.id = v_contrato_id and public.contrato_visible(c.creado_por, c.proyecto_id)) then
    raise exception 'No puedes emitir un recibí sobre un contrato que no ves' using errcode = '42501';
  end if;

  v_justificantes := case when jsonb_typeof(p_factura->'justificantes') = 'array'
                          then p_factura->'justificantes' else '[]'::jsonb end;
  if jsonb_array_length(v_justificantes) = 0
     and nullif(p_factura->>'justificante_path', '') is not null then
    v_justificantes := jsonb_build_array(jsonb_build_object('path', p_factura->>'justificante_path'));
  end if;

  if jsonb_array_length(v_justificantes) = 0 then
    raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
  end if;
  if jsonb_array_length(v_justificantes) > 8 then
    raise exception 'demasiados justificantes en un recibi (maximo 8)' using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_justificantes) j
     where nullif(j->>'path', '') is null
        or not exists (select 1 from storage.objects o
                        where o.bucket_id = 'justificantes' and o.name = j->>'path')
  ) then
    raise exception 'algun justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;

  if jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificantes, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', p_factura->>'proyecto_nombre',
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificantes, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = p_factura->>'proyecto_nombre', contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificantes = v_justificantes,
      datos = p_factura->'datos'
    where id = p_id and tipo = 'recibi' and anulada = false and public.es_suyo(creado_por)
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  for v_aplicacion in select * from jsonb_array_elements(p_aplicaciones) loop
    v_factura_id := (v_aplicacion->>'factura_id')::uuid;

    select f.numero, f.contrato_id, f.creado_por, f.proyecto_id
      into v_factura_numero, v_factura_contrato, v_factura_autor, v_factura_proyecto
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
    end if;

    -- Barrera (27-sep): solo se cobra contra facturas que quien emite ve (mismo predicado que su lectura).
    if not public.es_super_admin()
       and not public.documento_visible(v_factura_autor, v_factura_proyecto, v_factura_contrato) then
      raise exception 'la factura % no es un documento que veas: no le puedes aplicar un cobro',
        coalesce(v_factura_numero, '?') using errcode = '42501';
    end if;

    if v_factura_contrato is null then
      if public.es_super_admin() then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_factura_huerfana',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin() then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_otro_comprador',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero,
                             'importe', v_aplicacion->>'importe'));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;

    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, v_factura_id, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$function$;

revoke all on function public.guardar_recibi(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.guardar_recibi(uuid, jsonb, jsonb) to authenticated, service_role;
