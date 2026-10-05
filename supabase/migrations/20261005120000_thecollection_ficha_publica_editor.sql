-- destructivo-ok: UN update de datos, el de las fichas con precio_modo 'desde'/'consultar' que arrastran un precio_eur que nadie lee (hoy solo palm-field-bali, 31250): se pone a NULL porque el «desde» tiene un solo dueño (coleccion_publica() lo deriva de las unidades). Nada se borra; el trigger deja la fila de log con el valor anterior. El resto solo crea/reemplaza funciones, un indice y un CHECK.
-- THE COLLECTION v2 · F3a — backend de la pestaña «Ficha pública» de la intranet (editor). 5-oct-2026.
-- Encargo: encargos/20261002_lawang_thecollection_v2.md (F3). Contrato revisado por Datos + Seguridad + Desarrollo.
-- Base: 20261002120000 (esquema + ficha_publica_guarda v1) y 20261002150000 / 20261005101500 (coleccion_publica, que define qué claves de
-- `ficha`/`textos` se leen). Sin pareja en erp/migraciones/ (Lawang es independiente del maestro).
--
-- Qué cambia, con su porqué:
--   1. ficha_publica_guarda (text,jsonb) → (text,jsonb,timestamptz) returns jsonb {id,slug,version}. La v1 REEMPLAZABA `textos` y `ficha`
--      enteros: guardar solo «equipamiento» borraba imagenes/downloads/diseno. Ahora `textos`/`ficha` en p_cambios son PARCHES que el
--      SERVIDOR mezcla por clave de primer nivel (y `textos` además por idioma): editar `es` no pisa `en`; un null borra la clave.
--      p_version (= actualizado_en que devolvió `lee`) da concurrencia optimista: si la fila cambió desde que se leyó → 40001 «recárgala».
--      p_version null = sin control (alta, o scripts de servidor): la pantalla DEBE mandarlo siempre al editar.
--   2. `_ficha_valida(textos, ficha)`: lista blanca EXACTA de claves, tipos con jsonb_typeof, topes de tamaño y rechazo de `<`/`>` y de
--      URLs que no sean https:// o /ruta. El navegador no es de fiar (máxima del owner 26-sep): la SPA ya escapa, pero el servidor no
--      depende de eso. La lógica vive en `_ficha_error` (SQL puro, devuelve el primer problema o null) para poder probarla sin escribir.
--      La migración comprueba que las 12 fichas actuales pasan (si no, aborta sin tocar nada).
--   3. Vínculos: unidad_id debe ser de proyecto_id; modelo_id debe estar en modelos_villa de ese proyecto. PUBLICAR (false→true) exige
--      proyecto, título EN y ES y, con precio fijo, importe > 0. Despublicar siempre se puede (aunque la ficha haya perdido el proyecto
--      por ON DELETE SET NULL). Indice único PARCIAL sobre unidad_id (sustituye al indice simple, que queda redundante; comprobado: 0 duplicados).
--   4. CHECK ficha_publicada_completa relajado: el importe solo se exige con precio_modo 'fijo'. Con 'desde'/'consultar' guarda pone
--      precio_eur a NULL (un solo dueño del «desde»). Los errores de CHECK llegan a la UI como 23514 con mensaje en español.
--   5. ficha_publica_lee(p_proyecto_id): TODAS las fichas del proyecto (también las no publicadas) + `publico` (el trozo de
--      coleccion_publica() para esa ficha, o null si hoy no se sirve: un solo dueño del cálculo, aquí NO se reimplementa precio/«desde»),
--      + unidades y modelos para vincular. No hay `lista` (sin llamador: reducir la exposición).
--   Seguridad de ambas RPC: SECURITY DEFINER, search_path vacío, es_admin() dentro (42501), revoke de public/anon, grant a
--   authenticated y service_role. `_ficha_valida` y `_ficha_error` sin grants a nadie (las llama guarda, que corre como dueño).
--
-- Llamadores con nombre: ficha_publica_guarda y ficha_publica_lee → pestaña «Ficha pública» de intranet/v4/proyectos (F3b).
-- ROLLBACK (en este orden):
--   drop function public.ficha_publica_lee(uuid);
--   drop function public.ficha_publica_guarda(text, jsonb, timestamptz);
--   (volver a aplicar ficha_publica_guarda(text,jsonb) de 20261002120000, con su revoke/grant);
--   drop function public._ficha_valida(jsonb, jsonb); drop function public._ficha_error(jsonb, jsonb);
--   drop index public.fichas_publicas_unidad_uq; create index fichas_publicas_unidad_idx on public.fichas_publicas (unidad_id);
--   alter table public.fichas_publicas drop constraint ficha_publicada_completa, y volver a crearla con la definición de 20261002120000.
--   (el precio_eur de palm-field-bali, 31250, queda en fichas_publicas_log.antes si hiciera falta devolverlo.)

-- ── 0. Guardas previas ───────────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if exists (select 1 from public.fichas_publicas where unidad_id is not null group by unidad_id having count(*) > 1) then
    raise exception 'Hay dos fichas con la misma unidad_id: resolverlo a mano antes del indice unico';
  end if;
end $guarda$;

-- ── 1. Validador de forma (SQL puro: devuelve el primer problema o null) ─────────────────────────────────────────────────────────
create or replace function public._ficha_error(p_textos jsonb, p_ficha jsonb)
  returns text
  language sql immutable set search_path to ''
  as $v$
with t as (
  select case when jsonb_typeof(p_textos) = 'object' then p_textos else '{}'::jsonb end as t,
         case when jsonb_typeof(p_ficha)  = 'object' then p_ficha  else '{}'::jsonb end as f
),
lst as (   -- todos los elementos de las listas de primer nivel de `ficha` (tope 200: las demasiado largas ya se rechazan aparte)
  select e.k, a.v
    from t, jsonb_each(t.f) e(k, v),
         jsonb_array_elements(case when jsonb_typeof(e.v) = 'array' and jsonb_array_length(e.v) <= 200 then e.v else '[]'::jsonb end) a(v)
),
eq as (select q.k, q.v from t, jsonb_each(case when jsonb_typeof(t.f->'equipamiento') = 'object' then t.f->'equipamiento' else '{}'::jsonb end) q(k, v)),
dz as (select q.k, q.v from t, jsonb_each(case when jsonb_typeof(t.f->'diseno') = 'object' then t.f->'diseno' else '{}'::jsonb end) q(k, v)),
tb as (    -- pestañas del diseño (max 12)
  select a.v from dz, jsonb_array_elements(case when dz.k = 'tabs' and jsonb_typeof(dz.v) = 'array' and jsonb_array_length(dz.v) <= 12 then dz.v else '[]'::jsonb end) a(v)
),
ae as (select q.k, q.v from t, jsonb_each(case when jsonb_typeof(t.f->'aerial') = 'object' then t.f->'aerial' else '{}'::jsonb end) q(k, v)),
hs as (    -- puntos del aereo (max 20)
  select a.v from ae, jsonb_array_elements(case when ae.k = 'hotspots' and jsonb_typeof(ae.v) = 'array' and jsonb_array_length(ae.v) <= 20 then ae.v else '[]'::jsonb end) a(v)
)
select c.msg from (
  -- forma general
            select 'Los textos de la ficha no tienen forma de objeto' as msg where jsonb_typeof(p_textos) is distinct from 'object'
  union all select 'Los datos de la ficha no tienen forma de objeto' where jsonb_typeof(p_ficha) is distinct from 'object'
  union all select 'La ficha es demasiado grande' where char_length(p_textos::text) > 30000 or char_length(p_ficha::text) > 150000
  union all select 'Los textos son texto plano: no admiten los signos < ni >' where (p_textos::text || p_ficha::text) ~ '[<>]'
  -- textos: {clave: {en, es}}
  union all select 'Texto no permitido: «' || k || '»' from t, jsonb_object_keys(t.t) k
            where k <> all (array['title', 'sub', 'desc', 'meta', 'split_title', 'split_sub'])
  union all select 'El texto «' || e.k || '» debe llevar sus dos idiomas (en, es)' from t, jsonb_each(t.t) e(k, v) where jsonb_typeof(e.v) <> 'object'
  union all select 'El texto «' || e.k || '» solo admite los idiomas en y es (' || l.k || ')'
              from t, jsonb_each(t.t) e(k, v), jsonb_each(case when jsonb_typeof(e.v) = 'object' then e.v else '{}'::jsonb end) l(k, w)
             where l.k not in ('en', 'es')
  union all select 'El texto «' || e.k || '» (' || l.k || ') debe ser texto'
              from t, jsonb_each(t.t) e(k, v), jsonb_each(case when jsonb_typeof(e.v) = 'object' then e.v else '{}'::jsonb end) l(k, w)
             where jsonb_typeof(l.w) <> 'string'
  union all select 'El texto «' || e.k || '» (' || l.k || ') supera el máximo de caracteres'
              from t, jsonb_each(t.t) e(k, v), jsonb_each(case when jsonb_typeof(e.v) = 'object' then e.v else '{}'::jsonb end) l(k, w)
             where jsonb_typeof(l.w) = 'string'
               and char_length(l.w #>> '{}') > case e.k when 'title' then 120 when 'split_title' then 120 when 'desc' then 3000 else 200 end
  -- ficha: claves y tipos de primer nivel
  union all select 'Dato de ficha no permitido: «' || k || '»' from t, jsonb_object_keys(t.f) k
            where k <> all (array['highlights', 'tech_specs', 'equipamiento', 'view', 'handover', 'mapa_url', 'masterplan_imagen', 'masterplan_pins',
                                  'payment_plan', 'videos', 'aerial', 'downloads', 'imagenes', 'diseno'])
  union all select '«' || e.k || '» debe ser una lista' from t, jsonb_each(t.f) e(k, v)
            where e.k in ('highlights', 'tech_specs', 'imagenes', 'videos', 'downloads', 'payment_plan', 'masterplan_pins') and jsonb_typeof(e.v) <> 'array'
  union all select '«' || e.k || '» tiene demasiados elementos' from t, jsonb_each(t.f) e(k, v)
            where jsonb_typeof(e.v) = 'array'
              and jsonb_array_length(e.v) > case e.k when 'highlights' then 20 when 'tech_specs' then 20 when 'imagenes' then 60 when 'videos' then 10
                                                     when 'downloads' then 20 when 'payment_plan' then 12 when 'masterplan_pins' then 200 else 60 end
  union all select '«' || e.k || '» debe ser un objeto' from t, jsonb_each(t.f) e(k, v)
            where e.k in ('equipamiento', 'diseno', 'aerial') and jsonb_typeof(e.v) <> 'object'
  union all select '«' || e.k || '» debe ser texto y no pasar del máximo' from t, jsonb_each(t.f) e(k, v)
            where e.k in ('view', 'handover', 'mapa_url', 'masterplan_imagen')
              and (jsonb_typeof(e.v) <> 'string'
                   or char_length(e.v #>> '{}') > case e.k when 'view' then 60 when 'handover' then 40 when 'mapa_url' then 500 else 300 end)
  union all select '«' || e.k || '» debe ser una dirección https:// o una ruta del servidor' from t, jsonb_each(t.f) e(k, v)
            where e.k in ('mapa_url', 'masterplan_imagen') and jsonb_typeof(e.v) = 'string'
              and (e.v #>> '{}') !~ '^(https://[^\s"''\\]+|/[^/\s"''\\][^\s"''\\]*|)$'
  -- listas de textos / URLs
  union all select 'Cada punto destacado debe ser un texto de hasta 160 caracteres' from lst
            where k = 'highlights' and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 160)
  union all select 'Cada «' || k || '» debe ser una dirección https:// o una ruta del servidor (hasta 300 caracteres)' from lst
            where k in ('imagenes', 'videos')
              and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 300 or (v #>> '{}') !~ '^(https://[^\s"''\\]+|/[^/\s"''\\][^\s"''\\]*|)$')
  -- listas de objetos: forma y claves
  union all select 'Cada elemento de «' || k || '» debe ser un objeto' from lst
            where k in ('tech_specs', 'downloads', 'payment_plan', 'masterplan_pins') and jsonb_typeof(v) <> 'object'
  union all select 'Dato no permitido en «' || lst.k || '»: ' || kk
              from lst, jsonb_object_keys(case when jsonb_typeof(lst.v) = 'object' then lst.v else '{}'::jsonb end) kk
             where kk <> all (case lst.k when 'tech_specs' then array['l', 'v'] when 'downloads' then array['ext', 'url', 'name', 'size']
                                         when 'payment_plan' then array['step', 'pct', 'label', 'note'] when 'masterplan_pins' then array['code', 'x', 'y'] end)
  union all select 'Cada celda técnica necesita rótulo (hasta 40) y valor (hasta 120), ambos texto' from lst
            where k = 'tech_specs' and jsonb_typeof(v) = 'object'
              and (jsonb_typeof(v->'l') is distinct from 'string' or jsonb_typeof(v->'v') is distinct from 'string'
                   or char_length(v->>'l') > 40 or char_length(v->>'v') > 120)
  union all select 'Cada descarga necesita nombre (hasta 120) y una dirección https:// o ruta del servidor; ext (10) y size (20) son texto opcional' from lst
            where k = 'downloads' and jsonb_typeof(v) = 'object'
              and (jsonb_typeof(v->'name') is distinct from 'string' or char_length(v->>'name') > 120
                   or jsonb_typeof(v->'url') is distinct from 'string' or char_length(v->>'url') > 300
                   or (v->>'url') !~ '^(https://[^\s"''\\]+|/[^/\s"''\\][^\s"''\\]*)$'
                   or coalesce(jsonb_typeof(v->'ext'), 'string') <> 'string' or char_length(v->>'ext') > 10
                   or coalesce(jsonb_typeof(v->'size'), 'string') <> 'string' or char_length(v->>'size') > 20)
  union all select 'Cada paso del plan de pago necesita un porcentaje (0-100) y un rótulo; paso es un número y nota es texto (hasta 300)' from lst
            where k = 'payment_plan' and jsonb_typeof(v) = 'object'
              and (jsonb_typeof(v->'pct') is distinct from 'number'
                   or not (case when jsonb_typeof(v->'pct') = 'number' then (v->>'pct')::numeric between 0 and 100 else false end)
                   or coalesce(jsonb_typeof(v->'step'), 'number') <> 'number'
                   or jsonb_typeof(v->'label') is distinct from 'string' or char_length(v->>'label') > 200
                   or coalesce(jsonb_typeof(v->'note'), 'string') <> 'string' or char_length(v->>'note') > 300)
  union all select 'Cada pin del masterplan necesita código (hasta 40) y posición x, y entre 0 y 100' from lst
            where k = 'masterplan_pins' and jsonb_typeof(v) = 'object'
              and (jsonb_typeof(v->'code') is distinct from 'string' or char_length(v->>'code') > 40
                   or jsonb_typeof(v->'x') is distinct from 'number' or jsonb_typeof(v->'y') is distinct from 'number'
                   or not (case when jsonb_typeof(v->'x') = 'number' then (v->>'x')::numeric between 0 and 100 else false end)
                   or not (case when jsonb_typeof(v->'y') = 'number' then (v->>'y')::numeric between 0 and 100 else false end))
  -- equipamiento
  union all select 'Equipamiento no permitido: «' || k || '»' from eq where k <> all (array['pool', 'poolType', 'garage', 'garageDesc', 'furnished', 'style'])
  union all select 'Equipamiento «' || k || '» debe ser sí/no' from eq where k in ('pool', 'garage') and jsonb_typeof(v) <> 'boolean'
  union all select 'Equipamiento «' || k || '» debe ser texto de hasta 80 caracteres' from eq
            where k in ('poolType', 'garageDesc', 'furnished', 'style') and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 80)
  -- diseño
  union all select 'Diseño no permitido: «' || k || '»' from dz where k <> all (array['tabs', 'logo', 'isotype', 'landColor', 'splitImage', 'bleedImage', 'plan3dImage'])
  union all select 'Las pestañas del diseño deben ser una lista de hasta 12' from dz
            where k = 'tabs' and (jsonb_typeof(v) <> 'array' or jsonb_array_length(v) > 12)
  union all select 'Diseño «' || k || '» debe ser una dirección https:// o una ruta del servidor (hasta 300 caracteres)' from dz
            where k in ('logo', 'isotype', 'splitImage', 'bleedImage', 'plan3dImage')
              and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 300 or (v #>> '{}') !~ '^(https://[^\s"''\\]+|/[^/\s"''\\][^\s"''\\]*|)$')
  union all select 'Diseño «landColor» debe ser texto de hasta 30 caracteres' from dz
            where k = 'landColor' and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 30)
  union all select 'Cada pestaña del diseño debe ser un objeto' from tb where jsonb_typeof(v) <> 'object'
  union all select 'Pestaña del diseño: dato no permitido «' || kk || '»'
              from tb, jsonb_object_keys(case when jsonb_typeof(tb.v) = 'object' then tb.v else '{}'::jsonb end) kk
             where kk <> all (array['title', 'sub', 'body', 'beds', 'baths', 'built', 'land', 'images'])
  union all select 'Pestaña del diseño: «' || f.k || '» debe llevar {en, es} de texto, hasta ' || f.mx || ' caracteres'
              from tb, (values ('title', 120), ('sub', 200), ('body', 3000)) f(k, mx)
             where jsonb_typeof(tb.v) = 'object' and tb.v -> f.k is not null
               and (jsonb_typeof(tb.v -> f.k) <> 'object'
                    or exists (select 1 from jsonb_each(case when jsonb_typeof(tb.v -> f.k) = 'object' then tb.v -> f.k else '{}'::jsonb end) l(k, w)
                                where l.k not in ('en', 'es') or jsonb_typeof(l.w) <> 'string' or char_length(l.w #>> '{}') > f.mx))
  union all select 'Pestaña del diseño: «' || n.k || '» debe ser un número entre 0 y 100000'
              from tb, (values ('beds'), ('baths'), ('built'), ('land')) n(k)
             where jsonb_typeof(tb.v) = 'object' and tb.v -> n.k is not null
               and (jsonb_typeof(tb.v -> n.k) <> 'number'
                    or not (case when jsonb_typeof(tb.v -> n.k) = 'number' then (tb.v ->> n.k)::numeric between 0 and 100000 else false end))
  union all select 'Pestaña del diseño: «images» debe ser una lista de hasta 40 direcciones https:// o rutas del servidor (300 caracteres)'
              from tb
             where jsonb_typeof(tb.v) = 'object' and tb.v -> 'images' is not null
               and (jsonb_typeof(tb.v -> 'images') <> 'array'
                    or jsonb_array_length(tb.v -> 'images') > 40
                    or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(tb.v -> 'images') = 'array' and jsonb_array_length(tb.v -> 'images') <= 40
                                                                       then tb.v -> 'images' else '[]'::jsonb end) im(v)
                                where jsonb_typeof(im.v) <> 'string' or char_length(im.v #>> '{}') > 300
                                   or (im.v #>> '{}') !~ '^(https://[^\s"''\\]+|/[^/\s"''\\][^\s"''\\]*|)$'))
  -- aéreo
  union all select 'Aéreo no permitido: «' || k || '»' from ae where k <> all (array['image', 'entryPriceEUR', 'hotspots'])
  union all select 'Aéreo «image» debe ser una dirección https:// o una ruta del servidor (hasta 300 caracteres)' from ae
            where k = 'image' and (jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 300 or (v #>> '{}') !~ '^(https://[^\s"''\\]+|/[^/\s"''\\][^\s"''\\]*|)$')
  union all select 'Aéreo «entryPriceEUR» debe ser un número entre 0 y 1000000000' from ae
            where k = 'entryPriceEUR' and (jsonb_typeof(v) <> 'number' or not (case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric between 0 and 1000000000 else false end))
  union all select 'Aéreo «hotspots» debe ser una lista de hasta 20' from ae where k = 'hotspots' and (jsonb_typeof(v) <> 'array' or jsonb_array_length(v) > 20)
  union all select 'Cada punto del aéreo debe ser un objeto' from hs where jsonb_typeof(v) <> 'object'
  union all select 'Punto del aéreo: dato no permitido «' || kk || '»'
              from hs, jsonb_object_keys(case when jsonb_typeof(hs.v) = 'object' then hs.v else '{}'::jsonb end) kk
             where kk <> all (array['x', 'y', 'side', 'en', 'es'])
  union all select 'Cada punto del aéreo necesita x e y (0-100); lado (top, left o right) opcional' from hs
            where jsonb_typeof(v) = 'object'
              and (jsonb_typeof(v->'x') is distinct from 'number' or jsonb_typeof(v->'y') is distinct from 'number'
                   or not (case when jsonb_typeof(v->'x') = 'number' then (v->>'x')::numeric between 0 and 100 else false end)
                   or not (case when jsonb_typeof(v->'y') = 'number' then (v->>'y')::numeric between 0 and 100 else false end)
                   or (v ? 'side' and (jsonb_typeof(v->'side') <> 'string' or (v->>'side') not in ('top', 'left', 'right'))))
  union all select 'Punto del aéreo: «' || i.k || '» debe ser {l1, l2} de texto de hasta 80 caracteres'
              from hs, (values ('en'), ('es')) i(k)
             where jsonb_typeof(hs.v) = 'object' and hs.v -> i.k is not null
               and (jsonb_typeof(hs.v -> i.k) <> 'object'
                    or exists (select 1 from jsonb_each(case when jsonb_typeof(hs.v -> i.k) = 'object' then hs.v -> i.k else '{}'::jsonb end) l(k, w)
                                where l.k not in ('l1', 'l2') or jsonb_typeof(l.w) <> 'string' or char_length(l.w #>> '{}') > 80))
) c
limit 1
$v$;
revoke all on function public._ficha_error(jsonb, jsonb) from public, anon, authenticated, service_role;

create or replace function public._ficha_valida(p_textos jsonb, p_ficha jsonb)
  returns void
  language plpgsql immutable set search_path to ''
  as $$
declare m text := public._ficha_error(p_textos, p_ficha);
begin
  if m is not null then raise exception '%', m using errcode = '22023'; end if;
end $$;
revoke all on function public._ficha_valida(jsonb, jsonb) from public, anon, authenticated, service_role;
comment on function public._ficha_valida(jsonb, jsonb) is
  'Validación de forma de textos/ficha de fichas_publicas (The Collection v2, F3a). Sin grants: la llama ficha_publica_guarda (DEFINER). La lógica está en _ficha_error.';

-- ── 2. Verificación: las fichas que YA existen pasan el validador (si no, aborta la migración entera, sin tocar datos) ─────────────
do $ver$
declare f record; m text;
begin
  for f in select slug, textos, ficha from public.fichas_publicas loop
    m := public._ficha_error(f.textos, f.ficha);
    if m is not null then
      raise exception 'La ficha existente % no pasa _ficha_valida: %', f.slug, m;
    end if;
  end loop;
end $ver$;

-- ── 3. Datos, indice y CHECK ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- (El CHECK viejo exige precio_eur también con 'desde': hay que quitarlo antes de poner a NULL el de palm-field-bali.)
alter table public.fichas_publicas drop constraint if exists ficha_publicada_completa;

update public.fichas_publicas set precio_eur = null where precio_modo in ('desde', 'consultar') and precio_eur is not null;

alter table public.fichas_publicas add constraint ficha_publicada_completa check (
  not publicada_web or (
    (precio_modo <> 'fijo' or precio_eur is not null)
    and nullif(btrim(textos #>> '{title,en}'), '') is not null));

create unique index if not exists fichas_publicas_unidad_uq on public.fichas_publicas (unidad_id) where unidad_id is not null;
drop index if exists public.fichas_publicas_unidad_idx;

-- ── 4. ficha_publica_guarda v2 ────────────────────────────────────────────────────────────────────────────────────────────────────
drop function if exists public.ficha_publica_guarda(text, jsonb);

create or replace function public.ficha_publica_guarda(p_slug text, p_cambios jsonb, p_version timestamptz default null)
  returns jsonb
  language plpgsql security definer set search_path to ''
  as $$
declare
  v_ok  text[] := array['linea', 'region_key', 'region', 'publicada_web', 'en_coleccion', 'destacada', 'destacada_home', 'orden',
                        'proyecto_id', 'modelo_id', 'unidad_id', 'precio_modo', 'precio_eur', 'tenure', 'lease_years', 'estado_obra',
                        'dormitorios', 'banos', 'construido_m2', 'parcela_m2', 'textos', 'ficha'];
  v_old    public.fichas_publicas%rowtype;
  v_new    public.fichas_publicas%rowtype;
  v_slug   text := lower(btrim(coalesce(p_slug, '')));
  v_nueva  boolean := false;
  v_textos jsonb;
  v_ficha  jsonb;
  v_m      jsonb;
  v_ver    timestamptz;
  k text; w jsonb; l text; x jsonb;
  v_c text;
begin
  if not public.es_admin() then
    raise exception 'La ficha pública la edita administración' using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(v_slug) not between 3 and 60 then
    raise exception 'La dirección solo admite minúsculas, números y guiones (de 3 a 60)' using errcode = '22023';
  end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then
    raise exception 'Datos de la ficha no válidos' using errcode = '22023';
  end if;
  if char_length(p_cambios::text) > 200000 then
    raise exception 'La ficha es demasiado grande' using errcode = '22023';
  end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if not (k = any (v_ok)) then
      raise exception 'Ese dato de la ficha no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  for k in select e.key from jsonb_each(p_cambios) e where jsonb_typeof(e.value) = 'null'
                                                       and e.key in ('linea', 'region_key', 'publicada_web', 'en_coleccion', 'destacada', 'destacada_home', 'orden', 'precio_modo', 'textos', 'ficha') loop
    raise exception 'Ese dato de la ficha no puede quedar vacío: %', k using errcode = '22023';
  end loop;
  if p_cambios ? 'textos' and jsonb_typeof(p_cambios->'textos') <> 'object' then
    raise exception 'Los textos se envían como un objeto con las claves a cambiar' using errcode = '22023';
  end if;
  if p_cambios ? 'ficha' and jsonb_typeof(p_cambios->'ficha') <> 'object' then
    raise exception 'Los datos de ficha se envían como un objeto con las claves a cambiar' using errcode = '22023';
  end if;

  select * into v_old from public.fichas_publicas f where f.slug = v_slug for update;
  if not found then
    if p_version is not null then
      raise exception 'Esa ficha ya no existe; recarga la pantalla' using errcode = '40001';
    end if;
    if not (p_cambios ? 'linea' and p_cambios ? 'region_key') then
      raise exception 'Una ficha nueva necesita línea y región (bali o sumba)' using errcode = '22023';
    end if;
    if p_cambios ? 'publicada_web' and (p_cambios->>'publicada_web') is distinct from 'false' then
      raise exception 'Una ficha nueva nace sin publicar: créala y publícala después' using errcode = '22023';
    end if;
    begin
      insert into public.fichas_publicas (slug, linea, region_key)
      values (v_slug, p_cambios->>'linea', p_cambios->>'region_key')
      returning * into v_old;
    exception
      when unique_violation then
        raise exception 'Otra persona acaba de crear esa ficha; recárgala' using errcode = '40001';
      when check_violation then
        raise exception 'La línea debe ser signature, villa o land y la región bali o sumba' using errcode = '23514';
    end;
    v_nueva := true;
  elsif p_version is not null and v_old.actualizado_en is distinct from p_version then
    raise exception 'Otra persona cambió esta ficha; recárgala' using errcode = '40001';
  end if;

  -- MEZCLA POR CLAVE (en el servidor, nunca reemplazo entero). Un valor null en el parche borra esa clave.
  v_textos := v_old.textos;
  if p_cambios ? 'textos' then
    for k, w in select * from jsonb_each(p_cambios->'textos') loop
      if jsonb_typeof(w) = 'null' then
        v_textos := v_textos - k;
      elsif jsonb_typeof(w) = 'object' then
        v_m := case when jsonb_typeof(v_textos->k) = 'object' then v_textos->k else '{}'::jsonb end;
        for l, x in select * from jsonb_each(w) loop
          v_m := case when jsonb_typeof(x) = 'null' then v_m - l else v_m || jsonb_build_object(l, x) end;
        end loop;
        v_textos := case when v_m = '{}'::jsonb then v_textos - k else v_textos || jsonb_build_object(k, v_m) end;
      else
        v_textos := v_textos || jsonb_build_object(k, w);   -- el validador lo rechaza con su mensaje
      end if;
    end loop;
  end if;
  v_ficha := v_old.ficha;
  if p_cambios ? 'ficha' then
    for k, w in select * from jsonb_each(p_cambios->'ficha') loop
      v_ficha := case when jsonb_typeof(w) = 'null' then v_ficha - k else v_ficha || jsonb_build_object(k, w) end;
    end loop;
  end if;
  perform public._ficha_valida(v_textos, v_ficha);

  -- columnas escalares: las ausentes conservan su valor, las presentes lo sustituyen
  begin
    v_new := jsonb_populate_record(v_old, p_cambios - 'textos' - 'ficha');
  exception
    when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch or invalid_parameter_value then
      raise exception 'Algún dato de la ficha tiene un formato no válido (números, fechas o identificadores)' using errcode = '22023';
  end;
  v_new.textos := v_textos;
  v_new.ficha  := v_ficha;
  v_new.region := nullif(btrim(v_new.region), '');
  -- un solo dueño del «desde»: con 'desde' o 'consultar' no se guarda importe (coleccion_publica() lo deriva de las unidades)
  if v_new.precio_modo in ('desde', 'consultar') then v_new.precio_eur := null; end if;

  -- vínculos
  if v_new.proyecto_id is not null and not exists (select 1 from public.proyectos p where p.id = v_new.proyecto_id) then
    raise exception 'Ese proyecto no existe' using errcode = '22023';
  end if;
  -- unidad/modelo solo se comprueban si el vínculo CAMBIA: una ficha que perdió el proyecto por ON DELETE SET NULL debe poder despublicarse
  if v_new.unidad_id is not null
     and (v_new.unidad_id is distinct from v_old.unidad_id or v_new.proyecto_id is distinct from v_old.proyecto_id) then
    if v_new.proyecto_id is null or not exists (select 1 from public.unidades u where u.id = v_new.unidad_id and u.proyecto_id = v_new.proyecto_id) then
      raise exception 'La unidad elegida no pertenece al proyecto de la ficha' using errcode = '22023';
    end if;
    if exists (select 1 from public.fichas_publicas o where o.unidad_id = v_new.unidad_id and o.id <> v_old.id) then
      raise exception 'Esa unidad ya tiene otra ficha pública' using errcode = '22023';
    end if;
  end if;
  if v_new.modelo_id is not null
     and (v_new.modelo_id is distinct from v_old.modelo_id or v_new.proyecto_id is distinct from v_old.proyecto_id)
     and (v_new.proyecto_id is null
          or not exists (select 1 from public.modelos_villa mv where mv.proyecto_id = v_new.proyecto_id and mv.modelo_id = v_new.modelo_id)) then
    raise exception 'El modelo elegido no está entre los modelos de villa del proyecto de la ficha' using errcode = '22023';
  end if;

  -- reglas de lo que ve el cliente (con mensaje legible antes de que salte el CHECK de la base)
  if v_new.precio_modo = 'fijo' and v_new.linea <> 'signature' then
    raise exception 'El precio fijo solo existe en la línea Signature' using errcode = '23514';
  end if;
  if v_new.publicada_web then
    if not v_old.publicada_web and v_new.proyecto_id is null then
      raise exception 'Para publicar la ficha hace falta vincularla a un proyecto' using errcode = '23514';
    end if;
    if nullif(btrim(v_new.textos #>> '{title,en}'), '') is null then
      raise exception 'Para publicar la ficha hace falta el título en inglés' using errcode = '23514';
    end if;
    if not v_old.publicada_web and nullif(btrim(v_new.textos #>> '{title,es}'), '') is null then
      raise exception 'Para publicar la ficha hace falta el título en español' using errcode = '23514';
    end if;
    if v_new.precio_modo = 'fijo' and coalesce(v_new.precio_eur, 0) <= 0 then
      raise exception 'Para publicar con precio fijo hace falta un importe mayor que 0' using errcode = '23514';
    end if;
  end if;

  begin
    update public.fichas_publicas f set
      linea = v_new.linea, region_key = v_new.region_key, region = v_new.region,
      publicada_web = v_new.publicada_web, en_coleccion = v_new.en_coleccion, destacada = v_new.destacada,
      destacada_home = v_new.destacada_home, orden = v_new.orden,
      proyecto_id = v_new.proyecto_id, modelo_id = v_new.modelo_id, unidad_id = v_new.unidad_id,
      precio_modo = v_new.precio_modo, precio_eur = v_new.precio_eur, tenure = v_new.tenure, lease_years = v_new.lease_years,
      estado_obra = v_new.estado_obra, dormitorios = v_new.dormitorios, banos = v_new.banos,
      construido_m2 = v_new.construido_m2, parcela_m2 = v_new.parcela_m2,
      textos = v_new.textos, ficha = v_new.ficha
    where f.id = v_old.id;
  exception
    when unique_violation then
      raise exception 'Otra persona cambió esta ficha a la vez; recárgala' using errcode = '40001';
    when check_violation then
      get stacked diagnostics v_c = constraint_name;
      raise exception 'Algún dato está fuera de rango o falta para guardar la ficha (regla %)', v_c using errcode = '23514';
  end;

  select f.actualizado_en into v_ver from public.fichas_publicas f where f.id = v_old.id;
  return jsonb_build_object('id', v_old.id, 'slug', v_slug,
                            'version', to_char(v_ver at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
end $$;
comment on function public.ficha_publica_guarda(text, jsonb, timestamptz) is
  'Alta/edición de una ficha pública (The Collection v2, F3a). Solo admin/super_admin (comprobado dentro). Lista blanca de claves; el slug no se cambia. textos y ficha son PARCHES mezclados en el servidor por clave (null borra). p_version = actualizado_en leído: si no coincide, 40001. Valida forma (_ficha_valida), vínculos y publicación. Devuelve {id, slug, version}. Llamador: pestaña Ficha pública de intranet/v4/proyectos (F3b).';
revoke all on function public.ficha_publica_guarda(text, jsonb, timestamptz) from public, anon;
grant execute on function public.ficha_publica_guarda(text, jsonb, timestamptz) to authenticated, service_role;

-- ── 5. ficha_publica_lee ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.ficha_publica_lee(p_proyecto_id uuid)
  returns jsonb
  language plpgsql stable security definer set search_path to ''
  as $$
declare
  v_cp jsonb;
begin
  if not public.es_admin() then
    raise exception 'La ficha pública la edita administración' using errcode = '42501';
  end if;
  if not exists (select 1 from public.proyectos p where p.id = p_proyecto_id) then
    raise exception 'Ese proyecto no existe' using errcode = 'P0002';
  end if;
  v_cp := public.coleccion_publica() -> 'properties';   -- «lo que verá el público»: un solo dueño del cálculo
  return jsonb_build_object(
    'proyecto', (select jsonb_build_object('id', p.id, 'slug', p.slug, 'nombre', p.nombre) from public.proyectos p where p.id = p_proyecto_id),
    'fichas', coalesce((
        select jsonb_agg((to_jsonb(f) - 'actualizado_en') || jsonb_build_object(
                 'version', to_char(f.actualizado_en at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
                 'publico', (select x from jsonb_array_elements(v_cp) x where x ->> 'id' = f.slug limit 1))
               order by f.orden, f.slug)
          from public.fichas_publicas f where f.proyecto_id = p_proyecto_id), '[]'::jsonb),
    'unidades', coalesce((
        select jsonb_agg(jsonb_build_object('id', u.id, 'codigo', u.codigo) order by u.codigo_orden nulls last, u.codigo)
          from public.unidades u where u.proyecto_id = p_proyecto_id), '[]'::jsonb),
    'modelos', coalesce((
        select jsonb_agg(jsonb_build_object('id', m.id, 'nombre', m.nombre) order by m.nombre)
          from public.modelos m
         where m.id in (select mv.modelo_id from public.modelos_villa mv where mv.proyecto_id = p_proyecto_id and mv.modelo_id is not null)), '[]'::jsonb));
end $$;
comment on function public.ficha_publica_lee(uuid) is
  'Lectura para la pestaña Ficha pública (The Collection v2, F3a): todas las fichas del proyecto (también no publicadas) con su version y su `publico` (trozo de coleccion_publica(), null si hoy no se sirve), más las unidades y modelos vinculables. Solo admin/super_admin (comprobado dentro). Llamador: intranet/v4/proyectos (F3b).';
revoke all on function public.ficha_publica_lee(uuid) from public, anon;
grant execute on function public.ficha_publica_lee(uuid) to authenticated, service_role;
