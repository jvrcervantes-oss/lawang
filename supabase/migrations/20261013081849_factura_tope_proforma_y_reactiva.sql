-- LAW-553, revisión de código (13-oct-2026): dos caminos que convertían en factura viva un documento que NO contaba en
-- el tope de la venta sin volver a pasar el tope. Corrige sobre 20261013074408_factura_moneda_del_contrato (aplicada;
-- no se reescribe).
--
-- 1. _factura_tope_cadena: el atajo «editar sin subir el importe no se vuelve a comprobar» no miraba QUÉ era el
--    documento anterior. factura_guarda hace `tipo = v_tipo` en el UPDATE (20261013074408:417), así que una proforma de
--    1.000 editada a factura de 1.000 sobre una venta de 1.000 con 900 ya facturados pasaba por el atajo (v_ant = 1.000,
--    p_subtotal = 1.000) y dejaba 1.900 facturados. Igual con un documento anulado. Ahora el atajo solo vale si el
--    anterior es una factura viva (tipo = 'factura' y no anulada): es el único caso en que su importe ya estaba dentro
--    de `facturado` antes de excluirlo con p_id. Resto del cuerpo, idéntico a 20261013074408.
--
-- 2. factura_reactiva (super_admin, 20261008202000_f2_b2_2_facturas_por_empresa): `anulada = false` devuelve la factura
--    a la cuenta del tope sin pasarlo. Ejemplo: factura de 900 sobre 1.000, se anula, se emite otra de 900, se reactiva
--    la primera → 1.800. El trigger factura_anulada_solo_cambia_autor (20260924073638) solo paraba la «copia» con el
--    MISMO importe. Ahora reactivar pasa por _factura_tope_cadena con el subtotal del documento (proforma y recibí:
--    return inmediato, como siempre). Como reactivar ya es solo de super_admin, por encima del tope pasa con rastro
--    'factura_sobre_tope' — que HOY falla cerrado por contrato_eventos_evento_check (LAW-560, del owner): mientras no
--    se aplique, reactivar por encima del tope no se puede, ni el super_admin; por debajo, igual que antes.
--    Orden de candados: primero el del tope (advisory por raíz) y después la fila FOR UPDATE, el mismo orden que
--    factura_guarda, para no cruzarse en un interbloqueo; tras el candado se vuelve a comprobar que sigue anulada.
--
-- Otros caminos que podían convertir un documento en factura viva, revisados el 13-oct contra pg_proc vivo:
--   · Cambian facturas.tipo: solo factura_guarda (el UPDATE de guardar_recibi filtra `tipo = 'recibi'` y no lo
--     asigna). set_factura_numero solo numera en INSERT: una proforma pasada a factura conserva su número PRO.
--   · Cambian anulada a false: solo factura_reactiva.
--   · authenticated y anon: sin INSERT ni UPDATE sobre facturas (has_table_privilege, 13-oct).
--   · service_role SÍ tiene INSERT/UPDATE directos (lo usan las edges). El tope vive en las RPC, no en un trigger: una
--     edge que escribiera tipo='factura' directo se lo saltaría. Hoy: firma-submit solo inserta/actualiza proformas
--     (y PROFORMA_AUTO_PARADA = true) y facturarPrimerHito no se llama desde el 11-ago (código muerto, sin tope);
--     factura-vencimiento va por factura_vencimiento_emite. Límite escrito, no cerrado aquí.
--
-- Prueba: supabase/pruebas/factura_moneda_del_contrato.sql (casos a12, a13, h1, h2, c3; transacción que acaba en raise).
--
-- Vuelta atrás (sin pérdida de datos):
--   _factura_tope_cadena → la definición de 20261013074408 (sección 5);
--   factura_reactiva     → la definición de 20261008202000_f2_b2_2_facturas_por_empresa.
--   create or replace conserva las ACL (_factura_tope_cadena: solo postgres; factura_reactiva: postgres, service_role,
--   authenticated); se repite el revoke de la primera por si acaso.

create or replace function public._factura_tope_cadena(p_id uuid, p_contrato uuid, p_moneda text, p_subtotal numeric, p_tipo text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz uuid; v_raiz_moneda text; v_raiz_ant uuid; v_moneda_ant text; v_s record; v_ant numeric; v_tol numeric;
  v_otra boolean; v_tipo_ant text; v_anulada_ant boolean;
begin
  if p_tipo is distinct from 'factura' or p_contrato is null then return; end if;
  select coalesce(c.contrato_padre_id, c.id) into v_raiz from public.contratos c where c.id = p_contrato;
  if v_raiz is null then return; end if;
  select r.moneda into v_raiz_moneda from public.contratos r where r.id = v_raiz;
  perform pg_advisory_xact_lock(hashtextextended('factura_tope:' || v_raiz::text, 0));
  select * into v_s from public._cadena_saldo_en(p_contrato, p_moneda, p_id);
  if v_s.raiz is null then return; end if;
  v_otra := p_moneda is distinct from v_raiz_moneda;
  v_tol := power(10::numeric, -public.lw_decimales(p_moneda));

  if v_s.sin_precio or coalesce(v_s.precio, 0) <= 0 then
    if not v_otra then return; end if;   -- moneda de la raíz sin precio: como siempre, no hay tope
    if public.es_super_admin_de(public._empresa_doc(null::uuid, p_contrato)) then
      perform public.registra_privilegio(p_contrato, 'factura_sobre_tope',
        jsonb_build_object('raiz', v_s.raiz_numero, 'moneda', p_moneda, 'motivo', 'sin precio en esta moneda',
                           'facturado_antes', v_s.facturado, 'documento', p_subtotal));
      return;
    end if;
    raise exception 'Esta factura va en % y la venta % no tiene ningún contrato con precio en %: no hay contra qué comprobarla. Pon el precio en el contrato que va en %, o factura en % sobre la venta.',
      p_moneda, v_s.raiz_numero, p_moneda, p_moneda, coalesce(v_raiz_moneda, 'su moneda')
      using errcode = '23514';
  end if;

  if p_id is not null then
    select coalesce(nullif(f.datos->'totales'->>'subtotal', '')::numeric, f.total), f.moneda,
           (select coalesce(c.contrato_padre_id, c.id) from public.contratos c where c.id = f.contrato_id),
           f.tipo, coalesce(f.anulada, false)
      into v_ant, v_moneda_ant, v_raiz_ant, v_tipo_ant, v_anulada_ant
      from public.facturas f where f.id = p_id;
    -- El atajo solo vale si el anterior YA contaba: factura viva, misma venta, misma moneda, importe que no sube.
    -- Una proforma (o un documento anulado) que pasa a factura viva se comprueba entera (revisión de código, 13-oct).
    if v_ant is not null and v_tipo_ant = 'factura' and not v_anulada_ant
       and v_raiz_ant is not distinct from v_raiz and v_moneda_ant is not distinct from p_moneda
       and p_subtotal <= v_ant + v_tol then return; end if;
  end if;
  if v_s.facturado + p_subtotal <= v_s.precio + v_tol then return; end if;
  if public.es_super_admin_de(public._empresa_doc(null::uuid, p_contrato)) then
    perform public.registra_privilegio(p_contrato, 'factura_sobre_tope',
      jsonb_build_object('raiz', v_s.raiz_numero, 'moneda', p_moneda, 'precio', v_s.precio,
                         'facturado_antes', v_s.facturado, 'documento', p_subtotal));
    return;
  end if;
  raise exception 'Con este documento se facturarían % % y el precio acordado de % en % es %. Quedan % por facturar. Corrige el importe, o el precio del contrato si cambió.',
    v_s.facturado + p_subtotal, p_moneda, v_s.raiz_numero, p_moneda, v_s.precio, greatest(v_s.precio - v_s.facturado, 0)
    using errcode = '23514';
end $function$;
revoke all on function public._factura_tope_cadena(uuid, uuid, text, numeric, text) from public, anon, authenticated, service_role;

create or replace function public.factura_reactiva(p_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.facturas%rowtype;
begin
  select * into v_old from public.facturas f where f.id = p_id;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not public.es_super_admin_de(public._empresa_doc(v_old.proyecto_id, v_old.contrato_id)) then
    raise exception 'Solo un super admin puede reactivar un documento anulado' using errcode = '42501';
  end if;
  if not v_old.anulada then raise exception 'El documento % no está anulado', v_old.numero using errcode = '22023'; end if;
  -- LAW-553 (revisión de código, 13-oct): volver a activa una factura la devuelve al tope de su venta; se comprueba
  -- antes (candado del tope primero y luego la fila, como factura_guarda).
  perform public._factura_tope_cadena(p_id, v_old.contrato_id, v_old.moneda,
    coalesce(nullif(v_old.datos->'totales'->>'subtotal', '')::numeric, v_old.total), v_old.tipo);
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not v_old.anulada then raise exception 'El documento % no está anulado', v_old.numero using errcode = '22023'; end if;
  update public.facturas f set anulada = false where f.id = p_id;
end $function$;
