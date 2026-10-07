-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Lote 2 (OK del owner 6-oct-2026) · G2 paso 1 + G6 paso 1 (sin proyectos.empresa).
-- G2: el contrato hereda la sociedad del padre en altas vacías, rechaza si no coincide y exige sociedad activa; facturas/proformas se validan
--     contra su contrato SOLO en alta o al cambiar sociedad/contrato (no recibís). G6: la sociedad de un gasto debe estar activa.
-- destructivo-ok: solo funciones y triggers; no toca filas. Las 3 desalineadas (INV00005, PRO00110, PRO00223) NO se cambian.
-- REVERTIR: drop trigger trg_facturas_sociedad_coherente on public.facturas; drop function public.facturas_sociedad_coherente();
--   drop trigger gastos_sociedad_coherente_trg on public.gastos; drop function public.gastos_sociedad_coherente();
--   y recrear contrato_sociedad_existe() con su cuerpo anterior (md5 del def previo d07b5092c892e9501ff933ef8ce9d2ec):
--   create or replace function public.contrato_sociedad_existe() returns trigger language plpgsql set search_path to '' as $f$
--   declare v_clave text := new.datos->'fields'->>'sociedad_firmante';
--   begin
--     if v_clave is not null and v_clave <> '' and not exists (select 1 from public.sociedades s where s.clave = v_clave) then
--       raise exception 'La sociedad firmante «%» no existe en public.sociedades.', v_clave;
--     end if;
--     return new;
--   end; $f$;
--   grant execute on function public.contrato_sociedad_existe() to authenticated, service_role;

create or replace function public.contrato_sociedad_existe() returns trigger
language plpgsql security definer set search_path to '' as $$
declare
  v_clave  text := nullif(btrim(coalesce(new.datos->'fields'->>'sociedad_firmante','')), '');
  v_old    text;
  v_padre  text;
  v_activa boolean;
  v_cambia boolean;
begin
  if tg_op = 'UPDATE' then
    v_old := nullif(btrim(coalesce(old.datos->'fields'->>'sociedad_firmante','')), '');
  end if;
  v_cambia := (tg_op = 'INSERT') or v_clave is distinct from v_old;

  -- herencia: una construcción/carta colgada de una reserva con sociedad explícita
  if new.contrato_padre_id is not null and jsonb_typeof(new.datos->'fields') = 'object' then
    select nullif(btrim(coalesce(p.datos->'fields'->>'sociedad_firmante','')), '') into v_padre
      from public.contratos p where p.id = new.contrato_padre_id;
    if v_padre is not null then
      if v_clave is null and tg_op = 'INSERT' then
        new.datos := jsonb_set(new.datos, '{fields,sociedad_firmante}', to_jsonb(v_padre));
        v_clave := v_padre; v_cambia := true;
      elsif v_clave is not null and v_cambia and v_clave <> v_padre then
        raise exception 'La sociedad firmante «%» no coincide con la del contrato del que cuelga («%»).', v_clave, v_padre
          using errcode = '23514';
      end if;
    end if;
  end if;

  if v_clave is not null then
    select s.activa into v_activa from public.sociedades s where s.clave = v_clave;
    if not found then
      raise exception 'La sociedad firmante «%» no existe en public.sociedades.', v_clave;   -- mensaje original
    end if;
    if v_cambia and not v_activa then
      raise exception 'La sociedad firmante «%» está desactivada: elige una activa.', v_clave using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
-- Nota: un UPDATE de contrato_padre_id sin tocar datos (traspasos de carta, «carta colgada de su RP») NO dispara el rechazo a propósito
-- (no se tumba un flujo de servidor); el cruce queda para el vigilante (consulta de abajo, 0 hoy).

-- 1b) factura / proforma: coherente con su contrato y con sociedad activa. NO recibís (no verificado si un recibí puede cobrarse por otra sociedad).
create or replace function public.facturas_sociedad_coherente() returns trigger
language plpgsql security definer set search_path to '' as $$
declare v_c text; v_num text; v_activa boolean;
begin
  if new.tipo not in ('factura','proforma') then return new; end if;
  if tg_op = 'UPDATE' and new.sociedad is not distinct from old.sociedad
     and new.contrato_id is not distinct from old.contrato_id then return new; end if;
  select s.activa into v_activa from public.sociedades s where s.clave = new.sociedad;
  if v_activa is not true then
    raise exception 'La sociedad emisora «%» no está activa.', new.sociedad using errcode = '23514';
  end if;
  if new.contrato_id is not null then
    select nullif(btrim(coalesce(c.datos_fields->>'sociedad_firmante','')), ''), c.numero into v_c, v_num
      from public.contratos c where c.id = new.contrato_id;
    if v_c is not null and v_c <> new.sociedad then
      raise exception 'El documento sale por «%» pero el contrato % es de «%»: usa la sociedad del contrato.', new.sociedad, v_num, v_c
        using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.facturas_sociedad_coherente() from public, anon, authenticated;
drop trigger if exists trg_facturas_sociedad_coherente on public.facturas;
create trigger trg_facturas_sociedad_coherente before insert or update of sociedad, contrato_id on public.facturas
  for each row execute function public.facturas_sociedad_coherente();
-- Consecuencia: las 3 desalineadas (sin enviar) no podrán cambiar de sociedad ni de contrato hasta alinearlas; el resto de ediciones no se ve afectado (el trigger solo mira esas dos columnas).
revoke all on function public.contrato_sociedad_existe() from public, anon, authenticated;

create or replace function public.gastos_sociedad_coherente() returns trigger
language plpgsql security definer set search_path to '' as $$
declare v_activa boolean; v_emp text;
begin
  if tg_op = 'UPDATE' and new.sociedad is not distinct from old.sociedad
     and new.proyecto_id is not distinct from old.proyecto_id then return new; end if;
  select s.activa into v_activa from public.sociedades s where s.clave = new.sociedad;
  if v_activa is not true then
    raise exception 'La sociedad «%» no está activa: elige una sociedad activa para el gasto.', new.sociedad using errcode = '23514';
  end if;
  -- PASO 2 (descomentar cuando exista proyectos.empresa; ver G2): con empresa en el proyecto, la sociedad del gasto es esa.
  -- if new.proyecto_id is not null then
  --   select p.empresa into v_emp from public.proyectos p where p.id = new.proyecto_id;
  --   if v_emp is not null and v_emp <> new.sociedad then
  --     raise exception 'El gasto es del proyecto «%» y ese proyecto es de «%»: la sociedad del gasto no puede ser «%».',
  --       (select nombre from public.proyectos where id = new.proyecto_id), v_emp, new.sociedad using errcode = '23514';
  --   end if;
  -- end if;
  return new;
end $$;
revoke all on function public.gastos_sociedad_coherente() from public, anon, authenticated;
drop trigger if exists gastos_sociedad_coherente_trg on public.gastos;
create trigger gastos_sociedad_coherente_trg before insert or update of sociedad, proyecto_id on public.gastos
  for each row execute function public.gastos_sociedad_coherente();
