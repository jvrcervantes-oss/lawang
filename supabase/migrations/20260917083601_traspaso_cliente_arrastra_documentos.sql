-- Traspaso de cliente: arrastra tambien sus contratos, facturas y recibis —
-- 17-sep-2026, encargo del owner.
--
-- CONTEXTO. Desde el 14-sep existe /intranet/compradores/ -> "Traspasar", que
-- cambia SOLO `clients.propietario` y lo dice en el propio aviso: "Los
-- contratos y las facturas NO se mueven: el traspaso es de la ficha, no del
-- trabajo" (supabase/migrations/20260914_directorio_de_compradores_y_el_autor_corrige_lo_suyo.sql,
-- comentario de compradores/index.html linea ~1184). Fue deliberado para el
-- caso "el agente ya puede ABRIR la ficha que dio de alta otro". Lo que pide
-- el owner ahora es distinto: cuando de verdad se traspasa un cliente de un
-- agente a otro, sus contratos, facturas y recibis (misma tabla `facturas`,
-- distinguidos por tipo) tienen que seguirle. LAW-159 ya nombraba el hueco:
-- "probablemente traspasos de cliente entre agentes que no quedaron
-- documentados en ningun otro sitio".
--
-- QUE NO TOCA, a proposito:
--   - `contrato_closer`/`contrato_closer_log` (atribucion de venta/comision):
--     tabla aparte, deliberadamente desacoplada de `creado_por`
--     (20260911020137_crm_atribucion_ventas_y_ranking_closers.sql explica por
--     que `creado_por` NO sirve para medir quien cerro la venta). Un traspaso
--     de gestion no cambia quien cobra la comision.
--   - Contratos `bloqueado = true`: se quedan con su autor. Mismo limite que
--     ya tiene "Reasignar autor" (contracts/assets/autoria.js); ampliarlo es
--     la decision del dueño que describe, sin aplicar,
--     contracts/sql/reasignar_autor_bloqueados.sql.
--   - Facturas `anulada = true`: estas SI se mueven (solo `creado_por`), al
--     reves que los contratos bloqueados: LAW-71
--     (20260821152750_law71_super_admin_reasigna_autor_de_factura_anulada.sql)
--     ya construyo el trigger `factura_anulada_solo_cambia_autor` justo para
--     autorizar esto. Excluirlas aqui seria mas restrictivo que la propia base
--     y dejaria al admin reasignandolas una a una despues (Regla 0 de
--     contexto/suite_lawang.md: "una copia pegada de otra herramienta es
--     deuda").
--
-- QUIEN. `es_super_admin()`, no `es_admin()`. La ficha SOLA (sin cascada)
-- sigue siendo de cualquier admin (RLS de `clients`, sin cambios); arrastrar
-- documentos es la version en bloque de "Reasignar autor", ya restringida a
-- super_admin porque "reatribuir un documento es un acto de administracion de
-- personas, no de documentos" (autoria.js). Mismo criterio, aplicado a muchos
-- documentos de una vez.
--
-- COMO SE ENLAZAN LOS CONTRATOS. Por `contrato_compradores.client_id`, para
-- CUALQUIER rol (adquiriente_1, adquiriente_2...) — no por
-- `facturas.client_id`, que el trigger `factura_hereda_cliente` solo rellena
-- para `adquiriente_1` y dejaria fuera, en silencio, las facturas de un
-- comprador secundario.
--
-- SOLO SE MUEVE LO QUE ERA DEL PROPIETARIO SALIENTE. El filtro exige
-- `creado_por = v_anterior` (comparacion normal, nunca IS NOT DISTINCT FROM:
-- si `v_anterior` es NULL —fichas sin dueño reconstruible, LAW-180— no se
-- adivina nada, y todo lo de esa ficha cae en "sin autor" para que un humano
-- lo revise, nunca en "movido"). Un contrato de este cliente cuya autoria es
-- de un TERCER agente (admin, un compañero que lo redacto) no se reatribuye
-- solo por traspasar al comprador — se cuenta aparte para que el super_admin
-- lo vea y decida a mano con "Reasignar autor" si tambien hay que moverlo.
--
-- POR QUE `set local session_replication_role = replica` alrededor de las dos
-- UPDATE. `trg_sincroniza_unidad` (contratos, contracts/sql/vinculo_contrato_unidad.sql)
-- se creo SIN lista de columnas, asi que cualquier UPDATE lo dispara aunque
-- solo cambie `creado_por` — y su guard de reentrada solo protege llamadas
-- ANIDADAS (`pg_trigger_depth() > 1`), no esta, que es de primer nivel. Mismo
-- patron ya escrito en contexto/patrones_tecnicos.md -> "El dato tiene un
-- dueño" para backfills masivos: se desactivan los triggers de fila para las
-- dos UPDATE de este traspaso, que solo tocan `creado_por` y no necesitan que
-- ningun trigger de negocio reaccione.
--
-- CAPTURAR `v_anterior` ANTES de escribir nada: si se releyera
-- `clients.propietario` despues del primer UPDATE, la comparacion seria
-- contra el valor NUEVO y no moveria nunca nada.
--
-- UNA SOLA UPDATE por tabla, con OR en el WHERE (nunca dos pasadas): una
-- factura enlazada a la vez por `contrato_id` y por `client_id` no se toca
-- dos veces ni deja dos filas en `correcciones_datos` para el mismo cambio.
--
-- RASTRO. Una fila en `correcciones_datos` por cada columna cambiada (mismo
-- patron que autoria.js), TODO dentro de la misma transaccion que el propio
-- traspaso: si algo revienta a mitad, no queda ni el cambio ni un rastro de
-- que se intento — mas seguro que un traspaso a medias con rastro parcial.
--
-- Revision previa 17-sep con Seguridad + Datos (revision #22,
-- CEO/revisiones/estado.json): los 5+5 hallazgos de las dos estan plegados
-- arriba y en el cuerpo de la funcion.

create or replace function public.traspasar_cliente_con_documentos(
  p_client_id uuid,
  p_nuevo_propietario text,
  p_motivo text
)
returns table (
  propietario_anterior          text,
  contratos_movidos             int,
  contratos_omitidos_firmados   int,
  contratos_omitidos_otro_autor int,
  contratos_omitidos_sin_autor  int,
  facturas_movidas              int,
  facturas_movidas_anuladas     int,
  facturas_omitidas_otro_autor  int,
  facturas_omitidas_sin_autor   int
)
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_anterior      text;
  v_contratos     uuid[];
  v_cont_movidos  uuid[];
  v_fact_movidas  uuid[];
  v_fact_anuladas int;
  v_quien         text;
begin
  if not public.es_super_admin() then
    raise exception 'Solo super_admin puede traspasar contratos y facturas junto con la ficha'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'Falta el motivo del traspaso' using errcode = '23514';
  end if;

  if not exists (select 1 from public.usuarios u where u.email = p_nuevo_propietario and u.activo) then
    raise exception 'El nuevo propietario no es un usuario activo del equipo' using errcode = '23514';
  end if;

  v_quien := auth.email();

  select c.propietario into v_anterior from public.clients c where c.id = p_client_id;
  if not found then
    raise exception 'No existe esa ficha de comprador' using errcode = '23503';
  end if;
  if v_anterior is not distinct from p_nuevo_propietario then
    raise exception 'Esa ficha ya es de ese propietario' using errcode = '23514';
  end if;

  -- ── 1. la ficha ──────────────────────────────────────────────────────────
  insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
  values ('clients', p_client_id, 'propietario', v_anterior, p_nuevo_propietario, p_motivo, v_quien);

  update public.clients set propietario = p_nuevo_propietario where id = p_client_id;

  -- ── 2. sus contratos (cualquier rol en contrato_compradores) ─────────────
  select coalesce(array_agg(distinct cc.contrato_id), '{}')
    into v_contratos
    from public.contrato_compradores cc
   where cc.client_id = p_client_id;

  select count(*) into contratos_omitidos_firmados
    from public.contratos
   where id = any(v_contratos) and creado_por = v_anterior and coalesce(bloqueado, false);

  select count(*) into contratos_omitidos_otro_autor
    from public.contratos
   where id = any(v_contratos) and creado_por is not null and creado_por is distinct from v_anterior;

  select count(*) into contratos_omitidos_sin_autor
    from public.contratos
   where id = any(v_contratos) and creado_por is null;

  -- A partir de aqui, sin triggers de fila: solo tocamos `creado_por`.
  set local session_replication_role = replica;

  with mov as (
    update public.contratos
       set creado_por = p_nuevo_propietario
     where id = any(v_contratos)
       and creado_por = v_anterior
       and not coalesce(bloqueado, false)
     returning id
  )
  select array_agg(id) into v_cont_movidos from mov;

  contratos_movidos := coalesce(array_length(v_cont_movidos, 1), 0);
  if v_cont_movidos is not null then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'contratos', cid, 'creado_por', v_anterior, p_nuevo_propietario, p_motivo, v_quien
      from unnest(v_cont_movidos) cid;
  end if;

  -- ── 3. sus facturas y recibis (misma tabla, mismo criterio) ──────────────
  -- Enlace por CONTRATO (cualquier rol, via v_contratos) O por `client_id`
  -- directo — una sola condicion OR, nunca dos UPDATE separados.
  select count(*) into facturas_omitidas_otro_autor
    from public.facturas
   where creado_por is not null and creado_por is distinct from v_anterior
     and (contrato_id = any(v_contratos) or client_id = p_client_id);

  select count(*) into facturas_omitidas_sin_autor
    from public.facturas
   where creado_por is null
     and (contrato_id = any(v_contratos) or client_id = p_client_id);

  with mov as (
    update public.facturas
       set creado_por = p_nuevo_propietario
     where creado_por = v_anterior
       and (contrato_id = any(v_contratos) or client_id = p_client_id)
     returning id, anulada
  )
  select array_agg(id), count(*) filter (where anulada)
    into v_fact_movidas, v_fact_anuladas
    from mov;

  facturas_movidas := coalesce(array_length(v_fact_movidas, 1), 0);
  facturas_movidas_anuladas := coalesce(v_fact_anuladas, 0);
  if v_fact_movidas is not null then
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    select 'facturas', fid, 'creado_por', v_anterior, p_nuevo_propietario, p_motivo, v_quien
      from unnest(v_fact_movidas) fid;
  end if;

  propietario_anterior := v_anterior;
  return next;
end;
$$;

revoke execute on function public.traspasar_cliente_con_documentos(uuid, text, text) from public, anon;
grant  execute on function public.traspasar_cliente_con_documentos(uuid, text, text) to authenticated;

comment on function public.traspasar_cliente_con_documentos(uuid, text, text) is
  'Traspasa clients.propietario Y arrastra creado_por de sus contratos/facturas al nuevo agente (solo super_admin, motivo obligatorio, rastro en correcciones_datos). No toca contratos bloqueado=true ni contrato_closer. 17-sep-2026.';

-- ── Comprobaciones (el catalogo, nunca el "ya lo apliqué") ──────────────────
--   select proname from pg_proc where proname = 'traspasar_cliente_con_documentos';
--   select grantee, privilege_type from information_schema.routine_privileges
--    where routine_name = 'traspasar_cliente_con_documentos';
--   -- esperado: solo `authenticated` con EXECUTE, ni `public` ni `anon`.
--   -- Prueba de comportamiento con un cliente real de prueba, como super_admin:
--   --   select * from public.traspasar_cliente_con_documentos('<client_id>', 'otro@equipo.com', 'prueba');
--   --   select * from public.correcciones_datos where fila_id::text = '<client_id>' order by corregido_en desc;
