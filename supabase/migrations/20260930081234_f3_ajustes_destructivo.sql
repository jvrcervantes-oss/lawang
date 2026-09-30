-- destructivo-ok: owner 30-sep «(1) Borrar la función antigua, (2) Vaciar supervisados de los 3 SM»
-- =====================================================================================
-- F3 · AJUSTES, parte destructiva (30-sep-2026). Va después de 20260930081209_f3_ajustes_visibilidad.
-- E. Autorizado por el owner (30-sep-2026, literal: «(1) Borrar la función antigua, (2) Vaciar
--    supervisados de los 3 SM»):
--    (1) drop de public.contrato_visible(text, uuid): sin llamadores desde F3 (aserción 6a de F3 y
--        pg_depend vacío el 30-sep) y sin EXECUTE para los roles de sesión.
--    (2) proyectos_supervisados = '{}' en los usuarios con rol sales_manager que lo tenían relleno
--        (3 el 30-sep; si no son exactamente 3, aborta). No cambia lo que ven: desde F3 esa lista
--        solo cuenta con rol project_manager. VALOR PREVIO para revertir: fuera del repo (público), en private/reversiones/f3_supervisados_sm_20260930.sql del clon principal.
-- =====================================================================================

-- (1) contrato_visible: sin llamadores (se comprueba otra vez aquí antes de borrarla).
do $e1$
begin
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
                and p.proname <> 'contrato_visible'
                and pg_get_functiondef(p.oid) ~ 'contrato_visible\(')
     or exists (select 1 from pg_policies
                 where coalesce(qual, '') || coalesce(with_check, '') ~ 'contrato_visible\(') then
    raise exception 'F3 ajustes: algo llama todavía a contrato_visible; no se borra';
  end if;
end
$e1$;
drop function public.contrato_visible(text, uuid);

-- (2) supervisados de los SM: exactamente 3 el 30-sep (valor previo en la cabecera).
do $e2$
declare v_n int;
begin
  select count(*) into v_n from public.usuarios
   where rol = 'sales_manager' and cardinality(coalesce(proyectos_supervisados, '{}'::uuid[])) > 0;
  if v_n <> 3 then
    raise exception 'F3 ajustes: se esperaban 3 sales_manager con proyectos_supervisados y hay %; no se vacía nada', v_n;
  end if;
  update public.usuarios set proyectos_supervisados = '{}'::uuid[]
   where rol = 'sales_manager' and cardinality(coalesce(proyectos_supervisados, '{}'::uuid[])) > 0;
end
$e2$;

