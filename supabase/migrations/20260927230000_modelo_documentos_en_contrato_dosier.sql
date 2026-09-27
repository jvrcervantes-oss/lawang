-- destructivo-ok: sustituye el CHECK de tipo (drop+add, añade 'dosier') y la firma de modelo_documento_registra (drop de la de 6 argumentos + create con 7); no borra ni cambia ninguna fila salvo el backfill de en_contrato/orden descrito abajo.
-- Documentos del modelo que van AUTOMÁTICAMENTE en el contrato de obra — casilla por documento (27-sep-2026).
--
-- QUÉ CAMBIA
-- Hasta hoy el contrato de obra adjuntaba UN documento por modelo, elegido por su TIPO: el de tipo 'plano'
-- del techo elegido o, si no había, el plano sin techo. El tipo hacía dos trabajos a la vez (decir qué es el
-- documento y decidir si entra en el contrato), y por eso no se podía adjuntar nada más, ni un plano quedarse
-- fuera. Desde hoy lo decide una CASILLA por documento, `en_contrato`, y el tipo vuelve a decir solo qué es.
--   · Entran TODOS los marcados, en `orden` (desempate: subido_en, id).
--   · Cada uno entra solo si su techo es el del contrato; los de techo NULL («todos los techos») entran siempre.
--   · Tipo nuevo 'dosier' (el PDF comercial del modelo), con su propia sección en la pantalla.
--
-- QUIÉN LO DECIDE: solo administración (es_admin()). La regla vive en las RPC SECURITY DEFINER, que son el
-- único camino de escritura de la tabla (no hay policy de escritura: se quitó en 20260927123000). Se exige
-- admin si la casilla está marcada ANTES o DESPUÉS del cambio, si cambia la casilla, o si cambia el orden:
-- un agente no puede ni meter un documento en el contrato ni retocar (tipo, techo, orden) uno que ya entra.
-- El resto de documentos los sigue subiendo y retipando cualquiera del equipo, como antes.
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
-- genérico y plano de techo: ANTES DE APLICAR, comprobarlo con la consulta de abajo (debe devolver 0 filas).
--   select modelo_id from public.modelo_documentos where tipo = 'plano'
--    group by modelo_id having bool_or(techo_clave is null) and bool_or(techo_clave is not null);
--
-- EL DATO TIENE UN DUEÑO: `modelo_documentos` (en_contrato, orden, techo_clave) manda sobre qué se adjunta.
-- El contrato guarda por cada documento adjuntado una FICHA congelada {id: 'axauto-<doc id>', auto, techo,
-- sha, on} en su jsonb, nunca las páginas: el `sha` es lo que permite avisar de que el documento cambió desde
-- que se guardó el contrato, y deja de poder cambiar al firmarse (lo firmado es el documento emitido).

-- ── columnas ────────────────────────────────────────────────────────────────────────────────────────────
alter table public.modelo_documentos add column if not exists en_contrato boolean not null default false;
alter table public.modelo_documentos add column if not exists orden int not null default 0;
comment on column public.modelo_documentos.en_contrato is
  'Se adjunta automáticamente al contrato de obra del modelo (si su techo_clave es el del contrato o NULL). Solo lo cambia administración (modelo_documento_cambia / _registra).';
comment on column public.modelo_documentos.orden is
  'Orden en el que entran en el contrato los documentos con en_contrato = true. Desempate: subido_en, id. Sin significado para los no marcados.';

-- ── tipo nuevo: 'dosier' ────────────────────────────────────────────────────────────────────────────────
alter table public.modelo_documentos drop constraint if exists modelo_documentos_tipo_ck;
alter table public.modelo_documentos add constraint modelo_documentos_tipo_ck
  check (tipo in ('plano', 'calidades', 'ficha', 'render', 'dosier', 'otro'));

-- ── backfill: lo que entra hoy sigue entrando ─────────────────────────────────────────────────────────────
update public.modelo_documentos d
   set en_contrato = true, orden = x.n
  from (select id, row_number() over (partition by modelo_id order by subido_en, id)::int as n
          from public.modelo_documentos where tipo = 'plano') x
 where d.id = x.id and not d.en_contrato;

-- ── como mucho UN plano marcado por modelo y techo (la garantía de hoy) ───────────────────────────────────
create unique index if not exists modelo_documentos_un_plano_en_contrato
  on public.modelo_documentos (modelo_id, coalesce(techo_clave, ''))
  where en_contrato and tipo = 'plano';

-- ── cambiar un documento: tipo, techo, casilla y orden ──────────────────────────────────────────────────
create or replace function public.modelo_documento_cambia(p_id uuid, p_cambios jsonb) returns uuid
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
  -- Marcar sin orden explícito: entra el último.
  if v_en and not v_d.en_contrato and not (p_cambios ? 'orden') then
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
revoke all on function public.modelo_documento_cambia(uuid, jsonb) from public, anon;
grant execute on function public.modelo_documento_cambia(uuid, jsonb) to authenticated;

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
