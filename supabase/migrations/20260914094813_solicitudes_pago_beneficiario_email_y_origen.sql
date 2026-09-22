-- destructivo-ok: no hay DROP ni DELETE ni UPDATE sin WHERE en este fichero.
-- El UPDATE de backfill toca la unica fila existente hoy (numero SP-8,
-- estado='pendiente') y solo escribe la columna beneficiario_email nueva --
-- pasa por la maquina de estados existente por el camino
-- pendiente->pendiente, que no exige permiso ninguno y no se toca aqui. Los
-- "drop policy if exists" son el patron estandar del repo para poder
-- re-ejecutar sin fallar por nombre duplicado -- reemplaza la MISMA policy de
-- SELECT que ya existia (visto en pg_policies, no en el archivo original:
-- fue ampliada en algun punto entre el 9-sep y hoy para que el manager del
-- proyecto tambien vea la solicitud de su contrato -- esa ampliacion no
-- se toca, solo se le anade una rama mas).
--
-- BACKUP -- el intento de escribir el snapshot bajo Backups/ de este proyecto
-- lo bloquea permissions.deny (ya documentado: bloquea tambien escritura, no
-- solo lectura). El snapshot de la unica fila existente antes de esta
-- migracion queda aqui, en el propio fichero versionado:
--   id=f98278c6-9296-484a-8d48-35239efe85aa numero=8 estado=pendiente
--   contrato_id=4419c629-a0c4-40a3-a227-46c848eae1cc concepto='comision w30'
--   importe=1000 moneda=EUR creado_por=0b3592b6-d4a1-479e-8b31-42e9d4bdceb7
--   (gusabellan@gmail.com) creado_en=2026-09-10T02:51:14.98389+00:00
--   resuelto_por/en=null pagado_por/en=null motivo_rechazo=null
--   pago_referencia=null nota=null
-- ============================================================================
-- SOLICITUDES DE PAGO — beneficiario_email + origen — 14-sep-2026
-- ----------------------------------------------------------------------------
-- Subtarea del encargo de comisiones: cuando un tramo de
-- condicion_tramos se dispara para un MANAGER, el cobro pasa por esta misma
-- cola (ver comentario "solicitud_id" en comisiones_devengadas.sql,
-- 20260914093049 en remoto). Ese futuro proceso automatico va a insertar en
-- solicitudes_pago a nombre de un beneficiario que no es necesariamente quien
-- ejecuta el INSERT. Esta migracion solo deja el terreno listo: columnas +
-- trigger de alta + policy de lectura. NO crea el proceso que dispara el
-- devengo (es otra subtarea del mismo encargo) y NO toca la maquina de
-- estados de _trg_solicitud_pago_transicion.
--
-- (a) beneficiario_email — a quien hay que pagarle. Para una solicitud
--     'manual' (la que ya existia) es siempre quien la crea -- el trigger de
--     alta lo fuerza a auth.email(), igual que fuerza creado_por := auth.uid().
--     Para 'comision_automatica' es el dato que trae el proceso que dispara
--     el devengo, y puede ser una persona distinta de quien ejecuta el INSERT.
--     Backfill de la unica fila existente: el email de su creado_por (que es
--     tambien su beneficiario, porque nacio como solicitud manual).
--
-- (b) origen — 'manual' (default, lo que ya existia) | 'comision_automatica'.
--     Nunca se lee para decidir permisos por si solo: decide que rama toma el
--     trigger de alta.
--
-- (c) trigger de alta adaptado -- unico cambio de comportamiento real:
--       - origen='manual' (default): igual que hasta hoy. Fuerza
--         creado_por:=auth.uid() y ahora tambien beneficiario_email:=
--         auth.email() (mismo dueño que crea la solicitud).
--       - origen='comision_automatica': NO fuerza creado_por -- se queda con
--         lo que traiga el INSERT (su propio default sigue siendo
--         auth.uid(), asi que sigue satisfaciendo la policy de INSERT sin
--         cambiarla). beneficiario_email se toma tal cual lo manda el
--         proceso automatico (solo btrim). El CHECK
--         solicitud_beneficiario_automatica exige que venga relleno.
--
-- (d) policy de SELECT ampliada -- se anade "o el beneficiario se ve a si
--     mismo", sin tocar lo que ya veian admin/creador/manager del proyecto.
--
-- La policy de INSERT ("el equipo crea las suyas": es_agente() AND
-- creado_por=auth.uid()) y la de UPDATE no se tocan -- fuera del alcance de
-- esta subtarea, y el proceso automatico del encargo todavia no existe.
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
