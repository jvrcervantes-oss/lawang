-- Foto de NO-REGRESION del bloque 4 (comisiones, equipos de venta y condiciones), 8-oct-2026.
-- Por cada una de las fichas de usuario (los 34 de hoy): md5 de los IDS que ve de equipos_venta, equipo_miembros, condiciones_comision, condicion_tramos,
-- comisiones_devengadas, comisiones_diferencias y las 4 tablas del libro de administracion; y md5 de lo que le devuelven las funciones de la pantalla
-- (comisiones_ventas_equipo, mi_condicion_comision SIN la columna empresa, ventas_por_su_cuenta_cuota/_equipo, plantilla_reparto_lee y equipo_candidatos_sm de los
-- tres equipos activos de siempre, y comision_visible sobre todos los devengos). JWT simulado (sub, role, email) + set local role authenticated.
-- Las COPIAS de sandal_woods (migracion 1) se excluyen: el set que debe ser identico es el de lawang. Funciona antes y despues de la migracion 1: la clave `empresa`
-- se lee con to_jsonb(fila)->>'empresa' y, si no existe (antes), cuenta como 'lawang'.
-- Termina en raise (sin rastro). Salida: una linea por usuario + MD5_TABLAS y MD5_FUNCIONES globales. Antes y despues deben coincidir (dato vivo aparte).
-- destructivo-ok: solo lectura; termina en raise
do $t$
declare v_det boolean := false;  -- true = imprime una linea por usuario (para localizar la diferencia); false = solo los dos md5
  u record; o1 text; o2 text; out1 text := ''; out2 text := ''; h text; t text; w text; eq uuid;
  equipos uuid[] := array['d212a050-4297-4e1e-a7d3-fe4b4fcf30c0','7124be6e-a9bf-45d3-a775-5cc29f9d8259','e031468b-099a-46f2-9c6c-29ce6125cece']::uuid[];
begin
  for u in select user_id, email from public.usuarios order by email loop
    o1 := u.email; o2 := u.email;
    perform set_config('request.jwt.claims', json_build_object('sub',u.user_id,'role','authenticated','email',u.email)::text, true);
    set local role authenticated;
    foreach t in array array['equipos_venta','equipo_miembros','condiciones_comision','comisiones_devengadas','comisiones_diferencias','comision_admin_tarifas','comision_admin_fees','comision_admin_lineas','comision_admin_cobros'] loop
      begin
        execute format('select md5(coalesce(string_agg(x.id::text, '','' order by x.id::text),'''')) from public.%I x where coalesce(to_jsonb(x)->>''empresa'',''lawang'') = ''lawang''', t) into h;
        o1 := o1||'|'||left(h,5);
      exception when others then o1 := o1||'|E'||sqlstate; end;
    end loop;
    begin
      select md5(coalesce(string_agg(x.id::text, ',' order by x.id::text),'')) into h from public.condicion_tramos x
       where x.condicion_id in (select c.id from public.condiciones_comision c where coalesce(to_jsonb(c)->>'empresa','lawang') = 'lawang');
      o1 := o1||'|'||left(h,5);
    exception when others then o1 := o1||'|E'||sqlstate; end;
    -- funciones de la pantalla
    begin select md5(coalesce(string_agg(concat_ws('~', x.raiz_id, x.equipo_nombre, x.closer_email, x.setter_email, x.team_lead_email, x.soy_manager, x.reclamacion_estado), ',' order by x.raiz_id::text),'')) into h from public.comisiones_ventas_equipo() x; o2 := o2||'|cve'||left(h,5);
    exception when others then o2 := o2||'|cveE'||sqlstate; end;
    begin select md5(coalesce(string_agg(concat_ws('~', x.ambito, x.equipo_nombre, x.oculta, x.proyecto_id, x.nivel, x.pct_comision, x.base_calculo, x.importe_fijo, x.personal, x.vigente_desde), ',' order by concat_ws('~', x.ambito, x.equipo_nombre, x.proyecto_id, x.nivel, x.pct_comision, x.vigente_desde)),'')) into h from public.mi_condicion_comision() x; o2 := o2||'|mic'||left(h,5);
    exception when others then o2 := o2||'|micE'||sqlstate; end;
    begin select md5(coalesce(string_agg(concat_ws('~', x.equipo_id, x.closer_email, x.declaradas, x.por_su_cuenta), ',' order by x.equipo_id::text, x.closer_email),'')) into h from public.ventas_por_su_cuenta_cuota() x; o2 := o2||'|vcu'||left(h,5);
    exception when others then o2 := o2||'|vcuE'||sqlstate; end;
    begin select md5(coalesce(string_agg(concat_ws('~', x.raiz_id, x.closer_email, x.equipo_id, x.objecion_estado), ',' order by x.raiz_id::text),'')) into h from public.ventas_por_su_cuenta_equipo() x; o2 := o2||'|veq'||left(h,5);
    exception when others then o2 := o2||'|veqE'||sqlstate; end;
    foreach eq in array equipos loop
      begin select md5(coalesce(string_agg(concat_ws('~', x.rol_tipo, x.rol_nombre, x.pct), ',' order by x.rol_tipo, x.rol_nombre),'')) into h from public.plantilla_reparto_lee(eq) x; o2 := o2||'|pl'||left(h,4);
      exception when others then o2 := o2||'|plE'||sqlstate; end;
      begin select md5(coalesce(string_agg(x.email, ',' order by x.email),'')) into h from public.equipo_candidatos_sm(eq) x; o2 := o2||'|cn'||left(h,4);
      exception when others then o2 := o2||'|cnE'||sqlstate; end;
    end loop;
    begin select md5(coalesce(string_agg(d.id::text, ',' order by d.id::text) filter (where public.comision_visible(d.nivel, d.beneficiario_email, d.condicion_id, d.contrato_raiz_id)),'')) into h from public.comisiones_devengadas d; o2 := o2||'|cv'||left(h,5);
    exception when others then o2 := o2||'|cvE'||sqlstate; end;
    reset role;
    out1 := out1 || o1 || E'\n'; out2 := out2 || o2 || E'\n';
  end loop;
  raise exception E'FOTO_B4\n%\nMD5_TABLAS=%\nMD5_FUNCIONES=%', case when v_det then out1 || E'\n' || out2 else '' end, md5(out1), md5(out2);
end $t$;
