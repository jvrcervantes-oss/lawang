-- VUELTA ATRÁS de 20261017205000_law338_l6_unidades_policy (LAW-338 L6, tren 6, 17-oct-2026). NO se aplica sola: la decide quien orquesta.
-- Devuelve la policy de lectura de unidades a la de antes, «es_agente() AND unidad_visible(proyecto_id)» (20260922170000:115),
-- con sus roles (authenticated, lw_lector: alter policy sin TO no los cambia), y luego borra mis_proyectos_visibles (la policy
-- depende de ella: en el otro orden el drop falla). unidad_visible y proyecto_visible no se tocan.
-- Orden con unidades_busca (20261017210000): indiferente; sin L6 la búsqueda vuelve a ser lenta, no incorrecta.
-- Tras aplicarla, la huella de tools/salud_lawang.py (_MCP_COPIAS) vuelve a ser ba7ae87af69245a9b5305663e66f74ee.
-- destructivo-ok: alter policy a la regla anterior (misma visibilidad) y retira una función de lectura sin otro llamador
set local lock_timeout = '5s';

alter policy "agentes leen unidades de sus proyectos, manager de los suyos" on public.unidades
  using (public.es_agente() and public.unidad_visible(proyecto_id));

drop function if exists public.mis_proyectos_visibles();

do $c$
declare v_qual text;
begin
  -- la huella se mide como salud_lawang (pg_policies) con el search_path por defecto de Supabase: así se deparsa sin «public.»
  perform set_config('search_path', '"$user", public, extensions', true);
  select coalesce(p.qual, '') into v_qual from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'unidades' and p.policyname = 'agentes leen unidades de sus proyectos, manager de los suyos';
  if md5(v_qual) <> 'ba7ae87af69245a9b5305663e66f74ee' then
    raise exception 'la policy de unidades no volvió a la de antes: % (md5 %)', v_qual, md5(v_qual);
  end if;
  if to_regprocedure('public.mis_proyectos_visibles()') is not null then
    raise exception 'mis_proyectos_visibles sigue existiendo tras la vuelta atrás';
  end if;
end $c$;
