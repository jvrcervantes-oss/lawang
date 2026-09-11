-- destructivo-ok: ALTER TABLE ADD COLUMN, DROP+CREATE FUNCTION son adiciones y
-- sustituciones. El UPDATE de abajo lleva WHERE (email = ANY de 5 personas
-- concretas, pedido explícito del owner), no es masivo. Cero DELETE/TRUNCATE.
-- ════════════════════════════════════════════════════════════════════════════
-- `proyectos` (crea contratos) y `proyectos_supervisados` (a qué proyecto
-- supervisa un manager) son DOS COSAS DISTINTAS — 11-sep-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Corrección del owner sobre lo construido hoy: había fundido las dos cosas en
-- la misma columna `usuarios.proyectos`, y por eso hice de /usuarios/ un
-- espejo de solo lectura para managers (para no tener "dos sitios editando lo
-- mismo"). Pero NO son lo mismo:
--   · `usuarios.proyectos`              → en qué proyectos puede este usuario
--     CREAR/EDITAR contratos como agente. Se edita en /usuarios/. Vale igual
--     para un agente que para un manager: un manager también puede vender.
--   · `usuarios.proyectos_supervisados` → de qué proyecto es encargado este
--     manager — ve TODO lo que hagan los agentes ahí y puede corregirlo. Se
--     edita en /proyectos/ (ficha de CADA proyecto), nunca en /usuarios/.
-- `es_manager_de()` pasa a mirar la columna nueva: como la usan TODAS las
-- policies de lectura/escritura de managers (clients, unidades, contratos,
-- facturas, recibi_aplicaciones, solicitudes_pago, el aviso por email), este
-- es el único sitio que hay que tocar — ningún otro archivo .sql se reescribe.

alter table public.usuarios
  add column if not exists proyectos_supervisados uuid[] not null default '{}';

comment on column public.usuarios.proyectos_supervisados is
  'Proyectos (proyectos.id) de los que este usuario es MANAGER (sales_manager/project_manager): ve y corrige todo lo que hagan sus agentes ahí. Se asigna desde la ficha de CADA proyecto en /proyectos/, nunca desde /usuarios/. Distinto de `proyectos`, que es en qué proyectos puede CREAR contratos como agente. Vacío = no supervisa ninguno.';

create or replace function public.es_manager_de(p_proyecto_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when p_proyecto_id is null then false
    else exists (
      select 1 from public.usuarios u
       where u.user_id = (select auth.uid()) and u.activo
         and u.rol in ('sales_manager','project_manager')
         and p_proyecto_id = any (u.proyectos_supervisados))
  end
$$;

-- ── El RPC de /proyectos/ pasa a tocar la columna nueva, con nombre que ya
--    no confunda las dos cosas ──────────────────────────────────────────────
drop function if exists public.usuario_asigna_proyecto(uuid, uuid, boolean);
create or replace function public.usuario_supervisa_proyecto(
  p_user_id uuid, p_proyecto_id uuid, p_asignar boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare v_rol text;
begin
  if not (public.es_admin() and public.puede('usuarios')) then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  select rol into v_rol from public.usuarios where user_id = p_user_id;
  if v_rol is null then
    raise exception 'usuario no encontrado' using errcode = '22023';
  end if;
  if v_rol = 'super_admin' and not public.es_super_admin() then
    raise exception 'no autorizado' using errcode = '42501';
  end if;

  if p_asignar then
    update public.usuarios
       set proyectos_supervisados = (
         select array(select distinct unnest(coalesce(proyectos_supervisados, '{}'::uuid[]) || array[p_proyecto_id]))
       )
     where user_id = p_user_id;
  else
    update public.usuarios
       set proyectos_supervisados = array_remove(coalesce(proyectos_supervisados, '{}'::uuid[]), p_proyecto_id)
     where user_id = p_user_id;
  end if;
end;
$$;
revoke execute on function public.usuario_supervisa_proyecto(uuid, uuid, boolean) from public, anon;
grant execute on function public.usuario_supervisa_proyecto(uuid, uuid, boolean) to authenticated;

-- ── Los 5 managers con 26-29 proyectos en `proyectos` (creación) vuelven a
--    cero, a petición explícita del owner: «prefiero que no vean nada a que
--    vean todo». Se reasignan a mano desde /usuarios/ lo que de verdad
--    vendan ellos mismos. Su supervisión (columna nueva) ya nace en '{}' para
--    TODOS — no hace falta tocarla aparte. ──────────────────────────────────
update public.usuarios
   set proyectos = '{}'
 where email in (
   'balianhills@gmail.com', 'gusabellan@gmail.com', 'hello@lawangproperties.com',
   'fernando.margoz@gmail.com', 'martaruiz@lawangproperties.com'
 );

-- ── Comprobación ─────────────────────────────────────────────────────────
--   select column_name from information_schema.columns where table_name='usuarios' and column_name='proyectos_supervisados';
--   select email, array_length(proyectos,1), array_length(proyectos_supervisados,1) from usuarios
--    where email in ('balianhills@gmail.com','gusabellan@gmail.com','hello@lawangproperties.com',
--                     'fernando.margoz@gmail.com','martaruiz@lawangproperties.com');
--    -> los 5 con proyectos=0 (o NULL) y proyectos_supervisados=0
--   select proname from pg_proc where proname='usuario_supervisa_proyecto'; -- 1 fila
--   select proname from pg_proc where proname='usuario_asigna_proyecto';   -- 0 filas (borrada)
