-- ============================================================================
-- El tipo de contrato y el dinero mandan sobre el estado — 12-ago-2026
-- ----------------------------------------------------------------------------
-- Supera el CASE de `sincroniza_unidad_contrato()` en vinculo_contrato_unidad.sql
-- (31-jul-2026), que solo miraba `contratos.bloqueado` (firmado sí/no) y por eso
-- CUALQUIER contrato firmado —una Carta de Reserva incluida— saltaba directo a
-- `vendida`. Bug real reportado por el owner: firmar una Carta de Reserva no
-- debe mover la parcela ni generar proforma (la proforma ya se corrigió el
-- 12-ago en `crearProformaAutomatica`/`enviarProformaTotal`; esto corrige el
-- otro efecto del mismo bug, el estado).
--
-- FLUJO NUEVO:
--   · Carta de Reserva (CR), crear o firmar   → reservada (firmar NO avanza)
--   · Bloqueo de Parcela (RP), crear          → reservada
--   · Bloqueo de Parcela (RP), firmar         → bloqueada
--   · Contrato de Construcción (CC)           → no toca el estado de la parcela
--   · primer recibí real cobrado              → vendida
--   · 100% cobrado (misma base que ya usa la
--     ficha de Unidades: `contrato_cobrado()` contra `unidades.precio`) → cobrada
--
-- 'bloqueada' SE REUSA para dos causas — bloqueo manual (litigio, reserva
-- verbal que la base no conoce) y la firma automática de un RP — porque
-- pedirle al owner dos valores en el enum para "la parcela no se puede vender
-- a otro" es la misma pregunta dos veces. NO se guarda de cuál de las dos
-- viene: se DERIVA en cada evaluación (¿el contrato vinculado hoy es un RP
-- firmado? si sí, el automatismo puede seguir moviéndola; si no, es manual y
-- se protege igual que siempre). Guardar un origen en una columna aparte
-- sería una tercera copia de un dato que ya está en `contratos.tipo` +
-- `contratos.bloqueado` — la misma razón por la que el AVANCE DE COBRO
-- tampoco se guarda (comentario original de más abajo).
--
-- LÍMITE CONOCIDO, a propósito: ni este trigger ni `avanza_unidad_por_cobro`
-- REVIERTEN un estado. Si se anula el recibí que llevó una parcela a
-- `vendida`/`cobrada`, la parcela se queda ahí — mismo criterio que ya tenía
-- `sincroniza_unidad_contrato` (una edición del contrato tampoco hacía
-- retroceder `vendida`). Corrección manual desde `/proyectos/`.
-- ============================================================================

-- ---- 1) el tipo de contrato decide el TECHO al que llega la firma sola ----
create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod     text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy    text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant text;
  ocupada text;
begin
  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  select c.numero into ocupada
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;
  if ocupada is not null then
    raise exception 'La parcela % de % ya está asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  update public.unidades u
     set contrato_id = new.id,
         estado = case
           -- vendida/cobrada solo las mueve el dinero (avanza_unidad_por_cobro,
           -- más abajo) — ninguna firma ni edición de contrato las revierte.
           when u.estado in ('vendida','cobrada') then u.estado
           when u.estado = 'no_disponible' then u.estado
           -- bloqueada manual (sin RP firmado detrás): protegida, igual que siempre.
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
           -- Contrato de Construcción: no mueve el estado de la parcela.
           when new.tipo = 'construccion' then u.estado
           -- cualquier otro caso (crear CR/RP, o firmar una CR) se queda en reservada.
           else 'reservada'
         end
   where u.proyecto = proy and u.codigo = cod;

  return new;
end $$;
-- trg_sincroniza_unidad ya existe (creado en vinculo_contrato_unidad.sql) y
-- apunta a esta misma función por nombre — no hace falta recrearlo.

-- ---- 2) el dinero avanza vendida/cobrada, nunca las revierte --------------
-- Misma base que ya usa /proyectos/ para enseñar "Cobrado" y el % de la
-- parcela (`contrato_cobrado()` contra `unidades.precio`, vista
-- `unidades_estado`) — ninguna cuenta nueva, la misma.
--
-- FIX-FORWARD sobre la consulta de deploy del propio 12-ago (capa 1), 3
-- hallazgos reales de Administración/Desarrollo/Legal:
--   · Una parcela con Bloqueo de Parcela (suelo) + Contrato de Construcción
--     SEPARADO -patrón real y normal en Lawang, confirmado contra producción-
--     nunca sumaba el cobro de los dos contratos juntos, y encima
--     `unidades.contrato_id` apunta SIEMPRE al de suelo (la CC nunca lleva
--     `parcela_codigo` propio, así que `sincroniza_unidad_contrato` no la
--     vincula jamás) — un recibí contra la CC actualizaba 0 filas. Se resuelve
--     vía `contratos.contrato_padre_id` (ya existente, 29-jul) al contrato
--     "raíz" que `unidades.contrato_id` sí conoce, y se suma el cobro de la
--     raíz + el de todos sus hijos.
--   · El guardarraíl de moneda mezclada no cubría un recibí repartido vía
--     `recibi_aplicaciones` cuyo PROPIO contrato_id (y moneda) puede ser
--     distinto del contrato de la factura a la que se aplica — se amplía a
--     cubrir también esa vía, sobre el mismo cluster raíz+hijos.
--   · Un recibí contra una simple Carta de Reserva (sin Bloqueo de Parcela
--     firmado detrás) saltaba directo a 'vendida' — palabra con peso
--     contractual, publicada en el masterplan público. El dinero no se salta
--     la escalera: hace falta que la parcela ya esté en 'bloqueada' (o más
--     allá) antes de que un recibí la mueva.
create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_raiz_id uuid;
  v_cobrado numeric;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from (select u.moneda from public.unidades u where u.contrato_id = v_raiz_id)
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from (select u.moneda from public.unidades u where u.contrato_id = v_raiz_id)
  ) into v_mezcla;
  if v_mezcla then return; end if;

  v_cobrado := coalesce(public.contrato_cobrado(v_raiz_id), 0);
  select v_cobrado + coalesce(sum(public.contrato_cobrado(hijo.id)), 0)
    into v_cobrado
    from public.contratos hijo
   where hijo.contrato_padre_id = v_raiz_id;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when u.precio > 0 and v_cobrado >= u.precio then 'cobrada'
           when v_cobrado > 0 then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end $$;

revoke all on function public.avanza_unidad_por_cobro(uuid) from public, anon, authenticated;

-- Recibí directo (sin repartir entre contratos): INSERT nuevo, o el propio
-- recibí que se anula/corrige después.
create or replace function public.trg_avanza_por_recibi()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo = 'recibi' then
    perform public.avanza_unidad_por_cobro(new.contrato_id);
  end if;
  return new;
end $$;

drop trigger if exists trg_avanza_por_recibi on public.facturas;
create trigger trg_avanza_por_recibi
  after insert or update of anulada, total, contrato_id, tipo on public.facturas
  for each row execute function public.trg_avanza_por_recibi();

-- Recibí repartido entre varios contratos (recibi_aplicaciones, 11-ago-2026):
-- el pago aparece aquí, no como INSERT nuevo en `facturas` — sin este
-- segundo trigger, un cobro que llega por reparto nunca movería la parcela
-- aunque `contrato_cobrado()` ya lo cuente (hallazgo de la revisión previa,
-- confirmado por Datos y Administración de forma independiente).
create or replace function public.trg_avanza_por_aplicacion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_contrato_id uuid;
begin
  select f.contrato_id into v_contrato_id from public.facturas f where f.id = new.factura_id;
  perform public.avanza_unidad_por_cobro(v_contrato_id);
  return new;
end $$;

drop trigger if exists trg_avanza_por_aplicacion on public.recibi_aplicaciones;
create trigger trg_avanza_por_aplicacion
  after insert on public.recibi_aplicaciones
  for each row execute function public.trg_avanza_por_aplicacion();

-- ---- 3) nuevo estado en el catálogo ----------------------------------------
alter table public.unidades drop constraint unidades_estado_check;
alter table public.unidades add constraint unidades_estado_check
  check (estado = any (array['disponible','reservada','vendida','bloqueada','no_disponible','cobrada']));

-- ---- 4) fija en el repo lo que ya vivía solo en la base desde el 11-ago ----
-- (migración `20260811035145_unidades_estado_solo_recibi`, sin `.sql`
-- trackeado — hallazgo de la revisión previa). Redefinición idéntica a la
-- que ya corre en producción, cero cambio funcional: solo deja de haber un
-- estado vivo que el repo no puede reconstruir leyendo sus propios ficheros.
-- Columnas listadas una a una y en el mismo orden que la vista viva: un
-- `CREATE OR REPLACE VIEW` con `u.*` falla si el orden no coincide byte a
-- byte con lo que ya hay en producción (probado al aplicar esta migración).
create or replace view public.unidades_estado as
select u.id, u.codigo, u.proyecto, u.tipo, u.superficie_m2, u.precio, u.moneda, u.estado,
       u.contrato_id, u.notas, u.created_at, u.precio_suelo, u.precio_construccion, u.modelo,
       u.obra_fase, u.obra_fecha_entrega, u.obra_actualizado,
       c.numero          as contrato_numero,
       c.comprador_nombre,
       c.bloqueado       as contrato_firmado,
       coalesce(public.contrato_cobrado(u.contrato_id), 0) as facturado,
       case when u.precio > 0
            then round(coalesce(public.contrato_cobrado(u.contrato_id), 0) / u.precio * 100, 1) end as pct_cobrado,
       u.fase_masterplan, u.zona_masterplan
  from public.unidades u
  left join public.contratos c on c.id = u.contrato_id;

alter view public.unidades_estado set (security_invoker = true);
grant select on public.unidades_estado to authenticated;
