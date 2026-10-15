-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Notas en la ficha de la parcela (owner, 15-oct-2026: «En proyectos, en detalle de parcela mete unas notas»).
-- Hasta hoy: un único texto `unidades.notas` que se pisaba al editar (sin autor, sin fecha); 19 parcelas lo usaban (medido
-- el 15-oct). Ahora: un historial por parcela, calco de cliente_notas (20261015075011), con lo cerrado en la revisión
-- previa #376 (Backend, Seguridad, Frontend; contrato v2):
--  · Autor por id y fecha del servidor; nadie edita una nota: se retira (BORRA el texto + traza sin texto) y se escribe otra.
--  · LEER Y ESCRIBIR: solo quien puede EDITAR esa parcela, con la regla EXACTA de unidad_guarda viva
--    (`_puede_editar_proyectos() and _puede_herr_o_super_empresa('unidades')` + `es_manager_de(proyecto de la parcela)`),
--    y además ver la parcela (_unidad_ficha_ve, por la RLS de unidades). Motivo: regla del owner del 1-oct (agentes y
--    sales_manager solo leen Proyectos) y Seguridad midió que «ver la parcela» basta para leer nombres de compradores
--    sin ver su contrato. Reversible (CEO por defecto): aflojar _unidad_notas_editor.
--  · RETIRAR: su autor, un admin global o el admin de la empresa de la parcela; quien no ve la parcela recibe «no existe».
--  · `unidad_notas_datos` corre con dueño lw_lector (patrón LAW-338): las filas salen bajo la RLS de unidades. lw_lector NO
--    puede ejecutar `_puede_editar_proyectos` ni `admin_de_cliente` (medido el 15-oct con has_function_privilege): el
--    permiso va en funciones DEFINER aparte (_unidad_notas_editor, _unidad_notas_admin, _cliente_notas_admin), dueño
--    postgres, execute solo a lw_lector; no se amplía el execute de las dos funciones vivas.
--  · `cliente_notas_datos` se reemplaza para devolver además `autor_nombre` y `puede_retirar` por nota (la pieza de
--    pantalla compartida deja de necesitar LW_ROL y el mapa por email). Conserva TODAS sus claves (autor_email incluida):
--    la pantalla vieja sigue funcionando hasta que salga la nueva. `puede_retirar` copia la regla de cliente_nota_retira
--    viva (autor, es_admin(), admin_de_cliente(…, true)); cliente_nota_retira NO se toca, y la prueba U16 comprueba que la
--    bandera coincide con lo que hace la llamada real.
--  · `autor_nombre` sale por la RLS de usuarios para lw_lector («el equipo se ve entre sí»): si quien lee no puede ver la
--    ficha del autor sale null y la pantalla dice «sin autor». Prueba U7c: un admin de empresa ve el nombre de un admin global.
--  · TODOS los que escriben `unidades.notas` (unidad_guarda alta y edición, unidades_importa alta y actualización) quedan
--    cerrados con un disparador: lo que llegue pasa al historial (origen 'campo_notas', autor = quien llama, mismo tope de 30
--    en 10 minutos que unidad_nota_agrega: una pestaña vieja que reimporte un CSV con notas aborta limpio en vez de
--    duplicarlas) y la columna queda null. Y `check (notas is null)` en unidades: no hay dos sitios con el mismo texto.
--  · Borrar una parcela (borrar_unidad, único borrador) borra sus notas con traza 'ficha_borrada'. Clave ajena diferible,
--    no cascade: el borrado lo hace el disparador con traza, nunca en silencio.
--  · unidades_log NO se toca (18 filas con textos viejos; reescribir un registro de auditoría es destruir datos). Desde
--    aquí sus filas nuevas llevan notas null (prueba U13). Las 3 notas que ya no están en la columna no se resucitan.
--  · Las 19 notas vigentes pasan al historial con origen 'antigua', SIN autor y con la fecha de HOY (no se inventa otra).
--  · Lectores de la columna que siguen vivos: la vista unidades_estado (sale null; no se toca, lección 2-sep).
-- destructivo-ok: vacía `unidades.notas` SOLO después de copiar cada texto al historial en la misma transacción (19 filas
--   medidas el 15-oct, condición previa); el resto crea tablas, funciones y disparadores nuevos y reemplaza cliente_notas_datos
--   (sus claves de antes siguen). Las funciones nuevas contienen `delete from` de unidad_notas, detrás de su marca.
-- REVERTIR: supabase/reversion_unidad_notas/REVERSION.sql (quita el check y el disparador, devuelve TODAS las notas de cada
--   parcela a unidades.notas antes de borrar las tablas y repone literal cliente_notas_datos).
--   Ensayada en rama: supabase/pruebas/unidad_notas_reversion.sql.
set local lock_timeout = '5s';

do $pre$
declare n_notas int;
begin
  -- la que se reemplaza (cuerpo literal en la REVERSION)
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public.cliente_notas_datos(uuid)'::regprocedure) <> '4942e7bd0e0f91a49ef479929711e4d5' then
    raise exception 'cliente_notas_datos viva no es la del 15-oct (md5 4942e7bd…): alguien la cambió después; revisar a mano';
  end if;
  -- las que se CALCAN sin tocarlas: si cambiaron, la regla copiada aquí puede haberse quedado vieja
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public.unidad_guarda(uuid,jsonb,text)'::regprocedure) <> 'd9c60540ff28a23d9ad51560db8fcc4e' then
    raise exception 'unidad_guarda viva no es la del 15-oct (md5 d9c60540…): revisar que _unidad_notas_editor sigue siendo su regla';
  end if;
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public.cliente_nota_retira(bigint,text)'::regprocedure) <> '3ca7240883af471fe77f9f4552165f48' then
    raise exception 'cliente_nota_retira viva no es la del 15-oct (md5 3ca72408…): revisar que _cliente_notas_admin sigue siendo su regla';
  end if;
  -- las notas que pasan: 19 medidas el 15-oct, ninguna de más de 4000 (el check de unidad_notas las rechazaría).
  -- Una rama de ensayo de Lawang restaura la estructura SIN filas (erp/rama_prueba.py --lawang): con unidades vacía no hay
  -- nada que contar y el paso 8 mueve 0; en la viva (cientos de parcelas) el recuento exacto es obligatorio.
  select count(*) into n_notas from public.unidades u where u.notas is not null;
  if exists (select 1 from public.unidades)
     and (n_notas <> 19 or (select count(*) from public.unidades u where nullif(btrim(u.notas), '') is not null) <> 19) then
    raise exception 'unidades.notas tiene % notas, no las 19 medidas el 15-oct: alguien escribió o borró una; volver a medir', n_notas;
  end if;
  -- de sesión (false), no de transacción: en la rama el fichero va por psql -f sentencia a sentencia y $post$ es otra
  perform set_config('unidad_notas.migradas', n_notas::text, false);   -- lo comprueba $post$
  if exists (select 1 from public.unidades u where char_length(btrim(u.notas)) > 4000) then
    raise exception 'hay una nota de parcela de más de 4000 caracteres: no cabe en el historial; revisar a mano';
  end if;
  -- vaciar la columna dispara trg_unidad_precio_suma en cada fila: si alguna tuviera precio <> suelo + construcción,
  -- vaciar sus notas le cambiaría el precio sin que nadie lo pida (0 medidas el 15-oct)
  if exists (select 1 from public.unidades u
              where u.notas is not null and (u.precio_suelo is not null or u.precio_construccion is not null)
                and u.precio is distinct from coalesce(u.precio_suelo, 0) + coalesce(u.precio_construccion, 0)) then
    raise exception 'hay parcelas con notas cuyo precio no es suelo + construcción: vaciar sus notas lo recalcularía';
  end if;
  if to_regclass('public.unidad_notas') is not null or to_regprocedure('public._unidad_ficha_ve(uuid)') is not null then
    raise exception 'unidad_notas ya existe: esta migración ya se aplicó';
  end if;
end $pre$;

-- ── 1. tablas ─────────────────────────────────────────────────────────────────────────────────────────────────────
create table public.unidad_notas (
  id        bigint generated always as identity primary key,
  -- diferible: el disparador de unidades (abajo) crea la nota en el BEFORE INSERT de una parcela que aún no está escrita
  unidad_id uuid not null references public.unidades(id) deferrable initially deferred,
  texto     text not null check (char_length(btrim(texto)) between 1 and 4000),
  autor_id  uuid references public.usuarios(user_id),
  origen    text not null default 'nota' check (origen in ('nota', 'campo_notas', 'antigua')),
  creado_en timestamptz not null default now(),
  constraint unidad_notas_nota_con_autor check (origen <> 'nota' or autor_id is not null)
);
create index unidad_notas_unidad_idx on public.unidad_notas (unidad_id, creado_en desc);
create index unidad_notas_autor_idx  on public.unidad_notas (autor_id);

create table public.unidad_notas_retiradas (
  id              bigint generated always as identity primary key,
  cuando          timestamptz not null default now(),
  nota_id         bigint not null,   -- sin-fk-ok: la nota se borra al retirarla; la traza guarda su id (como cliente_notas_retiradas)
  unidad_id       uuid not null,     -- sin-fk-ok: la parcela puede borrarse y la traza se queda (como cliente_notas_retiradas)
  autor_id        uuid references public.usuarios(user_id),
  retirada_por_id uuid references public.usuarios(user_id),   -- null: la borró un proceso sin sesión (service_role)
  motivo          text not null check (motivo in ('dato_sensible', 'rectificacion', 'oposicion', 'autoridad', 'otro', 'ficha_borrada'))
);
create index unidad_notas_retiradas_unidad_idx on public.unidad_notas_retiradas (unidad_id);
create index unidad_notas_retiradas_autor_idx  on public.unidad_notas_retiradas (autor_id);
create index unidad_notas_retiradas_por_idx    on public.unidad_notas_retiradas (retirada_por_id);

alter table public.unidad_notas           enable row level security;
alter table public.unidad_notas_retiradas enable row level security;
revoke all on public.unidad_notas, public.unidad_notas_retiradas from public, anon, authenticated, service_role, lw_lector;
revoke all on sequence public.unidad_notas_id_seq, public.unidad_notas_retiradas_id_seq from public, anon, authenticated, service_role, lw_lector;
-- solo lee lw_lector, y solo las notas de las parcelas que la RLS de unidades le deja ver a quien llama (patrón LAW-338);
-- la regla de EDITOR la pone unidad_notas_datos antes de leer
grant select on public.unidad_notas to lw_lector;
create policy "notas: las de las parcelas que ves" on public.unidad_notas for select to lw_lector
  using (exists (select 1 from public.unidades u where u.id = unidad_notas.unidad_id));

-- inmutables: ni UPDATE ni DELETE ni TRUNCATE, salvo el borrado de las funciones de aquí (marca local de la transacción)
create function public._unidad_notas_inmutable() returns trigger
language plpgsql set search_path = '' as $f$
begin
  if tg_op = 'DELETE' and coalesce(current_setting('unidad_notas.borra', true), '') = 'on' then
    return old;
  end if;
  raise exception '% no se edita ni se borra a mano: una nota se retira (unidad_nota_retira)', tg_table_name using errcode = '42501';
end $f$;
revoke all on function public._unidad_notas_inmutable() from public, anon, authenticated, service_role;
create trigger trg_unidad_notas_inmutable before update or delete on public.unidad_notas
  for each row execute function public._unidad_notas_inmutable();
create trigger trg_unidad_notas_no_truncate before truncate on public.unidad_notas
  for each statement execute function public._unidad_notas_inmutable();

create function public._unidad_notas_retiradas_solo_anade() returns trigger
language plpgsql set search_path = '' as $f$
begin
  raise exception 'unidad_notas_retiradas es de solo añadir' using errcode = '42501';
end $f$;
revoke all on function public._unidad_notas_retiradas_solo_anade() from public, anon, authenticated, service_role;
create trigger trg_unidad_notas_retiradas_solo_anade before update or delete on public.unidad_notas_retiradas
  for each row execute function public._unidad_notas_retiradas_solo_anade();
create trigger trg_unidad_notas_retiradas_no_truncate before truncate on public.unidad_notas_retiradas
  for each statement execute function public._unidad_notas_retiradas_solo_anade();

-- ── 2. ¿ve quien llama la parcela? La MISMA regla que la policy SELECT de unidades (dueño lw_lector) ─────────────────
create function public._unidad_ficha_ve(p_unidad uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from public.unidades u where u.id = p_unidad)
$f$;
grant create on schema public to lw_lector;
alter function public._unidad_ficha_ve(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public._unidad_ficha_ve(uuid) from public, anon, authenticated, service_role;

-- ── 3. permisos que lw_lector no puede calcular solo (dueño postgres, execute SOLO a lw_lector) ─────────────────────
-- ¿puede quien llama EDITAR esta parcela? Calco literal de las dos puertas de unidad_guarda viva (md5 d9c60540… en la
-- condición previa): `_puede_editar_proyectos() and _puede_herr_o_super_empresa('unidades')` y, sobre la fila,
-- `found and es_manager_de(v_old.proyecto_id)`. No exige ver la parcela: eso lo añade quien la llama con _unidad_ficha_ve.
create function public._unidad_notas_editor(p_unidad uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select public.uid_sesion() is not null
     and public._puede_editar_proyectos() and public._puede_herr_o_super_empresa('unidades')
     and exists (select 1 from public.unidades u where u.id = p_unidad and public.es_manager_de(u.proyecto_id))
$f$;
revoke all on function public._unidad_notas_editor(uuid) from public, anon, authenticated, service_role;
grant execute on function public._unidad_notas_editor(uuid) to lw_lector;

-- ¿es quien llama admin de esta parcela? (retira cualquier nota suya). Lo usan unidad_nota_retira y la bandera
-- puede_retirar de unidad_notas_datos: una sola regla, no dos copias.
create function public._unidad_notas_admin(p_unidad uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select public.es_admin() or public.es_admin_de(public.empresa_de_unidad(p_unidad))
$f$;
revoke all on function public._unidad_notas_admin(uuid) from public, anon, authenticated, service_role;
grant execute on function public._unidad_notas_admin(uuid) to lw_lector;

-- ¿es quien llama admin de esta ficha de cliente? Copia de la condición de cliente_nota_retira viva (md5 3ca72408… en la
-- condición previa): `es_admin() or admin_de_cliente(client, true)`. lw_lector no puede ejecutar admin_de_cliente.
create function public._cliente_notas_admin(p_client uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select public.es_admin() or public.admin_de_cliente(p_client, true)
$f$;
revoke all on function public._cliente_notas_admin(uuid) from public, anon, authenticated, service_role;
grant execute on function public._cliente_notas_admin(uuid) to lw_lector;

-- ── 4. leer: las notas de una parcela (llamador: intranet/v4 ficha de la parcela, ficha-parcela.js) ───────────────────
create function public.unidad_notas_datos(p_unidad uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb; n int;
  v_uid uuid := public.uid_sesion();
  v_adm boolean;
begin
  if v_uid is null then
    raise exception 'unidad_notas_datos: sin sesión' using errcode = '42501';
  end if;
  -- no ver la parcela y no poder editarla dicen lo mismo (42501, no lista vacía): la pantalla esconde la tarjeta
  if p_unidad is null or not public._unidad_ficha_ve(p_unidad) or not public._unidad_notas_editor(p_unidad) then
    raise exception 'No puedes ver las notas de esta parcela' using errcode = '42501';
  end if;
  v_adm := public._unidad_notas_admin(p_unidad);   -- una vez por llamada, no por nota
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'texto', x.texto, 'origen', x.origen, 'creado_en', x.creado_en,
                                               'autor_id', x.autor_id, 'autor_nombre', x.autor_nombre,
                                               'puede_retirar', coalesce(x.autor_id = v_uid, false) or v_adm)
                            order by x.rn) filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
    into v, n
    from (select un.id, un.texto, un.origen, un.creado_en, un.autor_id, nullif(btrim(u.nombre), '') as autor_nombre,
                 row_number() over (order by un.creado_en desc, un.id desc) as rn
            from public.unidad_notas un
            left join public.usuarios u on u.user_id = un.autor_id
           where un.unidad_id = p_unidad
           order by un.creado_en desc, un.id desc limit 501) x;
  return jsonb_build_object('notas', v, 'recortado', n > 500);
end $$;
grant create on schema public to lw_lector;
alter function public.unidad_notas_datos(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.unidad_notas_datos(uuid) from public, anon, service_role;
grant execute on function public.unidad_notas_datos(uuid) to authenticated;

-- ── 5. escribir: añadir (llamador: intranet/v4 ficha de la parcela) ──────────────────────────────────────────────────
create function public.unidad_nota_agrega(p_unidad uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := public.uid_sesion();
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id    bigint;
  v_en    timestamptz;
begin
  if v_uid is null or not public.es_agente()
     or not exists (select 1 from public.usuarios u where u.user_id = v_uid and u.activo) then
    raise exception 'Sin permiso para escribir notas' using errcode = '42501';
  end if;
  if p_unidad is null or not public._unidad_ficha_ve(p_unidad) or not public._unidad_notas_editor(p_unidad) then
    raise exception 'Esa parcela no existe o no puedes escribir notas en ella' using errcode = '42501';
  end if;
  if v_texto = '' then
    raise exception 'La nota está vacía' using errcode = '22023';
  end if;
  if char_length(v_texto) > 4000 then
    raise exception 'La nota pasa de 4000 caracteres' using errcode = '22023';
  end if;
  if (select count(*) from public.unidad_notas n where n.autor_id = v_uid and n.creado_en > now() - interval '10 minutes') >= 30 then
    raise exception 'Demasiadas notas seguidas: espera unos minutos' using errcode = '54000';
  end if;
  insert into public.unidad_notas (unidad_id, texto, autor_id, origen)
       values (p_unidad, v_texto, v_uid, 'nota')
    returning id, creado_en into v_id, v_en;
  return jsonb_build_object('id', v_id, 'creado_en', v_en);
end $$;
revoke all on function public.unidad_nota_agrega(uuid, text) from public, anon, service_role;
grant execute on function public.unidad_nota_agrega(uuid, text) to authenticated;

-- ── 6. escribir: retirar = BORRAR el texto + traza sin texto (llamador: intranet/v4 ficha de la parcela) ─────────────
create function public.unidad_nota_retira(p_nota bigint, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.uid_sesion();
  v_n   public.unidad_notas;
begin
  if v_uid is null or not public.es_agente() then
    raise exception 'Sin permiso para retirar notas' using errcode = '42501';
  end if;
  if p_motivo is null or p_motivo not in ('dato_sensible', 'rectificacion', 'oposicion', 'autoridad', 'otro') then
    raise exception 'Motivo no válido' using errcode = '22023';
  end if;
  select * into v_n from public.unidad_notas n where n.id = p_nota for update;
  -- «no existe» y «no ves la parcela» dicen lo mismo, ANTES del permiso: los ids son correlativos y no se pueden sondear
  if not found or not public._unidad_ficha_ve(v_n.unidad_id) then
    raise exception 'Esa nota no existe' using errcode = 'P0002';
  end if;
  -- coalesce: con autor_id nulo (las 'antigua', o las que entran sin sesión) «null = v_uid» es NULL (lección de cliente_notas)
  if not (coalesce(v_n.autor_id = v_uid, false) or public._unidad_notas_admin(v_n.unidad_id)) then
    raise exception 'Solo su autor o un administrador puede retirar esta nota' using errcode = '42501';
  end if;
  perform set_config('unidad_notas.borra', 'on', true);
  delete from public.unidad_notas where id = v_n.id;
  perform set_config('unidad_notas.borra', '', true);
  insert into public.unidad_notas_retiradas (nota_id, unidad_id, autor_id, retirada_por_id, motivo)
       values (v_n.id, v_n.unidad_id, v_n.autor_id,
               (select u.user_id from public.usuarios u where u.user_id = v_uid), p_motivo);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.unidad_nota_retira(bigint, text) from public, anon, service_role;
grant execute on function public.unidad_nota_retira(bigint, text) to authenticated;

-- ── 7. cliente_notas_datos: además autor_nombre y puede_retirar (todas las claves de antes siguen) ─────────────────
-- Cuerpo anterior literal en la REVERSION. CREATE OR REPLACE conserva el dueño lw_lector y los grants; se repiten abajo.
create or replace function public.cliente_notas_datos(p_client uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb; n int;
  v_uid uuid := public.uid_sesion();
  v_adm boolean;
begin
  if v_uid is null then
    raise exception 'cliente_notas_datos: sin sesión' using errcode = '42501';
  end if;
  v_adm := public._cliente_notas_admin(p_client);   -- una vez por llamada; la regla de cliente_nota_retira
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'texto', x.texto, 'origen', x.origen, 'creado_en', x.creado_en,
                                               'autor_id', x.autor_id, 'autor_email', x.autor_email,
                                               'autor_nombre', x.autor_nombre,
                                               'puede_retirar', coalesce(x.autor_id = v_uid, false) or v_adm)
                            order by x.rn) filter (where x.rn <= 500), '[]'::jsonb), count(*)::int
    into v, n
    from (select cn.id, cn.texto, cn.origen, cn.creado_en, cn.autor_id, u.email as autor_email,
                 nullif(btrim(u.nombre), '') as autor_nombre,
                 row_number() over (order by cn.creado_en desc, cn.id desc) as rn
            from public.cliente_notas cn
            left join public.usuarios u on u.user_id = cn.autor_id
           where cn.client_id = p_client
           order by cn.creado_en desc, cn.id desc limit 501) x;
  return jsonb_build_object('notas', v, 'recortado', n > 500);
end $$;
grant create on schema public to lw_lector;
alter function public.cliente_notas_datos(uuid) owner to lw_lector;
revoke create on schema public from lw_lector;
revoke all on function public.cliente_notas_datos(uuid) from public, anon, service_role;
grant execute on function public.cliente_notas_datos(uuid) to authenticated;

-- ── 8. las 19 notas vigentes pasan al historial, ANTES del disparador de unidades ─────────────────────────────────
insert into public.unidad_notas (unidad_id, texto, autor_id, origen)
select u.id, btrim(u.notas), null, 'antigua'
  from public.unidades u
 where nullif(btrim(coalesce(u.notas, '')), '') is not null;
update public.unidades set notas = null where notas is not null;

-- ── 9. todo lo que escriba en unidades.notas pasa al historial (unidad_guarda, unidades_importa y lo que venga) ──────
create function public._unidades_notas_a_historial() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare
  v_t   text := nullif(btrim(coalesce(new.notas, '')), '');
  v_uid uuid := public.uid_sesion();
begin
  if v_t is not null and (tg_op = 'INSERT' or new.notas is distinct from old.notas) then
    -- como unidad_nota_agrega: de más se rechaza, no se recorta en silencio
    if char_length(v_t) > 4000 then
      raise exception 'La nota es demasiado larga (máximo 4000 caracteres).' using errcode = '22023';
    end if;
    -- el mismo tope que unidad_nota_agrega: una pestaña vieja que reimporta un CSV con notas aborta entera, no las duplica
    if v_uid is not null and (select count(*) from public.unidad_notas n
                               where n.autor_id = v_uid and n.creado_en > now() - interval '10 minutes') >= 30 then
      raise exception 'Demasiadas notas seguidas: espera unos minutos' using errcode = '54000';
    end if;
    insert into public.unidad_notas (unidad_id, texto, autor_id, origen)
         values (new.id, v_t, (select u.user_id from public.usuarios u where u.user_id = v_uid), 'campo_notas');
  end if;
  new.notas := null;
  return new;
end $f$;
revoke all on function public._unidades_notas_a_historial() from public, anon, authenticated, service_role;
create trigger trg_unidades_notas_a_historial before insert or update of notas on public.unidades
  for each row execute function public._unidades_notas_a_historial();

-- ── 10. borrar una parcela borra sus notas, con traza (borrar_unidad) ─────────────────────────────────────────────
create function public._unidades_notas_al_borrar() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_uid uuid := public.uid_sesion();
begin
  insert into public.unidad_notas_retiradas (nota_id, unidad_id, autor_id, retirada_por_id, motivo)
  select n.id, n.unidad_id, n.autor_id, (select u.user_id from public.usuarios u where u.user_id = v_uid), 'ficha_borrada'
    from public.unidad_notas n where n.unidad_id = old.id;
  perform set_config('unidad_notas.borra', 'on', true);
  delete from public.unidad_notas where unidad_id = old.id;
  perform set_config('unidad_notas.borra', '', true);
  return old;
end $f$;
revoke all on function public._unidades_notas_al_borrar() from public, anon, authenticated, service_role;
create trigger trg_unidades_notas_al_borrar before delete on public.unidades
  for each row execute function public._unidades_notas_al_borrar();

-- ── 11. la columna vieja ya no guarda texto: lo garantiza la base, no solo el disparador ───────────────────────────
-- ALTER TABLE no se deja hacer sobre una tabla con eventos de disparador diferidos pendientes en la transacción (unidades
-- tiene disparadores de restricción diferidos, y la clave ajena nueva lo es): se resuelven antes.
set constraints all immediate;
alter table public.unidades add constraint unidades_notas_al_historial check (notas is null);

do $post$
begin
  if (select count(*) from public.unidad_notas where origen = 'antigua') <> coalesce(nullif(current_setting('unidad_notas.migradas', true), ''), '-1')::int
     or exists (select 1 from public.unidades where notas is not null) then
    raise exception 'el paso de las notas al historial no cuadra (esperadas %): se deshace todo', current_setting('unidad_notas.migradas', true);
  end if;
end $post$;
