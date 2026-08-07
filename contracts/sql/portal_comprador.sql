-- ============================================================================
-- Portal del comprador — 5-ago-2026
-- ----------------------------------------------------------------------------
-- 🔴 7-ago-2026: este fichero se había quedado DESACTUALIZADO frente a lo que
-- de verdad corría en producción — los bloques `documentos` (documentos_proyecto,
-- visible_portal) y `kyc` (documents por client_id) de portal_situacion() se
-- añadieron a mano en el editor SQL de Supabase en algún momento y nunca se
-- volvieron a guardar aquí. Una migración posterior que redefinió la función
-- copiando el cuerpo de ESTE fichero los borró sin que nadie lo pidiera —
-- 60 horas sin documentos ni KYC en el portal de ningún comprador, hasta que
-- un cliente lo notó. Quedan ya incluidos abajo. La lección, no solo para este
-- fichero: antes de `create or replace function` sobre algo que puede haber
-- cambiado fuera de un `apply_migration`, se lee la definición VIVA
-- (`pg_get_functiondef`), nunca se asume que el .sql del repo es la fuente
-- de verdad. Ver [[reference_transformar_y_verificar_no_reescribir]].
-- ----------------------------------------------------------------------------
-- Los compradores de Lawang consultan su situación (contratos, pagos, facturas
-- y avance de obra) en /portal/. Decisiones de diseño que hay que respetar:
--
--   · Un comprador es un usuario de Auth con `app_metadata.portal = true`.
--     NUNCA lleva ficha en `usuarios` ni el flag `agente`: todas las policies
--     internas cuelgan de es_agente()/es_admin(), así que un portal-user no ve
--     NADA del equipo por construcción. Y al revés: es_portal() es la única
--     puerta de lo suyo.
--
--   · El vínculo persona↔acceso NO es "buscar por email en clients": las fichas
--     de familia se crean SIN correo a propósito (UNIQUE(email), ver
--     compradores_desde_contrato.sql). El vínculo es la tabla `portal_accesos`
--     (email → client_id), que rellena el equipo al invitar. Explícito y
--     auditable; una familia con un correo lleva N filas.
--
--   · El portal NO tiene policies de SELECT sobre contratos/facturas: lee TODO
--     por una única RPC `security definer` (portal_situacion) que filtra por el
--     email del JWT y devuelve solo los campos que se pintan. Menos superficie
--     que auditar y ningún blob del jsonb viaja (el 97% de `datos` son firmas y
--     anexos en base64 — nunca select(*)).
--
--   · "Pagado" = MISMO criterio que /operaciones/ y unidades_estado: suma de
--     facturas no anuladas y no proforma del contrato. El portal no inventa un
--     segundo criterio de cobro; el reparto entre hitos se calcula al pintar.
--
--   · EXECUTE se revoca de PUBLIC y anon NOMBRÁNDOLOS: `revoke from public` a
--     secas no cierra una función de Supabase (aprendido el 4-ago).
-- ============================================================================

-- ── el claim del portal ─────────────────────────────────────────────────────
create or replace function public.es_portal()
returns boolean language sql stable security definer set search_path = '' as
$$ select coalesce(((select auth.jwt())->'app_metadata'->>'portal')::boolean, false) $$;
revoke execute on function public.es_portal() from public;
revoke execute on function public.es_portal() from anon;
grant execute on function public.es_portal() to authenticated;

-- ── quién puede entrar y a qué fichas ───────────────────────────────────────
create table if not exists public.portal_accesos (
  id         uuid primary key default gen_random_uuid(),
  email      text not null check (email = lower(btrim(email))),
  client_id  uuid not null references public.clients(id) on delete cascade,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now(),
  creado_por text default auth.email(),
  unique (email, client_id)
);
comment on table public.portal_accesos is
  'Qué email del portal ve qué fichas de comprador. Lo rellena el equipo al invitar; una familia con un correo lleva varias filas. Revocar = activo:false, no borrar.';
alter table public.portal_accesos enable row level security;
drop policy if exists "admins gestionan accesos del portal" on public.portal_accesos;
create policy "admins gestionan accesos del portal" on public.portal_accesos
  for all to authenticated using (es_admin()) with check (es_admin());
drop policy if exists "agentes ven accesos del portal" on public.portal_accesos;
create policy "agentes ven accesos del portal" on public.portal_accesos
  for select to authenticated using (es_agente());

-- ── avance de obra ──────────────────────────────────────────────────────────
-- El catálogo de fases es una tabla y no una constante en JS porque lo pintan
-- DOS fronts (la herramienta interna y el portal) en dos idiomas: una lista
-- copiada en dos sitios es la clase de dato que diverge en silencio.
create table if not exists public.obra_fases (
  orden int primary key,
  clave text unique not null,
  es    text not null,
  en    text not null
);
insert into public.obra_fases (orden, clave, es, en) values
  (1, 'preparacion',   'Preparación del terreno', 'Site preparation'),
  (2, 'cimentacion',   'Cimentación',             'Foundations'),
  (3, 'estructura',    'Estructura',              'Structure'),
  (4, 'cubierta',      'Cubierta',                'Roofing'),
  (5, 'instalaciones', 'Instalaciones',           'Utilities & MEP'),
  (6, 'acabados',      'Acabados',                'Finishes'),
  (7, 'entregada',     'Entregada',               'Handed over')
on conflict (orden) do nothing;
alter table public.obra_fases enable row level security;
drop policy if exists "obra_fases: leer" on public.obra_fases;
create policy "obra_fases: leer" on public.obra_fases
  for select to authenticated using (es_agente() or es_portal());
drop policy if exists "obra_fases: escribir" on public.obra_fases;
create policy "obra_fases: escribir" on public.obra_fases
  for all to authenticated using (es_admin()) with check (es_admin());

-- El estado vive EN la unidad (no en tabla aparte): es 1:1 con ella y ya hay
-- vista/paneles que parten de `unidades`.
alter table public.unidades
  add column if not exists obra_fase text references public.obra_fases(clave),
  add column if not exists obra_fecha_entrega date,
  add column if not exists obra_actualizado timestamptz;

create table if not exists public.obra_fotos (
  id         uuid primary key default gen_random_uuid(),
  unidad_id  uuid not null references public.unidades(id) on delete cascade,
  path       text not null,             -- en el bucket 'obra': <unidad_id>/<fichero>
  titulo     text,
  tomada_en  date not null default current_date,
  visible    boolean not null default true,   -- false = el equipo la guarda pero el comprador no la ve
  creado_en  timestamptz not null default now(),
  creado_por text default auth.email()
);
alter table public.obra_fotos enable row level security;
drop policy if exists "obra_fotos: agentes leen" on public.obra_fotos;
create policy "obra_fotos: agentes leen" on public.obra_fotos
  for select to authenticated using (es_agente());
drop policy if exists "obra_fotos: con la herramienta escriben" on public.obra_fotos;
create policy "obra_fotos: con la herramienta escriben" on public.obra_fotos
  for all to authenticated
  using (es_agente() and puede('obra'))
  with check (es_agente() and puede('obra'));
-- (El portal no lee esta tabla: sus fotos llegan dentro de portal_situacion().)

-- bucket privado para las fotos de obra (idempotente)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('obra', 'obra', false, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- ── comparación de nombre de proyecto ───────────────────────────────────────
-- 🔴 El nombre del proyecto NO casa entre tablas: los contratos dicen «Palm
-- Field», la documentación «Palm Field by Balian Hills». Con `=` no aparecía
-- nada; renombrar datos de producción para que cuadraran habría sido peor.
-- Contención en minúsculas, en los dos sentidos.
create or replace function public.mismo_proyecto(a text, b text)
returns boolean language sql immutable set search_path to '' as
$$ select a is not null and b is not null and (
     lower(btrim(a)) = lower(btrim(b))
     or lower(btrim(a)) like '%' || lower(btrim(b)) || '%'
     or lower(btrim(b)) like '%' || lower(btrim(a)) || '%') $$;

-- ── la RPC única del portal ─────────────────────────────────────────────────
create or replace function public.portal_situacion()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  r jsonb;
begin
  -- La puerta es el claim + el email del JWT: nada que el cliente pueda mandar
  -- en el body cambia lo que ve.
  if not public.es_portal() or v_email = '' then
    raise exception 'solo usuarios del portal' using errcode = '42501';
  end if;

  with mis_clientes as (
    select distinct pa.client_id
      from portal_accesos pa
     where pa.activo and pa.email = v_email
  ),
  mis_ids as (
    select distinct cc.contrato_id as id
      from contrato_compradores cc
      join mis_clientes mc on mc.client_id = cc.client_id
  ),
  cobros as (
    select f.contrato_id,
           coalesce(sum(f.total) filter (where not coalesce(f.anulada, false)
                                           and f.tipo <> 'proforma'), 0) as cobrado
      from facturas f
     where f.contrato_id in (select id from mis_ids)
     group by f.contrato_id
  )
  select jsonb_build_object(
    'nombre', (select cl.full_name from clients cl
                join mis_clientes mc on mc.client_id = cl.id
                order by cl.created_at limit 1),
    'contratos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          c.id,
        'numero',      c.numero,
        'tipo',        c.tipo,
        'proyecto',    c.proyecto_nombre,
        'parcela',     c.datos->'fields'->>'parcela_codigo',
        'precio',      c.precio_total,
        'precio_txt',  nullif(c.datos->'fields'->>'precio_total', ''),
        'moneda',      c.moneda,
        'fecha_firma', c.fecha_firma,
        'firmado',     coalesce(c.bloqueado, false),
        'pdf',         c.pdf_firmado_path,
        'hitos',       case when jsonb_typeof(c.datos->'hitos') = 'array'
                            then c.datos->'hitos' else '[]'::jsonb end,
        'cobrado',     coalesce(k.cobrado, 0)
      ) order by c.created_at)
      from contratos c
      join mis_ids m on m.id = c.id
      left join cobros k on k.contrato_id = c.id), '[]'::jsonb),
    'facturas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',              f.id,
        'numero',          f.numero,
        'tipo',            f.tipo,
        'sociedad',        f.sociedad,
        'contrato_numero', f.contrato_numero,
        'fecha',           f.fecha_emision,
        'total',           f.total,
        'moneda',          f.moneda,
        'cliente',         f.cliente_nombre,
        'proyecto',        f.proyecto_nombre,
        'lineas',          f.datos->'lineas',
        'totales',         f.datos->'totales',
        'fields',          f.datos->'fields'
      ) order by f.fecha_emision desc, f.numero desc)
      from facturas f
     where f.contrato_id in (select id from mis_ids)
       and not coalesce(f.anulada, false)
       -- una proforma sin enviar es un borrador automático que el estudio
       -- todavía no ha revisado (facturas/sql/enviada_y_portal.sql, 7-ago)
       and (f.tipo <> 'proforma' or f.enviada)), '[]'::jsonb),
    'obra', coalesce((
      select jsonb_agg(jsonb_build_object(
        'unidad',          u.codigo,
        'proyecto',        u.proyecto,
        'contrato_numero', c2.numero,
        'fase',            u.obra_fase,
        'fecha_entrega',   u.obra_fecha_entrega,
        'actualizado',     u.obra_actualizado,
        'fotos', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'path', o.path, 'titulo', o.titulo, 'fecha', o.tomada_en)
                 order by o.tomada_en desc, o.creado_en desc)
            from obra_fotos o
           where o.unidad_id = u.id and o.visible), '[]'::jsonb)
      ))
      from unidades u
      join contratos c2 on c2.id = u.contrato_id
      join mis_ids m on m.id = c2.id), '[]'::jsonb),
    'documentos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',          dp.id,
        'titulo',      dp.titulo,
        'descripcion', dp.descripcion,
        'categoria',   dp.categoria,
        'proyecto',    dp.proyecto,
        'url',         dp.url,
        'path',        dp.path
      ) order by dp.creado_en desc)
      from documentos_proyecto dp
     where dp.visible_portal
       and exists (
         select 1 from contratos c3
         join mis_ids m3 on m3.id = c3.id
        where public.mismo_proyecto(dp.proyecto, c3.proyecto_nombre)
       )), '[]'::jsonb),
    'kyc', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tipo',   doc.doc_type,
        'subido', doc.uploaded_at,
        'caduca', doc.caduca_el,
        'path',   doc.storage_path
      ) order by doc.uploaded_at desc)
      from documents doc
      join mis_clientes mc2 on mc2.client_id = doc.client_id), '[]'::jsonb),
    'fases', coalesce((
      select jsonb_agg(jsonb_build_object(
               'orden', ff.orden, 'clave', ff.clave, 'es', ff.es, 'en', ff.en)
             order by ff.orden)
        from obra_fases ff), '[]'::jsonb)
  ) into r;
  return r;
end $$;
revoke execute on function public.portal_situacion() from public;
revoke execute on function public.portal_situacion() from anon;
grant execute on function public.portal_situacion() to authenticated;

-- ── lectura de ficheros: el comprador ve SU pdf y SUS fotos ─────────────────
-- Los helpers son security definer porque una policy de storage.objects corre
-- con los privilegios del que llama, y el que llama (portal) no puede leer
-- contratos/portal_accesos directamente.
create or replace function public.portal_ve_pdf(p_name text)
returns boolean language sql stable security definer set search_path = public as
$$ select public.es_portal() and exists (
     select 1
       from contratos c
       join contrato_compradores cc on cc.contrato_id = c.id
       join portal_accesos pa on pa.client_id = cc.client_id
      where pa.activo
        and pa.email = lower(coalesce(auth.email(), ''))
        and c.pdf_firmado_path = p_name) $$;

create or replace function public.portal_ve_foto(p_name text)
returns boolean language sql stable security definer set search_path = public as
$$ select public.es_portal() and exists (
     select 1
       from obra_fotos o
       join unidades u on u.id = o.unidad_id
       join contrato_compradores cc on cc.contrato_id = u.contrato_id
       join portal_accesos pa on pa.client_id = cc.client_id
      where pa.activo
        and pa.email = lower(coalesce(auth.email(), ''))
        and o.visible
        and o.path = p_name) $$;

revoke execute on function public.portal_ve_pdf(text) from public;
revoke execute on function public.portal_ve_pdf(text) from anon;
grant execute on function public.portal_ve_pdf(text) to authenticated;
revoke execute on function public.portal_ve_foto(text) from public;
revoke execute on function public.portal_ve_foto(text) from anon;
grant execute on function public.portal_ve_foto(text) to authenticated;

drop policy if exists "portal lee su contrato firmado" on storage.objects;
create policy "portal lee su contrato firmado" on storage.objects
  for select to authenticated
  using (bucket_id = 'contratos-firmados' and public.portal_ve_pdf(name));

drop policy if exists "portal ve sus fotos de obra" on storage.objects;
create policy "portal ve sus fotos de obra" on storage.objects
  for select to authenticated
  using (bucket_id = 'obra' and public.portal_ve_foto(name));

drop policy if exists "obra: el equipo gestiona las fotos" on storage.objects;
create policy "obra: el equipo gestiona las fotos" on storage.objects
  for all to authenticated
  using (bucket_id = 'obra' and es_agente() and puede('obra'))
  with check (bucket_id = 'obra' and es_agente() and puede('obra'));

-- ── la herramienta Obra toca SOLO las columnas de obra ──────────────────────
-- Sin esta RPC haría falta el permiso de Unidades entero (precios incluidos)
-- para cambiar una fase: el UPDATE de `unidades` exige puede('unidades').
create or replace function public.obra_actualizar(p_unidad uuid, p_fase text, p_fecha date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (es_agente() and puede('obra')) then
    raise exception 'sin permiso para obra' using errcode = '42501';
  end if;
  update unidades
     set obra_fase = nullif(btrim(coalesce(p_fase, '')), ''),
         obra_fecha_entrega = p_fecha,
         obra_actualizado = now()
   where id = p_unidad;
  if not found then
    raise exception 'unidad inexistente';
  end if;
end $$;
revoke execute on function public.obra_actualizar(uuid, text, date) from public;
revoke execute on function public.obra_actualizar(uuid, text, date) from anon;
grant execute on function public.obra_actualizar(uuid, text, date) to authenticated;
