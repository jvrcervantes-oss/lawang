-- B10a (LAW-338 a la par con el maestro) — las 4 lecturas con tabla DINÁMICA del front pasan a RPC del servidor.
-- Encargo: encargos/20260927_erp_b10_lecturas_a_la_par.md (revisión previa #136, Desarrollo 3). Pareja: maestro erp/migraciones/20260928080000_b10a_cifras_datos.sql + 20260928100000_b10a_cifras_una_pasada.sql (dueño erp_lector) · este fichero en Lawang (dueño lw_lector).
-- erp-ok: B10 a la par (decisión del owner 27-sep: cada *_datos nace en las dos bases con el mismo cuerpo)
--
-- Qué sustituye (FROM_DIN de erp/contrato_front.py: `.from(variable)`, que tras un revoke da 0 o 42501 sin que nadie
-- lo vea venir):
--   · intranet/index.html `contar()` (hub clásico)          → hub_cifras_datos()
--   · intranet/v4/assets/datos.js `cnt()` en Home           → inicio_cifras_datos(p_hoy)
--   · intranet/v4/assets/datos.js `cnt()` en Obra           → obra_cifras_datos()
--   · intranet/v4/assets/editores.js `cuenta()` ×2 (renombrar y borrar proyecto: aviso previo) → proyecto_vinculos_datos(p_nombre)
--
-- Por qué así:
--  · SECURITY DEFINER con dueño lw_lector (NOBYPASSRLS): la RLS se evalúa como lw_lector y uid_sesion() sigue siendo el
--    usuario ⇒ mismas cifras que la lectura directa de hoy; la regla vive solo en la policy (L0 ya puso lw_lector en
--    todas las policies SELECT de estas tablas). Sin `auth.*` en el cuerpo, search_path ''.
--  · Sin sesión: 42501 (falla en voz alta). Sin permiso sobre una tabla: la cifra que da la RLS (0), igual que hoy.
--  · CAMBIO DE COMPORTAMIENTO ASUMIDO: el hub pedía ~18 conteos sueltos y cada uno podía quedarse en null por su lado;
--    ahora es una llamada: si falla, TODAS las cifras salen «—/la base no contestó» (la pantalla ya pinta null así;
--    nunca un cero inventado).
--  · proyecto_vinculos_datos cuenta con el MISMO criterio que borrar_proyecto (nombre O proyecto_id), no solo por nombre
--    como el navegador de antes: el aviso previo tiene que coincidir con quien decide. Es solo el aviso; el que manda
--    sigue siendo borrar_proyecto/renombrar_proyecto en el servidor. El front, si esta RPC falla, PARA y lo dice.
--  · inicio_cifras_datos(p_hoy): la fecha del navegador (su huso) solo filtra un conteo; se acepta a ±1 día del
--    current_date de la base y fuera de eso se ignora.
--  · Aditiva: solo create function + dueño + grants. Ningún revoke de tabla (eso va por bloque, con OK del owner).
--  · Paridad medida ANTES de aplicar (28-sep, transacción revertida, receta de tools/flujos_lawang.py): los 65 usuarios de
--    auth.users, 2.080 llamadas, 0 distintas entre la misma lógica como authenticated (copia INVOKER) y la RPC como
--    lw_lector; «una pasada» == los conteos sueltos de antes (como postgres); sin sesión = 42501 en las cuatro; anon no ejecuta.

-- ── Las cuatro RPC (cuerpo IDÉNTICO en Lawang y en el maestro; solo cambia el rol lector) ──────────────────────────

create or replace function public.hub_cifras_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c record; f record; u record; x record; d record; m record;
begin
  if public.uid_sesion() is null then
    raise exception 'hub_cifras_datos: sin sesión' using errcode = '42501';
  end if;
  -- UNA pasada por tabla con `count(*) filter`: la RLS de contratos/facturas/unidades cuesta por fila (medido 28-sep
  -- en Lawang como agente: facturas ~390 ms, unidades ~240 ms por recorrido); tres conteos = tres recorridos.
  select count(*) as n, count(*) filter (where t.bloqueado = false) as editables into c from public.contratos t;
  select count(*) filter (where t.anulada = false) as vivas, count(*) filter (where t.anulada = true) as anuladas,
         count(*) filter (where t.tipo = 'recibi' and t.anulada = false) as recibis into f from public.facturas t;
  select count(*) as n, count(*) filter (where t.estado = 'disponible') as libres,
         count(*) filter (where t.obra_fase is not null and t.obra_fase <> 'entregada') as obra into u from public.unidades t;
  select count(*) filter (where t.activo = true) as activos, count(*) filter (where t.activo = false) as inactivos
    into x from public.usuarios t;
  -- proyectos distintos: el null cuenta como uno (lo que hacía el Set del navegador)
  select count(*) as n, count(distinct t.proyecto) + (case when bool_or(t.proyecto is null) then 1 else 0 end) as proyectos
    into d from public.documentos_proyecto t;
  select count(*) as n, count(*) filter (where t.publicado = true) as publicados,
         count(*) filter (where t.activo = true and t.precio_construccion is null) as sin_precio into m from public.modelos t;
  return jsonb_build_object(
    'contratos',           c.n,
    'contratos_editables', c.editables,
    'facturas',            f.vivas,
    'facturas_anuladas',   f.anuladas,
    'recibis',             f.recibis,
    'unidades',            u.n,
    'unidades_libres',     u.libres,
    'obra_activas',        u.obra,
    'compradores',         (select count(*) from public.clients k),
    'usuarios',            x.activos,
    'usuarios_inactivos',  x.inactivos,
    'documentos',          d.n,
    'proyectos_con_docs',  d.proyectos,
    -- vencimientos sin fecha de contratos FIRMADOS; la RLS de contratos también se aplica (antes: contratos!inner)
    'venc_sin_fecha',      (select count(*) from public.contrato_vencimientos v
                              join public.contratos k on k.id = v.contrato_id
                             where v.fecha is null and k.bloqueado = true),
    'hilos_abiertos',      (select count(*) from public.hilo_soporte h where h.estado = 'abierto'),
    'modelos',             m.n,
    'modelos_publicados',  m.publicados,
    'modelos_sin_precio',  m.sin_precio,
    'solicitudes_vivas',   (select count(*) from public.solicitudes_pago s where s.estado in ('pendiente', 'aprobada')));
end $$;

create or replace function public.inicio_cifras_datos(p_hoy date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- el «hoy» del navegador (su huso) solo se acepta a ±1 día del de la base: fuera de eso, el de la base
  v_hoy date := case when p_hoy between current_date - 1 and current_date + 1 then p_hoy else current_date end;
  v record; u record;
begin
  if public.uid_sesion() is null then
    raise exception 'inicio_cifras_datos: sin sesión' using errcode = '42501';
  end if;
  -- una pasada por tabla (ver hub_cifras_datos)
  select count(*) filter (where t.fecha <= v_hoy + 30) as d30, count(*) filter (where t.fecha <= v_hoy + 7) as d7 into v
    from public.contrato_vencimientos t join public.contratos k on k.id = t.contrato_id
   where k.bloqueado = true and t.fecha >= v_hoy and t.fecha <= v_hoy + 30;
  select count(*) as n, count(*) filter (where t.estado = 'disponible') as libres,
         count(*) filter (where t.estado = 'reservada') as reservadas into u from public.unidades t;
  return jsonb_build_object(
    'vencimientos_30',     v.d30,
    'vencimientos_7',      v.d7,
    'unidades',            u.n,
    'unidades_libres',     u.libres,
    'unidades_reservadas', u.reservadas);
end $$;

create or replace function public.obra_cifras_datos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.uid_sesion() is null then
    raise exception 'obra_cifras_datos: sin sesión' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'entregas_con_fecha', (select count(*) from public.unidades_estado u where u.obra_fecha_entrega is not null),
    'partes',             (select count(*) from public.obra_partes_trabajo o));
end $$;

create or replace function public.proyecto_vinculos_datos(p_nombre text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if public.uid_sesion() is null then
    raise exception 'proyecto_vinculos_datos: sin sesión' using errcode = '42501';
  end if;
  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'proyecto_vinculos_datos: falta el proyecto' using errcode = '22023';
  end if;
  select p.id into v_id from public.proyectos p where p.nombre = p_nombre;
  -- mismo criterio que borrar_proyecto (nombre O id): el aviso previo tiene que coincidir con quien decide
  return jsonb_build_object(
    'unidades',      (select count(*) from public.unidades u
                       where u.proyecto = p_nombre or (v_id is not null and u.proyecto_id = v_id)),
    'modelos_villa', (select count(*) from public.modelos_villa m
                       where m.proyecto = p_nombre or (v_id is not null and m.proyecto_id = v_id)),
    'documentos',    (select count(*) from public.documentos_proyecto d
                       where d.proyecto = p_nombre or (v_id is not null and d.proyecto_id = v_id)));
end $$;

-- dueño lw_lector (CREATE en public solo durante el ALTER, como en L1/B8)
grant create on schema public to lw_lector;
alter function public.hub_cifras_datos() owner to lw_lector;
alter function public.inicio_cifras_datos(date) owner to lw_lector;
alter function public.obra_cifras_datos() owner to lw_lector;
alter function public.proyecto_vinculos_datos(text) owner to lw_lector;
revoke create on schema public from lw_lector;

revoke all on function public.hub_cifras_datos() from public, anon, service_role;
revoke all on function public.inicio_cifras_datos(date) from public, anon, service_role;
revoke all on function public.obra_cifras_datos() from public, anon, service_role;
revoke all on function public.proyecto_vinculos_datos(text) from public, anon, service_role;
grant execute on function public.hub_cifras_datos() to authenticated;
grant execute on function public.inicio_cifras_datos(date) to authenticated;
grant execute on function public.obra_cifras_datos() to authenticated;
grant execute on function public.proyecto_vinculos_datos(text) to authenticated;

-- comprobación en la misma migración: dueño, proacl y CREATE; si no cuadra, no se aplica
do $chk$
declare f text; v_acl text; v_dueno text;
begin
  foreach f in array array['public.hub_cifras_datos()', 'public.inicio_cifras_datos(date)', 'public.obra_cifras_datos()', 'public.proyecto_vinculos_datos(text)'] loop
    select p.proacl::text, pg_get_userbyid(p.proowner) into v_acl, v_dueno from pg_proc p where p.oid = f::regprocedure;
    if v_dueno <> 'lw_lector' then raise exception '%: dueño % (esperado lw_lector)', f, v_dueno; end if;
    if v_acl is distinct from '{lw_lector=X/lw_lector,authenticated=X/lw_lector}' then
      raise exception '%: proacl % (esperado lw_lector + authenticated)', f, v_acl;
    end if;
  end loop;
  if has_schema_privilege('lw_lector', 'public', 'create') then raise exception 'lw_lector conserva CREATE en public'; end if;
end $chk$;
