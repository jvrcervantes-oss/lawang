/* ============================================================================
   CATÁLOGO DE MODELOS DE VIVIENDA — 7-sep-2026
   ----------------------------------------------------------------------------
   Encargo del owner: «al igual que tenemos un agregador de parcelas, poder dar
   de alta los tipos de vivienda que podemos construir — habitaciones, metros,
   precio, extras disponibles, anexos».

   POR QUÉ ESTA MIGRACIÓN EXISTE, Y NO ES SOLO "UNA TABLA MÁS"
   ----------------------------------------------------------
   El día que se escribió esto había TRES sitios distintos diciendo qué es un
   modelo de villa, y ninguno era dueño:

   1. `modelos_villa` (Supabase, 31-jul) — 2 filas, solo Palm Field, sin ninguna
      pantalla de alta. Sembrada por SQL y nunca vuelta a tocar. Es la que
      precarga el precio de construcción de un contrato.
   2. `modelo/modelos.php` (fichero del repo) — las specs ricas de 5 modelos:
      dormitorios, baños, m², dos techos con precio de hoy y de 2027, 7 extras.
      Es lo que publica la web. Un fichero, para un dato que el cliente da de
      alta: exactamente lo que prohíbe «Si el cliente lo puede dar de alta, no
      puede vivir en un fichero» (contexto/suite_lawang.md, 17-ago).
   3. `unidades.modelo` — texto libre. 342 unidades, 15 modelos reales
      escritos con 20 grafías (`Dali`/`DALI`/`Dalí`, `Dream`/`DREAM`…), o sea
      modelos distintos para el sistema.

   Y ya había mordido: la web publicaba Dune 68.000 € y Dream 101.000 € (price
   list del owner, 7-sep) mientras `modelos_villa` seguía en 64.000 y 94.000.
   Cuatro y siete mil euros por debajo, en la tabla que rellena los contratos.

   LA CASCADA — el dato existe UNA vez y cada nivel guarda solo lo que se aparta
   ----------------------------------------------------------------------------
       catálogo (`modelos`)      Dune · 68.000 €  ← la cifra vive aquí y solo aquí
         └─ proyecto             Palm Field: NULL → hereda 68.000
         └─ proyecto             Tamarind:   40.250 ← precio propio pactado
              └─ unidad          W3.1-D1:    46.500 ← precio propio de esa parcela

   Un NULL en un nivel significa «hereda», no «sin dato». Por eso el precio de
   Palm Field se vacía en la siembra en vez de copiarse: copiarlo sería volver a
   crear la divergencia que esta migración viene a cerrar. Decisión del owner
   (7-sep): manda la web, 68.000 y 101.000.

   ⚠️ EL PRECIO DE LA UNIDAD NO SE TOCA NUNCA DESDE AQUÍ. El catálogo es un
   VALOR POR DEFECTO que la app propone al elegir modelo; lo que ya está escrito
   en `unidades.precio_construccion` manda. Hace falta porque en Tamarind Rise
   las tres Dalí tienen tres precios distintos (40.250 / 43.375 / 46.500, sube
   cuando la parcela baja: se metieron con total fijo de villa restando el
   suelo), y tres de esas diez parcelas ya tienen contrato. Un catálogo que
   pisara la unidad les cambiaría el precio a espaldas de un contrato firmado.

   ALCANCE: esta migración crea estructura. No siembra ni engancha ninguna
   unidad — eso va en la siguiente, a propósito, para poder revisarlas por
   separado.
   ========================================================================== */


/* ---------------------------------------------------------------------------
   1. `modelos` — el catálogo. La FUENTE del tipo de vivienda.
   --------------------------------------------------------------------------- */
create table if not exists public.modelos (
  id                  uuid primary key default gen_random_uuid(),
  -- Clave estable y legible. La usa la web en /modelo/<slug>, así que renombrar
  -- el modelo NO cambia la URL: el nombre es texto de marca, el slug es la
  -- dirección. Separarlos es lo que permite corregir una errata de nombre sin
  -- romper un enlace que ya está en una campaña.
  slug                text not null unique,
  nombre              text not null,
  dormitorios         integer,
  banos               integer,
  villa_m2            numeric,
  terraza_m2          numeric,
  descripcion         text,
  /* Precio base de construcción del catálogo: el nivel 1 de la cascada. Es el
     del techo más barato (en los cinco modelos del price list es el Sirap), que
     es también el que fija el «desde» de la web. */
  precio_construccion numeric,
  moneda              text not null default 'EUR',
  /* `publicado` decide si sale en la web. NO es lo mismo que `activo`: un modelo
     puede estar vivo para el equipo (se firman contratos con él) y no publicarse
     todavía. Los 10 modelos que hoy solo existen en el inventario nacen sin
     publicar — publicarlos sin specs sería una ficha vacía de cara al cliente. */
  publicado           boolean not null default false,
  activo              boolean not null default true,
  /* Publicar un modelo sin render real es una decisión consciente del owner
     («no estamos en producción aún», 2-sep): la ficha enseña un estado honesto
     «Renders in progress» y nunca una foto inventada. Se declara aquí para que
     la web no tenga que deducirlo de la ausencia de ficheros. */
  renders_pendientes  boolean not null default false,
  orden               integer,
  notas               text,   -- interno. NUNCA sale por el RPC público.
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now()
);

comment on table public.modelos is
  'Catálogo de tipos de vivienda. FUENTE: el modelo se da de alta y se corrige aquí y solo aquí. `unidades.modelo_id` y `modelos_villa.modelo_id` lo referencian; `modelo/modelos.php` de la web lo lee por el RPC catalogo_publico().';
comment on column public.modelos.precio_construccion is
  'Nivel 1 de la cascada de precio. Un NULL en modelos_villa.precio_construccion hereda de aquí; un valor allí lo pisa para ese proyecto; y lo escrito en unidades.precio_construccion manda sobre los dos.';
comment on column public.modelos.notas is
  'Interno del equipo. Excluida a propósito del RPC publico (catalogo_publico): la web no la ve.';

create index if not exists modelos_publicado_idx on public.modelos (publicado, orden);

alter table public.modelos enable row level security;
drop policy if exists "modelos: leer"    on public.modelos;
drop policy if exists "modelos: escribir" on public.modelos;
create policy "modelos: leer" on public.modelos
  for select to authenticated using (public.es_agente());
-- Mismo criterio que `modelos_villa` desde el 31-jul: cambiar lo que cuesta
-- construir es una decisión de precio, y esas las toma un administrador.
create policy "modelos: escribir" on public.modelos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());


/* ---------------------------------------------------------------------------
   2. `modelo_techos` — las variantes de techo, con su precio y su vigencia.
   ---------------------------------------------------------------------------
   No es «un extra más»: el techo es lo que fija el precio del modelo, y cada
   uno tiene DOS precios porque el owner subió tarifa a partir del 1-ene-2027.
   Cuál de los dos está vigente lo decide el reloj del SERVIDOR, nunca un flag
   manual ni la fecha del visitante (hallazgo de la revisión previa de
   Seguridad, 2-sep): un visitante con el reloj adelantado no puede hacer que la
   web le enseñe la tarifa del año que viene.
   --------------------------------------------------------------------------- */
create table if not exists public.modelo_techos (
  id            uuid primary key default gen_random_uuid(),
  modelo_id     uuid not null references public.modelos(id) on delete cascade,
  clave         text not null,           -- 'sirap', 'bambu'
  nombre        text not null,
  descripcion   text,
  precio_ahora  numeric,
  precio_2027   numeric,
  orden         integer,
  unique (modelo_id, clave)
);

comment on table public.modelo_techos is
  'Variantes de techo de un modelo. `precio_ahora`/`precio_2027` son precios COMPLETOS del modelo con ese techo, no un recargo. El corte lo resuelve lw_techo_precio_activo() con el reloj del servidor en hora de Bali.';

alter table public.modelo_techos enable row level security;
drop policy if exists "techos: leer"    on public.modelo_techos;
drop policy if exists "techos: escribir" on public.modelo_techos;
create policy "techos: leer" on public.modelo_techos
  for select to authenticated using (public.es_agente());
create policy "techos: escribir" on public.modelo_techos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());


/* ---------------------------------------------------------------------------
   3. `extras` + `modelo_extras` — el catálogo de opcionales y su precio.
   ---------------------------------------------------------------------------
   Partido en dos a propósito, y el porqué está medido: de los siete extras del
   price list, CINCO valen lo mismo en los cinco modelos y DOS escalan con el
   modelo (Airbnb Kit y Oasis Pool). Una tabla mixta «estos cinco fijos + estos
   dos por modelo» es justo la forma de que el día que el owner mueva uno de los
   fijos alguien lo cambie en un sitio y no en el otro. Así que el NOMBRE y la
   DESCRIPCIÓN viven una vez (`extras`) y el PRECIO siempre por modelo
   (`modelo_extras`), aunque hoy cinco columnas repitan cifra.
   --------------------------------------------------------------------------- */
create table if not exists public.extras (
  id          uuid primary key default gen_random_uuid(),
  clave       text not null unique,      -- 'airbnb', 'zero', 'sauna'…
  nombre      text not null,
  descripcion text,
  orden       integer,
  activo      boolean not null default true
);

create table if not exists public.modelo_extras (
  id         uuid primary key default gen_random_uuid(),
  modelo_id  uuid not null references public.modelos(id) on delete cascade,
  extra_id   uuid not null references public.extras(id)  on delete cascade,
  precio     numeric,
  moneda     text not null default 'EUR',
  /* Un extra que NO está disponible para un modelo se marca aquí en vez de
     borrar la fila: borrarla y volver a crearla pierde el precio pactado, y
     «no disponible» y «sin precio todavía» no son lo mismo. */
  disponible boolean not null default true,
  unique (modelo_id, extra_id)
);

comment on table public.extras is
  'Catálogo de opcionales. Nombre y descripción viven aquí UNA vez porque son iguales para todos los modelos; el precio nunca, que va en modelo_extras.';

alter table public.extras        enable row level security;
alter table public.modelo_extras enable row level security;
drop policy if exists "extras: leer"     on public.extras;
drop policy if exists "extras: escribir" on public.extras;
drop policy if exists "modelo_extras: leer"     on public.modelo_extras;
drop policy if exists "modelo_extras: escribir" on public.modelo_extras;
create policy "extras: leer" on public.extras
  for select to authenticated using (public.es_agente());
create policy "extras: escribir" on public.extras
  for all to authenticated using (public.es_admin()) with check (public.es_admin());
create policy "modelo_extras: leer" on public.modelo_extras
  for select to authenticated using (public.es_agente());
create policy "modelo_extras: escribir" on public.modelo_extras
  for all to authenticated using (public.es_admin()) with check (public.es_admin());


/* ---------------------------------------------------------------------------
   4. `modelo_documentos` — los anexos del modelo (planos, calidades, ficha).
   ---------------------------------------------------------------------------
   Bucket propio y privado, como `obra`, `kyc` y `documentacion`. El nombre
   original del fichero va en la COLUMNA, nunca en la ruta del bucket (que es un
   uuid): misma regla que los justificantes de un recibí — un plano suele
   llegar con el nombre del proyecto o del cliente en el nombre de archivo.
   --------------------------------------------------------------------------- */
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('modelos', 'modelos', false, 52428800,
        array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create table if not exists public.modelo_documentos (
  id            uuid primary key default gen_random_uuid(),
  modelo_id     uuid not null references public.modelos(id) on delete cascade,
  nombre        text not null,           -- el nombre real del fichero, para enseñarlo
  path          text not null unique,    -- ruta en el bucket `modelos` (uuid)
  tipo          text not null default 'otro',
  /* Qué ve el comprador desde /portal/. Nace en `false`: un plano de obra o una
     memoria de calidades interna no se publica por descuido — se decide fichero
     a fichero, que es lo mismo que ya hace Documentación. */
  visible_portal boolean not null default false,
  tamano_bytes  bigint,
  subido_por    uuid,
  subido_en     timestamptz not null default now(),
  constraint modelo_documentos_tipo_ck
    check (tipo in ('plano','calidades','ficha','render','otro'))
);

comment on column public.modelo_documentos.path is
  'Ruta dentro del bucket `modelos`. Es un uuid: el nombre real del fichero vive en `nombre`, nunca en la ruta.';

create index if not exists modelo_documentos_modelo_idx on public.modelo_documentos (modelo_id);

alter table public.modelo_documentos enable row level security;
drop policy if exists "modelo_docs: leer"    on public.modelo_documentos;
drop policy if exists "modelo_docs: escribir" on public.modelo_documentos;
create policy "modelo_docs: leer" on public.modelo_documentos
  for select to authenticated using (public.es_agente());
-- Subir un plano no es cambiar un precio: basta con ser del equipo.
create policy "modelo_docs: escribir" on public.modelo_documentos
  for all to authenticated using (public.es_agente()) with check (public.es_agente());

drop policy if exists "modelos bucket: leer"   on storage.objects;
drop policy if exists "modelos bucket: subir"  on storage.objects;
drop policy if exists "modelos bucket: borrar" on storage.objects;
create policy "modelos bucket: leer" on storage.objects
  for select to authenticated using (bucket_id = 'modelos' and public.es_agente());
create policy "modelos bucket: subir" on storage.objects
  for insert to authenticated with check (bucket_id = 'modelos' and public.es_agente());
create policy "modelos bucket: borrar" on storage.objects
  for delete to authenticated using (bucket_id = 'modelos' and public.es_admin());


/* ---------------------------------------------------------------------------
   5. `modelos_villa` pasa a ser el NIVEL 2 de la cascada.
   ---------------------------------------------------------------------------
   No se renombra ni se sustituye, aunque el nombre se quede corto: la
   referencian el RPC de borrar proyecto, el de renombrar y la herramienta de
   Proyectos. Regla 0 de la suite — ampliar no es empezar. Lo que gana son los
   dos enlaces que le faltaban y el derecho a estar vacía.
   --------------------------------------------------------------------------- */
alter table public.modelos_villa add column if not exists modelo_id   uuid references public.modelos(id) on delete cascade;
alter table public.modelos_villa add column if not exists proyecto_id uuid references public.proyectos(id) on delete cascade;
create index if not exists modelos_villa_modelo_idx   on public.modelos_villa (modelo_id);
create index if not exists modelos_villa_proyecto_idx on public.modelos_villa (proyecto_id);

comment on table public.modelos_villa is
  'Nivel 2 de la cascada de precio: lo que cuesta construir un modelo EN un proyecto concreto. `precio_construccion` NULL significa «hereda del catálogo», no «sin dato». Las columnas de texto `proyecto` y `modelo` son ESPEJOS de los enlaces.';
comment on column public.modelos_villa.precio_construccion is
  'NULL = hereda modelos.precio_construccion. Solo se rellena cuando este proyecto tiene un precio propio pactado, distinto del de catálogo.';


/* ---------------------------------------------------------------------------
   6. ENLACE + ESPEJO — calcado de trg_espejo_proyecto (19-ago).
   ---------------------------------------------------------------------------
   El texto no desaparece: pasa a ser espejo del enlace y un trigger lo reescribe
   en cada guardado, así que deja de poder divergir. Y al revés: una fila que
   llegue con el texto y sin enlace se ata sola buscando por nombre (normalizado,
   porque el inventario trae `DALI` y `Dalí`). Esa segunda mitad es la que evita
   depender de que cada una de las trece herramientas se acuerde de mandar el id.
   --------------------------------------------------------------------------- */

/* Normalizador único de nombre de modelo. Existe UNA vez porque, si cada sitio
   se escribe el suyo, `Dalí` y `DALI` volverían a ser dos modelos en la pantalla
   que se olvidara del acento. Sin `unaccent` a propósito: la extensión no está
   instalada y añadirla por cinco vocales es traer una dependencia para nada. */
create or replace function public.modelo_norm(txt text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(lower(translate(coalesce(txt,''),
                                      'áéíóúàèìòùäëïöüâêîôûÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛ',
                                      'aeiouaeiouaeiouaeiouAEIOUAEIOUAEIOUAEIOU'))), '')
$$;

create index if not exists modelos_nombre_norm_idx on public.modelos (public.modelo_norm(nombre));

create or replace function public.trg_espejo_modelo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nombre text;
begin
  -- Se ata solo: texto sin enlace → busca el id por nombre normalizado.
  if new.modelo_id is null and public.modelo_norm(new.modelo) is not null then
    select m.id into new.modelo_id
      from public.modelos m
     where public.modelo_norm(m.nombre) = public.modelo_norm(new.modelo)
     limit 1;
  end if;

  -- El enlace manda: el texto se reescribe desde él.
  if new.modelo_id is not null then
    select m.nombre into v_nombre from public.modelos m where m.id = new.modelo_id;
    if v_nombre is not null then new.modelo := v_nombre; end if;
  end if;
  return new;
end $$;

revoke all on function public.trg_espejo_modelo() from public, anon, authenticated;
revoke all on function public.modelo_norm(text)   from public, anon;

alter table public.unidades add column if not exists modelo_id uuid references public.modelos(id);
create index if not exists unidades_modelo_idx on public.unidades (modelo_id);

comment on column public.unidades.modelo_id is
  'Referencia al catálogo. `modelo` (texto) es su ESPEJO: se reescribe desde aquí en cada guardado. Si es null, la unidad nombra un modelo que no está en el catálogo — huérfano VISIBLE en la vista modelos_sin_catalogar, no silencioso.';

-- destructivo-ok: DROP de un TRIGGER (objeto de definicion), no de datos.
drop trigger if exists trg_espejo_modelo on public.unidades;
-- destructivo-ok: "BEFORE INSERT OR UPDATE" declara CUANDO dispara el trigger,
-- no es una sentencia UPDATE sobre filas.
create trigger trg_espejo_modelo
before insert or update of modelo_id, modelo on public.unidades
for each row execute function public.trg_espejo_modelo();

-- destructivo-ok: DROP de un TRIGGER (objeto de definicion), no de datos.
drop trigger if exists trg_espejo_modelo on public.modelos_villa;
-- destructivo-ok: clausula DDL del trigger, no un UPDATE de filas.
create trigger trg_espejo_modelo
before insert or update of modelo_id, modelo on public.modelos_villa
for each row execute function public.trg_espejo_modelo();


/* Renombrar un modelo propaga POR ID, igual que renombrar un proyecto. Lo que
   NO se toca: el texto ya impreso dentro de un documento congelado. Aquí no hace
   falta excluirlo explícitamente porque el nombre del modelo no viaja a
   `contratos.datos` — si algún día lo hace, esta función es donde hay que
   añadir el filtro por `bloqueado`, igual que trg_proyecto_renombrado. */
create or replace function public.trg_modelo_renombrado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.nombre is not distinct from old.nombre then return new; end if;
  update public.unidades      set modelo = new.nombre where modelo_id = new.id;
  update public.modelos_villa set modelo = new.nombre where modelo_id = new.id;
  return new;
end $$;

revoke all on function public.trg_modelo_renombrado() from public, anon, authenticated;

-- destructivo-ok: DROP de un TRIGGER (objeto de definicion), no de datos.
drop trigger if exists trg_modelo_renombrado on public.modelos;
-- destructivo-ok: clausula DDL del trigger, no un UPDATE de filas.
create trigger trg_modelo_renombrado after update of nombre on public.modelos
for each row execute function public.trg_modelo_renombrado();


/* ---------------------------------------------------------------------------
   7. La cascada, resuelta en un solo sitio.
   ---------------------------------------------------------------------------
   Devuelve lo que la app debe PROPONER al elegir modelo en una unidad. No
   escribe nada: quien decide es la pantalla, y lo ya escrito en la unidad manda.
   Vive en la base y no en JS porque lo van a preguntar tres sitios (el
   formulario de la unidad, el de contratos y la web) y tres implementaciones de
   una cascada de tres niveles son tres formas de que no coincidan.
   --------------------------------------------------------------------------- */
create or replace function public.modelo_precio_construccion(p_modelo_id uuid, p_proyecto_id uuid default null)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select mv.precio_construccion from public.modelos_villa mv
      where mv.modelo_id = p_modelo_id and mv.proyecto_id = p_proyecto_id
        and mv.precio_construccion is not null),
    (select m.precio_construccion from public.modelos m where m.id = p_modelo_id)
  )
$$;

revoke all on function public.modelo_precio_construccion(uuid, uuid) from public, anon;
grant execute on function public.modelo_precio_construccion(uuid, uuid) to authenticated;


/* ---------------------------------------------------------------------------
   8. Lo que NO casa se ve. Es la diferencia entre un dato roto que alguien
      puede arreglar y uno que nadie sabrá nunca que está roto.
   --------------------------------------------------------------------------- */
create or replace view public.modelos_sin_catalogar as
select u.proyecto,
       u.modelo                       as nombra_a,
       count(*)                       as unidades,
       count(u.contrato_id)           as con_contrato,
       min(u.precio_construccion)     as precio_min,
       max(u.precio_construccion)     as precio_max
  from public.unidades u
 where public.modelo_norm(u.modelo) is not null
   and u.modelo_id is null
 group by 1, 2;

alter view public.modelos_sin_catalogar set (security_invoker = true);
grant select on public.modelos_sin_catalogar to authenticated;

comment on view public.modelos_sin_catalogar is
  'Unidades que nombran un modelo sin enlace al catálogo. Al cerrar esta migración las únicas ahí dentro son, a propósito, las 81 de Sumba Hills bajo «Dream»: dos bloques con precio distinto (109.000 y 95.000) que el owner decidió el 7-sep revisar con el cliente antes de unificar.';


/* ---------------------------------------------------------------------------
   9. Lo que ve la web. Y solo lo que ve la web.
   ---------------------------------------------------------------------------
   La web pública pasa a leer de aquí (decisión del owner, 7-sep: fuente única
   desde el día 1), y eso obliga a acotar qué sale. NO sale:
     · `modelos_villa` entera — son los precios PACTADOS por proyecto, negocio
       interno. Que la web lea el catálogo no puede convertirse en que un
       anónimo descubra a cuánto se vendió en Tamarind.
     · `notas`, ni nada de `unidades`, `clients` o `contratos`.
     · Los modelos con `publicado = false`.
   Se sirve como FUNCIÓN y no como tabla con policy `anon`, siguiendo el
   precedente de `unidades_estado_publico` (6-ago): una función devuelve
   columnas elegidas a mano, así que una columna nueva en la tabla no se publica
   sola el día que alguien la añada. Con una policy de tabla, sí.
   --------------------------------------------------------------------------- */
create or replace function public.catalogo_publico()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.slug, x.ficha), '{}'::jsonb)
    from (
      select m.slug,
             jsonb_strip_nulls(jsonb_build_object(
               'nombre',             m.nombre,
               'dormitorios',        m.dormitorios,
               'banos',              m.banos,
               'villa_m2',           m.villa_m2,
               'terraza_m2',         m.terraza_m2,
               'sub',                m.descripcion,
               'moneda',             m.moneda,
               'desde',              m.precio_construccion,
               'renders_pendientes', nullif(m.renders_pendientes, false),
               'techos', (select jsonb_object_agg(t.clave, jsonb_build_object(
                                   'nombre', t.nombre, 'desc', t.descripcion,
                                   'now',    t.precio_ahora, 'y2027', t.precio_2027))
                            from public.modelo_techos t where t.modelo_id = m.id),
               'extras', (select jsonb_object_agg(e.clave, me.precio)
                            from public.modelo_extras me
                            join public.extras e on e.id = me.extra_id
                           where me.modelo_id = m.id and me.disponible and e.activo)
             )) as ficha
        from public.modelos m
       where m.publicado and m.activo
       order by m.orden nulls last, m.nombre
    ) x
$$;

revoke all on function public.catalogo_publico() from public;
grant execute on function public.catalogo_publico() to anon, authenticated;

comment on function public.catalogo_publico() is
  'Lo único del catálogo que ve un anónimo: modelos publicados, con specs, techos y extras. Nunca notas, ni precios por proyecto (modelos_villa), ni nada de unidades. Declarada en departamentos/seguridad/rls_publico.txt.';
