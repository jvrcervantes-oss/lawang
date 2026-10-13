-- LAW-553, revisión de código (13-oct-2026) sobre b40a8a2f8: reactivar un documento anulado no volvía a comprobar su
-- moneda. Corrige sobre 20261013074408_factura_moneda_del_contrato y 20261013081849_factura_tope_proforma_y_reactiva
-- (aplicadas; no se reescriben). Solo construye: dos create or replace.
--
-- El camino que lo rompía:
--   1. Se anula una factura EUR de un contrato EUR.
--   2. El contrato pasa a IDR: trg_zz_00_contrato_moneda_con_documentos (20261013074408:474 y 481) solo mira documentos
--      NO anulados, así que lo deja (fn_contrato_moneda_desde_unidad lo hace sola en el siguiente guardado si la parcela
--      o la unidad van en IDR).
--   3. Un super_admin la reactiva (factura_reactiva) → factura viva en EUR sobre un contrato IDR, sin rastro:
--      trg_01_moneda_del_contrato solo validaba en INSERT o al cambiar moneda o contrato_id, y reactivar solo cambia
--      `anulada`. Lo mismo un UPDATE directo de service_role (las edges lo tienen; factura_anulada_solo_cambia_autor
--      devuelve la fila sin mirar nada cuando auth.uid() es null).
--   Igual con un hijo sin moneda propia cuyo padre cambia de moneda (la efectiva es coalesce(hijo, raíz)).
--
-- Qué cambia:
--   1. trg_factura_moneda_del_contrato: valida también cuando un documento REVIVE (anulada true → false), por
--      cualquier camino (factura_reactiva, service_role, lo que venga). Resto idéntico a 20261013074408 (sección 2).
--   2. factura_reactiva: antes del tope compara la moneda del documento con la efectiva del contrato y para con un
--      mensaje propio («no se reactiva, emite uno nuevo»): el del trigger dice «pon la moneda del documento y vuelve a
--      guardar», que en un anulado no se puede (es inmutable). Va ANTES del tope para que el super_admin vea la moneda y
--      no el rastro del tope, que hoy falla cerrado por LAW-560. El trigger lo vuelve a exigir con candado al hacer el
--      UPDATE (si el contrato no tiene moneda, o es un Hak Sewa, el mensaje es el del trigger). Resto idéntico a 081849.
--   No cambia, a propósito, trg_contrato_moneda_con_documentos: un contrato con TODO anulado sigue pudiendo cambiar de
--   moneda (es la salida para corregir una moneda mal puesta); la comprobación se hace al revivir, no al anular.
--
-- Medido en producción el 13-oct antes de aplicar: 59 documentos anulados, 0 con moneda distinta de la efectiva de su
-- contrato (coalesce(contrato, raíz)). Ninguno que hoy se pueda reactivar deja de poder hacerse.
--
-- Otros caminos que reviven un documento, revisados el 13-oct:
--   · pg_proc vivo, funciones con «update public.facturas» y «anulada» en el cuerpo (10): solo factura_reactiva pone
--     anulada = false; borrar_operacion, factura_anula y resolver_solicitud_cambio la ponen a true; guardar_recibi,
--     factura_marca_enviada, renombrar_proyecto, traspasar_cliente_con_documentos, trg_cliente_actualizado y
--     trg_proyecto_renombrado solo la usan de filtro. (comision_admin_repone_devengo revive comision_admin_lineas, no
--     facturas.)
--   · Edges (supabase/functions y contracts/edge): solo LEEN anulada (asistente-peticiones, send-contract-email,
--     envia-correo, firma-submit).
--   El trigger cubre además cualquier UPDATE directo que venga después.
--
-- Prueba: supabase/pruebas/factura_moneda_del_contrato.sql (casos h3 —super_admin por factura_reactiva— y h4
-- —service_role por UPDATE directo, el camino del trigger—; transacción que acaba en raise).
--
-- Vuelta atrás (sin pérdida de datos):
--   trg_factura_moneda_del_contrato → la definición de 20261013074408 (sección 2);
--   factura_reactiva               → la definición de 20261013081849.
--   create or replace conserva las ACL (trg_factura_moneda_del_contrato: solo postgres; factura_reactiva: postgres,
--   service_role, authenticated); se repite el revoke del trigger por si acaso.

create or replace function public.trg_factura_moneda_del_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- Revivir (anulada → viva) también se valida: entre la anulación y la reactivación la moneda del contrato pudo
  -- cambiar, porque trg_contrato_moneda_con_documentos solo mira documentos vivos (revisión de código, 13-oct).
  if tg_op = 'INSERT' or new.moneda is distinct from old.moneda or new.contrato_id is distinct from old.contrato_id
     or (coalesce(old.anulada, false) and not coalesce(new.anulada, false)) then
    perform public._factura_moneda_valida(new.contrato_id, new.moneda, true);
  end if;
  -- valida_recibi_aplicacion solo salta al tocar recibi_aplicaciones: cambiar la moneda de un documento ya aplicado
  -- (como factura o como recibí) dejaría la aplicación en dos monedas.
  if tg_op = 'UPDATE' and new.moneda is distinct from old.moneda
     and exists (select 1 from public.recibi_aplicaciones ra where ra.factura_id = new.id or ra.recibi_id = new.id) then
    raise exception 'El documento % ya tiene cobros aplicados en %: su moneda no se cambia', old.numero, old.moneda
      using errcode = '23514';
  end if;
  return new;
end $function$;
revoke all on function public.trg_factura_moneda_del_contrato() from public, anon, authenticated, service_role;

create or replace function public.factura_reactiva(p_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_old public.facturas%rowtype; v_mon text; v_num text;
begin
  select * into v_old from public.facturas f where f.id = p_id;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not public.es_super_admin_de(public._empresa_doc(v_old.proyecto_id, v_old.contrato_id)) then
    raise exception 'Solo un super admin puede reactivar un documento anulado' using errcode = '42501';
  end if;
  if not v_old.anulada then raise exception 'El documento % no está anulado', v_old.numero using errcode = '22023'; end if;
  -- LAW-553 (revisión de código, 13-oct): la moneda del contrato pudo cambiar mientras estaba anulado. Misma regla que
  -- _factura_moneda_valida (moneda efectiva = la del contrato o, si no tiene, la de su raíz); el trigger
  -- trg_01_moneda_del_contrato la vuelve a exigir con candado en el UPDATE.
  if v_old.contrato_id is not null then
    select coalesce(c.moneda, r.moneda), c.numero into v_mon, v_num
      from public.contratos c left join public.contratos r on r.id = c.contrato_padre_id
     where c.id = v_old.contrato_id;
    if v_mon is not null and v_old.moneda is distinct from v_mon then
      raise exception 'El contrato % va en % y el documento % está en %: no se reactiva (sus importes están en %). Emite uno nuevo en %.',
        v_num, v_mon, v_old.numero, coalesce(v_old.moneda, 'ninguna'), coalesce(v_old.moneda, 'ninguna'), v_mon
        using errcode = '23514';
    end if;
  end if;
  -- LAW-553 (revisión de código, 13-oct): volver a activa una factura la devuelve al tope de su venta; se comprueba
  -- antes (candado del tope primero y luego la fila, como factura_guarda).
  perform public._factura_tope_cadena(p_id, v_old.contrato_id, v_old.moneda,
    coalesce(nullif(v_old.datos->'totales'->>'subtotal', '')::numeric, v_old.total), v_old.tipo);
  select * into v_old from public.facturas f where f.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe' using errcode = 'P0002'; end if;
  if not v_old.anulada then raise exception 'El documento % no está anulado', v_old.numero using errcode = '22023'; end if;
  update public.facturas f set anulada = false where f.id = p_id;
end $function$;
