-- ════════════════════════════════════════════════════════════════════════════
-- HISTORIAL DE EVENTOS DEL CONTRATO — 18-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Segunda mitad del registro de envíos (registro_correos.sql): el owner pidió
-- ver también «los estados y cambios en los estados de los contratos». La misma
-- pregunta del CR00025 («¿qué le ha pasado a este contrato?») tiene más
-- respuestas que los correos: quién lo creó, quién lo editó y qué campos tocó,
-- cuándo se generó cada enlace de firma, cuándo se recogió o anuló cada firma,
-- cuándo quedó cerrado.
--
-- POR QUÉ TRIGGERS Y NO LA APP: en `contratos` escriben varios caminos (la app,
-- la Edge firma-submit al cerrar, un admin por SQL) — apuntar el evento en cada
-- uno sería la lista a mano en dos sitios que ES el bug. El trigger lo ve todo.
-- Dirección única, como el calendario de vencimientos.
--
-- REGLA DE ORO, la misma que en correos_enviados: el historial JAMÁS puede
-- vetar una escritura real. El cuerpo entero va en BEGIN/EXCEPTION → warning:
-- si el log falla, el guardado o la firma siguen adelante.
--
-- QUIÉN: el email del JWT si la escritura vino de un agente con sesión
-- (PostgREST lo expone en request.jwt.claims); null = automatismo (edges con
-- service_role, SQL a mano) — la UI lo pinta como «Sistema».
--
-- SEMILLA: solo eventos con fecha REAL ya guardada (contratos.created_at,
-- contrato_firmas.creado_en / firmado_en). Nada de fechas inventadas: una firma
-- anulada no guarda cuándo se anuló y un cierre manual no guarda cuándo se
-- bloqueó, así que esos NO se siembran. Todo lo sembrado lleva
-- detalle {"semilla": true}.

create table if not exists public.contrato_eventos (
  id          uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  evento      text not null check (evento in
                ('creado','editado','tipo_cambiado','enviado_a_firma','firma_abierta',
                 'firma_recogida','firma_anulada','firmado_del_todo','desbloqueado','traspaso')),
  detalle     jsonb,
  quien       text,
  creado_en   timestamptz not null default now()
);

create index if not exists contrato_eventos_contrato_idx
  on public.contrato_eventos (contrato_id, creado_en desc);

alter table public.contrato_eventos enable row level security;

-- Solo lectura para agentes. SIN policy de escritura a propósito: aquí solo
-- escriben los triggers (corren como owner y saltan la RLS); un insert desde
-- el navegador debe rebotar — un historial que se puede fabricar no es historial.
drop policy if exists "agentes leen eventos" on public.contrato_eventos;
create policy "agentes leen eventos" on public.contrato_eventos
  for select to authenticated using (public.es_agente());

-- el email del agente con sesión, o null si escribe un automatismo
create or replace function public._quien_actua()
returns text language sql stable
set search_path to ''
as $$
  select nullif(coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''), '')
$$;
revoke execute on function public._quien_actua() from public, anon, authenticated;

-- ── contratos: creado / editado / tipo / cierre / reapertura / traspaso ─────
create or replace function public.contrato_evento_log()
returns trigger language plpgsql security definer
set search_path to ''
as $$
declare
  v_quien  text;
  v_campos text[];
  v_hitos  boolean;
  v_padre  text;
begin
  v_quien := public._quien_actua();

  if tg_op = 'INSERT' then
    insert into public.contrato_eventos (contrato_id, evento, quien)
    values (new.id, 'creado', coalesce(v_quien, new.creado_por));
    return new;
  end if;

  -- Cada cambio es su propio evento: un update puede producir varios.
  if old.bloqueado is distinct from new.bloqueado then
    if coalesce(new.bloqueado, false) then
      insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
      values (new.id, 'firmado_del_todo',
              jsonb_build_object('via',
                case when new.pdf_firmado_path like '%\_manual.pdf' escape '\'
                     then 'pdf subido a mano' else 'firma electronica' end),
              v_quien);
    else
      insert into public.contrato_eventos (contrato_id, evento, quien)
      values (new.id, 'desbloqueado', v_quien);
    end if;
  end if;

  if old.tipo is distinct from new.tipo then
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.id, 'tipo_cambiado',
            jsonb_build_object('de', old.tipo, 'a', new.tipo), v_quien);
  end if;

  -- el traspaso Carta→Bloqueo cuelga la Carta de su padre (sincroniza_unidad_contrato)
  if old.contrato_padre_id is null and new.contrato_padre_id is not null then
    select c.numero into v_padre from public.contratos c where c.id = new.contrato_padre_id;
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.id, 'traspaso', jsonb_build_object('colgado_de', v_padre), v_quien);
  end if;

  if old.datos is distinct from new.datos then
    -- qué campos del formulario cambiaron (tope 15: con más, la lista dice menos
    -- que el número) y si se tocó el calendario de hitos
    select array_agg(key order by key) into v_campos from (
      select key, a.value as va, b.value as vb
        from jsonb_each(coalesce(old.datos->'fields', '{}'::jsonb)) a
        full join jsonb_each(coalesce(new.datos->'fields', '{}'::jsonb)) b using (key)
    ) s where va is distinct from vb;
    v_hitos := (old.datos->'hitos') is distinct from (new.datos->'hitos');
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.id, 'editado', jsonb_strip_nulls(jsonb_build_object(
              'campos',       to_jsonb(v_campos[1:15]),
              'campos_total', case when coalesce(array_length(v_campos,1),0) > 15
                                   then array_length(v_campos,1) end,
              'hitos',        case when v_hitos then true end)), v_quien);
  end if;

  return new;
exception when others then
  -- el historial nunca veta una escritura real
  raise warning 'contrato_eventos (contratos %): %', tg_op, sqlerrm;
  return new;
end $$;
revoke execute on function public.contrato_evento_log() from public, anon, authenticated;

drop trigger if exists trg_contrato_evento_log on public.contratos;
create trigger trg_contrato_evento_log
  after insert or update on public.contratos
  for each row execute function public.contrato_evento_log();

-- ── contrato_firmas: enlace generado / abierto / firmado / anulado ──────────
create or replace function public.firma_evento_log()
returns trigger language plpgsql security definer
set search_path to ''
as $$
declare
  v_quien text;
  v_det   jsonb;
begin
  v_quien := public._quien_actua();
  v_det := jsonb_build_object('rol', new.firmante_rol, 'email', new.firmante_email);

  if tg_op = 'INSERT' then
    insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
    values (new.contrato_id, 'enviado_a_firma', v_det, v_quien);
  elsif old.estado is distinct from new.estado then
    if new.estado = 'en_proceso' then
      -- el firmante abrió el enlace (claim de firma-submit); no hay agente detrás
      insert into public.contrato_eventos (contrato_id, evento, detalle)
      values (new.contrato_id, 'firma_abierta', v_det);
    elsif new.estado = 'firmado' then
      insert into public.contrato_eventos (contrato_id, evento, detalle)
      values (new.contrato_id, 'firma_recogida', v_det);
    elsif new.estado = 'anulado' then
      insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
      values (new.contrato_id, 'firma_anulada', v_det, v_quien);
    end if;
    -- en_proceso→pendiente (claim caducado que se reabre): ruido, no se apunta
  end if;

  return new;
exception when others then
  raise warning 'contrato_eventos (firmas %): %', tg_op, sqlerrm;
  return new;
end $$;
revoke execute on function public.firma_evento_log() from public, anon, authenticated;

drop trigger if exists trg_firma_evento_log on public.contrato_firmas;
create trigger trg_firma_evento_log
  after insert or update on public.contrato_firmas
  for each row execute function public.firma_evento_log();

-- ── Semilla: el pasado con fecha real, marcado como semilla ─────────────────
-- Idempotente: cada bloque comprueba que su evento no exista ya.
insert into public.contrato_eventos (contrato_id, evento, detalle, quien, creado_en)
select c.id, 'creado', '{"semilla":true}'::jsonb, c.creado_por, c.created_at
  from public.contratos c
 where not exists (select 1 from public.contrato_eventos e
                    where e.contrato_id = c.id and e.evento = 'creado');

insert into public.contrato_eventos (contrato_id, evento, detalle, creado_en)
select cf.contrato_id, 'enviado_a_firma',
       jsonb_build_object('semilla', true, 'rol', cf.firmante_rol, 'email', cf.firmante_email),
       cf.creado_en
  from public.contrato_firmas cf
 where not exists (select 1 from public.contrato_eventos e
                    where e.contrato_id = cf.contrato_id
                      and e.evento = 'enviado_a_firma' and e.creado_en = cf.creado_en);

insert into public.contrato_eventos (contrato_id, evento, detalle, creado_en)
select cf.contrato_id, 'firma_recogida',
       jsonb_build_object('semilla', true, 'rol', cf.firmante_rol, 'email', cf.firmante_email),
       cf.firmado_en
  from public.contrato_firmas cf
 where cf.estado = 'firmado' and cf.firmado_en is not null
   and not exists (select 1 from public.contrato_eventos e
                    where e.contrato_id = cf.contrato_id
                      and e.evento = 'firma_recogida' and e.creado_en = cf.firmado_en);

-- cierre: solo donde hay una fecha real de firma electrónica (la última firma
-- recogida); un bloqueo por subida manual no guardó cuándo ocurrió → no se siembra
insert into public.contrato_eventos (contrato_id, evento, detalle, creado_en)
select c.id, 'firmado_del_todo',
       jsonb_build_object('semilla', true, 'via', 'firma electronica'),
       x.ultima
  from public.contratos c
  join lateral (select max(cf.firmado_en) as ultima from public.contrato_firmas cf
                 where cf.contrato_id = c.id and cf.estado = 'firmado') x on x.ultima is not null
 where coalesce(c.bloqueado, false)
   and not exists (select 1 from public.contrato_eventos e
                    where e.contrato_id = c.id and e.evento = 'firmado_del_todo');

-- ── Comprobación (la del catálogo, nunca el «ya lo mandé») ──────────────────
--   select tgname, tgenabled from pg_trigger
--    where tgrelid in ('public.contratos'::regclass, 'public.contrato_firmas'::regclass)
--      and tgname like 'trg_%evento%';                     → 2 filas, 'O'
--   select relrowsecurity from pg_class where relname='contrato_eventos';  → t
--   select polcmd from pg_policy where polrelid='public.contrato_eventos'::regclass; → solo r
-- Y la de comportamiento: DO con rollback — crear borrador → 'creado';
-- editarlo → 'editado' con la lista de campos; insertar firma → 'enviado_a_firma';
-- estado→'firmado' → 'firma_recogida'; bloquear → 'firmado_del_todo'.
