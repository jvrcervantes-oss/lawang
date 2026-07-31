-- ============================================================================
-- El contrato reserva la unidad, y la unidad lo sabe — 31-jul-2026
-- ----------------------------------------------------------------------------
-- Hasta hoy `unidades.contrato_id` existía pero lo rellenaba una persona a mano
-- desde /unidades/. O sea: el contrato podía decir "parcela A5" y el inventario
-- seguir enseñando A5 como disponible. Eso es una parcela vendible dos veces.
--
-- Ahora lo hace la BASE DE DATOS y no la aplicación, porque a `contratos` le
-- escriben tres sitios distintos —la app de contratos, la función de firma y
-- cualquier corrección por SQL— y una regla que vive en uno de los tres no se
-- cumple desde los otros dos.
--
-- QUÉ SE MUEVE SOLO Y QUÉ NO:
--   · contrato con parcela  →  la unidad queda `reservada` y apuntando a él
--   · contrato firmado      →  `vendida`
--   · se quita la parcela   →  la unidad vuelve a `disponible`
--   · se borra el contrato  →  la unidad vuelve a `disponible`
--   · `bloqueada` y `no_disponible` NO se tocan NUNCA: los pone una persona por
--     un motivo que la base no conoce (un litigio, una reserva verbal), y un
--     automatismo que los pisa es peor que no tener automatismo.
--
-- El AVANCE DE COBRO no se guarda en la unidad: se calcula al leerlo desde
-- `facturas`. Guardarlo sería una tercera copia del mismo dato que se queda
-- vieja en cuanto alguien anule una factura.
-- ============================================================================

-- ---- el contrato manda sobre la unidad -------------------------------------
create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod     text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy    text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant text;
  ocupada text;
begin
  -- 1) Si el contrato cambió de parcela (o se la quitaron), la anterior se
  --    suelta. Sin esto, corregir un código dejaría reservada una parcela que
  --    ya no vende nadie, y esa no vuelve sola nunca.
  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  -- 2) Nadie le quita una parcela a otro contrato en silencio. Si ya está
  --    tomada, se para el guardado con un mensaje que se entiende: es
  --    justamente el caso de la doble venta, y fallar aquí es barato comparado
  --    con descubrirlo cuando los dos compradores han firmado.
  select c.numero into ocupada
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;
  if ocupada is not null then
    raise exception 'La parcela % de % ya está asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  -- 3) Vincular y mover el estado.
  update public.unidades u
     set contrato_id = new.id,
         estado = case
           when u.estado in ('bloqueada','no_disponible') then u.estado
           when coalesce(new.bloqueado, false) then 'vendida'
           else 'reservada'
         end
   where u.proyecto = proy and u.codigo = cod;

  return new;
end $$;

drop trigger if exists trg_sincroniza_unidad on public.contratos;
create trigger trg_sincroniza_unidad
  after insert or update on public.contratos
  for each row execute function public.sincroniza_unidad_contrato();

-- ---- una unidad sin contrato vuelve a estar libre --------------------------
-- Cubre dos caminos de golpe: el borrado del contrato (la clave ajena pone
-- `contrato_id` a NULL) y el desvinculado a mano desde /unidades/. Sin esto, un
-- contrato borrado dejaba la parcela marcada como vendida para siempre.
-- La condición `new.estado = old.estado` es la que impide pisar a quien esté
-- cambiando el estado a propósito en esa misma operación.
create or replace function public.libera_unidad_sin_contrato()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.contrato_id is null and old.contrato_id is not null
     and new.estado = old.estado
     and old.estado in ('reservada','vendida') then
    new.estado := 'disponible';
  end if;
  return new;
end $$;

drop trigger if exists trg_libera_unidad on public.unidades;
create trigger trg_libera_unidad
  before update on public.unidades
  for each row execute function public.libera_unidad_sin_contrato();

-- ---- lo que se cobra de cada unidad, calculado, no guardado ----------------
-- Las proformas y las anuladas NO suman: una proforma no es un cobro y una
-- anulada dejó de serlo. Mismo criterio que /operaciones/.
create or replace view public.unidades_estado as
select u.*,
       c.numero          as contrato_numero,
       c.comprador_nombre,
       c.bloqueado       as contrato_firmado,
       coalesce(f.facturado, 0) as facturado,
       case when u.precio > 0
            then round(coalesce(f.facturado, 0) / u.precio * 100, 1) end as pct_cobrado
  from public.unidades u
  left join public.contratos c on c.id = u.contrato_id
  left join lateral (
     select sum(x.total) as facturado
       from public.facturas x
      where x.contrato_id = u.contrato_id
        and coalesce(x.anulada, false) = false
        and x.tipo <> 'proforma'
  ) f on true;

-- La vista hereda la RLS de las tablas de debajo (`security_invoker`): sin esto
-- una vista de un `security definer` enseñaría filas que la policy niega.
alter view public.unidades_estado set (security_invoker = true);
grant select on public.unidades_estado to authenticated;
