-- LAW-37 (continuación, decisión de Administración del 11-oct-2026): un recibí ENVIADO no
-- cambia lo que dice el papel que tiene el cliente.
--
-- PROBLEMA (medido 11-oct, pg_get_functiondef de producción):
--   1. `guardar_recibi` editaba un recibí sin mirar `enviada`: el UPDATE solo filtraba
--      `tipo='recibi' and anulada=false` y la autoría. Un recibí ya enviado (por correo o
--      marcado) podía cambiar total, moneda, contrato y aplicaciones: el saldo de las
--      facturas que salda dejaba de cuadrar con el recibí que el cliente tiene en la mano.
--      La pantalla ya lo impedía (intranet/v4/assets/editores.js:4094, «Ya enviado al
--      cliente: no se edita»), pero la RPC no: la regla vivía solo en el navegador.
--   2. `factura_marca_enviada` no miraba `anulada`: `_factura_puede_editar` devuelve true a
--      un super admin aunque el documento esté anulado, así que llamándola a mano un super
--      admin podía marcar como enviado un anulado. Hoy lo frenaba de rebote el trigger
--      `factura_anulada_solo_cambia_autor` con un mensaje equivocado («solo se puede cambiar
--      su autor»), y ese trigger se aparta con auth.uid() nulo.
--
-- QUÉ HACE:
--   1. `guardar_recibi`, al EDITAR (p_id no nulo): bloquea la fila FOR UPDATE con el mismo
--      filtro de autoría que el UPDATE (si no es tuyo, el error de siempre: no se filtra si
--      está enviado), y si está `enviada` rechaza (23514) cualquier cambio de total, moneda,
--      contrato o aplicaciones (suma por factura; 1 y 1.00 son iguales). Corregir un recibí
--      enviado = anularlo y emitir otro (Administración). Si no cambia nada de eso, se guarda
--      lo demás y NO se reescriben las aplicaciones (no se toca su creado_por ni se recalculan
--      cobros por nada). Sin excepción para super admin: el papel del cliente es el mismo.
--      Los recibís NO enviados se comportan exactamente igual que antes.
--      El contrato entra porque mover el recibí de contrato mueve el cobro
--      (`trg_avanza_por_recibi`: avanza_unidad_por_cobro del contrato viejo y del nuevo).
--      El FOR UPDATE ordena el guardado frente a la marca de `enviada` (no frente al envío:
--      la edge envía antes de marcar; ver 20261010231825).
--   2. `factura_marca_enviada`: un documento anulado no se marca enviado (42501), tras el
--      atajo «ya enviada → true» para que un reenvío de algo enviado y luego anulado no pase
--      a contestar `marcada:false` en la edge.
--
-- DECISIONES POR DEFECTO (CEO por defecto, reversibles):
--   a) NO se rechaza el tipo `recibi` en `factura_marca_enviada`: la edge
--      `send-contract-email` (index.ts:299) marca recibís llamando a ESTA RPC con la sesión
--      del usuario, y una llamada «a mano» de un super admin es indistinguible desde dentro.
--      Filtrar el tipo rompería el correo de recibís. Alternativa descartada: que la edge
--      marque como service_role por una función aparte y cerrar esta a recibís. Revertir:
--      añadir `if v_old.tipo = 'recibi' then raise …` tras mover la edge.
--   b) Fecha de emisión, nombre del cliente, `datos` y justificantes siguen editables en un
--      recibí enviado (fuera del encargo, la pantalla ya bloquea la edición entera). Si
--      Administración lo pide, se añaden a la misma comprobación.
--
-- Ambas siguen SECURITY DEFINER con search_path vacío; CREATE OR REPLACE conserva los
-- GRANT (medidos 11-oct: postgres, authenticated, service_role EXECUTE en las dos).
--
-- VUELTA ATRÁS: reaplicar los cuerpos anteriores, que están en
--   supabase/migrations/20260926085354_frontera_facturas_rpc.sql:260 (factura_marca_enviada) y
--   supabase/migrations/20261008202000_f2_b2_2_facturas_por_empresa.sql (guardar_recibi; es
--   este mismo cuerpo sin el bloque «LAW-37: recibí enviado» ni `v_viejo`/`v_congelado`).

-- destructivo-ok: el único DELETE es el que guardar_recibi ya llevaba dentro de su cuerpo (reescribe las aplicaciones de un recibí NO enviado al editarlo); aplicar esto solo redefine dos funciones y no borra ninguna fila.
create or replace function public.factura_marca_enviada(p_id uuid)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then return false; end if;
  if v_old.enviada then return true; end if;
  -- LAW-37 (11-oct): _factura_puede_editar deja pasar al super admin aunque esté anulado.
  if coalesce(v_old.anulada, false) then
    raise exception 'El documento % está anulado: no se marca como enviado', coalesce(v_old.numero, '?')
      using errcode = '42501';
  end if;
  if not public._factura_puede_editar(v_old) then
    raise exception 'No puedes marcar este documento como enviado' using errcode = '42501';
  end if;
  update public.facturas f set enviada = true, fecha_envio = now() where f.id = p_id;
  return true;
end $function$;

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
  v_importe_aplic numeric;
  v_pend_factura numeric;
  v_moneda_factura text;
  v_rest boolean := public.alcance_restringido() and not public.es_admin();
  v_pnombre text := p_factura->>'proyecto_nombre';
  v_pid uuid; v_emp text; v_emp_fac text;
  v_viejo public.facturas%rowtype;
  v_congelado boolean := false;
begin
  if not public._puede_herr('facturas') then
    raise exception 'sin permiso para crear recibis' using errcode = '42501';
  end if;

  v_contrato_id := nullif(p_factura->>'contrato_id', '')::uuid;
  if v_contrato_id is null then
    raise exception 'el recibi necesita un contrato' using errcode = '23514';
  end if;

  if not public.es_super_admin_de(public._empresa_doc(null::uuid, v_contrato_id))
     and not exists (select 1 from public.contratos c
                      where c.id = v_contrato_id and public.puede_ver_contrato(c.id)) then
    raise exception 'No puedes emitir un recibí sobre un contrato que no ves' using errcode = '42501';
  end if;

  v_emp := public._empresa_doc(null::uuid, v_contrato_id);
  if v_rest then
    select c.proyecto_id into v_pid from public.contratos c where c.id = v_contrato_id;
    select pr.nombre into v_pnombre from public.proyectos pr where pr.id = v_pid;
    if v_emp is null or not public.puede_empresa(v_emp) then
      raise exception 'Ese recibí no es de ninguna de tus empresas' using errcode = '42501';
    end if;
    if (p_id is null or (p_factura->>'sociedad') is distinct from (select f.sociedad from public.facturas f where f.id = p_id))
       and not exists (select 1 from public.empresas e where e.clave = v_emp and e.sociedad_clave = p_factura->>'sociedad') then
      raise exception 'Ese recibí tiene que salir por la sociedad de la empresa del proyecto' using errcode = '42501';
    end if;
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
      ('recibi', p_factura->>'sociedad', p_factura->>'cliente_nombre', v_pnombre,
       p_factura->>'contrato_numero', v_contrato_id, (p_factura->>'total')::numeric, p_factura->>'moneda',
       nullif(p_factura->>'fecha_emision','')::date, v_justificantes, p_factura->'datos')
    returning id, numero into v_id, v_numero;
  else
    -- LAW-37: recibí enviado (11-oct). Se bloquea la fila con el MISMO filtro de autoría que el
    -- UPDATE de abajo: quien no puede editarlo recibe el error de siempre, sin saber si está enviado.
    select * into v_viejo from public.facturas f
     where f.id = p_id and f.tipo = 'recibi' and f.anulada = false
       and (public.es_suyo(f.creado_por) or public.es_admin_de(public._empresa_doc(f.proyecto_id, f.contrato_id)))
     for update;
    if not found then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    if coalesce(v_viejo.enviada, false) then
      if (p_factura->>'total')::numeric is distinct from v_viejo.total
         or (p_factura->>'moneda') is distinct from v_viejo.moneda
         or v_contrato_id is distinct from v_viejo.contrato_id
         or exists (
           select 1
             from (select ra.factura_id, sum(ra.importe_aplicado) as importe
                     from public.recibi_aplicaciones ra where ra.recibi_id = p_id
                    group by ra.factura_id) o
             full join (select (a->>'factura_id')::uuid as factura_id, sum((a->>'importe')::numeric) as importe
                          from jsonb_array_elements(p_aplicaciones) a
                         group by 1) n on n.factura_id = o.factura_id
            where o.factura_id is null or n.factura_id is null or o.importe is distinct from n.importe) then
        raise exception 'El recibí % ya se envió al cliente: su importe, moneda, contrato y facturas que salda no se cambian. Anúlalo y emite otro.',
          coalesce(v_viejo.numero, '?') using errcode = '23514';
      end if;
      v_congelado := true;
    end if;

    update public.facturas set
      sociedad = p_factura->>'sociedad', cliente_nombre = p_factura->>'cliente_nombre',
      proyecto_nombre = v_pnombre, contrato_numero = p_factura->>'contrato_numero',
      contrato_id = v_contrato_id, total = (p_factura->>'total')::numeric, moneda = p_factura->>'moneda',
      fecha_emision = nullif(p_factura->>'fecha_emision','')::date, justificantes = v_justificantes,
      datos = p_factura->'datos'
    where id = p_id and tipo = 'recibi' and anulada = false
      and (public.es_suyo(creado_por) or public.es_admin_de(public._empresa_doc(proyecto_id, contrato_id)))
    returning id, numero into v_id, v_numero;
    if v_id is null then
      raise exception 'no se pudo actualizar: no existe, esta anulado, o no es tuyo' using errcode = '42501';
    end if;
    -- enviado y sin cambios en lo que salda: las aplicaciones se quedan como están
    if v_congelado then
      return jsonb_build_object('id', v_id, 'numero', v_numero);
    end if;
    delete from public.recibi_aplicaciones where recibi_id = v_id;
  end if;

  perform 1 from public.facturas fl
   where fl.id in (select (a->>'factura_id')::uuid from jsonb_array_elements(p_aplicaciones) a)
   order by fl.id for update;
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
    v_emp_fac := public._empresa_doc(v_factura_proyecto, v_factura_contrato);

    if not public.es_super_admin_de(v_emp_fac)
       and not public.documento_visible(v_factura_autor, v_factura_proyecto, v_factura_contrato) then
      raise exception 'la factura % no es un documento que veas: no le puedes aplicar un cobro',
        coalesce(v_factura_numero, '?') using errcode = '42501';
    end if;

    if v_factura_contrato is null then
      if public.es_super_admin_de(v_emp_fac) then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_factura_huerfana',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero));
      else
        raise exception 'la factura % no cuelga de ningun contrato: no se le puede aplicar un cobro (LAW-38)',
          coalesce(v_factura_numero, '?') using errcode = '23514';
      end if;
    elsif not public.contratos_mismo_comprador(v_contrato_id, v_factura_contrato) then
      if public.es_super_admin_de(v_emp) and public.es_super_admin_de(v_emp_fac) then
        perform public.registra_privilegio(v_contrato_id, 'cobro_a_otro_comprador',
          jsonb_build_object('recibi', v_numero, 'factura', v_factura_numero,
                             'importe', v_aplicacion->>'importe'));
      else
        raise exception 'la factura % es de otro comprador que el recibi', coalesce(v_factura_numero, '?')
          using errcode = '23514';
      end if;
    end if;

    v_importe_aplic := (v_aplicacion->>'importe')::numeric;
    if v_importe_aplic is null or v_importe_aplic <= 0 then
      raise exception 'el importe que se aplica a la factura % tiene que ser mayor que cero', coalesce(v_factura_numero, '?') using errcode = '23514';
    end if;
    select f.total - coalesce((select sum(ra.importe_aplicado) from public.recibi_aplicaciones ra
                                 join public.facturas rc on rc.id = ra.recibi_id
                                where ra.factura_id = f.id and not coalesce(rc.anulada, false)), 0), f.moneda
      into v_pend_factura, v_moneda_factura from public.facturas f where f.id = v_factura_id;
    if v_importe_aplic > v_pend_factura + power(10::numeric, -public.lw_decimales(v_moneda_factura)) then
      raise exception 'la factura % solo tiene % pendiente de cobro y este recibí le aplica %', coalesce(v_factura_numero, '?'), v_pend_factura, v_importe_aplic using errcode = '23514';
    end if;
    insert into public.recibi_aplicaciones (recibi_id, factura_id, importe_aplicado, creado_por)
    values (v_id, v_factura_id, (v_aplicacion->>'importe')::numeric, (select auth.email()));
  end loop;

  return jsonb_build_object('id', v_id, 'numero', v_numero);
end;
$function$;
