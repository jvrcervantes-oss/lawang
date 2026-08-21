create or replace function public.trg_factura_exige_contrato_bloqueado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bloqueado boolean;
  v_numero    text;
begin
  if new.tipo is distinct from 'factura' then return new; end if;

  if tg_op = 'UPDATE'
     and old.tipo is not distinct from new.tipo
     and old.contrato_id is not distinct from new.contrato_id then
    return new;
  end if;

  if new.contrato_id is null then return new; end if;

  select c.bloqueado, c.numero into v_bloqueado, v_numero
    from public.contratos c where c.id = new.contrato_id;

  if not coalesce(v_bloqueado, false) then
    if public.es_super_admin() then
      perform public.registra_privilegio(new.contrato_id, 'factura_sin_bloquear',
        jsonb_build_object('factura', new.numero, 'total', new.total, 'moneda', new.moneda));
      return new;
    end if;
    raise exception 'el contrato % no esta bloqueado: una factura se emite cuando el contrato esta firmado y cerrado. Para cobrar antes, emite una proforma y su recibi',
      coalesce(v_numero, '?') using errcode = '23514';
  end if;

  return new;
end $$;

create or replace function public.guardar_recibi(p_id uuid, p_factura jsonb, p_aplicaciones jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_numero text;
  v_aplicacion jsonb;
  v_contrato_id uuid;
  v_justificante text;
  v_factura_id uuid;
  v_factura_numero text;
  v_factura_contrato uuid;
begin
  if not (public.es_agente() and public.puede('facturas')) then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  v_justificante := nullif(p_factura->>'justificante_path', '');
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;
  if v_justificante is null then
    raise exception 'el recibi necesita un justificante de pago adjunto' using errcode = '23514';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'justificantes' and name = v_justificante) then
    raise exception 'el justificante adjunto no existe en el almacenamiento' using errcode = '23514';
  end if;
  if jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'el recibi necesita al menos una factura que salde' using errcode = '23514';
  end if;

  if p_id is null then
    insert into public.facturas
      (tipo, sociedad, cliente_nombre, proyecto_nombre, contrato_numero, contrato_id,
       total, moneda, fecha_emision, justificante_path, datos)
    values
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', p_factura->>'proyecto_nombre',
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificante, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = p_factura->>'proyecto_nombre', contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificante_path = v_justificante,
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

    select f.numero, f.contrato_id into v_factura_numero, v_factura_contrato
      from public.facturas f
     where f.id = v_factura_id
       and f.tipo = 'factura' and not coalesce(f.anulada, false);
    if not found then
      raise exception 'la aplicacion referencia una factura invalida o anulada' using errcode = '23514';
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
$$;

revoke all on function public.guardar_recibi(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.guardar_recibi(uuid, jsonb, jsonb) to authenticated;

create or replace view public.privilegios_ejercidos as
select e.creado_en as cuando, e.quien, e.evento, c.numero as contrato, e.detalle
  from public.contrato_eventos e
  left join public.contratos c on c.id = e.contrato_id
 where e.evento in ('editado_estando_firmado','desbloqueado','factura_sin_bloquear',
                    'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha')
union all
select b.borrado_en, b.quien, 'borrado_' || b.tabla, b.numero,
       jsonb_build_object('fila_id', b.fila_id)
  from public.borrados b;

alter view public.privilegios_ejercidos set (security_invoker = true);
grant select on public.privilegios_ejercidos to authenticated;;
