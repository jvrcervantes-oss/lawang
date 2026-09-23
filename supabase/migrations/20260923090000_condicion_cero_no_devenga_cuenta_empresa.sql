-- Una condición al 0% significa «esta persona no cobra comisión» — 23-sep-2026, owner
-- ----------------------------------------------------------------------------
-- Decisión del owner: lo que se cierra desde hello@lawangproperties.com (cuenta
-- de empresa, hoy la usa Yesy) NO genera comisión. Con el esquema anterior no
-- se podía decir: pct_comision exigía > 0 y un override inactivo hace que el
-- motor caiga a la condición general (2,5%). Ahora:
--   · pct_comision admite 0.
--   · el motor salta una condición a porcentaje con pct 0: ni devengo ni
--     solicitud de pago de 0 €. Vale para cualquier nivel (estándar, closer
--     de equipo, manager), así que sirve también para excluir a otra persona.
--   · override estándar al 0% para hello@, vigente desde siempre.
-- El parche del motor se aplica sobre la definición viva y falla si no
-- encuentra el punto de inserción (no se reescribe a mano la función entera).

-- destructivo-ok: se sustituye un CHECK (>0) por otro más amplio (>=0); no toca datos
alter table public.condiciones_comision
  drop constraint condiciones_comision_pct_comision_check;
alter table public.condiciones_comision
  add constraint condiciones_comision_pct_comision_check check (pct_comision >= 0);

do $$
declare
  v_def    text := pg_get_functiondef('public.comisiones_evaluar_contrato(uuid)'::regprocedure);
  v_marca  text := 'if v_condicion.id is null or v_beneficiario is null then
      continue;
    end if;';  -- la versión viva está aplicada sin comentarios: la marca no los lleva
  v_nuevo  text;
begin
  if position(v_marca in v_def) = 0 then
    raise exception 'comisiones_evaluar_contrato: no se encuentra el punto de inserción; revisar a mano';
  end if;
  if position('pct_comision = 0' in v_def) > 0 then
    return; -- ya aplicado
  end if;
  v_nuevo := replace(v_def, v_marca, v_marca || '

    -- condición a porcentaje con 0% = esta persona no cobra (23-sep-2026):
    -- ni devengo ni solicitud de 0 €
    if v_condicion.base_calculo <> ''importe_fijo'' and v_condicion.pct_comision = 0 then
      continue;
    end if;');
  execute v_nuevo;
end $$;

insert into public.condiciones_comision
  (equipo_id, proyecto_id, nivel, closer_email, pct_comision, base_calculo, importe_fijo, activo, created_by, vigente_desde)
select null, null, 'closer', 'hello@lawangproperties.com', 0, 'precio_total', null, true, 'sistema:owner-23sep', '1900-01-01'
 where not exists (
   select 1 from public.condiciones_comision
    where equipo_id is null and lower(closer_email) = 'hello@lawangproperties.com');
