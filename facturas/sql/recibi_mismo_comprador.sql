-- LAW-41(2) — un recibí solo puede saldar facturas DE SU MISMO COMPRADOR
-- 19-ago-2026. Cierra el hueco por el que REC00019 (1.000 €, Jorge Miguel
-- Domingo Berenguer, CR00020) acabó aplicado a INV00001, una factura de
-- Carmen Ribera Valdes. El único check del bucle de guardar_recibi() era
-- "existe, es tipo factura y no está anulada": nada miraba de QUIÉN era.
--
-- Por qué NO se exige "mismo contrato": aplicar un recibí a la factura de
-- OTRO contrato del mismo comprador es un caso de uso real y vivo — REC00020
-- (Eduardo Cuellar) cuelga de CC00026 y salda INV00015, que es de RP00047.
-- Cruzar contrato entre padre e hija sí; cruzar comprador no.
--
-- La identidad se compara con `contrato_identificadores` (pasaporte + email
-- del jsonb), la MISMA función con la que LAW-51 decide si dos contratos son
-- del mismo comprador al traspasar una parcela. Un solo criterio de identidad
-- en toda la suite: si mañana cambia, cambia en un sitio.
--
-- Decisión heredada de LAW-51 (owner): si falta identidad en cualquiera de los
-- dos lados, SE BLOQUEA. `&&` sobre un array vacío da false, así que sale
-- gratis y no hay que escribirlo aparte.
--
-- Efecto colateral buscado: una factura sin `contrato_id` no cuelga de ningún
-- comprador, así que deja de poder recibir dinero. Son exactamente las 3 de
-- LAW-38 (INV00001/2/3, 60.000 €, clientes que no tienen contrato en el
-- sistema). Hasta que alguien les dé contrato, no vuelven a contaminar cobros.

-- ── el criterio, UNA sola vez ────────────────────────────────────────────────
-- security definer a propósito: un agente puede saldar la factura de un
-- contrato que firmó otro agente (por eso existen contratos_equipo/
-- facturas_equipo), y la RLS por autor no le dejaría leerlo. Devuelve un
-- booleano, no datos del contrato ajeno.
create or replace function public.contratos_mismo_comprador(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select public.contrato_identificadores(a.datos)
        && public.contrato_identificadores(b.datos)
      from public.contratos a, public.contratos b
     where a.id = p_a and b.id = p_b
  ), false);
$$;

revoke all on function public.contratos_mismo_comprador(uuid, uuid) from public, anon;
grant execute on function public.contratos_mismo_comprador(uuid, uuid) to authenticated;

-- ── el selector de facturas del recibí pregunta, no reimplementa ─────────────
-- La norma de la suite duplica la regla (trigger + selector) cuando el
-- selector NO puede preguntar. Aquí sí puede: devolviendo los contratos del
-- mismo comprador, facturas/index.html filtra su lista con el MISMO criterio
-- que aplicará la base de datos, y no hay dos definiciones que puedan derivar.
create or replace function public.contratos_del_mismo_comprador(p_contrato_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
    from public.contratos c
   where public.contrato_identificadores(c.datos)
      && (select public.contrato_identificadores(datos)
            from public.contratos where id = p_contrato_id);
$$;

revoke all on function public.contratos_del_mismo_comprador(uuid) from public, anon;
grant execute on function public.contratos_del_mismo_comprador(uuid) to authenticated;

-- ── guardar_recibi: misma función, un check más en el bucle ──────────────────
-- Cuerpo en ASCII y sin tildes, como está en producción (verificado contra
-- prosrc antes de reemplazar: idéntico al repo salvo tildes y comentarios).
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

    -- LAW-41(2), 19-ago: de quien es la factura. Los dos mensajes van
    -- separados porque las dos salidas del agente son distintas: a una
    -- factura huerfana hay que darle contrato; a una de otro comprador, no
    -- hay nada que arreglar, es la factura equivocada.
    if v_factura_contrato is null then
      raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
        coalesce(v_factura_numero, '?') using errcode = '23514';
    end if;
    if not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
        using errcode = '23514';
    end if;

    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, v_factura_id, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$$;

revoke all on function public.guardar_recibi(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.guardar_recibi(uuid, jsonb, jsonb) to authenticated;
