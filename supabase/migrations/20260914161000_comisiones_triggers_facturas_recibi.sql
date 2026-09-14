-- COMISIONES: LOS TRIGGERS — 14-sep-2026.
-- Cuelga comisiones_evaluar_contrato() (migración anterior, 20260914160000) de
-- los DOS eventos que pueden mover el cobrado de un contrato: un cambio en
-- `facturas` (alta/anulación de una factura o de un recibi, y también la
-- anulación de una factura que YA tenía recibis aplicados -- contrato_cobrado
-- excluye f.anulada del lado aplicado, así que anular la factura mueve el
-- cobrado tanto como anular el recibi) y un cambio en `recibi_aplicaciones`
-- (aplicar/reaplicar/retirar un recibi contra una factura).
--
-- POR QUÉ NO SE FILTRA POR tipo EN EL TRIGGER DE facturas -- inspección de
-- contrato_cobrado(uuid): usa TANTO f.contrato_id (la factura que recibe el
-- pago) COMO r.contrato_id (el recibi cuando queda parte sin aplicar). Filtrar
-- solo por tipo='recibi' dejaría fuera la anulación de una factura ya cobrada.
-- El coste de reevaluar en cada INSERT/UPDATE/DELETE de facturas es una
-- consulta de agregación sobre datos de hoy (236 contratos, 462 unidades) --
-- aceptable para esta subtarea; si el volumen crece, es una optimización de
-- otra subtarea (filtrar por tipo, o encolar en vez de evaluar en línea).
--
-- BLINDAJE: cada trigger envuelve la llamada en EXCEPTION WHEN OTHERS (mismo
-- patrón que _trg_solicitud_pago_aviso, 20260909071823) -- un fallo del motor
-- de comisiones NUNCA debe tumbar el alta/anulación de una factura o de un
-- recibi real. Se deja RAISE WARNING (visible en los logs de Supabase) en vez
-- de silenciar del todo. La verificación de esta migración llama a
-- comisiones_evaluar_contrato() DIRECTAMENTE (no a través del trigger) para
-- que un fallo real del cálculo SÍ se vea en la prueba -- ver el DO+rollback
-- de la sesión de aplicación, no incluido en este fichero.
--
-- ANULACIÓN DE UN RECIBI YA DISPARADO -- _comisiones_marca_disputa_por_recibi
-- lee comisiones_devengadas.disparado_por_snapshot->>'recibi_id' (congelado
-- por comisiones_evaluar_contrato en cada devengo) y pasa esas filas a
-- estado='en_disputa'. Se dispara en DOS casos, los dos sobre `facturas`
-- porque un recibi ES una fila de facturas con tipo='recibi':
--   · UPDATE que pone anulada:false->true en una fila tipo='recibi'.
--   · DELETE de una fila tipo='recibi' (borrado físico, no solo anulación).
-- NUNCA borra la fila de comisiones_devengadas ni genera un pago nuevo --
-- exactamente lo que pide el encargo. Si el devengo ya tenía solicitud_id
-- (nivel=manager con solicitud creada), esa solicitud NO se toca aquí: queda
-- para quien resuelva la disputa a mano, es otra subtarea decidir qué pasa
-- con una solicitud de pago ya aprobada/pagada cuyo devengo se disputa.
--
-- destructivo-ok: el UPDATE de _comisiones_marca_disputa_por_recibi lleva
-- WHERE por disparado_por_snapshot->>'recibi_id' + estado <> 'en_disputa' --
-- no es un UPDATE sin filtro, es exactamente la fila (o filas -- un mismo
-- recibi puede haber disparado un tramo de manager Y uno de closer) que ese
-- recibi disparó. No hay DROP ni DELETE de datos en este fichero. Los "drop
-- trigger/policy if exists" son el patrón estándar del repo para poder
-- re-ejecutar la migración sin fallar por nombre duplicado.

create or replace function public._comisiones_marca_disputa_por_recibi(p_recibi_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recibi_id is null then
    return;
  end if;

  update public.comisiones_devengadas d
     set estado = 'en_disputa'
   where d.estado <> 'en_disputa'
     and d.disparado_por_snapshot ->> 'recibi_id' = p_recibi_id::text;
end;
$$;

comment on function public._comisiones_marca_disputa_por_recibi(uuid) is
  'Pone estado=en_disputa en toda fila de comisiones_devengadas cuyo disparado_por_snapshot apunte a p_recibi_id -- nunca borra, nunca genera un pago nuevo. La llaman los triggers de esta misma migración cuando un recibi tipo=recibi se anula (UPDATE anulada:false->true) o se borra (DELETE).';

create index if not exists comisiones_devengadas_recibi_snapshot_idx
  on public.comisiones_devengadas ((disparado_por_snapshot ->> 'recibi_id'));

-- ══════════════ TRIGGER SOBRE facturas ══════════════
create or replace function public._trg_comisiones_desde_facturas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.tipo = 'recibi' then
      perform public._comisiones_marca_disputa_por_recibi(old.id);
    end if;
    if old.contrato_id is not null then
      perform public.comisiones_evaluar_contrato(old.contrato_id);
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and new.tipo = 'recibi'
     and coalesce(new.anulada, false) and not coalesce(old.anulada, false) then
    perform public._comisiones_marca_disputa_por_recibi(new.id);
  end if;

  if new.contrato_id is not null then
    perform public.comisiones_evaluar_contrato(new.contrato_id);
  end if;

  return new;
exception when others then
  raise warning 'comisiones (trigger facturas, %, factura %): %',
    tg_op, coalesce(new.id, old.id), sqlerrm;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_comisiones_desde_facturas on public.facturas;
create trigger trg_comisiones_desde_facturas
  after insert or update or delete on public.facturas
  for each row execute function public._trg_comisiones_desde_facturas();

-- ══════════════ TRIGGER SOBRE recibi_aplicaciones ══════════════
create or replace function public._trg_comisiones_desde_recibi_aplicaciones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contrato_id uuid;
begin
  if tg_op = 'DELETE' then
    select f.contrato_id into v_contrato_id from public.facturas f where f.id = old.factura_id;
  else
    select f.contrato_id into v_contrato_id from public.facturas f where f.id = new.factura_id;
  end if;

  if v_contrato_id is not null then
    perform public.comisiones_evaluar_contrato(v_contrato_id);
  end if;

  return coalesce(new, old);
exception when others then
  raise warning 'comisiones (trigger recibi_aplicaciones, %, aplicacion %): %',
    tg_op, coalesce(new.id, old.id), sqlerrm;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_comisiones_desde_recibi_aplicaciones on public.recibi_aplicaciones;
create trigger trg_comisiones_desde_recibi_aplicaciones
  after insert or update or delete on public.recibi_aplicaciones
  for each row execute function public._trg_comisiones_desde_recibi_aplicaciones();

revoke all on function public._comisiones_marca_disputa_por_recibi(uuid) from public, anon, authenticated;
revoke all on function public._trg_comisiones_desde_facturas() from public, anon, authenticated;
revoke all on function public._trg_comisiones_desde_recibi_aplicaciones() from public, anon, authenticated;
