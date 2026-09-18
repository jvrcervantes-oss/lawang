-- ============================================================================
-- `puede_proyecto` deja de ABRIR cuando el nombre no casa. 18-sep-2026.
--
-- POR QUE. La puerta que gobierna UPDATE/DELETE de `contratos` y todo
-- `documentos_proyecto` decidia por NOMBRE y decia, literalmente:
--     when coalesce(btrim(p_nombre), '') = '' then true
--     when not exists (select 1 from proyectos where nombre = btrim(p_nombre)) then true
-- Es decir: si el nombre venia vacio, o no casaba con ningun proyecto, la
-- funcion ABRIA. Y el nombre que la alimenta en `contratos` sale de
-- `datos -> 'fields' ->> 'proyecto_nombre'`, un campo que escribe el cliente:
-- un espacio, una tilde o una mayuscula distinta y la puerta devuelve true. En
-- el INSERT de `contratos` esa funcion es el UNICO gate de proyecto (no hay
-- comprobacion de autoria), asi que hoy un agente con la herramienta puede
-- crear un contrato en un proyecto que no es suyo mandando un nombre que no
-- case.
--
-- Hallazgo de Datos en la revision previa del 18-sep-2026 del encargo de
-- multiempresa (`encargos/20260918_lawang_multiempresa_karana.md`). Se arregla
-- AHORA y no dentro de ese encargo porque no depende de el: el agujero esta
-- abierto con un solo cliente dentro.
--
-- COMO SE ARREGLA. El id manda sobre el texto (`contexto/patrones_tecnicos.md`
-- -> «El dato tiene un dueño»: referencia = guarda el id, no el nombre). Donde
-- la fila tiene `proyecto_id` se gobierna por id; el nombre queda de respaldo
-- solo para las filas que no lo tienen, y ahi «vacio» y «no casa» pasan a
-- DENEGAR.
--
-- MEDIDO ANTES DE TOCAR, en produccion, no estimado:
--   · 17 contratos cuyo `datos->fields->>proyecto_nombre` no casa con ningun
--     proyecto (nombres comerciales: «Palm Field by Balian Hills»...). Los 17
--     TIENEN `proyecto_id`, asi que al resolver por id quedan bien gobernados,
--     no bloqueados. `trg_espejo_proyecto` ya normaliza la COLUMNA
--     `proyecto_nombre`; lo que no normaliza nadie es el jsonb.
--   · 4 contratos sin `proyecto_id` (CR00058, CH00001, CC00086, HS00006): pasan
--     a ser editables solo por admin. Se dejan asi A PROPOSITO -- rellenarles el
--     id es un UPDATE sobre `contratos` que dispara `trg_sincroniza_unidad`, y
--     eso va con `session_replication_role = replica` dentro del encargo, no en
--     una migracion de seguridad.
--   · 4 `documentos_proyecto` sin `proyecto_id` y con un nombre que no casa:
--     mismo caso, mismo trato.
--   · `modelos_villa`: 32 filas, 0 sin match. `unidades`: 0 sin match. Las
--     cuatro funciones `obra_*` que llaman a `puede_proyecto` resuelven el
--     nombre desde `proyectos`/`unidades` y ya lanzan si no existe, asi que no
--     cambian de comportamiento.
--
-- LO QUE NO HACE: no toca una sola fila de datos, no crea tablas y no relaja
-- ningun permiso. Solo cierra.
--
-- destructivo-ok: los unicos DROP son `drop policy` + `create policy` de la
-- misma politica dentro de la misma transaccion, para cambiar el gate de
-- proyecto. No se borra ni una fila ni un objeto que no se reponga acto
-- seguido, y todas las politicas quedan mas restrictivas que antes. Aprobado
-- por el owner el 18-sep-2026 al pedir la Fase 0 entera.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. La version por id. Conserva las dos ramas de cabecera de `puede_proyecto`
--    tal cual: admin abre, y un JWT sin fila en `usuarios` (edges, firma) sigue
--    resolviendo por `app_metadata.agente` -- si no, esta migracion cerraria de
--    paso caminos que hoy funcionan y que no son el agujero.
-- ---------------------------------------------------------------------------
create or replace function public.puede_proyecto_id(p_proyecto_id uuid)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when not exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
    when p_proyecto_id is null then false
    else public.proyecto_visible(p_proyecto_id)
  end
$$;

comment on function public.puede_proyecto_id(uuid) is
  'Gobierna por proyecto_id. Es la version buena: el nombre es texto que escribe el cliente.';

-- ---------------------------------------------------------------------------
-- 2. La version por nombre deja de abrir. Dos lineas, que son el agujero.
-- ---------------------------------------------------------------------------
create or replace function public.puede_proyecto(p_nombre text)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select case
    when public.es_admin() then true
    when not exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
    -- Antes: `then true` en las dos. Un nombre vacio o que no casa ya no abre.
    when coalesce(btrim(p_nombre), '') = '' then false
    when not exists (select 1 from public.proyectos p where p.nombre = btrim(p_nombre)) then false
    else exists (
      select 1
        from public.usuarios u
        join public.proyectos p
          on p.id = any (u.proyectos)
          or (u.rol in ('sales_manager', 'project_manager') and p.id = any (u.proyectos_supervisados))
       where u.user_id = (select auth.uid()) and u.activo
         and p.nombre = btrim(p_nombre))
  end
$$;

-- ---------------------------------------------------------------------------
-- 3. Sobrecargas que prefieren el id y solo caen al nombre si no lo hay.
--    Se anaden como sobrecarga, no se cambia la firma de 2 argumentos: esa la
--    llaman politicas que se recrean abajo y cambiarla de golpe dejaria un
--    hueco entre el `drop` y el `create`.
-- ---------------------------------------------------------------------------
create or replace function public.puede_proyecto(p_nombre text, p_proyecto_id uuid)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select case
    when p_proyecto_id is not null then public.puede_proyecto_id(p_proyecto_id)
    else public.puede_proyecto(p_nombre)
  end
$$;

create or replace function public.puede_proyecto_de(datos jsonb, col text, p_proyecto_id uuid)
returns boolean
language sql stable security definer set search_path to ''
as $$
  select case
    when p_proyecto_id is not null then public.puede_proyecto_id(p_proyecto_id)
    else public.puede_proyecto_de(datos, col)
  end
$$;

grant execute on function public.puede_proyecto_id(uuid)            to authenticated;
grant execute on function public.puede_proyecto(text, uuid)         to authenticated;
grant execute on function public.puede_proyecto_de(jsonb, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Las politicas pasan a gobernar por id. Se recrean con el mismo texto que
--    tenian, cambiando UNICAMENTE la llamada al gate de proyecto.
-- ---------------------------------------------------------------------------
drop policy if exists "agentes o su manager insertan contratos" on public.contratos;
create policy "agentes o su manager insertan contratos"
  on public.contratos for insert to authenticated
  with check (
    es_agente() and puede('contratos')
    and (puede_proyecto_de(datos, proyecto_nombre, proyecto_id) or es_manager_de(proyecto_id))
  );

drop policy if exists "el autor, su manager, o un admin editan contratos sin firma viv" on public.contratos;
create policy "el autor, su manager, o un admin editan contratos sin firma viv"
  on public.contratos for update to authenticated
  using (
    es_super_admin() or (
      bloqueado = false and not contrato_firma_viva(id)
      and es_agente() and puede('contratos')
      and (es_suyo(creado_por) or es_manager_de(proyecto_id))
      and puede_proyecto_de(datos, proyecto_nombre, proyecto_id))
  )
  with check (
    es_super_admin() or (
      es_agente() and puede('contratos')
      and (es_suyo(creado_por) or es_manager_de(proyecto_id))
      and puede_proyecto_de(datos, proyecto_nombre, proyecto_id))
  );

drop policy if exists "borrar contratos" on public.contratos;
create policy "borrar contratos"
  on public.contratos for delete to authenticated
  using (
    es_super_admin() or (
      coalesce(bloqueado, false) = false
      and es_agente() and puede('contratos')
      and creado_por is not null
      and creado_por = (select auth.email())
      and puede_proyecto_de(datos, proyecto_nombre, proyecto_id))
  );

drop policy if exists "documentacion: leer" on public.documentos_proyecto;
create policy "documentacion: leer"
  on public.documentos_proyecto for select to authenticated
  using (es_agente() and puede_proyecto(proyecto, proyecto_id));

drop policy if exists "documentacion: subir" on public.documentos_proyecto;
create policy "documentacion: subir"
  on public.documentos_proyecto for insert to authenticated
  with check (es_agente() and puede('documentacion') and puede_proyecto(proyecto, proyecto_id));

drop policy if exists "documentacion: editar" on public.documentos_proyecto;
create policy "documentacion: editar"
  on public.documentos_proyecto for update to authenticated
  using (es_agente() and puede('documentacion') and puede_proyecto(proyecto, proyecto_id))
  with check (es_agente() and puede('documentacion') and puede_proyecto(proyecto, proyecto_id));

drop policy if exists "modelos: leer" on public.modelos_villa;
create policy "modelos: leer"
  on public.modelos_villa for select to authenticated
  using (es_agente() and puede_proyecto(proyecto, proyecto_id));
-- `modelos_villa` SI tiene `proyecto_id` y sus 32 filas lo llevan puesto (0
-- nulos, comprobado), asi que pasa a gobernarse por id como las demas. Nadie
-- pierde acceso: lo que cambia es que un nombre que no case deniega en vez de
-- abrir.
