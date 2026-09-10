/* CATÁLOGO DE MODELOS — SIEMBRA Y ENGANCHE. 7-sep-2026.
   Fichero canónico con todos los porqués:
   supabase/migrations/20260907191000_catalogo_de_modelos_siembra.sql

   -- destructivo-ok: no hay DROP, DELETE ni TRUNCATE, y todos los UPDATE van
   acotados por WHERE. Lo único que se vacía a propósito son los dos precios de
   Palm Field en `modelos_villa`, que pasan a NULL porque NULL significa «hereda
   del catálogo» — decisión del owner (7-sep, «manda la web»). Su valor anterior
   se guarda antes en `correcciones_datos` Y en la columna `notas` de su propia
   fila, así que no se pierde.
   Ensayado en seco antes de aplicar: 261 unidades se enlazan (76 con contrato),
   157 nombres se normalizan, 18 precios vacíos se rellenan, 81 quedan sin
   enlazar a propósito y nacen 22 precios por proyecto. 261 + 81 = 342. */

insert into public.extras (clave, nombre, descripcion, orden) values
  ('airbnb',   'Airbnb Kit',         null, 1),
  ('zero',     'Zero Chemical Pool', 'Ozone purification, no chlorine', 2),
  ('recovery', 'Recovery',           'Fire & Ice 2 m pools', 3),
  ('sauna',    'Sauna',              '2 × 1.5 m — fits four', 4),
  ('rooftop',  'Rooftop',            'Sofa, BBQ and shade included', 5),
  ('oasis',    'Oasis Pool',         'White cement pool with a beach finish, natural rock and palms', 6),
  ('gym',      'Exterior Gym',       'Three-level pull-up bar, dip bar, dumbbell kit, press bench, flat bench', 7)
on conflict (clave) do nothing;

insert into public.modelos
  (slug, nombre, dormitorios, banos, villa_m2, terraza_m2, descripcion,
   precio_construccion, moneda, publicado, renders_pendientes, orden) values
  ('dali','Dali',1,1,30,17,
   'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
   48000,'EUR',true,false,1),
  ('dune','Dune',1,1,47,30,
   'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
   68000,'EUR',true,false,2),
  ('dream','Dream',2,2,76,49,
   'A 2-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
   101000,'EUR',true,false,3),
  ('trinity','Trinity',3,2,92,35,
   'A 3-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
   121000,'EUR',true,true,4),
  ('temple','Temple',4,3,114,46,
   'A 4-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
   146000,'EUR',true,true,5)
on conflict (slug) do nothing;

insert into public.modelos (slug, nombre, moneda, publicado, orden, notas) values
  ('clan',        'Clan',        'EUR', false, 20, 'Alta automática desde el inventario (7-sep-2026): Tangkuban Village. Sin specs — pendientes del cliente.'),
  ('dali-plus',   'Dali+',       'EUR', false, 21, 'Alta automática desde el inventario (7-sep-2026): Sumba Hills. ¿Es una variante de Dali o un modelo propio? Sin decidir.'),
  ('granada',     'Granada',     'EUR', false, 22, 'Alta automática desde el inventario (7-sep-2026): Pura Dalem.'),
  ('loftbung',    'Loftbung',    'EUR', false, 23, 'Alta automática desde el inventario (7-sep-2026): Horizon S1.'),
  ('mandala',     'Mandala',     'EUR', false, 24, 'Alta automática desde el inventario (7-sep-2026): Java Sunset S2.'),
  ('minimalist',  'Minimalist',  'EUR', false, 25, 'Alta automática desde el inventario (7-sep-2026): Sumba Hills.'),
  ('modernist-c', 'Modernist C', 'IDR', false, 26, 'Alta automática desde el inventario (7-sep-2026): Riverfront II. Precios en RUPIAS.'),
  ('restoration', 'Restoration', 'EUR', false, 27, 'Alta automática desde el inventario (7-sep-2026): Bonian Village. Su única unidad no tiene precio de construcción.'),
  ('tropical',    'Tropical',    'EUR', false, 28, 'Alta automática desde el inventario (7-sep-2026): Sari Village, Tamarind Rise y Sumba Hills.'),
  ('villa-l',     'Villa L',     'IDR', false, 29, 'Alta automática desde el inventario (7-sep-2026): Riverfront I. Precios en RUPIAS.')
on conflict (slug) do nothing;

insert into public.modelo_techos (modelo_id, clave, nombre, descripcion, precio_ahora, precio_2027, orden)
select m.id, t.clave, t.nombre, t.descripcion, t.ahora, t.y2027, t.orden
  from (values
    ('dali','sirap','Sirap Ulin','Ulin wood shingle across the whole roof. The most weather-resistant, lowest-maintenance option.',48000,52000,1),
    ('dali','bambu','Bamboo & Ulin shingle','Bamboo structure combined with ulin wood shingle. Handcrafted character and greater durability.',50000,56000,2),
    ('dune','sirap','Sirap',null,68000,72000,1),
    ('dune','bambu','Bamboo',null,70000,76000,2),
    ('dream','sirap','Sirap',null,101000,109000,1),
    ('dream','bambu','Bamboo',null,106000,119000,2),
    ('trinity','sirap','Sirap',null,121000,129000,1),
    ('trinity','bambu','Bamboo',null,126000,139000,2),
    ('temple','sirap','Sirap',null,146000,159000,1),
    ('temple','bambu','Bamboo',null,151000,169000,2)
  ) as t(slug, clave, nombre, descripcion, ahora, y2027, orden)
  join public.modelos m on m.slug = t.slug
on conflict (modelo_id, clave) do nothing;

insert into public.modelo_extras (modelo_id, extra_id, precio)
select m.id, e.id, p.precio
  from (values
    ('dali','airbnb',5000),('dali','zero',6000),('dali','recovery',9000),('dali','sauna',8000),('dali','rooftop',9000),('dali','oasis',5000),('dali','gym',6000),
    ('dune','airbnb',5000),('dune','zero',6000),('dune','recovery',9000),('dune','sauna',8000),('dune','rooftop',9000),('dune','oasis',5000),('dune','gym',6000),
    ('dream','airbnb',6000),('dream','zero',6000),('dream','recovery',9000),('dream','sauna',8000),('dream','rooftop',9000),('dream','oasis',6000),('dream','gym',6000),
    ('trinity','airbnb',7000),('trinity','zero',6000),('trinity','recovery',9000),('trinity','sauna',8000),('trinity','rooftop',9000),('trinity','oasis',7000),('trinity','gym',6000),
    ('temple','airbnb',8000),('temple','zero',6000),('temple','recovery',9000),('temple','sauna',8000),('temple','rooftop',9000),('temple','oasis',8000),('temple','gym',6000)
  ) as p(slug, clave, precio)
  join public.modelos m on m.slug  = p.slug
  join public.extras  e on e.clave = p.clave
on conflict (modelo_id, extra_id) do nothing;

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'modelos_villa', mv.id, 'precio_construccion', mv.precio_construccion::text, null,
       'Catálogo de modelos (7-sep-2026): pasa a NULL = hereda del catálogo. Decisión del owner «manda la web»: '
       || mv.modelo || ' queda en ' || (select m.precio_construccion::text from public.modelos m
                                         where public.modelo_norm(m.nombre) = public.modelo_norm(mv.modelo))
       || ' EUR. La cifra de aquí (' || mv.precio_construccion::text || ') llevaba sin tocarse desde el 31-jul y '
       || 'era la que precargaba los contratos, 4.000-7.000 EUR por debajo de lo publicado.',
       'migracion catalogo_de_modelos_siembra'
  from public.modelos_villa mv
 where mv.proyecto = 'Palm Field W5' and mv.precio_construccion is not null;

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'unidades', u.id, 'modelo', u.modelo, m.nombre,
       'Catálogo de modelos (7-sep-2026): el nombre pasa a ser espejo del enlace al catálogo.',
       'migracion catalogo_de_modelos_siembra'
  from public.unidades u
  join public.modelos m on public.modelo_norm(m.nombre) = public.modelo_norm(u.modelo)
 where u.modelo_id is null
   and u.modelo is distinct from m.nombre
   and not (u.proyecto = 'Sumba Hills' and public.modelo_norm(u.modelo) = 'dream');

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'unidades', u.id, 'precio', null,
       (coalesce(u.precio_suelo,0) + coalesce(u.precio_construccion,0))::text,
       'Catálogo de modelos (7-sep-2026): efecto de trg_unidad_precio_suma al enlazar el modelo. '
       || 'El total estaba VACÍO con suelo y construcción rellenos — la unidad no se había vuelto a '
       || 'guardar desde que existe la regla «el total es siempre la suma» (28-ago-2026).',
       'migracion catalogo_de_modelos_siembra'
  from public.unidades u
  join public.modelos m on public.modelo_norm(m.nombre) = public.modelo_norm(u.modelo)
 where u.modelo_id is null
   and u.precio is null
   and (u.precio_suelo is not null or u.precio_construccion is not null)
   and not (u.proyecto = 'Sumba Hills' and public.modelo_norm(u.modelo) = 'dream');

update public.modelos_villa mv
   set precio_construccion = null,
       notas = coalesce(mv.notas || ' · ', '')
               || 'Hasta el 7-sep-2026 tenía precio propio ' || mv.precio_construccion::text
               || ' EUR (sembrado el 31-jul del inventario). Pasa a heredar del catálogo por '
               || 'decisión del owner: manda la web.'
 where mv.proyecto = 'Palm Field W5' and mv.precio_construccion is not null;

update public.modelos_villa mv
   set modelo_id = m.id
  from public.modelos m
 where mv.modelo_id is null
   and public.modelo_norm(m.nombre) = public.modelo_norm(mv.modelo);

update public.modelos_villa mv
   set proyecto_id = p.id
  from public.proyectos p
 where mv.proyecto_id is null and p.nombre = mv.proyecto;

update public.unidades u
   set modelo_id = m.id
  from public.modelos m
 where u.modelo_id is null
   and public.modelo_norm(m.nombre) = public.modelo_norm(u.modelo)
   and not (u.proyecto = 'Sumba Hills' and public.modelo_norm(u.modelo) = 'dream');

insert into public.modelos_villa (proyecto, modelo, modelo_id, proyecto_id, precio_construccion, moneda, notas)
select u.proyecto,
       max(m.nombre),
       u.modelo_id,
       u.proyecto_id,
       min(u.precio_construccion),
       coalesce(max(u.moneda), 'EUR'),
       'Sembrado del inventario el 7-sep-2026: las ' || count(*)::text
       || ' unidades de este modelo en este proyecto coinciden en el precio de construcción.'
  from public.unidades u
  join public.modelos m on m.id = u.modelo_id
 where u.precio_construccion is not null
 group by u.proyecto, u.proyecto_id, u.modelo_id
having count(distinct u.precio_construccion) = 1
   and not exists (select 1 from public.modelos_villa mv
                    where mv.modelo_id = u.modelo_id and mv.proyecto = u.proyecto);;
