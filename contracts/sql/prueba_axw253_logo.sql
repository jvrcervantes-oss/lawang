-- destructivo-ok: prueba que se deshace sola (raise exception final); solo inserta y actualiza una sociedad de prueba PRB.
-- PRUEBA — AXW-253 (11-oct-2026): 20261011150000_sociedades_logo_solo_estatico, para correr JUSTO DESPUÉS de aplicarla en Lawang.
-- Se pega entera en execute_sql (como postgres). NO ESCRIBE NADA: termina en `raise exception 'FIN DE PRUEBAS…'`.
-- Autocontenida a propósito: contracts/sql/prueba_ajustes_sociedades.sql está desfasada desde el bloque 12 (7-oct) y no llega al
-- final (fila LAW-535); esta no depende de ella ni de ningún usuario de prueba (el camino que mide, el UPDATE directo, no pasa por
-- la sesión). Casos: bucket privado y sin políticas; trigger puesto y su función sin EXECUTE para nadie con sesión; sociedad_guarda
-- ya no nombra la URL pública y nombra al trigger; las sociedades reales cumplen; un UPDATE directo con un logo de fuera da
-- 22023|logo_no_admitido y con una ruta válida entra; reenviar un logo viejo sin cambiarlo no bloquea otra columna; un alta con
-- logo de fuera no entra. El caso 1 da por hecho 512 KB de límite (medido el 11-oct en Lawang: 524288).
do $$
declare
  r text := ''; v text; n bigint; e text; h text; malo text;
  k text := 'prb_axw253';
  def text := pg_get_functiondef('public.sociedad_guarda(text,jsonb,boolean)'::regprocedure);
begin
  select format('%s/%s', b.public, b.file_size_limit) into v from storage.buckets b where b.id = 'sociedades';
  r := r || format(E'\n1 bucket sociedades privado (512 KB): %s → %s', v, case when v = 'f/524288' then 'ok' else 'FALLA' end);
  select count(*) into n from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
     and (p.policyname ilike '%sociedades%' or (coalesce(p.qual, '') || coalesce(p.with_check, '')) like '%sociedades%');
  r := r || format(E'\n2 ninguna política nombra sociedades: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  select count(*) into n from pg_trigger t where t.tgrelid = 'public.sociedades'::regclass and t.tgname = 'sociedades_logo_valida' and not t.tgisinternal;
  r := r || format(E'\n3 trigger sociedades_logo_valida puesto: %s → %s', n, case when n = 1 then 'ok' else 'FALLA' end);
  select count(*) into n from information_schema.role_routine_grants g
   where g.routine_schema = 'public' and g.routine_name = '_sociedades_logo_valida' and g.grantee in ('PUBLIC', 'anon', 'authenticated');
  r := r || format(E'\n4 su función sin EXECUTE para nadie con sesión: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);
  r := r || format(E'\n5 sociedad_guarda ya no nombra v_url_logo ni object/public/sociedades y sí al trigger: %s/%s/%s → %s',
    position('v_url_logo' in def) > 0, position('object/public/sociedades' in def) > 0, position('sociedades_logo_valida' in def) > 0,
    case when position('v_url_logo' in def) = 0 and position('object/public/sociedades' in def) = 0
              and position('sociedades_logo_valida' in def) > 0 then 'ok' else 'FALLA' end);
  select count(*) into n from public.sociedades s
   where s.logo is not null and s.logo !~* '^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\.(png|jpe?g|webp)$';
  r := r || format(E'\n6 sociedades reales con logo que no cumple: %s → %s', n, case when n = 0 then 'ok' else 'FALLA' end);

  -- sociedad PRB (los triggers de identidad/registro piden contexto de sesión al dar de alta: el alta va en modo replica,
  -- y los casos ya en modo normal, que es donde se dispara el trigger que se mide)
  execute 'set local session_replication_role = replica';
  insert into public.sociedades (clave, label, razon, domicilio, logo) values (k, 'PRB AXW-253', 'PRB AXW-253', 'PRB domicilio', null);
  execute 'set local session_replication_role = origin';
  foreach malo in array array[
      'https://evil.example/logo.png',
      'https://vtulllundrfennhjddhc.supabase.co/storage/v1/object/public/sociedades/' || k || '/' || repeat('a', 64) || '.png',
      '/contracts/assets/brand/../x.png',
      '/contracts/assets/brand/a.png?x=1',
      '/contracts/assets/brand/logo.svg',
      'javascript:alert(1)//a.png'] loop
    begin update public.sociedades set logo = malo where clave = k; e := 'entró'; h := '-';
    exception when others then get stacked diagnostics e = returned_sqlstate, h = pg_exception_hint; end;
    r := r || format(E'\n7 UPDATE directo rechaza %s: %s|%s → %s', left(malo, 60), e, coalesce(h, '-'),
      case when e = '22023' and h = 'logo_no_admitido' then 'ok' else 'FALLA' end);
  end loop;
  begin update public.sociedades set logo = '/contracts/assets/brand/sandalwoods-lockup.png' where clave = k; e := 'ok';
  exception when others then e := sqlstate; end;
  r := r || format(E'\n8 UPDATE directo con ruta válida entra: %s → %s', e, case when e = 'ok' then 'ok' else 'FALLA' end);
  -- un logo viejo que ya no cumple (puesto con el trigger apagado) no impide editar otra columna
  execute 'set local session_replication_role = replica';
  update public.sociedades set logo = 'https://viejo.example/a.png' where clave = k;
  execute 'set local session_replication_role = origin';
  -- `logo = logo` como hace sociedad_guarda (siempre manda el logo): dispara el trigger y mide la guarda «solo si cambia»
  begin update public.sociedades set logo = logo, domicilio = 'PRB domicilio 2' where clave = k; e := 'ok';
  exception when others then e := sqlstate; end;
  r := r || format(E'\n9 un logo viejo no bloquea editar el domicilio: %s → %s', e, case when e = 'ok' then 'ok' else 'FALLA' end);
  -- rama INSERT del trigger: un alta con un logo de fuera (modo normal; el trigger del logo corre antes que los de registro)
  begin insert into public.sociedades (clave, label, razon, domicilio, logo)
        values (k || '_2', 'PRB AXW-253 2', 'PRB AXW-253 2', 'PRB domicilio', 'https://evil.example/logo.png'); e := 'entró'; h := '-';
  exception when others then get stacked diagnostics e = returned_sqlstate, h = pg_exception_hint; end;
  r := r || format(E'
10 un ALTA con logo de fuera no entra: %s|%s → %s', e, coalesce(h, '-'),
    case when e = '22023' and h = 'logo_no_admitido' then 'ok' else 'FALLA' end);
  raise exception 'FIN DE PRUEBAS (se deshace todo):%', r;
end $$;
