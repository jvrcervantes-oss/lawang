-- LAW-338 L5 (16-oct-2026, sesión lecturas-servidor-2): compradores, documentos KYC, soporte, portal, campana y registro de
-- correos se leen por el SERVIDOR. Encargo: encargos/20260927_lawang_law338_lecturas_bloques.md (L5) · pareja del maestro:
-- erp/migraciones/20261016090000_b10_l5_compradores_datos.sql (mismos nombres, argumentos y forma del jsonb; FORMAS_DATOS de
-- erp/modulos.py). Revisión previa #396 (Seguridad + Backend).
-- Aditiva: create function + dueño + grants, y dos INVOKER que pasan a DEFINER-lw_lector. NINGÚN revoke de tabla: el cierre va
-- en supabase/por_aplicar/law338_l5_revoke.sql hasta que producción sirva el front que llama a estas RPC.
--
-- Reglas de la forma (LAW-338 §diseño, revisión previa #128):
--  · DEFINER con dueño lw_lector: dentro, la RLS se evalúa como lw_lector con las claims del usuario real, así que cada RPC
--    devuelve las MISMAS filas que la lectura directa de hoy. La regla vive en la policy, no aquí. (Las policies de
--    notificaciones, correos_enviados, hilo_soporte y mensajes_comprador llaman auth.email(): lw_lector no tiene USAGE en
--    `auth` pero sí EXECUTE en auth.email()/auth.uid(), medido 16-oct; una expresión guardada no vuelve a buscar el nombre.)
--  · search_path '', stable, sin auth.* en el cuerpo (public.uid_sesion()), 1.ª línea: sin sesión → 42501.
--  · Columnas explícitas = las que pide hoy cada pantalla, ni una más. Tope en servidor + `recortado` (lista de las listas
--    que no cupieron). Orden determinista (fecha desc, id desc).
--
-- LLAMADORES CON NOMBRE (§1.ter, seguridad_2026.md):
--  clientes_lista_datos ← v4 Compradores (qué fichas ves enteras), editores.js (elegir cliente de un documento), emitir.js
--     (firmantes), edges ficheros-kyc (¿ves al comprador?) y portal-invitar (¿ves todas esas fichas?), con el JWT del usuario.
--  comprador_ficha_datos ← v4 Compradores (ficha, documentos, portal, resumen de soporte, vista previa del portal) y editores.js
--     (datos del cliente para un documento: nombre, documento, email, domicilio).
--  operacion_compradores_datos ← cajón de la operación (datos.js: clientes del contrato + su documentación).
--  operaciones_compradores_datos ← contracts/assets/operaciones-cuentas.js (vínculos con su ficha + documentación).
--  soporte_datos ← v4 Soporte. notificaciones_datos ← campana (contracts/assets/avisos.js) y auditoría de Usuarios.
--  correos_registro_datos ← registro de envíos (v4 Compradores, editores.js, contracts/app.html, intranet/facturas ?vista=).
--  documentos_desactualizados_datos ← «Ficha ≠» de los listados, de la ficha de cliente y del editor (datos.js, editores.js,
--     contracts/assets/ficha_divergencia.js). Se mueve en L5 porque la vista es security_invoker y lee clients: con el revoke
--     de clients la lectura directa de authenticated se rompería. La vista se cierra en L6.
--  Ninguna con service_role, cron ni PHP: fuera public/anon/service_role, grant solo a authenticated.
--  clientes_busca (edge asistente-peticiones, JWT del usuario) y contratos_busca (asistente-contrato.js): eran INVOKER y nombran
--     clients; pasan a DEFINER-lw_lector para que el revoke no las rompa. clientes_busca gana los modos correo y teléfono que la
--     edge hacía con `.from('clients')` (misma regla: la RLS decide). Quedan solo para authenticated (sin service_role).
-- EL DATO TIENE UN DUEÑO: no cambia nada; estas funciones solo leen lo de hoy.
-- VUELTA ATRÁS: supabase/reversion_law338_l5/REVERSION.sql (drop de las 8 nuevas; clientes_busca, contratos_busca y bot_pendientes
--   vuelven a INVOKER-postgres con su cuerpo de antes).

-- ── 1. Clientes que la sesión ve enteros (id y nombre) ─────────────────────────────────────────────────────────────────
create or replace function public.clientes_lista_datos(p_ids uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'clientes_lista_datos: sin sesión' using errcode = '42501';
  end if;
  if p_ids is not null and cardinality(p_ids) > 5000 then
    raise exception 'clientes_lista_datos: demasiados ids' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'full_name', x.full_name) order by x.rn) filter (where x.rn <= 5000),
                  '[]'::jsonb), count(*)::int
    into v, n
    from (select c.id, c.full_name, row_number() over (order by c.full_name, c.id) as rn
            from public.clients c
           where p_ids is null or c.id = any(p_ids)
           order by c.full_name, c.id limit 5001) x;
  return jsonb_build_object('clientes', v,
                            'recortado', case when n > 5000 then '["clientes"]'::jsonb else '[]'::jsonb end);
end $$;

-- ── 2. La ficha de UN comprador, por partes (cada pantalla pide solo lo suyo) ───────────────────────────────────────────
-- ve = la sesión ve la ficha entera (la regla de clients). Si NO la ve, devuelve solo {ve:false, recortado:[]}, ninguna parte
-- (Seguridad #396.2: la policy de hilo_soporte no exige ver la ficha, y ninguna pantalla pide el soporte de una ficha que no ves).
-- Partes, cada una con su lista blanca de columnas (Seguridad #396.3): ficha = lo que pinta la ficha de Compradores; documento =
-- lo que copia un documento al elegir cliente (con el domicilio, que solo piden los editores); documentos; portal; soporte.
create or replace function public.comprador_ficha_datos(p_client uuid, p_partes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare r jsonb; v jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'comprador_ficha_datos: sin sesión' using errcode = '42501';
  end if;
  if p_client is null or p_partes is null or cardinality(p_partes) = 0
     or not (p_partes <@ array['ficha', 'documento', 'documentos', 'portal', 'soporte']) then
    raise exception 'comprador_ficha_datos: argumentos' using errcode = '22023';
  end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then
    return jsonb_build_object('ve', false, 'recortado', '[]'::jsonb);
  end if;
  r := jsonb_build_object('ve', true, 'recortado', '[]'::jsonb);
  if 'ficha' = any(p_partes) then
    r := r || jsonb_build_object('ficha', (
      select jsonb_build_object('id', c.id, 'numero_cliente', c.numero_cliente, 'full_name', c.full_name, 'email', c.email,
                                'phone', c.phone, 'nationality', c.nationality, 'passport_number', c.passport_number, 'tipo', c.tipo,
                                'forma_juridica', c.forma_juridica, 'registro_num', c.registro_num, 'rep_nombre', c.rep_nombre,
                                'rep_cargo', c.rep_cargo, 'kyc_status', c.kyc_status, 'idioma_comunicacion', c.idioma_comunicacion,
                                'propietario', c.propietario, 'created_at', c.created_at)
        from public.clients c where c.id = p_client));
  end if;
  if 'documento' = any(p_partes) then
    r := r || jsonb_build_object('documento', (
      select jsonb_build_object('id', c.id, 'full_name', c.full_name, 'email', c.email, 'passport_number', c.passport_number,
                                'registro_num', c.registro_num, 'address', c.address)
        from public.clients c where c.id = p_client));
  end if;
  if 'documentos' = any(p_partes) then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'doc_type', x.doc_type, 'storage_path', x.storage_path,
                                                 'uploaded_at', x.uploaded_at, 'caduca_el', x.caduca_el) order by x.rn)
                    filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
      into v, n
      from (select d.id, d.doc_type, d.storage_path, d.uploaded_at, d.caduca_el,
                   row_number() over (order by d.uploaded_at desc nulls last, d.id desc) as rn
              from public.documents d where d.client_id = p_client
             order by d.uploaded_at desc nulls last, d.id desc limit 501) x;
    r := r || jsonb_build_object('documentos', v);
    if n > 500 then r := jsonb_set(r, '{recortado}', (r->'recortado') || '["documentos"]'::jsonb); end if;
  end if;
  if 'portal' = any(p_partes) then
    r := r || jsonb_build_object('portal', (
      select coalesce(jsonb_agg(jsonb_build_object('email', p.email, 'activo', p.activo, 'ultimo_acceso', p.ultimo_acceso,
                                                   'accesos', p.accesos) order by p.creado_en, p.id), '[]'::jsonb)
        from public.portal_accesos p where p.client_id = p_client));
  end if;
  if 'soporte' = any(p_partes) then
    r := r || jsonb_build_object('soporte', jsonb_build_object(
      'ultimo', (select jsonb_build_object('de', m.de, 'texto', m.texto, 'creado_en', m.creado_en)
                   from public.mensajes_comprador m where m.client_id = p_client
                  order by m.creado_en desc, m.id desc limit 1),
      'hilos', (select coalesce(jsonb_agg(jsonb_build_object('estado', h.estado, 'actualizado_en', h.actualizado_en)
                                          order by h.actualizado_en desc, h.id desc), '[]'::jsonb)
                  from public.hilo_soporte h where h.client_id = p_client)));
  end if;
  return r;
end $$;

-- ── 3. Cajón de la operación: los clientes del contrato y su documentación ──────────────────────────────────────────────
-- p_clientes = los client_id de contrato_compradores de ese contrato (los lee la pantalla); la RLS de clients/documents decide.
create or replace function public.operacion_compradores_datos(p_contrato uuid, p_clientes uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_cl jsonb; v_do jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'operacion_compradores_datos: sin sesión' using errcode = '42501';
  end if;
  if p_contrato is null or cardinality(coalesce(p_clientes, '{}')) > 200 then
    raise exception 'operacion_compradores_datos: argumentos' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'full_name', c.full_name, 'kyc_status', c.kyc_status)
                            order by c.full_name, c.id), '[]'::jsonb)
    into v_cl
    from public.clients c where c.id = any(coalesce(p_clientes, '{}'));
  select coalesce(jsonb_agg(jsonb_build_object('doc_type', x.doc_type, 'uploaded_at', x.uploaded_at, 'caduca_el', x.caduca_el,
                                               'client_id', x.client_id) order by x.rn) filter (where x.rn <= 1000), '[]'::jsonb),
         count(*)::int
    into v_do, n
    from (select d.doc_type, d.uploaded_at, d.caduca_el, d.client_id,
                 row_number() over (order by d.uploaded_at desc nulls last, d.id desc) as rn
            from public.documents d
           where d.contrato_id = p_contrato or d.client_id = any(coalesce(p_clientes, '{}'))
           order by d.uploaded_at desc nulls last, d.id desc limit 1001) x;
  return jsonb_build_object('clientes', v_cl, 'documentos', v_do,
                            'recortado', case when n > 1000 then '["documentos"]'::jsonb else '[]'::jsonb end);
end $$;

-- ── 4. Operaciones (operaciones-cuentas.js): vínculos contrato→comprador con su ficha, y la documentación ───────────────
create or replace function public.operaciones_compradores_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_vi jsonb; n_vi int; v_do jsonb; n_do int;
begin
  if public.uid_sesion() is null then
    raise exception 'operaciones_compradores_datos: sin sesión' using errcode = '42501';
  end if;
  -- `cliente` = null si la sesión ve el vínculo pero no la ficha (lo mismo que daba el embebido de PostgREST)
  select coalesce(jsonb_agg(jsonb_build_object('contrato_id', x.contrato_id, 'rol', x.rol, 'cliente', x.cliente) order by x.rn)
                  filter (where x.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_vi, n_vi
    from (select cc.contrato_id, cc.rol,
                 (select jsonb_build_object('id', c.id, 'full_name', c.full_name, 'email', c.email, 'phone', c.phone,
                                            'kyc_status', c.kyc_status)
                    from public.clients c where c.id = cc.client_id) as cliente,   -- sin pasaporte: la pantalla no lo pinta (#396.3)
                 row_number() over (order by cc.contrato_id, cc.client_id) as rn
            from public.contrato_compradores cc
           order by cc.contrato_id, cc.client_id limit 5001) x;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'client_id', x.client_id, 'contrato_id', x.contrato_id,
                                               'doc_type', x.doc_type, 'storage_path', x.storage_path, 'status', x.status,
                                               'uploaded_at', x.uploaded_at, 'caduca_el', x.caduca_el) order by x.rn)
                  filter (where x.rn <= 5000), '[]'::jsonb), count(*)::int
    into v_do, n_do
    from (select d.id, d.client_id, d.contrato_id, d.doc_type, d.storage_path, d.status, d.uploaded_at, d.caduca_el,
                 row_number() over (order by d.uploaded_at desc nulls last, d.id desc) as rn
            from public.documents d
           order by d.uploaded_at desc nulls last, d.id desc limit 5001) x;
  return jsonb_build_object('vinculos', v_vi, 'documentos', v_do,
                            'recortado', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (
                                            select 'vinculos' k where n_vi > 5000
                                            union all select 'documentos' where n_do > 5000) r));
end $$;

-- ── 5. Soporte: hilos (con su referencia a factura o contrato), las fichas que nombran y los últimos 600 mensajes ───────
create or replace function public.soporte_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_hi jsonb; n_hi int; v_ms jsonb; v_cl jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'soporte_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'client_id', x.client_id, 'categoria', x.categoria, 'estado', x.estado,
                                               'actualizado_en', x.actualizado_en, 'factura_id', x.factura_id,
                                               'contrato_id', x.contrato_id) order by x.rn) filter (where x.rn <= 5000), '[]'::jsonb),
         count(*)::int
    into v_hi, n_hi
    from (select h.id, h.client_id, h.categoria, h.estado, h.actualizado_en, h.factura_id, h.contrato_id,
                 row_number() over (order by h.actualizado_en desc, h.id desc) as rn
            from public.hilo_soporte h order by h.actualizado_en desc, h.id desc limit 5001) x;
  select coalesce(jsonb_agg(jsonb_build_object('hilo_id', m.hilo_id, 'client_id', m.client_id, 'de', m.de, 'autor', m.autor,
                                               'texto', m.texto, 'creado_en', m.creado_en) order by m.creado_en desc, m.id desc), '[]'::jsonb)
    into v_ms
    from (select mc.id, mc.hilo_id, mc.client_id, mc.de, mc.autor, mc.texto, mc.creado_en
            from public.mensajes_comprador mc order by mc.creado_en desc, mc.id desc limit 600) m;
  -- solo las fichas que nombran los hilos o los mensajes (la pantalla las usa para el nombre y el contacto)
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'full_name', c.full_name, 'email', c.email, 'phone', c.phone,
                                               'tipo', c.tipo) order by c.full_name, c.id), '[]'::jsonb)
    into v_cl
    from public.clients c
   where c.id in (select h.client_id from public.hilo_soporte h
                  union select mc.client_id from public.mensajes_comprador mc);
  return jsonb_build_object('hilos', v_hi, 'mensajes', v_ms, 'clientes', v_cl,
                            'recortado', case when n_hi > 5000 then '["hilos"]'::jsonb else '[]'::jsonb end);
end $$;

-- ── 6. Campana y auditoría: las notificaciones que la sesión ve, las más recientes primero ──────────────────────────────
create or replace function public.notificaciones_datos(p_limite int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; n int; lim int := least(greatest(coalesce(p_limite, 30), 1), 400);
begin
  if public.uid_sesion() is null then
    raise exception 'notificaciones_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'titulo', x.titulo, 'detalle', x.detalle, 'enlace', x.enlace,
                                               'creado_en', x.creado_en, 'destinatario', x.destinatario) order by x.rn)
                  filter (where x.rn <= lim), '[]'::jsonb), count(*)::int
    into v, n
    from (select t.tipo, t.titulo, t.detalle, t.enlace, t.creado_en, t.destinatario,
                 row_number() over (order by t.creado_en desc, t.id desc) as rn
            from public.notificaciones t order by t.creado_en desc, t.id desc limit lim + 1) x;
  return jsonb_build_object('notificaciones', v, 'hay_mas', n > lim);
end $$;

-- ── 7. Registro de envíos: los correos de unos contratos o de una factura (exactamente uno de los dos) ──────────────────
create or replace function public.correos_registro_datos(p_contratos uuid[], p_factura uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'correos_registro_datos: sin sesión' using errcode = '42501';
  end if;
  if (p_factura is null) = (cardinality(coalesce(p_contratos, '{}')) = 0) or cardinality(coalesce(p_contratos, '{}')) > 500 then
    raise exception 'correos_registro_datos: pide por contratos o por factura' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('para', x.para, 'asunto', x.asunto, 'via', x.via, 'enviado_por', x.enviado_por,
                                               'enviado_en', x.enviado_en, 'contrato_id', x.contrato_id, 'factura_id', x.factura_id)
                            order by x.rn) filter (where x.rn <= 200), '[]'::jsonb), count(*)::int
    into v, n
    from (select e.para, e.asunto, e.via, e.enviado_por, e.enviado_en, e.contrato_id, e.factura_id,
                 row_number() over (order by e.enviado_en desc, e.id desc) as rn
            from public.correos_enviados e
           where (p_factura is not null and e.factura_id = p_factura)
              or (p_factura is null and e.contrato_id = any(p_contratos))
           order by e.enviado_en desc, e.id desc limit 201) x;
  return jsonb_build_object('correos', v, 'recortado', case when n > 200 then '["correos"]'::jsonb else '[]'::jsonb end);
end $$;

-- ── 8. «Ficha ≠»: documentos que dicen otra cosa que su ficha (vista documentos_desactualizados), por UN filtro ──────────
create or replace function public.documentos_desactualizados_datos(p_tipo text, p_client uuid, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; n int;
begin
  if public.uid_sesion() is null then
    raise exception 'documentos_desactualizados_datos: sin sesión' using errcode = '42501';
  end if;
  if (p_tipo is not null)::int + (p_client is not null)::int + (p_id is not null)::int <> 1 then
    raise exception 'documentos_desactualizados_datos: un filtro y solo uno' using errcode = '22023';
  end if;
  -- Tres ramas con una IGUALDAD cada una (Backend #396.4): la vista entera tarda ~12,7 s y authenticated tiene statement_timeout
  -- de 8 s; un `(p_x is null or d.x = p_x)` dentro de plpgsql puede pasar a plan genérico tras 5 llamadas y dejar de empujar el
  -- filtro dentro de la vista (cada ficha recalcularía todos los contratos). Solo las filas que DIFIEREN: es lo único que pintan
  -- los cuatro lectores (los que no difieren se descartaban en el navegador).
  if p_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('tipo', d.tipo, 'id', d.id, 'numero', d.numero, 'congelado', d.congelado,
                                                 'ficha', d.ficha, 'diferencias', d.diferencias)), '[]'::jsonb), count(*)::int
      into v, n
      from public.documentos_desactualizados d
     where d.id = p_id and jsonb_typeof(d.diferencias) = 'array' and jsonb_array_length(d.diferencias) > 0;
  elsif p_client is not null then
    select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'id', x.id, 'numero', x.numero, 'congelado', x.congelado,
                                                 'ficha', x.ficha, 'diferencias', x.diferencias) order by x.tipo, x.id)
                    filter (where x.rn <= 2000), '[]'::jsonb), count(*)::int
      into v, n
      from (select d.tipo, d.id, d.numero, d.congelado, d.ficha, d.diferencias, row_number() over (order by d.tipo, d.id) as rn
              from public.documentos_desactualizados d
             where d.client_id = p_client and jsonb_typeof(d.diferencias) = 'array' and jsonb_array_length(d.diferencias) > 0) x;
  else
    select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'id', x.id, 'numero', x.numero, 'congelado', x.congelado,
                                                 'ficha', x.ficha, 'diferencias', x.diferencias) order by x.tipo, x.id)
                    filter (where x.rn <= 2000), '[]'::jsonb), count(*)::int
      into v, n
      from (select d.tipo, d.id, d.numero, d.congelado, d.ficha, d.diferencias, row_number() over (order by d.tipo, d.id) as rn
              from public.documentos_desactualizados d
             where d.tipo = p_tipo and jsonb_typeof(d.diferencias) = 'array' and jsonb_array_length(d.diferencias) > 0) x;
  end if;
  return jsonb_build_object('documentos', v, 'recortado', case when n > 2000 then '["documentos"]'::jsonb else '[]'::jsonb end);
end $$;

-- ── 9. Búsquedas que eran INVOKER: pasan a DEFINER-lw_lector (el revoke de clients las rompería) ────────────────────────
-- clientes_busca: además del nombre/pasaporte de siempre, el correo y el teléfono que la edge asistente-peticiones buscaba con
-- `.from('clients')`. Misma firma y mismas columnas de salida. Seguridad #396.1: el correo se compara por IGUALDAD (la edge hacía
-- `ilike` con la entrada cruda y `%@%` listaba fichas cualesquiera), el teléfono solo con dígitos; sin sesión → 42501 (antes, vacío
-- en silencio) y solo con la herramienta del asistente, que es su único llamador.
create or replace function public.clientes_busca(p_q text)
 returns table(id uuid, full_name text, email text, phone text)
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_q text; v_crudo text; v_dig text;
begin
  if public.uid_sesion() is null then
    raise exception 'clientes_busca: sin sesión' using errcode = '42501';
  end if;
  if not public.puede('asistente') then
    raise exception 'clientes_busca: sin la herramienta del asistente' using errcode = '42501';
  end if;
  v_q := public.normaliza_busqueda(left(p_q, 200));
  v_crudo := lower(btrim(left(coalesce(p_q, ''), 200)));
  v_dig := regexp_replace(v_crudo, '[^0-9]', '', 'g');
  if char_length(coalesce(v_q, '')) < 2 then
    return;
  end if;
  return query
    select c.id, c.full_name, c.email, c.phone
      from public.clients c
     where public.es_agente()
       and case
             when strpos(v_crudo, '@') > 0 then lower(btrim(c.email)) = v_crudo
             when char_length(v_dig) >= 6
                  and char_length(v_dig) >= char_length(regexp_replace(v_crudo, '[[:space:]]', '', 'g')) - 2
               then strpos(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), right(v_dig, 6)) > 0
             else strpos(public.normaliza_busqueda(c.full_name), v_q) > 0 or lower(c.passport_number) = v_crudo
           end
     order by c.full_name, c.id
     limit 6;
end
$function$;
alter function public.clientes_busca(text) security definer;
-- las dos búsquedas llaman normaliza_busqueda (INVOKER, inmutable); como dueño lw_lector necesitan su EXECUTE (medido 16-oct: no lo tenía)
grant execute on function public.normaliza_busqueda(text) to lw_lector;
alter function public.contratos_busca(text) security definer;
-- bot_pendientes (Backend #396.1): INVOKER que lee documentos_desactualizados (vista invoker sobre clients) y la llama la edge
-- bot-agentes con el JWT de la persona (index.ts:686; si falla, 500 no_se_pudo_leer_contexto). Con el revoke de clients el bot
-- de agentes caería en cada contrato → DEFINER-lw_lector, cuerpo intacto. Lee sociedades(clave, razon), que authenticated tiene por
-- permiso de COLUMNA y lw_lector no (medido 16-oct en attacl): se le dan esas dos columnas, ni una más.
alter function public.bot_pendientes(uuid) security definer;
grant select (clave, razon) on public.sociedades to lw_lector;

-- ── dueño, ACL ───────────────────────────────────────────────────────────────────────────────────────────────────────────
grant create on schema public to lw_lector;
alter function public.clientes_lista_datos(uuid[]) owner to lw_lector;
alter function public.comprador_ficha_datos(uuid, text[]) owner to lw_lector;
alter function public.operacion_compradores_datos(uuid, uuid[]) owner to lw_lector;
alter function public.operaciones_compradores_datos() owner to lw_lector;
alter function public.soporte_datos() owner to lw_lector;
alter function public.notificaciones_datos(int) owner to lw_lector;
alter function public.correos_registro_datos(uuid[], uuid) owner to lw_lector;
alter function public.documentos_desactualizados_datos(text, uuid, uuid) owner to lw_lector;
alter function public.clientes_busca(text) owner to lw_lector;
alter function public.contratos_busca(text) owner to lw_lector;
alter function public.bot_pendientes(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;

revoke all on function public.clientes_lista_datos(uuid[]) from public, anon, service_role;
revoke all on function public.comprador_ficha_datos(uuid, text[]) from public, anon, service_role;
revoke all on function public.operacion_compradores_datos(uuid, uuid[]) from public, anon, service_role;
revoke all on function public.operaciones_compradores_datos() from public, anon, service_role;
revoke all on function public.soporte_datos() from public, anon, service_role;
revoke all on function public.notificaciones_datos(int) from public, anon, service_role;
revoke all on function public.correos_registro_datos(uuid[], uuid) from public, anon, service_role;
revoke all on function public.documentos_desactualizados_datos(text, uuid, uuid) from public, anon, service_role;
grant execute on function public.clientes_lista_datos(uuid[]) to authenticated;
grant execute on function public.comprador_ficha_datos(uuid, text[]) to authenticated;
grant execute on function public.operacion_compradores_datos(uuid, uuid[]) to authenticated;
grant execute on function public.operaciones_compradores_datos() to authenticated;
grant execute on function public.soporte_datos() to authenticated;
grant execute on function public.notificaciones_datos(int) to authenticated;
grant execute on function public.correos_registro_datos(uuid[], uuid) to authenticated;
grant execute on function public.documentos_desactualizados_datos(text, uuid, uuid) to authenticated;
-- clientes_busca / contratos_busca: solo authenticated. service_role sale (Seguridad #396.5): ningún llamador de servicio (grep
-- 16-oct: la edge usa el JWT de la persona) y una llamada de servicio a una DEFINER de lw_lector daría 0 filas en silencio.
revoke all on function public.clientes_busca(text) from public, anon, service_role;
revoke all on function public.contratos_busca(text) from public, anon, service_role;
revoke all on function public.bot_pendientes(uuid) from public, anon, service_role;
grant execute on function public.clientes_busca(text) to authenticated;
grant execute on function public.contratos_busca(text) to authenticated;
grant execute on function public.bot_pendientes(uuid) to authenticated;
