-- AVISO AL ESTUDIO CUANDO EL PORTAL DEJA A UN COMPRADOR SIN ENLACE — 15-oct-2026 (sesión lawang-cola-2, resto 3 de «Invitar al portal»;
-- revisión previa #371 con Backend y Seguridad).
--
-- portal-acceso (contracts/edge/portal-acceso/index.ts) solo llama a portal_enlace_freno DESPUÉS de que portal_autoservicio diga
-- «elegible» y de descartar al equipo: un 'global' o un 'ip' es un COMPRADOR CON DERECHO que pidió su enlace, recibió «enviado»
-- (respuesta uniforme a propósito) y no le llegó nada. Hasta hoy solo quedaba una línea en el log de la edge que nadie mira.
-- Ahora la edge, en esa misma rama, llama a portal_freno_anota(motivo) y la vigilancia diaria del estudio (erp/salud_instancia.py,
-- chequeo «portal») lo pone en rojo.
--
-- Por qué NO se toca portal_enlace_freno: reemitir su cuerpo vuelve a meter sus dos purgas (delete) y tools/no_destruir.py lo para
-- en Lawang sin la válvula del owner. Esta pieza no borra nunca: la tabla es un ANILLO de 768 ranuras horarias (32 días) que se
-- reutilizan; una ranura con la hora de hace 32 días se reinicia al volver a usarse.
--
-- DUEÑO DEL DATO: portal_freno_anota (única que escribe). SUPERFICIE: la tabla vive en `privado` (revocado a todos, 20260927210500)
-- y sin grant a nadie, ni a service_role; la función, solo service_role, con un llamador con nombre: portal-acceso. Lee:
-- axw_lectura (pg_read_all_data + bypassrls, 20260925140000) desde salud_instancia. No guarda correo, IP ni su hash: hora y cuentas.
-- No hay serial ni identity: un ensayo deshecho no gasta ninguna serie.
-- VUELTA ATRÁS: devolver la edge a la versión anterior (sin la llamada); la función y la tabla pueden quedarse sin daño (no las llama
-- nadie más). Quitarlas del todo es un DROP: va por la válvula del owner.

create table if not exists privado.portal_frenos (
  ranura   int primary key check (ranura between 0 and 767),
  hora     timestamptz not null,
  n_global int not null default 0 check (n_global >= 0),
  n_ip     int not null default 0 check (n_ip >= 0),
  primero  timestamptz not null,
  ultimo   timestamptz not null
);
alter table privado.portal_frenos enable row level security;
revoke all on table privado.portal_frenos from public, anon, authenticated, service_role;
comment on table privado.portal_frenos is
  'Compradores con derecho que recibieron «enviado» sin enlace, por hora (anillo de 768 ranuras = 32 días, sin borrados). Escribe solo '
  'public.portal_freno_anota (llamada por la edge portal-acceso); lee la vigilancia del estudio (axw_lectura). 20261015201000.';

create or replace function public.portal_freno_anota(p_motivo text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_ahora  timestamptz := clock_timestamp();                       -- no now(): la hora real del frenazo, no la del inicio de la transacción
  v_hora   timestamptz := date_trunc('hour', v_ahora, 'UTC');      -- sin depender del huso de la sesión
  v_ranura int := (floor(extract(epoch from v_hora) / 3600)::bigint % 768)::int;
  v_g      int := case when p_motivo = 'global' then 1 else 0 end;
  v_i      int := case when p_motivo = 'ip' then 1 else 0 end;
begin
  if p_motivo is null or p_motivo not in ('global', 'ip') then
    raise exception 'portal_freno_anota: motivo no válido' using errcode = '22023';
  end if;
  insert into privado.portal_frenos as f (ranura, hora, n_global, n_ip, primero, ultimo)
  values (v_ranura, v_hora, v_g, v_i, v_ahora, v_ahora)
  on conflict (ranura) do update
     set n_global = case when f.hora = excluded.hora then f.n_global + excluded.n_global else excluded.n_global end,
         n_ip     = case when f.hora = excluded.hora then f.n_ip + excluded.n_ip else excluded.n_ip end,
         primero  = case when f.hora = excluded.hora then f.primero else excluded.primero end,
         hora     = excluded.hora,
         ultimo   = excluded.ultimo;
end
$$;
revoke all on function public.portal_freno_anota(text) from public, anon, authenticated;
grant execute on function public.portal_freno_anota(text) to service_role;
comment on function public.portal_freno_anota(text) is
  'Anota un frenazo del portal (global | ip) en privado.portal_frenos. Solo service_role; llamador: edge portal-acceso. 20261015201000.';
