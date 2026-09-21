-- destructivo-ok: el DROP POLICY de abajo es el patron "drop if exists +
-- create" para reemplazar la MISMA policy de SELECT que ya vivia en
-- produccion (visto en pg_policies) por una version ampliada -- no se
-- retira ninguna visibilidad que ya existiera, solo se anade una rama mas
-- (beneficiario_email = auth.email()). El UPDATE de backfill toca la unica
-- fila existente hoy y solo escribe beneficiario_email (nueva, antes NULL).
-- Backup de esa fila: ver cabecera del .sql versionado en el repo
-- (proyectos/Lawang/supabase/migrations/20260914150000_...). Nada se borra.
-- ============================================================================

-- (a) + (b) columnas nuevas ---------------------------------------------------
alter table public.solicitudes_pago
  add column beneficiario_email text,
  add column origen text not null default 'manual';

alter table public.solicitudes_pago
  add constraint solicitud_origen_valido
    check (origen in ('manual', 'comision_automatica'));

alter table public.solicitudes_pago
  add constraint solicitud_beneficiario_automatica
    check (origen <> 'comision_automatica'
           or (beneficiario_email is not null and btrim(beneficiario_email) <> ''));

comment on column public.solicitudes_pago.beneficiario_email is
  'A quien hay que pagarle. En una solicitud manual, siempre quien la crea (el trigger de alta lo fuerza a auth.email()). En una comision_automatica, lo trae el proceso que dispara el devengo -- puede ser distinto de quien ejecuta el INSERT.';
comment on column public.solicitudes_pago.origen is
  'manual (comercial pidiendo un pago, default) | comision_automatica (el disparo de un tramo de comisiones la crea a nombre de otro beneficiario). Decide que rama toma _trg_solicitud_pago_alta -- no decide permisos por si sola.';

-- backfill de lo que ya existe: el beneficiario de una solicitud manual
-- siempre fue quien la creo.
update public.solicitudes_pago sp
   set beneficiario_email = u.email
  from public.usuarios u
 where u.user_id = sp.creado_por
   and sp.beneficiario_email is null;

create index solicitudes_pago_beneficiario_email_idx
  on public.solicitudes_pago (beneficiario_email);

-- (c) trigger de alta: misma funcion, misma firma, misma cabecera de resets
-- -- solo se mueve creado_por a la rama 'manual' y se anade la rama
-- 'comision_automatica'. -----------------------------------------------------
create or replace function public._trg_solicitud_pago_alta()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  new.estado := 'pendiente';
  new.creado_en := now();
  new.resuelto_por := null; new.resuelto_en := null;
  new.pagado_por := null;   new.pagado_en := null;
  new.pago_referencia := null;
  new.motivo_rechazo := null;
  new.concepto := btrim(new.concepto);

  if new.origen = 'comision_automatica' then
    -- el proceso que dispara el devengo trae el beneficiario explicito; quien
    -- ejecuta el INSERT no tiene por que serlo. No se toca creado_por aqui --
    -- se queda con lo que traiga la sentencia (su default sigue siendo
    -- auth.uid(), asi que la policy de INSERT ni se entera del cambio). El
    -- CHECK solicitud_beneficiario_automatica ya exige que venga relleno.
    new.beneficiario_email := btrim(new.beneficiario_email);
  else
    new.creado_por := auth.uid();
    new.beneficiario_email := auth.email();
  end if;

  return new;
end
$$;

-- (d) policy de SELECT: misma que ya vivia en produccion (admin todo,
-- creador lo suyo, manager del proyecto del contrato), mas el beneficiario
-- viendose a si mismo. ---------------------------------------------------
drop policy if exists "solicitudes: cada agente lee las suyas, admin todas, manager la" on public.solicitudes_pago;
create policy "solicitudes: cada agente lee las suyas, admin todas, manager la"
  on public.solicitudes_pago for select
  using (
    public.es_admin()
    or creado_por = (select auth.uid())
    or beneficiario_email = (select auth.email())
    or exists (
      select 1 from public.contratos c
       where c.id = solicitudes_pago.contrato_id
         and public.es_manager_de(c.proyecto_id)
    )
  );
;
