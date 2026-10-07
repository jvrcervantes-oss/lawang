-- Foto del BLOQUE 12 (7-oct-2026): por cada usuario real (JWT simulado con email + set local role authenticated) lo que ve y lo que le contestan las
-- pantallas «Comision de administracion», «Sociedades emisoras» y «Ajustes». Una linea por usuario (hash corto); se compara linea a linea ANTES y DESPUES de cada migracion.
-- Cambio esperado y unico: sociedades / sociedades_log / sociedades_ajustes_datos para los que no son propietario. La comision de administracion debe dar lo mismo a los 34.
-- Solo lectura; termina en raise (sin rastro). destructivo-ok: solo lectura; termina en raise
do $t$
declare u record; out text := ''; o text; h text; r text; det text := '';
begin
  for u in select user_id, email, rol from public.usuarios order by email loop
    o := u.email || '|' || u.rol;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    for r in select unnest(array['comision_admin_lineas','comision_admin_fees','comision_admin_cobros','comision_admin_tarifas','sociedades','sociedades_log']) loop
      begin execute format('select md5(coalesce(string_agg(id::text, '','' order by id::text),'''')) || ''/'' || count(*) from public.%I', r) into h;
      exception when others then
        begin execute format('select md5(coalesce(string_agg(clave::text, '','' order by clave::text),'''')) || ''/'' || count(*) from public.%I', r) into h;
        exception when others then h := 'ERR' || sqlstate; end;
      end;
      o := o || '|' || left(h, 6) || substr(h, strpos(h, '/'));
    end loop;
    for r in select unnest(array['comision_admin_descuadres()','comision_admin_prevision()','sociedades_ajustes_datos()','ajustes_config_datos()','mantenimiento_datos()']) loop
      begin execute format('select md5(public.%s::text)', r) into h; o := o || '|' || left(h, 6);
      exception when others then o := o || '|E' || sqlstate; end;
    end loop;
    reset role;
    out := out || o || E'\n';
    det := det || u.email || '|' || u.rol || '|' || left(md5(o), 8) || E'\n';
  end loop;
  raise exception E'FOTOB12\nMD5=%\n%', md5(out), det;
end $t$;
