-- Foto de no-regresion del BLOQUE 1 del cierre de empresas (8-oct-2026): lo que cada uno de los usuarios reales ve/puede, en md5, ANTES y DESPUES de cada migracion de f2_b1.
-- Complementa a f2_foto_ids.sql (que cubre proyectos, unidades, contratos, facturas...). Aqui: las tablas hijas de contratos que cambian de policy (eventos, firmas, prorrogas, paginas de anexo)
-- y el resultado de las funciones convertidas que NO piden argumentos de escritura (es_manager_de sobre todos los proyectos, _puede_editar_proyectos, es_admin_de/es_super_admin_de sobre la empresa de cada proyecto,
-- ventas_por_su_cuenta_cuota/equipo, unidad_parte_cobrada_split sobre todas las parcelas, proyecto_vinculos_datos sobre todos los proyectos).
-- Con JWT simulado (con email) + set local role authenticated. Termina en raise (sin rastro). El md5 de los 34 usuarios reales debe ser IDENTICO antes y despues.
-- destructivo-ok: solo lectura; termina en raise
do $t$
declare u record; o text; h text; t text; sal text := ''; sal2 text := '';
begin
  for u in select user_id, email from public.usuarios order by email loop
    o := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array array['contrato_eventos','contrato_firmas','contrato_prorrogas','contrato_anexo_paginas'] loop
      begin execute format('select md5(coalesce(string_agg(id::text, '','' order by id::text),'''')) from public.%I', t) into h; o := o||'|'||left(h,6);
      exception when others then o := o||'|ERR'||sqlstate; end;
    end loop;
    begin select md5(coalesce(string_agg(x::text, ',' order by x::text),'')) into h from (select p.id::text||':'||public.es_manager_de(p.id)::text||public.es_admin_de(public.empresa_de_proyecto(p.id))::text||public.es_super_admin_de(public.empresa_de_proyecto(p.id))::text x from public.proyectos p) s; o := o||'|em'||left(h,6);
    exception when others then o := o||'|ERRem'||sqlstate; end;
    begin select md5(coalesce(string_agg(x::text, ',' order by x::text),'')) into h from (select k.equipo_id::text||k.closer_email||k.declaradas||'/'||k.por_su_cuenta x from public.ventas_por_su_cuenta_cuota() k) s; o := o||'|cuo'||left(h,6);
    exception when others then o := o||'|ERRcuo'||sqlstate; end;
    begin select md5(coalesce(string_agg(x::text, ',' order by x::text),'')) into h from (select k.raiz_id::text x from public.ventas_por_su_cuenta_equipo() k) s; o := o||'|eqp'||left(h,6);
    exception when others then o := o||'|ERReqp'||sqlstate; end;
    reset role;
    sal := sal || o || E'\n';
    -- segundo bloque: como postgres con los mismos claims, sobre TODAS las filas
    o := u.email||'|pe'||public._puede_editar_proyectos()::text;
    begin select md5(coalesce(string_agg(x, ',' order by x),'')) into h from (select s.cobrado_suelo::text||'/'||s.cobrado_obra::text||'/'||s.obra_firmada::text||':'||un.id::text x
          from public.unidades un cross join lateral public.unidad_parte_cobrada_split(un.id) s) q; o := o||'|upc'||left(h,6);
    exception when others then o := o||'|ERRupc'||sqlstate; end;
    begin select md5(coalesce(string_agg(x, ',' order by x),'')) into h from (select p.id::text||':'||(public.proyecto_vinculos_datos(p.nombre))::text x from public.proyectos p) q; o := o||'|vin'||left(h,6);
    exception when others then o := o||'|ERRvin'||sqlstate; end;
    sal2 := sal2 || o || E'\n';
  end loop;
  raise exception E'FOTO_B1\nMD5_TABLAS=%\nMD5_FUNCIONES=%', md5(sal), md5(sal2);
end $t$;
