-- Prueba de LAW-650 (17-oct-2026, sesión lawang-mejoras-ux): la migración 20261017132000_law650_huella_texto_correos.sql.
-- Se ensaya con `--aplica 20260927130000_law343_prueba_envios_y_reactivar.sql,20261016112502_law338_l5_revoke.sql,20261017132000_law650_huella_texto_correos.sql`:
-- la rama de Lawang nace sin filas ni buckets, y la 343 crea `correos-enviados` como está en producción (privado, solo
-- application/pdf); el resto de la 343 ya está en la estructura y no cambia nada (add column if not exists, on conflict do
-- nothing, y su bloque de usuario_guarda_permisos vuelve al ver su marca). Así la 650 se mide sobre el bucket real.
-- La L5 (cierre de correos_enviados al navegador, aplicada en la viva el 16-oct) va antes porque la rama restaura la estructura
-- y luego reaplica los privilegios por defecto, que vuelven a dar SELECT a authenticated (1.er ensayo, 17-oct: E1/E3 en rojo
-- sin ella; mismo patrón que law338_l5_ataque.sql). Sin la L5 en la rama la prueba para en P0 en vez de dar un rojo falso.
-- Termina en raise: no deja rastro. Cada línea con su resultado:
--   A  las 5 columnas que escribe la fila de un contrato (las 2 nuevas + las 3 de LAW-343) y los comentarios
--   B  una fila VIEJA (huella y ruta nulas) pasa los dos checks, y los checks nacieron validados contra las filas que había
--   C  una fila nueva bien formada pasa; huella mal formada, ruta de otra huella y ruta sin huella se rechazan
--   D  el bucket: privado, application/pdf + text/plain (unido, sin repetidos) y sin policies en storage.objects
--   E  permisos: authenticated y anon siguen sin leer la tabla (L5) y la migración no dio nada nuevo
-- destructivo-ok: prueba en transacción que termina en raise (rollback)
create or replace function pg_temp.l(c boolean, t text) returns text language sql as $f$
  select E'\n' || replace(t, E'\n', ' ') || case when coalesce(c, false) then ' → ok' else ' → FALLA' end
$f$;

do $todo$
declare
  c_fin constant text := 'FIN DE PRUEBAS LAW-650 HUELLA DEL TEXTO (se deshace todo):%';
  r text := '';
  h constant text := repeat('ab', 32);
  h2 constant text := repeat('cd', 32);
  tipos text[];
  n int;
begin
  if has_table_privilege('authenticated', 'public.correos_enviados', 'select') then
    raise exception using message = replace(c_fin, '%', pg_temp.l(false,
      'P0 el cierre L5 no está en la rama (authenticated lee correos_enviados): falta --aplica 20261016112502_law338_l5_revoke.sql antes de la 650'));
  end if;

  -- ============================================================ A. columnas
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'correos_enviados'
     and column_name in ('mensaje_sha256', 'mensaje_path', 'pdf_path', 'pdf_sha256', 'pdf_bytes');
  r := r || pg_temp.l(n = 5, 'A1 las 5 columnas que pide la sonda de send-contract-email existen (' || n || ' de 5)');
  r := r || pg_temp.l(col_description('public.correos_enviados'::regclass,
                        (select attnum from pg_attribute where attrelid = 'public.correos_enviados'::regclass and attname = 'mensaje_path'))
                      ~ 'contratos/<sha256>\.txt', 'A2 mensaje_path lleva su comentario');

  -- ============================================================ B. filas viejas
  select count(*) into n from pg_constraint
   where conrelid = 'public.correos_enviados'::regclass and convalidated
     and conname in ('correos_mensaje_sha256_formato', 'correos_mensaje_path_de_su_huella');
  r := r || pg_temp.l(n = 2, 'B1 los dos checks existen y nacieron VALIDADOS (no NOT VALID): se comprobaron contra las filas que había');
  set local session_replication_role = replica;   -- sin claves ajenas: el contrato no existe en la rama (los CHECK sí se aplican)
  begin
    insert into public.correos_enviados (contrato_id, para, asunto, via, enviado_por)
    values (gen_random_uuid(), 'vieja@prueba.test', 'Fila vieja', 'manual', 'agente@prueba.test');
    r := r || pg_temp.l(true, 'B2 una fila vieja con huella y ruta nulas pasa los dos checks');
  exception when others then r := r || pg_temp.l(false, 'B2 fila vieja rechazada: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;

  -- ============================================================ C. filas nuevas
  begin
    insert into public.correos_enviados (contrato_id, para, asunto, via, enviado_por, mensaje_sha256, mensaje_path, pdf_path, pdf_sha256, pdf_bytes)
    values (gen_random_uuid(), 'nueva@prueba.test', 'Contrato', 'enlace_firma', 'agente@prueba.test', h, 'contratos/' || h || '.txt',
            'contratos/' || h2 || '.pdf', h2, 1234);
    r := r || pg_temp.l(true, 'C1 la fila que escribe la edge (huella, su ruta y las 3 del PDF) pasa');
  exception when others then r := r || pg_temp.l(false, 'C1 fila nueva rechazada: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  begin
    insert into public.correos_enviados (factura_id, para, asunto, via, enviado_por, mensaje_sha256)
    values (gen_random_uuid(), 'factura@prueba.test', 'Factura', 'factura', 'agente@prueba.test', h);
    r := r || pg_temp.l(true, 'C2 una factura con huella y sin ruta pasa');
  exception when others then r := r || pg_temp.l(false, 'C2 factura con huella rechazada: ' || sqlstate || ' ' || left(sqlerrm, 200));
  end;
  begin
    insert into public.correos_enviados (contrato_id, para, asunto, via, mensaje_sha256)
    values (gen_random_uuid(), 'x@prueba.test', 'x', 'manual', upper(h));
    r := r || pg_temp.l(false, 'C3 una huella en MAYÚSCULAS debería rechazarse');
  exception when check_violation then r := r || pg_temp.l(true, 'C3 huella en mayúsculas ⇒ rechazada (' || left(sqlerrm, 120) || ')');
  end;
  begin
    insert into public.correos_enviados (contrato_id, para, asunto, via, mensaje_sha256)
    values (gen_random_uuid(), 'x@prueba.test', 'x', 'manual', left(h, 63));
    r := r || pg_temp.l(false, 'C4 una huella de 63 caracteres debería rechazarse');
  exception when check_violation then r := r || pg_temp.l(true, 'C4 huella corta ⇒ rechazada');
  end;
  begin
    insert into public.correos_enviados (contrato_id, para, asunto, via, mensaje_sha256, mensaje_path)
    values (gen_random_uuid(), 'x@prueba.test', 'x', 'manual', h, 'contratos/' || h2 || '.txt');
    r := r || pg_temp.l(false, 'C5 la ruta de OTRA huella debería rechazarse');
  exception when check_violation then r := r || pg_temp.l(true, 'C5 ruta de otra huella ⇒ rechazada (' || left(sqlerrm, 120) || ')');
  end;
  begin
    insert into public.correos_enviados (contrato_id, para, asunto, via, mensaje_path)
    values (gen_random_uuid(), 'x@prueba.test', 'x', 'manual', 'contratos/' || h || '.txt');
    r := r || pg_temp.l(false, 'C6 una ruta sin huella debería rechazarse (el hueco del NULL)');
  exception when check_violation then r := r || pg_temp.l(true, 'C6 ruta con huella nula ⇒ rechazada');
  end;
  begin
    update public.correos_enviados set mensaje_path = 'otra/cosa.txt' where para = 'nueva@prueba.test';
    r := r || pg_temp.l(false, 'C7 cambiar la ruta de una fila buena debería rechazarse');
  exception when check_violation then r := r || pg_temp.l(true, 'C7 un UPDATE que desata la ruta de su huella ⇒ rechazado');
  end;
  set local session_replication_role = origin;

  -- ============================================================ D. bucket
  select b.allowed_mime_types into tipos from storage.buckets b where b.id = 'correos-enviados';
  r := r || pg_temp.l(tipos @> array['application/pdf', 'text/plain'],
                      'D1 el bucket admite application/pdf y text/plain: ' || coalesce(array_to_string(tipos, ','), '(nulo)'));
  r := r || pg_temp.l(cardinality(tipos) = (select count(distinct t) from unnest(tipos) t), 'D2 sin tipos repetidos');
  r := r || pg_temp.l((select not b.public from storage.buckets b where b.id = 'correos-enviados'), 'D3 el bucket sigue siendo privado');
  select count(*) into n from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and (coalesce(qual, '') || coalesce(with_check, '')) ~ 'correos-enviados';
  r := r || pg_temp.l(n = 0, 'D4 ninguna policy de storage.objects alcanza correos-enviados (solo service role): ' || n);

  -- ============================================================ E. permisos
  r := r || pg_temp.l(not has_table_privilege('authenticated', 'public.correos_enviados', 'select'),
                      'E1 authenticated sigue sin SELECT sobre correos_enviados (L5)');
  r := r || pg_temp.l(not has_table_privilege('anon', 'public.correos_enviados', 'select'),
                      'E2 anon sin SELECT sobre correos_enviados');
  r := r || pg_temp.l(not has_column_privilege('authenticated', 'public.correos_enviados', 'mensaje_path', 'select')
                      and not has_column_privilege('authenticated', 'public.correos_enviados', 'mensaje_sha256', 'select'),
                      'E3 authenticated tampoco lee las dos columnas nuevas por columna');

  raise exception using message = replace(c_fin, '%', r);
end $todo$;
