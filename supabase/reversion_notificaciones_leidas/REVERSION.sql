-- VUELTA ATRÁS de 20261017200000_notificaciones_leidas (H7, 17-oct-2026). NO se aplica sola: la decide quien orquesta.
-- Orden: primero el front (o nada: el front de H7 sin `id` en la respuesta ya se porta como el de antes y marca al abrir).
-- 1. notificaciones_datos vuelve al cuerpo EXACTO de L5 (20261016063536 §6), sin `id` ni `leida`. Se escribe ya DEFINER y con
--    search_path '' (L5 lo dejó así con su `alter … security definer` final); dueño lw_lector y permisos se conservan.
-- 2. Se retiran la RPC y el ayudante: sin llamador, no se quedan expuestos (§1.ter).
-- 3. La TABLA con marcas dentro NO se borra aquí: `drop table` destruye datos y para con el owner (hard-stop). Sin la RPC nadie
--    escribe en ella y sin la función nueva nadie la lee: puede quedarse.
-- destructivo-ok: los dos drop son de funciones de H7 (no guardan datos); la tabla no se toca

create or replace function public.notificaciones_datos(p_limite int)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v jsonb; n int; lim int := least(greatest(coalesce(p_limite, 30), 1), 400);
begin
  if public.uid_sesion() is null then
    raise exception 'notificaciones_datos: sin sesión' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'titulo', x.titulo, 'detalle', x.detalle, 'enlace', x.enlace,
                                               'creado_en', x.creado_en, 'destinatario', x.destinatario) order by x.rn)
                  filter (where x.rn <= lim), '[]'::jsonb), count(*)::int
    into v, n
    from (select t.tipo, t.titulo, t.detalle, t.enlace, t.creado_en, t.destinatario,
                 row_number() over (order by t.creado_en desc, t.id desc) as rn
            from public.notificaciones t order by t.creado_en desc, t.id desc limit lim + 1) x;
  return jsonb_build_object('notificaciones', v, 'hay_mas', n > lim);
end $$;

revoke execute on function public.notificaciones_marca_leidas(uuid[]) from authenticated;
drop function if exists public.notificaciones_marca_leidas(uuid[]);
drop function if exists public._notificaciones_visibles(uuid[]);

do $$
begin
  if not (select prosecdef and proconfig @> array['search_path=""'] and pg_get_userbyid(proowner) = 'lw_lector'
            from pg_proc where oid = 'public.notificaciones_datos(int)'::regprocedure) then
    raise exception 'reversión H7: notificaciones_datos no quedó DEFINER de lw_lector con search_path vacío';
  end if;
end $$;

-- SOLO CON EL OK DEL OWNER (borra las marcas de leído de todo el equipo):
--   drop table public.notificaciones_leidas;
