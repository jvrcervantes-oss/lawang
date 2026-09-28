-- destructivo-ok: sustituye el CHECK de tipo (drop+add, añade 'dosier'), la firma de modelo_documento_registra (drop de la de 6 argumentos + create con 7) y retira modelo_documento_cambia (su único llamador, la ficha del modelo, pasa a modelo_documentos_guarda) y amplía el CHECK de contrato_eventos.evento (drop+add, lista vigente en producción + 'envio_sin_anexo_confirmado'); no borra ni cambia ninguna fila salvo el backfill de en_contrato/orden descrito abajo.
-- Documentos del modelo que van AUTOMÁTICAMENTE en el contrato de obra — casilla por documento (27-sep-2026).
--
-- QUÉ CAMBIA
-- Hasta hoy el contrato de obra adjuntaba UN documento por modelo, elegido por su TIPO: el de tipo 'plano'
-- del techo elegido o, si no había, el plano sin techo. El tipo hacía dos trabajos a la vez (decir qué es el
-- documento y decidir si entra en el contrato), y por eso no se podía adjuntar nada más, ni un plano quedarse
-- fuera. Desde hoy lo decide una CASILLA por documento, `en_contrato`, y el tipo vuelve a decir solo qué es.
--   · Entran TODOS los marcados, en `orden` (desempate: subido_en, id).
--   · Cada uno entra solo si su techo es el del contrato; los de techo NULL («todos los techos») entran siempre.
--   · Tipo nuevo 'dosier' (el PDF comercial del modelo), con su propia sección en la pantalla. El dosier NUNCA
--     va en el contrato (owner, 28-sep-2026): la casilla no se puede marcar en un dosier, y un documento marcado
--     no se puede retipar a dosier. Lo rechazan _modelo_documento_aplica y modelo_documento_registra.
--   · En el contrato el plano sale como Apéndice A (el único vinculante, Legal 28-sep-2026) y el resto como
--     apéndices informativos B, C, D… por tipo (calidades, ficha, render, otro): eso vive en el navegador
--     (contracts/assets/docs_contrato.js). `orden` solo ordena dentro de un mismo tipo.
--
-- QUIÉN LO DECIDE: solo administración (es_admin()). La regla vive en las RPC SECURITY DEFINER, que son el
-- único camino de escritura de la tabla (no hay policy de escritura: se quitó en 20260927123000). Se exige
-- admin si la casilla está marcada ANTES o DESPUÉS del cambio, si cambia la casilla, o si cambia el orden:
-- un agente no puede ni meter un documento en el contrato ni retocar (tipo, techo, orden) uno que ya entra.
-- El resto de documentos los sigue subiendo y retipando cualquiera del equipo, como antes.
--
-- GUARDAR ES UNA TRANSACCIÓN (revisor de código, 28-sep-2026): la pantalla guarda TODOS los cambios de
-- documentos de un modelo en UNA llamada, `modelo_documentos_guarda`. Antes eran N llamadas sueltas y un
-- fallo a medias podía dejar un techo sin su plano marcado, o el orden de los anexos de un contrato a
-- medias. La comprobación de cada documento vive UNA vez, en `_modelo_documento_aplica` (interna, sin
-- permiso de ejecución para nadie de fuera), y la llaman guarda por cada fila. `modelo_documento_cambia`
-- se retira: su único llamador era esa pantalla (reducir la exposición).
--
-- GARANTÍA QUE SE CONSERVA: hasta hoy el contrato llevaba como mucho UN plano por techo. Con la casilla se
-- podrían marcar dos planos del mismo techo y el contrato llevaría los dos. Lo impide un índice único parcial
-- (no una comprobación dentro de la RPC: el `for update` de la fila propia no bloquea a sus hermanas, el
-- índice sí). Dos planos marcados, uno sin techo y otro con techo, SÍ pueden coexistir: los dos entran en el
-- contrato de ese techo, y la pantalla lo enseña en el resumen por techo antes de guardar.
--
-- BACKFILL: los documentos de tipo 'plano' que existan pasan a en_contrato = true, con orden por subido_en
-- dentro de su modelo. Con la regla vieja entraba el plano del techo o, si no había, el genérico; con la
-- nueva entran el del techo Y el genérico. Solo es el mismo resultado si ningún modelo tiene a la vez plano
-- genérico y plano de techo, ni dos planos del mismo techo: la migración lo COMPRUEBA antes del backfill y
-- aborta entera si no se cumple (revisor de código, 28-sep-2026: un comentario no para nada).
--
-- EL DATO TIENE UN DUEÑO: `modelo_documentos` (en_contrato, orden, techo_clave) manda sobre qué se adjunta.
-- El contrato guarda por cada documento adjuntado una FICHA congelada {id: 'axauto-<doc id>', auto, techo,
-- sha, on} en su jsonb, nunca las páginas: el `sha` es lo que permite avisar de que el documento cambió desde
-- que se guardó el contrato, y deja de poder cambiar al firmarse (lo firmado es el documento emitido).

-- ── columnas ────────────────────────────────────────────────────────────────────────────────────────────
alter table public.modelo_documentos add column if not exists en_contrato boolean not null default false;
alter table public.modelo_documentos add column if not exists orden int not null default 0;
comment on column public.modelo_documentos.en_contrato is
  'Se adjunta automáticamente al contrato de obra del modelo (si su techo_clave es el del contrato o NULL). Solo lo cambia administración (modelo_documentos_guarda / modelo_documento_registra).';
comment on column public.modelo_documentos.orden is
  'Orden en el que entran en el contrato los documentos con en_contrato = true. Desempate: subido_en, id. Sin significado para los no marcados.';

-- ── tipo nuevo: 'dosier' ────────────────────────────────────────────────────────────────────────────────
alter table public.modelo_documentos drop constraint if exists modelo_documentos_tipo_ck;
alter table public.modelo_documentos add constraint modelo_documentos_tipo_ck
  check (tipo in ('plano', 'calidades', 'ficha', 'render', 'dosier', 'otro'));

-- ── backfill: lo que entra hoy sigue entrando ─────────────────────────────────────────────────────────────
-- Condición previa: si no se cumple, el backfill cambiaría lo que adjuntan los contratos. Aborta TODO.
do $$
declare v_mezcla text; v_dobles text;
begin
  select string_agg(modelo_id::text, ', ') into v_mezcla from (
    select modelo_id from public.modelo_documentos where tipo = 'plano'
     group by modelo_id having bool_or(techo_clave is null) and bool_or(techo_clave is not null)) x;
  if v_mezcla is not null then
    raise exception 'Backfill abortado: modelos con plano sin techo Y plano con techo a la vez (%). Con la regla nueva entrarían los dos: decidir cuál se marca antes de aplicar.', v_mezcla
      using errcode = 'P0001';
  end if;
  select string_agg(modelo_id::text || '/' || coalesce(techo_clave, '(todos)'), ', ') into v_dobles from (
    select modelo_id, techo_clave from public.modelo_documentos where tipo = 'plano'
     group by modelo_id, techo_clave having count(*) > 1) x;
  if v_dobles is not null then
    raise exception 'Backfill abortado: dos planos del mismo modelo y techo (%). Con la regla vieja entraba el más reciente; decidir cuál se marca antes de aplicar.', v_dobles
      using errcode = 'P0001';
  end if;
end $$;
update public.modelo_documentos d
   set en_contrato = true, orden = x.n
  from (select id, row_number() over (partition by modelo_id order by subido_en, id)::int as n
          from public.modelo_documentos where tipo = 'plano') x
 where d.id = x.id and not d.en_contrato;

-- ── como mucho UN plano marcado por modelo y techo (la garantía de hoy) ───────────────────────────────────
create unique index if not exists modelo_documentos_un_plano_en_contrato
  on public.modelo_documentos (modelo_id, coalesce(techo_clave, ''))
  where en_contrato and tipo = 'plano';

-- ── aplicar el cambio de UN documento: la comprobación, una sola vez ─────────────────────────────────────
-- Interna: no la llama nadie de fuera (sin grant). La usa modelo_documentos_guarda por cada fila.
create or replace function public._modelo_documento_aplica(p_id uuid, p_cambios jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_d public.modelo_documentos%rowtype; k text; v_tipo text; v_techo text; v_en boolean; v_orden int;
begin
  if not public.es_agente() then raise exception 'Solo el equipo cambia documentos' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then raise exception 'Datos del documento no válidos' using errcode = '22023'; end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if k not in ('tipo', 'techo_clave', 'en_contrato', 'orden') then
      raise exception 'Ese dato del documento no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  select * into v_d from public.modelo_documentos d where d.id = p_id for update;
  if not found then raise exception 'Ese documento ya no existe: recarga la página' using errcode = '22023'; end if;

  v_tipo := case when p_cambios ? 'tipo' then btrim(coalesce(p_cambios->>'tipo', '')) else v_d.tipo end;
  if v_tipo not in ('plano', 'calidades', 'ficha', 'render', 'dosier', 'otro') then raise exception 'Tipo de documento no válido' using errcode = '22023'; end if;
  v_techo := case when p_cambios ? 'techo_clave' then nullif(btrim(coalesce(p_cambios->>'techo_clave', '')), '') else v_d.techo_clave end;
  if p_cambios ? 'en_contrato' then
    if jsonb_typeof(p_cambios->'en_contrato') is distinct from 'boolean' then raise exception 'La casilla del contrato no es válida' using errcode = '22023'; end if;
    v_en := (p_cambios->>'en_contrato')::boolean;
  else v_en := v_d.en_contrato; end if;
  if p_cambios ? 'orden' then
    if jsonb_typeof(p_cambios->'orden') is distinct from 'number' or (p_cambios->>'orden') !~ '^[0-9]{1,6}$' then
      raise exception 'El orden no es válido' using errcode = '22023';
    end if;
    v_orden := (p_cambios->>'orden')::int;
  else v_orden := v_d.orden; end if;

  -- Lo que va en el contrato lo decide administración: la casilla (antes o después), el orden, y el tipo o
  -- el techo de lo que ya entra.
  if (v_d.en_contrato or v_en or v_orden is distinct from v_d.orden) and not public.es_admin() then
    raise exception 'Solo administración decide qué va en el contrato' using errcode = '42501';
  end if;
  -- El plano sigue siendo de administración aunque no esté marcado (25-sep-2026): se conserva la regla.
  if (v_d.tipo = 'plano' or v_tipo = 'plano') and not public.es_admin() then
    raise exception 'El plano solo lo cambia administración' using errcode = '42501';
  end if;
  if v_techo is not null and not exists (select 1 from public.modelo_techos t where t.modelo_id = v_d.modelo_id and t.clave = v_techo) then
    raise exception 'Ese techo no es de este modelo' using errcode = '22023';
  end if;
  -- El dosier es comercial: nunca va en el contrato (owner, 28-sep-2026). Ni marcarlo, ni pasar a dosier uno marcado.
  if v_en and v_tipo = 'dosier' then
    raise exception 'El dosier es comercial: no va en el contrato' using errcode = '22023';
  end if;
  -- Marcar sin orden explícito: entra el último. Se bloquean las filas del modelo para que dos marcados a la
  -- vez no saquen el mismo número.
  if v_en and not v_d.en_contrato and not (p_cambios ? 'orden') then
    perform 1 from public.modelo_documentos d where d.modelo_id = v_d.modelo_id for update;
    select coalesce(max(d.orden), 0) + 1 into v_orden from public.modelo_documentos d
     where d.modelo_id = v_d.modelo_id and d.en_contrato and d.id <> p_id;
  end if;

  begin
    update public.modelo_documentos set tipo = v_tipo, techo_clave = v_techo, en_contrato = v_en, orden = v_orden where id = p_id;
  exception when unique_violation then
    raise exception 'Ya hay otro plano marcado para el contrato con ese techo: desmarca uno de los dos' using errcode = '23505';
  end;
  return p_id;
end $$;
revoke all on function public._modelo_documento_aplica(uuid, jsonb) from public, anon, authenticated, service_role;

-- ── guardar los cambios de documentos de UN modelo, en UNA transacción ──────────────────────────────────
-- p_cambios: [{"id": uuid, "cambios": {tipo?, techo_clave?, en_contrato?, orden?}}, ...] — los valores
-- FINALES de lo que cambia. El ORDEN lo decide el servidor, no la pantalla: el índice «un plano marcado por
-- techo» se comprueba en cada fila, así que primero se desmarca todo lo que deja de estar marcado o se
-- retoca estando marcado (tipo o techo), después se aplican los no marcados, luego los marcados que solo
-- cambian de orden, y al final se marcan (con sus valores finales). Cualquier error deshace TODO.
-- Devuelve cuántos documentos cambió.
create or replace function public.modelo_documentos_guarda(p_modelo uuid, p_cambios jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare e jsonb; v_id uuid; c jsonb; v_d public.modelo_documentos%rowtype; v_en_final boolean; v_retoca boolean;
        v_n int := 0; v_ids uuid[] := '{}'; v_hechos uuid[] := '{}'; v_fase int; v_antes jsonb := '{}'; v_orden_antes jsonb := '{}';
begin
  if not public.es_agente() then raise exception 'Solo el equipo cambia documentos' using errcode = '42501'; end if;
  if jsonb_typeof(p_cambios) is distinct from 'array' then raise exception 'Datos de los documentos no válidos' using errcode = '22023'; end if;
  if jsonb_array_length(p_cambios) > 200 then raise exception 'Demasiados documentos en un guardado' using errcode = '22023'; end if;
  if not exists (select 1 from public.modelos m where m.id = p_modelo) then raise exception 'Ese modelo ya no existe' using errcode = '22023'; end if;
  -- se bloquean las filas del modelo: dos guardados a la vez no se cruzan a mitad
  perform 1 from public.modelo_documentos d where d.modelo_id = p_modelo for update;
  -- validación de la forma, y que cada documento sea de ESTE modelo y aparezca una sola vez
  for e in select * from jsonb_array_elements(p_cambios) loop
    if jsonb_typeof(e) is distinct from 'object' or jsonb_typeof(e->'cambios') is distinct from 'object'
       or coalesce(e->>'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Datos de los documentos no válidos' using errcode = '22023';
    end if;
    -- la casilla, si viene, es booleana: un null o un "false" de texto se leerían como «sin cambio» o al revés
    if (e->'cambios') ? 'en_contrato' and jsonb_typeof(e->'cambios'->'en_contrato') is distinct from 'boolean' then
      raise exception 'La casilla del contrato no es válida' using errcode = '22023';
    end if;
    v_id := (e->>'id')::uuid;
    if v_id = any(v_ids) then raise exception 'Un documento aparece dos veces en el guardado' using errcode = '22023'; end if;
    v_ids := v_ids || v_id;
    if not exists (select 1 from public.modelo_documentos d where d.id = v_id and d.modelo_id = p_modelo) then
      raise exception 'Ese documento no es de este modelo o ya no existe: recarga la página' using errcode = '22023';
    end if;
    -- la casilla de ANTES del guardado: las fases la cambian por el camino y el «final» se decide con esta
    v_antes := v_antes || jsonb_build_object(v_id::text, (select d.en_contrato from public.modelo_documentos d where d.id = v_id));
    v_orden_antes := v_orden_antes || jsonb_build_object(v_id::text, (select d.orden from public.modelo_documentos d where d.id = v_id));
  end loop;
  -- cuatro fases, en este orden. `v_hechos`: los ya aplicados con su valor final.
  for v_fase in 1..4 loop
    for e in select * from jsonb_array_elements(p_cambios) loop
      v_id := (e->>'id')::uuid; c := e->'cambios';
      continue when v_id = any(v_hechos);
      select * into v_d from public.modelo_documentos d where d.id = v_id;   -- como está AHORA (tras las fases anteriores)
      v_en_final := case when c ? 'en_contrato' then (c->>'en_contrato') = 'true' else (v_antes->>v_id::text)::boolean end;
      v_retoca := c ? 'tipo' or c ? 'techo_clave';
      if v_fase = 1 then
        -- 1) desmarcar: lo que deja de ir (ya con su valor final) y lo que sigue marcado pero cambia de tipo o techo
        if v_d.en_contrato and not v_en_final then
          perform public._modelo_documento_aplica(v_id, c || '{"en_contrato": false}'::jsonb);
          v_hechos := v_hechos || v_id; v_n := v_n + 1;
        elsif v_d.en_contrato and v_retoca then
          perform public._modelo_documento_aplica(v_id, '{"en_contrato": false}'::jsonb);   -- se vuelve a marcar en la 4
        end if;
      elsif v_fase = 2 then
        -- 2) los que no estaban marcados y siguen sin estarlo
        if not v_en_final and not v_d.en_contrato then
          perform public._modelo_documento_aplica(v_id, c);
          v_hechos := v_hechos || v_id; v_n := v_n + 1;
        end if;
      elsif v_fase = 3 then
        -- 3) los que siguen marcados sin cambiar de tipo ni de techo: el orden
        if v_en_final and v_d.en_contrato then
          perform public._modelo_documento_aplica(v_id, c);
          v_hechos := v_hechos || v_id; v_n := v_n + 1;
        end if;
      else
        -- 4) marcar: los nuevos y los desmarcados en la fase 1 para retocarlos, con sus valores finales
        if v_en_final and not v_d.en_contrato then
          -- uno que ya estaba marcado (desmarcado en la fase 1 para retocarlo) conserva su orden si no trae otro
          perform public._modelo_documento_aplica(v_id, c || '{"en_contrato": true}'::jsonb
            || case when (v_antes->>v_id::text)::boolean and not (c ? 'orden')
                    then jsonb_build_object('orden', (v_orden_antes->>v_id::text)::int) else '{}'::jsonb end);
          v_hechos := v_hechos || v_id; v_n := v_n + 1;
        end if;
      end if;
    end loop;
  end loop;
  return v_n;
end $$;
revoke all on function public.modelo_documentos_guarda(uuid, jsonb) from public, anon;
grant execute on function public.modelo_documentos_guarda(uuid, jsonb) to authenticated;

-- ── se retira modelo_documento_cambia: su único llamador (la ficha del modelo) usa ahora _guarda ─────────
drop function if exists public.modelo_documento_cambia(uuid, jsonb);

-- ── registrar un documento subido (solo la edge `ficheros`) ──────────────────────────────────────────────
-- Firma nueva con p_en_contrato (7º argumento, por defecto false): la edge vieja, que manda 6 argumentos por
-- nombre, sigue resolviendo esta función. Se borra la de 6 para no dejar dos sobrecargas.
drop function if exists public.modelo_documento_registra(uuid, uuid, text, text, text, text);
create or replace function public.modelo_documento_registra(p_uid uuid, p_modelo uuid, p_path text, p_nombre text, p_tipo text,
  p_techo_clave text default null, p_en_contrato boolean default false) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_tam bigint; v_nombre text; v_techo text := nullif(btrim(coalesce(p_techo_clave, '')), '');
        v_en boolean := coalesce(p_en_contrato, false); v_orden int := 0;
begin
  perform public._actua_como(p_uid);
  if not public.es_agente() then raise exception 'Solo el equipo sube documentos' using errcode = '42501'; end if;
  if p_tipo is null or p_tipo not in ('plano', 'calidades', 'ficha', 'render', 'dosier', 'otro') then raise exception 'Tipo de documento no válido' using errcode = '22023'; end if;
  if p_tipo = 'plano' and not public.es_admin() then raise exception 'El plano solo lo sube administración' using errcode = '42501'; end if;
  if v_en and not public.es_admin() then raise exception 'Solo administración decide qué va en el contrato' using errcode = '42501'; end if;
  if v_en and p_tipo = 'dosier' then raise exception 'El dosier es comercial: no va en el contrato' using errcode = '22023'; end if;
  if not exists (select 1 from public.modelos m where m.id = p_modelo) then raise exception 'Ese modelo ya no existe' using errcode = '22023'; end if;
  if p_path is null or p_path !~ ('^' || p_modelo::text || '/[0-9a-f-]{36}\.(pdf|jpg|jpeg|png|webp)$') then
    raise exception 'Ruta de documento no válida' using errcode = '22023';
  end if;
  if v_techo is not null and not exists (select 1 from public.modelo_techos t where t.modelo_id = p_modelo and t.clave = v_techo) then
    raise exception 'Ese techo no es de este modelo' using errcode = '22023';
  end if;
  select (o.metadata->>'size')::bigint into v_tam from storage.objects o where o.bucket_id = 'modelos' and o.name = p_path;
  if not found then raise exception 'El fichero no ha llegado al archivo: vuelve a subirlo' using errcode = '22023'; end if;
  -- el nombre real va en la COLUMNA (la ruta es un uuid): sin caracteres de control, con tope
  v_nombre := left(btrim(regexp_replace(coalesce(p_nombre, ''), '[[:cntrl:]]', '', 'g')), 200);
  if v_nombre = '' then v_nombre := 'Documento'; end if;
  -- marcado al subir: entra el último
  if v_en then
    perform 1 from public.modelo_documentos d where d.modelo_id = p_modelo for update;
    select coalesce(max(d.orden), 0) + 1 into v_orden from public.modelo_documentos d where d.modelo_id = p_modelo and d.en_contrato;
  end if;
  begin
    insert into public.modelo_documentos (modelo_id, nombre, path, tipo, tamano_bytes, subido_por, techo_clave, en_contrato, orden)
    values (p_modelo, v_nombre, p_path, p_tipo, v_tam, p_uid, v_techo, v_en, v_orden)
    returning id into v_id;
  exception when unique_violation then
    if exists (select 1 from public.modelo_documentos d where d.path = p_path) then
      raise exception 'Ese fichero ya está registrado' using errcode = '23505';
    end if;
    raise exception 'Ya hay otro plano marcado para el contrato con ese techo: súbelo sin marcar y cambia la casilla en Editar' using errcode = '23505';
  end;
  return v_id;
end $$;
revoke all on function public.modelo_documento_registra(uuid, uuid, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.modelo_documento_registra(uuid, uuid, text, text, text, text, boolean) to service_role;

-- ── constancia de «Enviar igualmente» sin un anexo del modelo (owner, 28-sep-2026) ──────────────────────
-- Enviar a firma sin los documentos marcados del modelo (porque no hay ninguno, o porque uno marcado no se ha
-- podido adjuntar) se permite con una confirmación, pero queda en el historial del contrato: quién, cuándo y
-- qué faltaba. Lo escribe el SERVIDOR: la edge `ficheros-contrato` (acción envia_firma) llama a esta función
-- con service_role ANTES de crear el enlace, con el actor sacado de la sesión; si no se puede apuntar, no se
-- envía. El «qué faltaba» lo declara la pantalla (el servidor no reconstruye el documento): se guarda como
-- declaración, acotado y sin HTML, junto a quién la hizo.
-- Lista del CHECK copiada de la VIGENTE en producción el 28-sep-2026 (incluye 'anexos_al_archivo', LAW-78).
alter table public.contrato_eventos drop constraint if exists contrato_eventos_evento_check;
alter table public.contrato_eventos add constraint contrato_eventos_evento_check check (evento = any (array[
  'creado', 'editado', 'tipo_cambiado', 'enviado_a_firma', 'firma_abierta', 'firma_recogida', 'firma_anulada',
  'firmado_del_todo', 'desbloqueado', 'traspaso', 'editado_estando_firmado', 'desbloqueado_estando_firmado',
  'factura_sin_bloquear', 'cobro_a_factura_huerfana', 'cobro_a_otro_comprador', 'comprador_sin_ficha',
  'factura_borrada', 'contrato_borrado', 'reserva_liberada', 'reserva_prorrogada', 'reserva_liberacion_deshecha',
  'pdf_descargado', 'factura_reactivada', 'anexos_al_archivo', 'envio_sin_anexo_confirmado']));

create or replace function public.contrato_envio_sin_anexo(p_contrato uuid, p_actor text, p_detalle jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_motivo text; v_faltan jsonb := '[]'; x jsonb;
begin
  if not exists (select 1 from public.contratos c where c.id = p_contrato) then
    raise exception 'Ese contrato no existe' using errcode = '22023';
  end if;
  if jsonb_typeof(p_detalle) is distinct from 'object' then raise exception 'Detalle no válido' using errcode = '22023'; end if;
  v_motivo := p_detalle->>'motivo';
  -- ninguno: no salió ningún documento del modelo; sin_apendice_a: salieron informativos pero no el plano que el contrato
  -- cita (el único apéndice vinculante, Legal 28-sep); fallo: uno marcado no se pudo adjuntar
  if v_motivo is null or v_motivo not in ('ninguno', 'sin_apendice_a', 'fallo') then raise exception 'Motivo no válido' using errcode = '22023'; end if;
  if p_detalle ? 'faltan' then
    if jsonb_typeof(p_detalle->'faltan') is distinct from 'array' or jsonb_array_length(p_detalle->'faltan') > 20 then
      raise exception 'Lista de lo que falta no válida' using errcode = '22023';
    end if;
    for x in select * from jsonb_array_elements(p_detalle->'faltan') loop
      if jsonb_typeof(x) is distinct from 'string' then raise exception 'Lista de lo que falta no válida' using errcode = '22023'; end if;
      v_faltan := v_faltan || to_jsonb(left(regexp_replace(x #>> '{}', '[[:cntrl:]<>]', '', 'g'), 200));
    end loop;
  end if;
  insert into public.contrato_eventos (contrato_id, evento, detalle, quien)
  values (p_contrato, 'envio_sin_anexo_confirmado',
          jsonb_build_object('motivo', v_motivo, 'faltan', v_faltan, 'declarado_por', 'pantalla'),
          left(nullif(btrim(coalesce(p_actor, '')), ''), 200))
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.contrato_envio_sin_anexo(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.contrato_envio_sin_anexo(uuid, text, jsonb) to service_role;
