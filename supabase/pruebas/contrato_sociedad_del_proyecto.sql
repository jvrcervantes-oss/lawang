-- Prueba de contrato_sociedad_existe del 15-oct-2026 (migracion 20261015150000_contrato_sociedad_del_proyecto): la sociedad
-- firmante de un contrato es la de la empresa de su proyecto, y la base lo exige solo cuando cambia la sociedad o el proyecto.
-- Cada NO lleva al lado un SI que solo cambia en lo que se prueba.
-- S1/S2 alta con la del proyecto entra; con otra se rechaza. S3 alta sin sociedad entra y NO se rellena (decision por defecto).
-- S4 alta que solo trae el NOMBRE del proyecto (este trigger corre antes que trg_espejo_proyecto): se rechaza igual.
-- S5 cambiar la sociedad a otra se rechaza. S6 cambiar de proyecto a uno de otra empresa con la sociedad vieja se rechaza; con la
-- del proyecto nuevo entra. S7 un contrato viejo descuadrado (montado con el trigger apagado) se sigue pudiendo tocar (precio,
-- bloqueo) sin que reviente, y corregirlo a la del proyecto entra («corregir al reabrir»). S8 proyecto de una empresa sin
-- sociedad: no se exige nada. S9 hijo de una reserva descuadrada con la del proyecto: lo frena la regla del padre (ya existia).
-- !! CREA CONTRATOS (gasta numeracion) Y APAGA UN TRIGGER DENTRO DE LA TRANSACCION: SOLO EN RAMA, NUNCA EN LA BASE VIVA.
--    python erp/rama_prueba.py lawang --lawang <copia de Lawang> --aplica 20261015150000_contrato_sociedad_del_proyecto.sql
--           --prueba contrato_sociedad_del_proyecto.sql
-- Formato de erp/pruebas/corre.py: termina en «FIN DE PRUEBAS» y cada linea acaba en «→ ok» o «→ FALLA». Todo va marcado ZZ-SP.
-- destructivo-ok: prueba en transaccion que termina en raise (rollback); solo en rama
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;
-- ejecuta y devuelve 'OK' o el error (sqlstate:mensaje)
create or replace function pg_temp.x(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
end $f$;
-- un contrato de prueba: id, o el error
create or replace function pg_temp.alta(p_num text, p_proy uuid, p_nombre text, p_fields jsonb, p_padre uuid default null) returns text
language plpgsql as $f$
declare v uuid;
begin
  insert into public.contratos (numero, tipo, proyecto_id, proyecto_nombre, moneda, precio_total, datos, creado_por, contrato_padre_id)
    values (p_num, 'contrato_general', p_proy, p_nombre, 'EUR', 100000,
            jsonb_build_object('hitos', '[]'::jsonb, 'fields', p_fields), 'zz-sp@prueba.invalid', p_padre)
    returning id into v;
  return v::text;
exception when others then
  return 'ERR' || sqlstate || ':' || left(sqlerrm, 200);
end $f$;

do $todo$
declare
  r text := ''; v text;
  p1 uuid; p2 uuid; p3 uuid; k1 uuid; k3 uuid; k6 uuid; k7 uuid; kp uuid;
  c_fin constant text := 'FIN DE PRUEBAS SOCIEDAD DEL PROYECTO (se deshace todo):%';
  c_rech constant text := 'ERR23514:La sociedad firmante «%» no es la del proyecto%';
begin
  if coalesce(current_setting('erp.en_rama', true), '') <> 'si' then
    raise exception 'FIN DE PRUEBAS SOCIEDAD DEL PROYECTO:%', E'\nP0 esta prueba crea contratos y apaga un trigger: solo corre en rama → FALLA';
  end if;

  -- ============================================================ P. montaje (como postgres)
  begin
    insert into public.sociedades (clave, label, razon, domicilio) values
      ('zz_sp1', 'ZZ-SP 1', 'ZZ-SP PT 1', 'ZZ-domicilio'), ('zz_sp2', 'ZZ-SP 2', 'ZZ-SP PT 2', 'ZZ-domicilio')
      on conflict (clave) do nothing;
    insert into public.empresas (clave, nombre) values ('zz_sp_e1', 'ZZ-SP Empresa 1'), ('zz_sp_e2', 'ZZ-SP Empresa 2'), ('zz_sp_e3', 'ZZ-SP Empresa 3');
    update public.empresas set sociedad_clave = 'zz_sp1' where clave = 'zz_sp_e1';
    update public.empresas set sociedad_clave = 'zz_sp2' where clave = 'zz_sp_e2';   -- zz_sp_e3 se queda SIN sociedad (S8)
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 1', 'zz-sp-proyecto-1', 'zz_sp_e1', true) returning id into p1;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 2', 'zz-sp-proyecto-2', 'zz_sp_e2', true) returning id into p2;
    insert into public.proyectos (nombre, slug, empresa, activo) values ('ZZ-SP Proyecto 3', 'zz-sp-proyecto-3', 'zz_sp_e3', true) returning id into p3;
    r := r || pg_temp.l(true, 'P montaje: 2 sociedades, 3 empresas (la 3 sin sociedad), 3 proyectos');
  exception when others then
    raise exception using message = replace(c_fin, '%', r || pg_temp.l(false, 'P montaje: ' || sqlstate || ' ' || left(sqlerrm, 300)));
  end;

  -- ============================================================ S1/S2 alta
  v := pg_temp.alta('ZZ-SP-K1', p1, null, '{"sociedad_firmante": "zz_sp1"}');
  r := r || pg_temp.l(v !~ '^ERR', 'S1 alta en el proyecto 1 con SU sociedad entra (' || left(v, 90) || ')');
  if v !~ '^ERR' then k1 := v::uuid; end if;
  v := pg_temp.alta('ZZ-SP-K2', p1, null, '{"sociedad_firmante": "zz_sp2"}');
  r := r || pg_temp.l(v like c_rech, 'S2 alta en el proyecto 1 con la sociedad de OTRA empresa se rechaza (' || left(v, 120) || ')');

  -- ============================================================ S3 sin sociedad: entra y no se rellena
  v := pg_temp.alta('ZZ-SP-K3', p1, null, '{}');
  r := r || pg_temp.l(v !~ '^ERR'
                      and (select c.datos->'fields'->>'sociedad_firmante' from public.contratos c where c.id::text = v) is null,
                      'S3 alta sin sociedad entra y la base NO la rellena (' || left(v, 90) || ')');
  if v !~ '^ERR' then k3 := v::uuid; end if;

  -- ============================================================ S4 solo el nombre del proyecto
  v := pg_temp.alta('ZZ-SP-K4', null, 'ZZ-SP Proyecto 1', '{"sociedad_firmante": "zz_sp2"}');
  r := r || pg_temp.l(v like c_rech, 'S4 alta con solo el NOMBRE del proyecto 1 y otra sociedad se rechaza igual (' || left(v, 120) || ')');
  v := pg_temp.alta('ZZ-SP-K4b', null, 'ZZ-SP Proyecto 1', '{"sociedad_firmante": "zz_sp1"}');
  r := r || pg_temp.l(v !~ '^ERR', 'S4b la misma alta por nombre con SU sociedad entra (' || left(v, 90) || ')');

  -- ============================================================ S5 cambiar la sociedad
  v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp2"') where id = %L$q$, k1));
  r := r || pg_temp.l(v like c_rech, 'S5 cambiar la sociedad de K1 a la de otra empresa se rechaza (' || left(v, 120) || ')');
  v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, k3));
  r := r || pg_temp.l(v = 'OK', 'S5b poner a K3 (sin sociedad) la de su proyecto entra (' || left(v, 90) || ')');

  -- ============================================================ S6 cambiar de proyecto
  v := pg_temp.x(format($q$update public.contratos set proyecto_id = %L, proyecto_nombre = 'ZZ-SP Proyecto 2' where id = %L$q$, p2, k1));
  r := r || pg_temp.l(v like c_rech, 'S6 pasar K1 al proyecto 2 (otra empresa) con la sociedad vieja se rechaza (' || left(v, 120) || ')');
  v := pg_temp.x(format($q$update public.contratos set proyecto_id = %L, proyecto_nombre = 'ZZ-SP Proyecto 2',
                          datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp2"') where id = %L$q$, p2, k1));
  r := r || pg_temp.l(v = 'OK' and (select c.proyecto_id from public.contratos c where c.id = k1) = p2,
                      'S6b pasarlo al proyecto 2 CON la sociedad del 2 entra (' || left(v, 90) || ')');

  -- ============================================================ S7 contrato viejo descuadrado
  begin
    alter table public.contratos disable trigger trg_contrato_sociedad_existe;
    v := pg_temp.alta('ZZ-SP-K7', p1, null, '{"sociedad_firmante": "zz_sp2"}');
    alter table public.contratos enable trigger trg_contrato_sociedad_existe;
    if v !~ '^ERR' then k7 := v::uuid; end if;
  exception when others then
    r := r || pg_temp.l(false, 'S7 montaje del descuadrado: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  if k7 is not null then
    v := pg_temp.x(format($q$update public.contratos set precio_total = 120000 where id = %L$q$, k7));
    r := r || pg_temp.l(v = 'OK', 'S7 a un descuadrado viejo se le puede cambiar el precio sin tocar la sociedad (' || left(v, 90) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,resort}', '"ZZ-SP resort"') where id = %L$q$, k7));
    r := r || pg_temp.l(v = 'OK', 'S7b y otro campo de sus datos, tambien (' || left(v, 90) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, k7));
    r := r || pg_temp.l(v = 'OK', 'S7c corregirlo a la sociedad de su proyecto entra («corregir al reabrir») (' || left(v, 90) || ')');
  end if;

  -- ============================================================ S8 empresa sin sociedad
  v := pg_temp.alta('ZZ-SP-K8', p3, null, '{"sociedad_firmante": "zz_sp2"}');
  r := r || pg_temp.l(v !~ '^ERR', 'S8 proyecto de una empresa sin sociedad: cualquier sociedad activa entra, como antes (' || left(v, 90) || ')');

  -- ============================================================ S9 hijo de una reserva descuadrada
  begin
    alter table public.contratos disable trigger trg_contrato_sociedad_existe;
    v := pg_temp.alta('ZZ-SP-KP', p1, null, '{"sociedad_firmante": "zz_sp2"}');
    alter table public.contratos enable trigger trg_contrato_sociedad_existe;
    if v !~ '^ERR' then kp := v::uuid; end if;
  exception when others then
    r := r || pg_temp.l(false, 'S9 montaje del padre: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  if kp is not null then
    v := pg_temp.alta('ZZ-SP-K9', p1, null, '{"sociedad_firmante": "zz_sp1"}', kp);
    r := r || pg_temp.l(v like 'ERR23514:La sociedad firmante «zz_sp1» no coincide con la del contrato del que cuelga%',
                        'S9 hijo con la del proyecto de un padre descuadrado: lo frena la regla del padre; se corrige antes el padre (' || left(v, 120) || ')');
    v := pg_temp.x(format($q$update public.contratos set datos = jsonb_set(datos, '{fields,sociedad_firmante}', '"zz_sp1"') where id = %L$q$, kp));
    v := v || ' / ' || pg_temp.alta('ZZ-SP-K9b', p1, null, '{"sociedad_firmante": "zz_sp1"}', kp);
    r := r || pg_temp.l(v ~ '^OK / [0-9a-f-]{36}$', 'S9b corregido el padre, el hijo entra (' || left(v, 90) || ')');
  end if;

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
