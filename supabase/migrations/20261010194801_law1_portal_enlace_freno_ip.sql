-- LAW-1 S1 bis (11-oct-2026): freno POR IP del formulario anónimo del portal, motivo del frenazo y purga de lo viejo.
-- Encargo: encargos/20261011_lawang_portal_enlace_por_correo.md (repo de la agencia). Lo pide Seguridad en la consulta del
-- revisor sobre S2/S3 (punto 2) y Datos/CEO (purga del correo normalizado). No edita 20261010182058, que ya está aplicada:
-- la reemplaza con una función de firma nueva.
--
-- POR QUÉ:
--   · Por IP: con solo «60 s y 5/h por correo» y «30/h global», una sola máquina puede pedir el enlace para 30 compradores
--     distintos en una hora: cada enlace nuevo invalida el que el comprador ya tenía, y el tope global deja sin enlace a los
--     compradores de verdad el resto de la hora. Como mucho 5 enlaces por hora desde una misma IP (solo el formulario
--     anónimo, origen 'autoservicio'; un admin que invita en tandas va con sesión y no pasa por aquí).
--   · Motivo: la función devolvía true/false y la edge no podía distinguir «frenado por tope global» (la señal de que alguien
--     está martilleando el formulario, o de que 30/h se queda corto) de un frenado normal por correo. Ahora devuelve texto
--     de lista cerrada: 'pasa' | 'correo' | 'ip' | 'global' | 'invalido' ('liberado' con p_libera). La respuesta al navegador
--     sigue siendo la misma en todos los casos: eso lo decide la edge.
--   · Purga: el correo normalizado se quedaba para siempre en `portal_enlaces_envios` aunque sus marcas ya no contaran. Las
--     reglas solo miran la última hora: una fila (correo o IP) cuya última escritura tiene más de 1 h no sirve para nada y se
--     borra al pasar por la función (con el candado puesto). La del correo/IP de la llamada en curso no se toca.
--
-- POR QUÉ SE BORRA LA FUNCIÓN VIEJA (y no se deja al lado): la firma cambia (parámetro p_ip_hash y devuelve texto), y dos
-- funciones con el mismo nombre y argumentos con valor por defecto son ambiguas para PostgREST. Medido el 11-oct-2026 antes de
-- aplicar: `portal_enlaces_envios` tenía 1 fila ('*') y 0 marcas, es decir, la función vieja NO la ha llamado nadie en
-- producción (las edges que la usan, S2, no están publicadas: portal-invitar v22 publicada aún usa signInWithOtp). Sin
-- llamador, fuera (reducir la exposición). No guarda datos.
-- destructivo-ok: DROP de portal_enlace_freno(text,text,boolean) sin ningún llamador (0 marcas medidas el 11-oct-2026), y DELETE
-- dentro de la función nueva que solo purga marcas de ritmo de más de 1 h de las dos tablas del freno; ninguna tabla de clientes.
--
-- LA IP NO SE GUARDA EN CLARO: la edge manda HMAC-SHA256 (clave = la service_role de la edge, etiqueta propia
-- 'lawang-portal-acceso-ip:'), 64 hex. Un sha256 sin clave de una IPv4 se deshace probando las 4.300 millones de IPs; con la
-- clave, no. Y la fila dura como mucho 1 h después de su última petición (purga de arriba).
--
-- DUEÑO DEL DATO: estas dos tablas son la única fuente del ritmo de envíos del enlace del portal; nadie más las lee ni las
-- copia. `portal_enlaces_envios`: una fila por correo con derecho que pidió enlace en la última hora + la fila '*' del global
-- (que no se purga). `portal_enlaces_ip`: una fila por IP (hash) que pidió un enlace con derecho en la última hora. Ninguna
-- crece: cada fila guarda solo sus marcas de la última hora, y las filas sin actividad en 1 h se borran.
--
-- SUPERFICIE: tablas con RLS activada, SIN políticas y sin permisos para nadie (ni anon, ni authenticated, ni service_role:
-- solo las toca la función DEFINER). La función: solo service_role (las dos edges). search_path vacío.
--
-- VUELTA ATRÁS (a mano y con el OK del owner; las edges deben volver a su versión anterior a la vez):
--   drop function public.portal_enlace_freno(text, text, text, boolean);
--   drop table public.portal_enlaces_ip;
--   y reponer la función de 20261010182058 (su cuerpo está en ese fichero).

create table if not exists public.portal_enlaces_ip (
  ip_hash        text primary key,
  envios         timestamptz[] not null default '{}',
  actualizado_at timestamptz   not null default now(),
  constraint portal_enlaces_ip_hash_ck check (ip_hash ~ '^[0-9a-f]{64}$'),
  constraint portal_enlaces_ip_tope_ck check (cardinality(envios) <= 60)
);
comment on table public.portal_enlaces_ip is
  'LAW-1: marcas de la última hora de enlaces del portal pedidos desde cada IP (HMAC, nunca la IP en claro). Solo la escribe portal_enlace_freno(); filas sin actividad en 1 h se purgan.';

alter table public.portal_enlaces_ip enable row level security;
revoke all on table public.portal_enlaces_ip from public, anon, authenticated, service_role;

drop function if exists public.portal_enlace_freno(text, text, boolean);

create or replace function public.portal_enlace_freno(
  p_email   text,
  p_origen  text,
  p_ip_hash text    default null,
  p_libera  boolean default false
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_min_seg    constant int := 60;   -- segundos mínimos entre dos envíos al mismo correo
  c_max_correo constant int := 5;    -- envíos por correo en la última hora
  c_max_ip     constant int := 5;    -- envíos del formulario anónimo por IP en la última hora
  c_max_global constant int := 30;   -- envíos del formulario anónimo en la última hora (techo)
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_ip     text := nullif(btrim(coalesce(p_ip_hash, '')), '');
  v_ahora  timestamptz;
  v_desde  timestamptz;
  v_mio    timestamptz[];
  v_ipm    timestamptz[] := '{}';
  v_global timestamptz[];
  v_anonimo boolean;
begin
  if p_origen is null or p_origen not in ('autoservicio', 'invitar') then
    raise exception 'portal_enlace_freno: origen no válido' using errcode = '22023';
  end if;
  v_anonimo := (p_origen = 'autoservicio');
  if not v_anonimo then
    v_ip := null;   -- un admin no cuenta por IP
  elsif v_ip is not null and v_ip !~ '^[0-9a-f]{64}$' then
    raise exception 'portal_enlace_freno: ip_hash no válido' using errcode = '22023';
  end if;
  if length(v_email) not between 3 and 320 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return 'invalido';
  end if;

  -- Un solo candado para todo el freno (clave fija, la misma de 20261010182058): serializa también el global y la IP.
  perform pg_advisory_xact_lock(7316402251001);
  v_ahora := clock_timestamp();   -- la hora DESPUÉS de esperar el candado
  v_desde := v_ahora - interval '1 hour';

  -- Purga: filas sin actividad en la última hora (sus marcas ya no cuentan). Nunca la global ni las de esta llamada.
  delete from public.portal_enlaces_envios
   where clave <> '*' and clave <> v_email and actualizado_at < v_desde;
  delete from public.portal_enlaces_ip
   where ip_hash is distinct from v_ip and actualizado_at < v_desde;

  insert into public.portal_enlaces_envios (clave) values (v_email) on conflict (clave) do nothing;
  select coalesce(array_agg(e order by e), '{}') into v_mio
    from public.portal_enlaces_envios f, unnest(f.envios) e
   where f.clave = v_email and e > v_desde;
  select coalesce(array_agg(e order by e), '{}') into v_global
    from public.portal_enlaces_envios f, unnest(f.envios) e
   where f.clave = '*' and e > v_desde;
  if v_ip is not null then
    insert into public.portal_enlaces_ip (ip_hash) values (v_ip) on conflict (ip_hash) do nothing;
    select coalesce(array_agg(e order by e), '{}') into v_ipm
      from public.portal_enlaces_ip f, unnest(f.envios) e
     where f.ip_hash = v_ip and e > v_desde;
  end if;

  if p_libera then
    -- Devuelve el último hueco: quita la marca más reciente del correo y, si era del formulario, también la global y la de la IP.
    if cardinality(v_mio) > 0 then
      update public.portal_enlaces_envios
         set envios = v_mio[1:cardinality(v_mio) - 1], actualizado_at = v_ahora
       where clave = v_email;
      if v_anonimo and cardinality(v_global) > 0 then
        update public.portal_enlaces_envios
           set envios = v_global[1:cardinality(v_global) - 1], actualizado_at = v_ahora
         where clave = '*';
      end if;
      if v_ip is not null and cardinality(v_ipm) > 0 then
        update public.portal_enlaces_ip
           set envios = v_ipm[1:cardinality(v_ipm) - 1], actualizado_at = v_ahora
         where ip_hash = v_ip;
      end if;
    end if;
    return 'liberado';
  end if;

  if cardinality(v_mio) > 0 and v_mio[cardinality(v_mio)] > v_ahora - make_interval(secs => c_min_seg) then
    return 'correo';
  end if;
  if cardinality(v_mio) >= c_max_correo then
    return 'correo';
  end if;
  if v_ip is not null and cardinality(v_ipm) >= c_max_ip then
    return 'ip';
  end if;
  if v_anonimo and cardinality(v_global) >= c_max_global then
    return 'global';
  end if;

  update public.portal_enlaces_envios
     set envios = v_mio || v_ahora, actualizado_at = v_ahora
   where clave = v_email;
  if v_anonimo then
    update public.portal_enlaces_envios
       set envios = v_global || v_ahora, actualizado_at = v_ahora
     where clave = '*';
  end if;
  if v_ip is not null then
    update public.portal_enlaces_ip
       set envios = v_ipm || v_ahora, actualizado_at = v_ahora
     where ip_hash = v_ip;
  end if;
  return 'pasa';
end;
$$;

comment on function public.portal_enlace_freno(text, text, text, boolean) is
  'LAW-1: ''pasa'' = puede enviarse el enlace del portal (y queda anotado); ''correo''|''ip''|''global''|''invalido'' = frenado y por qué. p_libera devuelve el hueco de un envío fallido (''liberado''). Solo service_role (edges portal-acceso y portal-invitar).';

revoke all     on function public.portal_enlace_freno(text, text, text, boolean) from public, anon, authenticated;
grant  execute on function public.portal_enlace_freno(text, text, text, boolean) to service_role;
