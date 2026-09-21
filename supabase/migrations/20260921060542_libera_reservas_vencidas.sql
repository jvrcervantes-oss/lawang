-- ════════════════════════════════════════════════════════════════════════════
-- LIBERACIÓN DE RESERVAS — 21-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Una Carta de Reserva (CR/CA/CH/CP) trae un plazo contractual
-- (datos.fields.fecha_pago_reserva + validez_dias, legado validez_meses). Si
-- vence sin que exista detrás un Bloqueo de Parcela (RP, tipo='reserva_parcela')
-- la parcela se libera sola. Si el comprador desiste antes, el equipo la libera
-- a mano. En NINGÚN caso se borra o edita el contrato — la cuota de reserva es
-- no reembolsable y el recibí ya emitido no se toca. Pasó por revisión previa
-- con Datos+Seguridad+Administración; las dos decisiones ambiguas (blindaje de
-- columnas por trigger, y qué rol puede liberar por desistimiento) ya las
-- resolvió el owner y van aplicadas tal cual abajo.
--
-- Verificado contra la base real antes de escribir esto (21-sep-2026):
--   · contrato_tipo_etapa.etapa='reserva' menos 'reserva_parcela' da
--     exactamente {carta_reserva, carta_reserva_ampliada,
--     carta_reserva_hak_sewa, carta_reserva_pma} — el catálogo no se escribe
--     a mano, sale de esa tabla (punto 5 del encargo).
--   · sincroniza_unidad_contrato() es AFTER INSERT OR UPDATE (sin "OF"): CUALQUIER
--     UPDATE de contratos la dispara, incluida la que hace esta función —
--     de ahí el guard obligatorio al principio.
--   · el UPDATE de esta función solo toca liberado_en/liberado_motivo, así que
--     los triggers "BEFORE UPDATE OF <columna>" de contratos (datos, poder_id,
--     unidad_id, proyecto_id/nombre, bloqueado) no se disparan; los que sí son
--     incondicionales (contrato_no_editable_en_firma, carta_cobrado_congelado_
--     en_update, contrato_sociedad_existe, contrato_evento_log,
--     registra_edicion_privilegiada) se comprobaron uno a uno y ninguno bloquea
--     ni duplica el evento (contrato_no_editable_en_firma sale en su primera
--     línea si datos no cambió).
--   · avisos-manager y _avisar_managers ya existen (18/19-sep): el aviso de
--     "vence mañana" reusa ese canal, no se inventa uno nuevo.
-- ════════════════════════════════════════════════════════════════════════════


-- ── 1. Columnas nuevas ───────────────────────────────────────────────────────
alter table public.contratos
  add column if not exists liberado_en timestamptz,
  add column if not exists liberado_motivo text;

alter table public.contratos
  add constraint contratos_liberado_motivo_check
  check (liberado_motivo is null or liberado_motivo in ('vencida_reserva', 'desistida'));

-- Referencia histórica: qué contrato ocupaba la parcela antes de liberarse.
-- Administración lo pidió explícitamente para no perder trazabilidad de lo
-- cobrado (la cuota de reserva) cuando unidades.contrato_id se vacíe.
alter table public.unidades
  add column if not exists contrato_liberado_id uuid references public.contratos(id) on delete set null;


-- ── 2. Blindar liberado_en/liberado_motivo contra escritura directa ─────────
-- Hallazgo Seguridad: la policy de UPDATE de contratos no filtra por columna,
-- solo por fila — un agente con permiso de editar SU contrato podría hacer
-- `UPDATE contratos SET liberado_motivo=...` directo por PostgREST sin pasar
-- por libera_reserva(). Este trigger revierte cualquier cambio a esas dos
-- columnas salvo que venga marcado por la propia función vía una GUC de
-- transacción (set_config con is_local=true: dura solo el statement/tx actual,
-- nunca se queda "encendida" para la siguiente petición).
create or replace function public._protege_liberado_contrato()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if (new.liberado_en is distinct from old.liberado_en
      or new.liberado_motivo is distinct from old.liberado_motivo)
     and coalesce(nullif(current_setting('app.via_libera_reserva', true), ''), 'off') <> 'on' then
    new.liberado_en := old.liberado_en;
    new.liberado_motivo := old.liberado_motivo;
  end if;
  return new;
end;
$function$;

-- destructivo-ok: drop trigger if exists + create es el idiom estandar de este
-- repo para (re)crear un trigger de forma idempotente (correr la migracion dos
-- veces no falla) — no borra datos, solo redefine el trigger. Hablado en la
-- revision previa de esta misma sesion (Datos+Seguridad+Administracion).
drop trigger if exists trg_protege_liberado_contrato on public.contratos;
create trigger trg_protege_liberado_contrato
  before update on public.contratos
  for each row execute function public._protege_liberado_contrato();


-- ── 3. Guardas en los triggers ya existentes (se editan, no se duplican) ────

-- 3a. sincroniza_unidad_contrato(): un contrato ya liberado no debe volver a
-- "reclamar" su parcela solo porque cualquier UPDATE (incluido el de esta
-- misma liberación) dispara este trigger AFTER UPDATE sin "OF columna".
-- Y en el JOIN que resuelve si la parcela está ocupada, un contrato liberado
-- ya no cuenta como ocupante (defensa en profundidad: en la práctica
-- unidades.contrato_id ya se vació al liberar).
create or replace function public.sincroniza_unidad_contrato()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  cods_ant text[];
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  proy_ant     text;
  cod          text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  ids_nuevo    text[];
  ids_ocupa    text[];
  traspaso_ok  boolean;
  exige        boolean;
  master       text;
  falta        text;
begin
  if new.liberado_en is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cods_ant := (
      select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
        from unnest(string_to_array(coalesce(old.datos->'fields'->>'parcela_codigo',''), ',')) x);
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      proy_ant := case when tg_op = 'UPDATE'
                  then coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre)
                  end;
      if tg_op = 'UPDATE'
         and cods_ant is not distinct from cods
         and proy_ant is not distinct from proy then
        return new;
      end if;

      falta := case
                 when proy is null and coalesce(array_length(cods, 1), 0) = 0
                   then 'el proyecto y la parcela'
                 when proy is null then 'el proyecto'
                 else 'la parcela'
               end;

      master := nullif(btrim(coalesce(new.datos->'fields'->>'parcela_master','')), '');

      if master is not null and coalesce(array_length(cods, 1), 0) = 0 then
        raise exception
          'Rellena: %. El código «%» está en «Parcela máster» por error — va en el campo «Parcela».',
          falta, master using errcode = '23514';
      end if;

      raise exception
        'Rellena: %.',
        falta using errcode = '23514';
    end if;

    return new;
  end if;

  ids_nuevo := public.contrato_identificadores(new.datos);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id
       and c.liberado_en is null;

    if ocupada_id is not null then
      if new.tipo like 'carta_reserva%'
         and ocupada_tipo = 'reserva_parcela'
         and ids_nuevo && ids_ocupa then
        continue;
      end if;

      traspaso_ok := new.tipo = 'reserva_parcela'
                 and ocupada_tipo like 'carta_reserva%';

      if not traspaso_ok then
        raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
          using errcode = '23505';
      end if;

      if coalesce(array_length(ids_nuevo, 1), 0) = 0
         or coalesce(array_length(ids_ocupa, 1), 0) = 0 then
        raise exception 'El traspaso de la parcela % de % no se puede comprobar: falta el pasaporte o el email del comprador en % o en el contrato que estás guardando. Complétalo y vuelve a guardar.',
          cod, proy, ocupada using errcode = '23514';
      end if;
      if not (ids_nuevo && ids_ocupa) then
        raise exception 'El traspaso de la parcela % de % no cuadra: % está a nombre de otro comprador. La parcela solo pasa de una Carta de Reserva a su Bloqueo si coincide el pasaporte o el email.',
          cod, proy, ocupada using errcode = '23514';
      end if;
    end if;

    update public.unidades u
       set contrato_id = new.id,
           estado = case
             when u.estado in ('vendida','cobrada') then u.estado
             when u.estado = 'no_disponible' then u.estado
             when u.estado = 'bloqueada' and not exists (
                    select 1 from public.contratos c2
                     where c2.id = u.contrato_id
                       and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                  ) then u.estado
             when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
             when new.tipo = 'construccion' then u.estado
             else 'reservada'
           end
     where u.proyecto = proy and u.codigo = cod;

    if ocupada_id is not null and traspaso_ok then
      update public.contratos c
         set contrato_padre_id = new.id
       where c.id = ocupada_id and c.contrato_padre_id is null;
    end if;

    ocupada_id := null; ocupada := null; ocupada_tipo := null; ids_ocupa := null;
  end loop;

  return new;
end;
$function$;

-- 3b. avanza_unidad_por_cobro(): un recibí tardío contra un contrato ya
-- liberado no debe mover ninguna unidad (esa parcela ya siguió su camino).
create or replace function public.avanza_unidad_por_cobro(p_contrato_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raiz_id uuid;
  v_mon     text;
  v_nmon    int;
  v_mezcla  boolean;
begin
  if p_contrato_id is null then return; end if;

  select coalesce(contrato_padre_id, id) into v_raiz_id
    from public.contratos where id = p_contrato_id;
  if v_raiz_id is null then return; end if;

  if exists (select 1 from public.contratos where id = v_raiz_id and liberado_en is not null) then
    return;
  end if;

  select min(u.moneda), count(distinct u.moneda)
    into v_mon, v_nmon
    from public.unidades u where u.contrato_id = v_raiz_id;
  if coalesce(v_nmon, 0) > 1 then return; end if;

  select exists (
    select 1 from public.facturas f
     where f.tipo = 'recibi' and not coalesce(f.anulada, false)
       and (f.contrato_id = v_raiz_id
            or f.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and f.moneda is distinct from v_mon
    union all
    select 1 from public.recibi_aplicaciones ra
      join public.facturas r   on r.id = ra.recibi_id
      join public.facturas fac on fac.id = ra.factura_id
     where not coalesce(r.anulada, false) and not coalesce(fac.anulada, false)
       and (fac.contrato_id = v_raiz_id
            or fac.contrato_id in (select hijo.id from public.contratos hijo where hijo.contrato_padre_id = v_raiz_id))
       and r.moneda is distinct from v_mon
  ) into v_mezcla;
  if v_mezcla then return; end if;

  update public.unidades u
     set estado = case
           when u.estado = 'no_disponible' then u.estado
           when u.estado = 'bloqueada' and not exists (
                  select 1 from public.contratos c2
                   where c2.id = u.contrato_id
                     and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                ) then u.estado
           when u.estado not in ('bloqueada', 'vendida', 'cobrada') then u.estado
           when coalesce(u.precio, 0) > 0
                and (select cobrado_suelo + cobrado_obra from public.unidad_parte_cobrada_interno(u.id)) >= u.precio
                then 'cobrada'
           when coalesce(u.precio_suelo, 0) > 0
                and (select cobrado_suelo from public.unidad_parte_cobrada_interno(u.id)) >= u.precio_suelo
                then 'vendida'
           else u.estado
         end
   where u.contrato_id = v_raiz_id;
end;
$function$;


-- ── 4. Catálogo de eventos: reserva_liberada ────────────────────────────────
-- destructivo-ok: drop constraint + add constraint amplia el CHECK con un
-- valor nuevo ('reserva_liberada') — no es un enum nativo, es texto con CHECK,
-- y esta es la unica forma de ampliarlo (mismo patron ya usado en este mismo
-- proyecto para contratos_tipo_check). No borra ni una fila de
-- contrato_eventos; los 17 valores viejos siguen todos permitidos. Hablado en
-- la revision previa de esta sesion (Datos+Seguridad+Administracion).
alter table public.contrato_eventos drop constraint contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check
  check (evento = any (array[
    'creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta','firma_recogida',
    'firma_anulada','firmado_del_todo','desbloqueado','traspaso','editado_estando_firmado',
    'factura_sin_bloquear','cobro_a_factura_huerfana','cobro_a_otro_comprador',
    'comprador_sin_ficha','factura_borrada','contrato_borrado','reserva_liberada'
  ]));


-- ── 5. La función libera_reserva ─────────────────────────────────────────────
-- p_unidad_id: la parcela a liberar. p_contrato_id: el contrato que el
-- llamante CREE que la ocupa — se valida contra la realidad en el propio
-- UPDATE, nunca se confía a ciegas.
--
-- Idempotente (se comprueba primero, sin más efectos): si el contrato ya está
-- liberado, no hay nada que hacer — una segunda llamada (reintento del cron,
-- doble clic del botón manual) no debe romper nada.
--
-- 'vencida_reserva' SOLO la aplica el automatismo: si auth.uid() no es null,
-- es una sesión de usuario real y se rechaza — la Edge del cron llama con
-- service_role sin JWT de usuario, así que ahí auth.uid() es null.
--
-- 'desistida' exige nota y uno de dos roles — EXCEPCIÓN DELIBERADA Y ACOTADA,
-- decisión del owner (revisión previa Seguridad+Datos+Administración,
-- 21-sep-2026): sales_manager es de solo lectura en el resto de la suite,
-- pero aquí SÍ puede liberar por desistimiento, restringido a los proyectos
-- que supervisa (es_manager_de). project_manager NO entra en esta excepción.
--
-- La validación de que la parcela sigue libre para liberarse va en el WHERE
-- del UPDATE de unidades, no en un SELECT previo: un SELECT-luego-UPDATE deja
-- una ventana de carrera (Seguridad). Si ese UPDATE no toca ninguna fila,
-- nunca es silencioso: se relanza como excepción con el motivo.
create or replace function public.libera_reserva(
  p_unidad_id uuid,
  p_contrato_id uuid,
  p_motivo text,
  p_nota text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_proyecto_id uuid;
  v_quien       text;
  v_filas       int;
begin
  if p_motivo not in ('vencida_reserva', 'desistida') then
    raise exception 'Motivo de liberación no reconocido: %', p_motivo using errcode = '22023';
  end if;

  -- idempotencia: ya liberado, no hay nada más que hacer (ni falla ni repite)
  if exists (select 1 from public.contratos where id = p_contrato_id and liberado_en is not null) then
    return;
  end if;

  if p_motivo = 'vencida_reserva' then
    if (select auth.uid()) is not null then
      raise exception 'vencida_reserva solo la aplica el automatismo (cron); esto es una sesión de usuario.'
        using errcode = '42501';
    end if;
  else -- desistida
    if p_nota is null or btrim(p_nota) = '' then
      raise exception 'Liberar por desistimiento exige una nota.' using errcode = '23514';
    end if;

    select u.proyecto_id into v_proyecto_id from public.unidades u where u.id = p_unidad_id;

    if not (
      public.es_admin()
      or (
        exists (
          select 1 from public.usuarios uu
           where uu.user_id = (select auth.uid()) and uu.activo and uu.rol = 'sales_manager'
        )
        and public.es_manager_de(v_proyecto_id)
      )
    ) then
      raise exception 'No tienes permiso para liberar esta reserva por desistimiento.' using errcode = '42501';
    end if;
  end if;

  v_quien := coalesce(public._quien_actua(), 'cron:libera-reservas-vencidas');

  -- la contraseña que abre el candado del trigger de blindaje (punto 2),
  -- solo para el UPDATE de contratos de más abajo, solo esta transacción
  perform set_config('app.via_libera_reserva', 'on', true);

  -- ── el UPDATE que valida Y libera a la vez, atómico ───────────────────────
  update public.unidades u
     set estado = 'disponible',
         contrato_liberado_id = p_contrato_id,
         contrato_id = null
   where u.id = p_unidad_id
     and u.estado = 'reservada'
     and u.contrato_id = p_contrato_id
     and not exists (
       select 1 from public.contratos rp
        where rp.tipo = 'reserva_parcela'
          and rp.liberado_en is null
          and rp.id in (
            u.contrato_id,
            (select c2.contrato_padre_id from public.contratos c2 where c2.id = p_contrato_id)
          )
     );

  get diagnostics v_filas = row_count;
  if v_filas = 0 then
    raise exception
      'No se pudo liberar la unidad %: no está reservada por el contrato %, o ya existe un Bloqueo de Parcela vivo sobre ella.',
      p_unidad_id, p_contrato_id using errcode = 'P0001';
  end if;

  update public.contratos
     set liberado_en = now(),
         liberado_motivo = p_motivo
   where id = p_contrato_id;

  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato_id, 'reserva_liberada',
          jsonb_build_object('motivo', p_motivo, 'nota', p_nota, 'unidad_id', p_unidad_id),
          v_quien);
end;
$function$;

revoke all on function public.libera_reserva(uuid, uuid, text, text) from public, anon;
grant execute on function public.libera_reserva(uuid, uuid, text, text) to authenticated, service_role;


-- ── 6. El secreto del cron + el programador ─────────────────────────────────
-- Mismo patrón exacto que facturacion_automatica.sql (18-ago-2026): secreto
-- generado dentro de la base (Vault), función-ventanilla solo para
-- service_role, cron.schedule con nombre (upsert, correr esto dos veces no
-- duplica el job). Diario a las 04:00 UTC — antes que facturas-vencimiento-d3
-- (05:00 UTC), para que una parcela que se libera hoy no aparezca facturable
-- en la misma pasada.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_libera_reservas') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_libera_reservas');
  end if;
end $$;

create or replace function public.cron_libera_reservas_secret()
returns text
language sql
security definer
set search_path to ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_libera_reservas';
$$;
revoke execute on function public.cron_libera_reservas_secret() from public, anon, authenticated;
grant execute on function public.cron_libera_reservas_secret() to service_role;

select cron.schedule(
  'libera-reservas-vencidas-diario',
  '0 4 * * *',
  $$
  select net.http_post(
    url     := 'https://vtulllundrfennhjddhc.supabase.co/functions/v1/libera-reservas-vencidas',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_libera_reservas')
    ),
    body    := '{"dry": false}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

-- ── Comprobación (la del catálogo) ──────────────────────────────────────────
--   select jobname, schedule, active from cron.job where jobname = 'libera-reservas-vencidas-diario';
--   select name from vault.secrets where name = 'cron_libera_reservas';
--   select tipo from public.contrato_tipo_etapa where etapa='reserva' and tipo <> 'reserva_parcela';
