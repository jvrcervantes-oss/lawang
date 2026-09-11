-- `puede_proyecto()` no sabía qué es un encargado — 11-sep-2026
--
-- HAY DOS PREDICADOS DE «¿ESTE PROYECTO ES COSA MÍA?» Y NO DECÍAN LO MISMO:
--   · `proyecto_visible(uuid)`  → admin · **el que lo supervisa** · el que lo tiene asignado
--   · `puede_proyecto(text)`    → admin · el que lo tiene asignado  ← y nada más
-- Divergían justo en `proyectos_supervisados`, que es la columna entera sobre la que
-- se apoya el rol de manager. Dos copias de una regla que acaban diciendo cosas
-- distintas: el fallo que este proyecto lleva dos días pagando.
--
-- ESO ROMPÍA DOS COSAS, una vieja y una recién introducida por el arreglo de hoy:
--
-- 1. VIEJA, y contradice la decisión del propio 11-sep («un manager ESCRIBE en su
--    proyecto, no solo lee»). La policy UPDATE de `contratos` pide
--    `(es_suyo OR es_manager_de) AND puede_proyecto_de(...)`. Para Don Santiago
--    —`proyectos` vacío, 3 proyectos supervisados— la primera mitad daba TRUE y la
--    segunda FALSE, así que **no podía editar ni un solo contrato de sus agentes**.
--    Comprobado contrato a contrato antes de esto: `lo_supervisa` true,
--    `pasa_el_and_final` false. Después: 35 editables.
--
-- 2. NUEVA, de veinte minutos antes: al filtrar `modelos_villa` y
--    `documentos_proyecto` con `puede_proyecto(proyecto)` (20260911033911), Santiago
--    pasó a ver sus 3 carpetas con **0 modelos de villa** dentro. Una regresión
--    introducida por el propio arreglo, cazada impersonándolo — no estaba entre los
--    cinco de la primera verificación, y ése fue el error del método: se verificó a
--    un manager con proyectos asignados, no al que solo supervisa.
--
-- SE ARREGLA EN LA FUENTE, no con un `OR es_manager_de` pegado en cada policy: son
-- cuatro sitios y el quinto se olvidaría. Con la rama aquí heredan a la vez las
-- policies de `contratos` (UPDATE y DELETE), `modelos_villa`, `documentos_proyecto` y
-- `obra_actualizar()`.
--
-- El rol se comprueba explícitamente, igual que hace `es_manager_de()`: si algún día
-- alguien rellena `proyectos_supervisados` en la ficha de un agente raso, que no le
-- regale permisos. Un agente sin supervisados no gana absolutamente nada con esto —
-- verificado con Ismael: 1 proyecto, 6 modelos, 3 docs, 2 contratos, 2 editables,
-- idéntico antes y después.
--
-- Las dos ramas «pasa siempre» de arriba se conservan tal cual: nombre vacío y nombre
-- que no existe en `proyectos`. La segunda es la que mantiene comunes los documentos
-- de «Lawang (general)» — ver 20260911033911.

create or replace function public.puede_proyecto(p_nombre text)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select case
    when public.es_admin() then true
    when not exists (select 1 from public.usuarios u where u.user_id = (select auth.uid()))
      then coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'agente')::boolean, false)
    when coalesce(btrim(p_nombre), '') = '' then true
    when not exists (select 1 from public.proyectos p where p.nombre = btrim(p_nombre)) then true
    else exists (
      select 1
        from public.usuarios u
        join public.proyectos p
          on p.id = any (u.proyectos)
          or (u.rol in ('sales_manager', 'project_manager') and p.id = any (u.proyectos_supervisados))
       where u.user_id = (select auth.uid()) and u.activo
         and p.nombre = btrim(p_nombre))
  end
$function$;
