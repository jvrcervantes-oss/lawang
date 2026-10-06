-- Foto de visibilidad por usuario (Fase 2, paso 1, 7-oct-2026). Se ejecuta por execute_sql ANTES y DESPUES de cada migracion de la Fase 2;
-- termina con un raise a proposito (sin rastro) cuyo mensaje trae un md5 y las filas. Debe dar el md5 de supabase/pruebas/f2_foto_previa.json (md5_servidor).
-- Por usuario: JWT simulado con email + set local role authenticated; filas visibles de 9 tablas; es_admin/es_super_admin/es_agente; proyecto_visible sobre
-- 3 proyectos (Bonian Village, el primer Sumba Hills por nombre, el primero con empresa nula = Karana). Nota: si cambia el reparto de empresas o usuarios, la foto previa ya no vale.
do $t$
declare u record; out text := ''; o text; n bigint; t text; pids uuid[]; p uuid;
begin
  select array[(select id from public.proyectos where nombre='Bonian Village'),
               (select id from public.proyectos where resort ilike '%sumba%' order by nombre limit 1),
               (select id from public.proyectos where empresa is null order by nombre limit 1)] into pids;
  for u in select user_id, email, rol, activo from public.usuarios order by email loop
    o := u.email||'|'||u.rol||'|'||u.activo::int;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array array['proyectos','unidades','contratos','facturas','clients','contrato_vencimientos','solicitudes_pago','comision_admin_lineas','usuarios'] loop
      begin execute format('select count(*) from public.%I', t) into n; o := o||'|'||n;
      exception when others then o := o||'|ERR'||sqlstate; end;
    end loop;
    o := o||'|'||public.es_admin()::int||public.es_super_admin()::int||public.es_agente()::int||'|';
    foreach p in array pids loop o := o||public.proyecto_visible(p)::int; end loop;
    reset role;
    out := out || o || E'\n';
  end loop;
  raise exception E'FOTO\nMD5=%\n%', md5(out), out;
end $t$;
