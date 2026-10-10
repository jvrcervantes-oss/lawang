-- LAW-1 S1 (11-oct-2026): freno propio del enlace de entrada al portal del comprador.
-- Encargo: encargos/20261011_lawang_portal_enlace_por_correo.md (repo de la agencia), revisión previa #261 (Backend + Seguridad).
--
-- POR QUÉ: las edges `portal-acceso` (formulario ANÓNIMO) y `portal-invitar` (admin) pasan a generar el enlace con
-- `auth.admin.generateLink` y a mandarlo por `envia-correo` (el buzón SMTP de Lawang, el mismo de firmas y facturas).
-- `generateLink` se salta el límite por correo de GoTrue, y cada enlace nuevo invalida el anterior: sin freno, repetir el
-- formulario inundaría al comprador, le dejaría sin poder entrar (su enlace ya no vale) y gastaría la cuota del buzón.
--
-- REGLA (fijada en Decisiones del encargo):
--   · por correo normalizado: como mínimo 60 s entre dos envíos y como máximo 5 en la última hora (ventana deslizante);
--   · global: como máximo 30 enlaces por hora del formulario anónimo (origen 'autoservicio'). Los de un admin ('invitar')
--     no cuentan en el global ni los frena: van con sesión y en tandas (44 compradores no caben en 30/h), y no son la puerta
--     que un extraño puede martillear. Siguen frenados por correo (60 s y 5/h), porque cada enlace invalida el anterior.
--   · frenado = la función devuelve false; la edge contesta lo mismo que a un correo sin derecho (`{ok:true}`).
--   · solo cuentan los correos con derecho: la edge llama a esta función DESPUÉS de comprobar la regla y el equipo.
--   · `p_libera = true` devuelve el hueco de un envío que no salió (falló la cuenta, `generateLink` o `envia-correo`). Sin
--     esto, quien pulsa otra vez tras «no se pudo enviar» caería en «frenado» y la página le diría «enviado» sin que saliera
--     nada, que es justo la avería que este encargo arregla.
--
-- ATÓMICO: `pg_advisory_xact_lock` con una clave fija al principio serializa TODAS las llamadas (no solo las del mismo
-- correo): así dos correos distintos no pueden pasar a la vez cuando falta uno para el tope global. A este volumen
-- (decenas por hora como mucho) serializar no cuesta nada.
--
-- DUEÑO DEL DATO: esta tabla es la única fuente del ritmo de envíos del enlace del portal; nadie más la lee ni la copia.
-- Una fila por correo con derecho (decenas) + la fila '*' del contador global; cada fila guarda solo sus marcas de la
-- última hora (como mucho 5, o 30 en la global): no crece y no hace falta purgarla.
--
-- SUPERFICIE: tabla con RLS activada, SIN políticas y sin permisos para nadie más que su dueño (ni anon, ni authenticated,
-- ni service_role: solo la toca la función DEFINER). La función: solo service_role (las dos edges). search_path vacío.
--
-- VUELTA ATRÁS (a mano y con el OK del owner; las edges dejarían de enviar el enlace hasta volver a su versión anterior):
--   drop function public.portal_enlace_freno(text, text, boolean);
--   drop table public.portal_enlaces_envios;

create table if not exists public.portal_enlaces_envios (
  clave          text primary key,
  envios         timestamptz[] not null default '{}',
  actualizado_at timestamptz   not null default now(),
  constraint portal_enlaces_envios_clave_ck check (
    clave = '*' or (clave = lower(btrim(clave)) and length(clave) between 3 and 320 and clave ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
  ),
  constraint portal_enlaces_envios_tope_ck check (cardinality(envios) <= 60)
);
comment on table public.portal_enlaces_envios is
  'LAW-1 S1: marcas de envío del enlace del portal de la última hora, por correo (y ''*'' = global del formulario anónimo). Solo la escribe portal_enlace_freno().';

alter table public.portal_enlaces_envios enable row level security;
revoke all on table public.portal_enlaces_envios from public, anon, authenticated, service_role;

insert into public.portal_enlaces_envios (clave) values ('*') on conflict (clave) do nothing;

create or replace function public.portal_enlace_freno(p_email text, p_origen text, p_libera boolean default false)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_min_seg    constant int := 60;   -- segundos mínimos entre dos envíos al mismo correo
  c_max_correo constant int := 5;    -- envíos por correo en la última hora
  c_max_global constant int := 30;   -- envíos del formulario anónimo en la última hora
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_ahora  timestamptz := clock_timestamp();
  v_desde  timestamptz;
  v_mio    timestamptz[];
  v_global timestamptz[];
  v_cuenta_global boolean;
begin
  if p_origen is null or p_origen not in ('autoservicio', 'invitar') then
    raise exception 'portal_enlace_freno: origen no válido' using errcode = '22023';
  end if;
  if length(v_email) not between 3 and 320 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return false;
  end if;
  v_cuenta_global := (p_origen = 'autoservicio');

  -- Un solo candado para todo el freno (clave fija): serializa también el tope global.
  perform pg_advisory_xact_lock(7316402251001);
  v_ahora := clock_timestamp();   -- la hora DESPUÉS de esperar el candado
  v_desde := v_ahora - interval '1 hour';

  insert into public.portal_enlaces_envios (clave) values (v_email) on conflict (clave) do nothing;
  select coalesce(array_agg(e order by e), '{}') into v_mio
    from public.portal_enlaces_envios f, unnest(f.envios) e
   where f.clave = v_email and e > v_desde;
  select coalesce(array_agg(e order by e), '{}') into v_global
    from public.portal_enlaces_envios f, unnest(f.envios) e
   where f.clave = '*' and e > v_desde;

  if p_libera then
    -- Devuelve el último hueco: quita la marca más reciente (del correo y, si era del formulario, también la global).
    if cardinality(v_mio) > 0 then
      update public.portal_enlaces_envios
         set envios = v_mio[1:cardinality(v_mio) - 1], actualizado_at = v_ahora
       where clave = v_email;
      if v_cuenta_global and cardinality(v_global) > 0 then
        update public.portal_enlaces_envios
           set envios = v_global[1:cardinality(v_global) - 1], actualizado_at = v_ahora
         where clave = '*';
      end if;
    end if;
    return true;
  end if;

  if cardinality(v_mio) > 0 and v_mio[cardinality(v_mio)] > v_ahora - make_interval(secs => c_min_seg) then
    return false;
  end if;
  if cardinality(v_mio) >= c_max_correo then
    return false;
  end if;
  if v_cuenta_global and cardinality(v_global) >= c_max_global then
    return false;
  end if;

  update public.portal_enlaces_envios
     set envios = v_mio || v_ahora, actualizado_at = v_ahora
   where clave = v_email;
  if v_cuenta_global then
    update public.portal_enlaces_envios
       set envios = v_global || v_ahora, actualizado_at = v_ahora
     where clave = '*';
  end if;
  return true;
end;
$$;

comment on function public.portal_enlace_freno(text, text, boolean) is
  'LAW-1 S1: true = puede enviarse el enlace del portal (y queda anotado); false = frenado. p_libera devuelve el hueco de un envío fallido. Solo service_role (edges portal-acceso y portal-invitar).';

revoke all     on function public.portal_enlace_freno(text, text, boolean) from public, anon, authenticated;
grant  execute on function public.portal_enlace_freno(text, text, boolean) to service_role;
