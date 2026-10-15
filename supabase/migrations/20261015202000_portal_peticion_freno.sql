-- FRENO DEL FORMULARIO DEL PORTAL ANTES DE LA REGLA — 15-oct-2026 (sesión lawang-cola-2, resto 6 de «Invitar al portal»; revisión
-- previa #373 con Backend y Seguridad, que frenó la v1).
--
-- portal-acceso (contracts/edge/portal-acceso/index.ts) es un formulario ANÓNIMO: valida el formato del correo y llamaba directamente
-- a portal_autoservicio (que puede CREAR accesos por regla) y a `usuarios`, sin ningún tope. El freno que ya había
-- (portal_enlace_freno) solo lo alcanza un comprador con derecho. Ahora la edge llama ANTES a portal_peticion_freno(hash de la IP).
--
-- Cómo cuenta (Seguridad #373.1: el orden es lo que impide que una sola máquina cierre el formulario a todos):
--   1. el cubo de la IP (12 bits del HMAC, 4096 cubos; sin IP legible, su propio cubo 4096 «sin_ip»): suma SIEMPRE, también frenado;
--   2. solo si la IP está dentro de su tope suma al total de la hora. Una IP frenada nunca gasta el global.
-- Topes (decisión por defecto, a revisar el 15-nov-2026 con lo que midan las columnas de privado.portal_peticiones_hora):
--   · 20 por hora por cubo de IP. No se baja: detrás del NAT de los operadores móviles (CGNAT, muy común en Indonesia) hay mucha gente
--     con la misma IP.
--   · 1000 por hora en total: es un CORTACIRCUITOS, no el control (el control es el tope por IP). Uno de 300 lo cierra a voluntad
--     cualquiera con 15 IP (Seguridad #373.1). Lo que avisa pronto es la vigilancia (una hora con más de 100 = aviso).
-- Si el tope global salta igualmente, la salida para un comprador es que un admin le invite desde portal-invitar (no pasa por aquí).
--
-- Mide además el tráfico real (Backend #373.3): privado.portal_peticiones_hora guarda por hora cuántas peticiones pasaron su tope de
-- IP (n = la demanda), cuántas frenó cada tope y la IP más activa (max_ip). Lo lee la vigilancia del estudio (erp/salud_instancia.py,
-- chequeo «portal»): un frenazo global es ROJO (puede dejar fuera a compradores), uno por IP es solo informativo.
--
-- Por qué así:
--   · sin delete: tools/no_destruir.py para cualquier delete en Lawang sin la válvula del owner. Las dos tablas son anillos que se
--     reutilizan (la del cubo, 2 franjas horarias × 4097 cubos = como mucho 8194 filas; la de la hora, 768 ranuras = 32 días, como
--     privado.portal_frenos). Una fila con otra hora se reinicia al volver a usarse;
--   · sin pg_advisory_xact_lock (Seguridad #373.5): bajo una inundación pondría todas las llamadas en fila y el freno sería el DoS de
--     la base. Cada contador es un upsert de UNA fila con returning;
--   · la misma llamada anota sus negativas: no hay segunda RPC por petición frenada (Backend #373.4);
--   · el cubo se calcula AQUÍ a partir de un hash validado (64 hex), no lo manda la edge: nadie elige su cubo.
--
-- DUEÑO DEL DATO: portal_peticion_freno (única que escribe en las dos tablas). SUPERFICIE: tablas en `privado` (revocado a todos,
-- 20260927210500), con RLS y sin grant a nadie, ni a service_role; la función, solo service_role, con un llamador con nombre:
-- portal-acceso. Lee: axw_lectura (pg_read_all_data + bypassrls, 20260925140000) desde salud_instancia. No guarda correo, IP ni el
-- hash: cubo, hora y cuentas. Sin serial ni identity: un ensayo deshecho no gasta ninguna serie.
-- ORDEN DE DESPLIEGUE: esta migración ANTES que la edge que la llama (la edge falla cerrada con un 500 si la función no existe).
-- VUELTA ATRÁS: devolver la edge a la versión anterior; la función y las tablas pueden quedarse sin daño (no las llama nadie más).
-- Quitarlas del todo es un DROP: va por la válvula del owner.
--
-- Prueba: supabase/pruebas/portal_peticion_freno.sql (rama).

create table if not exists privado.portal_peticiones_ip (
  franja smallint not null check (franja between 0 and 1),
  cubo   int not null check (cubo between 0 and 4096),
  hora   timestamptz not null,
  n      int not null default 0 check (n >= 0),
  primary key (franja, cubo)
);
alter table privado.portal_peticiones_ip enable row level security;
revoke all on table privado.portal_peticiones_ip from public, anon, authenticated, service_role;
comment on table privado.portal_peticiones_ip is
  'Peticiones al formulario del portal por cubo de IP (12 bits del HMAC; 4096 = sin IP) y hora; anillo de 2 franjas, sin borrados. '
  'Escribe solo public.portal_peticion_freno (edge portal-acceso). 20261015202000.';

create table if not exists privado.portal_peticiones_hora (
  ranura          int primary key check (ranura between 0 and 767),
  hora            timestamptz not null,
  n               int not null default 0 check (n >= 0),
  frenadas_ip     int not null default 0 check (frenadas_ip >= 0),
  frenadas_global int not null default 0 check (frenadas_global >= 0),
  max_ip          int not null default 0 check (max_ip >= 0)
);
alter table privado.portal_peticiones_hora enable row level security;
revoke all on table privado.portal_peticiones_hora from public, anon, authenticated, service_role;
comment on table privado.portal_peticiones_hora is
  'Formulario del portal por hora: n = peticiones dentro de su tope de IP (la demanda y el contador del cortacircuitos global), '
  'frenadas por cada tope y la IP más activa. Anillo de 768 ranuras = 32 días, sin borrados. Escribe solo public.portal_peticion_freno; '
  'lee la vigilancia del estudio (axw_lectura). 20261015202000.';

create or replace function public.portal_peticion_freno(p_ip_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  c_tope_ip     constant int := 20;      -- por cubo de IP y hora (revisar el 15-nov-2026; no bajar: CGNAT)
  c_tope_global constant int := 1000;    -- cortacircuitos por hora, no el control (revisar el 15-nov-2026)
  c_sin_ip      constant int := 4096;    -- el cubo de las peticiones sin IP legible, con su propio tope
  v_ahora  timestamptz := clock_timestamp();                       -- la hora real de la petición, no la del inicio de la transacción
  v_hora   timestamptz := date_trunc('hour', v_ahora, 'UTC');      -- sin depender del huso de la sesión
  v_h      bigint := floor(extract(epoch from v_hora) / 3600)::bigint;
  v_cubo   int;
  v_nip    int;
  v_frena  boolean;
  v_ng     int;
begin
  if p_ip_hash is null then
    v_cubo := c_sin_ip;
  elsif p_ip_hash ~ '^[0-9a-f]{64}$' then
    v_cubo := ('x' || substr(p_ip_hash, 1, 3))::bit(12)::int;
  else
    raise exception 'portal_peticion_freno: hash de IP no válido' using errcode = '22023';
  end if;

  -- 1. el cubo de la IP: suma siempre (también frenado), así una IP que martillea sigue frenada toda la hora
  insert into privado.portal_peticiones_ip as t (franja, cubo, hora, n)
  values ((v_h % 2)::smallint, v_cubo, v_hora, 1)
  on conflict (franja, cubo) do update
     set n    = case when t.hora = excluded.hora then least(t.n, 1000000000) + 1 else 1 end,
         hora = excluded.hora
  returning n into v_nip;
  v_frena := v_nip > c_tope_ip;

  -- 2. la hora: una IP frenada NO suma a n (no gasta el global); en el mismo upsert, las negativas y la IP más activa
  insert into privado.portal_peticiones_hora as h (ranura, hora, n, frenadas_ip, frenadas_global, max_ip)
  values ((v_h % 768)::int, v_hora, case when v_frena then 0 else 1 end, case when v_frena then 1 else 0 end, 0, v_nip)
  on conflict (ranura) do update
     set n               = case when h.hora = excluded.hora then least(h.n, 1000000000) else 0 end + excluded.n,
         frenadas_ip     = case when h.hora = excluded.hora then least(h.frenadas_ip, 1000000000) else 0 end + excluded.frenadas_ip,
         frenadas_global = case when h.hora = excluded.hora then least(h.frenadas_global, 1000000000) else 0 end
                           + case when excluded.n = 1 and case when h.hora = excluded.hora then h.n else 0 end + 1 > c_tope_global
                                  then 1 else 0 end,
         max_ip          = greatest(case when h.hora = excluded.hora then h.max_ip else 0 end, excluded.max_ip),
         hora            = excluded.hora
  returning n into v_ng;

  if v_frena then return 'ip'; end if;
  if v_ng > c_tope_global then return 'global'; end if;
  return 'pasa';
end
$$;
revoke all on function public.portal_peticion_freno(text) from public, anon, authenticated;
grant execute on function public.portal_peticion_freno(text) to service_role;
comment on function public.portal_peticion_freno(text) is
  'Freno del formulario anónimo del portal ANTES de la regla: pasa | ip (20/h por cubo de IP) | global (cortacircuitos 1000/h, solo '
  'cuenta lo que pasó su tope de IP). Solo service_role; llamador: edge portal-acceso. 20261015202000.';
