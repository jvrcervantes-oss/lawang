-- destructivo-ok: los DELETE van DENTRO de _reparto_aplica (quitar una cuenta de un reparto, lo mismo que hacía la pantalla); esta migración no borra ninguna fila al aplicarse.
-- Frontera frontend/backend — A QUIÉN SE PAGA Y QUIÉN FIRMA por el servidor (26-sep-2026, LAW-336 pieza 4).
-- Máxima del owner: «no te creas NADA del front-end». SOLO AÑADE; el revoke va en otra migración,
-- cuando las pantallas servidas ya llamen a estas funciones.
-- Tablas: cuentas_bancarias, plantilla_cuentas, proyecto_cuentas, plantillas_contrato (solo `archivada`),
-- sociedades. Son la materia prima de un fraude de transferencia (rev. previa #118): el número de
-- cuenta que imprime el contrato y la sociedad que lo emite.
-- Permiso = policies de hoy: es_super_admin() en las cinco.
-- Lo que decidía la PANTALLA y ya no:
-- · alta de cuenta: clave válida, nace DESACTIVADA, `orden` al final — ahora lo pone el servidor;
-- · reparto: la pantalla mandaba N inserts/deletes sueltos (un fallo a media cadena dejaba el reparto
--   a medias); ahora cada nivel es un conjunto que se aplica entero en una transacción, la precargada
--   tiene que estar entre las marcadas, y si alguien lo cambió desde que se abrió la pantalla, para;
-- · plantillas_contrato: la pantalla podía escribir cualquier columna (cobra, nombre…); ahora solo `archivada`;
-- · sociedades: allowlist de las 16 columnas en el servidor; razón y domicilio obligatorios; nace activa.
-- Los triggers de autoría (sella_cuenta_bancaria, un_solo_default_*, _sociedades_autoria/_log) siguen
-- funcionando: auth.uid()/auth.email() leen el JWT de la petición también dentro de un DEFINER.

create or replace function public._super_o_para() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not public.es_super_admin() then
    raise exception 'Cuentas de cobro, reparto y sociedades son solo para super_admin' using errcode = '42501';
  end if;
end $$;
revoke all on function public._super_o_para() from public, anon, authenticated;

-- Aplica una lista de niveles de reparto. Cada nivel:
--   {"proyecto_id": uuid|null, "slug": text, "claves": [text], "def": text|null, "antes": [text]?}
-- proyecto_id null = plantilla_cuentas (regla general); con proyecto = proyecto_cuentas (excepción,
-- slug '*' = cualquier contrato). `antes` (opcional) = las claves que la pantalla tenía: si la base ya
-- no coincide, alguien lo cambió en medio y se para en vez de pisarlo.
create or replace function public._reparto_aplica(p_niveles jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  n jsonb; v_proy uuid; v_slug text; v_claves text[]; v_def text; v_antes text[]; v_hoy text[];
begin
  if p_niveles is null or jsonb_typeof(p_niveles) <> 'array' then
    raise exception 'Reparto sin niveles' using errcode = '22023';
  end if;
  for n in select * from jsonb_array_elements(p_niveles) loop
    v_proy := nullif(n->>'proyecto_id', '')::uuid;
    v_slug := nullif(btrim(coalesce(n->>'slug', '')), '');
    if v_slug is null then raise exception 'Reparto sin tipo de contrato' using errcode = '22023'; end if;
    if jsonb_typeof(n->'claves') is distinct from 'array' then raise exception 'Reparto sin lista de cuentas' using errcode = '22023'; end if;
    select coalesce(array_agg(distinct x), '{}') into v_claves from jsonb_array_elements_text(n->'claves') x;
    v_def := nullif(n->>'def', '');
    if v_def is not null and not (v_def = any(v_claves)) then
      raise exception 'La precargada «%» no está entre las cuentas marcadas', v_def using errcode = '22023';
    end if;
    if exists (select 1 from unnest(v_claves) c where not exists (select 1 from public.cuentas_bancarias b where b.clave = c)) then
      raise exception 'Alguna cuenta del reparto no existe' using errcode = '23503';
    end if;

    if v_proy is null then
      if not exists (select 1 from public.plantillas_contrato where slug = v_slug) then
        raise exception 'El tipo de contrato «%» no existe', v_slug using errcode = '23503';
      end if;
      select coalesce(array_agg(clave), '{}') into v_hoy from public.plantilla_cuentas where slug = v_slug;
    else
      if v_slug <> '*' and not exists (select 1 from public.plantillas_contrato where slug = v_slug) then
        raise exception 'El tipo de contrato «%» no existe', v_slug using errcode = '23503';
      end if;
      if not exists (select 1 from public.proyectos where id = v_proy) then
        raise exception 'Ese proyecto no existe' using errcode = '23503';
      end if;
      select coalesce(array_agg(clave), '{}') into v_hoy from public.proyecto_cuentas where proyecto_id = v_proy and slug = v_slug;
    end if;

    if n ? 'antes' and jsonb_typeof(n->'antes') = 'array' then
      select coalesce(array_agg(distinct x), '{}') into v_antes from jsonb_array_elements_text(n->'antes') x;
      if not (v_antes @> v_hoy and v_hoy @> v_antes) then
        raise exception 'Alguien ha cambiado este reparto mientras lo tenías abierto: recarga la pantalla y vuelve a hacerlo'
          using errcode = '40001';
      end if;
    end if;

    if v_proy is null then
      delete from public.plantilla_cuentas where slug = v_slug and not (clave = any(v_claves));
      insert into public.plantilla_cuentas (slug, clave)
        select v_slug, c from unnest(v_claves) c on conflict (slug, clave) do nothing;
      -- primero se desmarca, luego se marca: el trigger garantiza «no dos», no «ninguna»
      update public.plantilla_cuentas set es_default = false
        where slug = v_slug and es_default and clave is distinct from v_def;
      if v_def is not null then
        update public.plantilla_cuentas set es_default = true where slug = v_slug and clave = v_def and not es_default;
      end if;
    else
      delete from public.proyecto_cuentas where proyecto_id = v_proy and slug = v_slug and not (clave = any(v_claves));
      insert into public.proyecto_cuentas (proyecto_id, slug, clave)
        select v_proy, v_slug, c from unnest(v_claves) c on conflict (proyecto_id, slug, clave) do nothing;
      update public.proyecto_cuentas set es_default = false
        where proyecto_id = v_proy and slug = v_slug and es_default and clave is distinct from v_def;
      if v_def is not null then
        update public.proyecto_cuentas set es_default = true
          where proyecto_id = v_proy and slug = v_slug and clave = v_def and not es_default;
      end if;
    end if;
  end loop;
end $$;
revoke all on function public._reparto_aplica(jsonb) from public, anon, authenticated;

create or replace function public.reparto_cuentas_guarda(p_niveles jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public._super_o_para();
  perform public._reparto_aplica(p_niveles);
end $$;
revoke all on function public.reparto_cuentas_guarda(jsonb) from public, anon;
grant execute on function public.reparto_cuentas_guarda(jsonb) to authenticated;

-- Alta (p_nueva) o edición de una cuenta de cobro, y opcionalmente su reparto, en una transacción.
-- Edición: solo cambian las columnas que vienen en p_datos (la pantalla clásica no manda es_propia);
-- `clave`, `orden` y la autoría no se tocan nunca desde aquí.
create or replace function public.cuenta_bancaria_guarda(p_clave text, p_datos jsonb, p_nueva boolean default false,
                                                         p_reparto jsonb default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_clave text := lower(btrim(coalesce(p_clave, '')));
  v_extra jsonb := case when p_datos ? 'extra' and jsonb_typeof(p_datos->'extra') <> 'null' then p_datos->'extra' else '""'::jsonb end;
  v_propia boolean := case when jsonb_typeof(p_datos->'es_propia') = 'boolean' then (p_datos->>'es_propia')::boolean end;
  v_n int;
begin
  perform public._super_o_para();
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Faltan los datos de la cuenta' using errcode = '22023'; end if;
  if p_nueva then
    if v_clave !~ '^[a-z0-9_]{3,}$' then
      raise exception 'La clave va en minúsculas, números y guión bajo, mínimo 3 caracteres' using errcode = '22023';
    end if;
    if exists (select 1 from public.cuentas_bancarias where clave = v_clave) then
      raise exception 'Ya existe una cuenta con la clave «%»', v_clave using errcode = '23505';
    end if;
    if btrim(coalesce(p_datos->>'label', '')) = '' or btrim(coalesce(p_datos->>'titular', '')) = ''
       or btrim(coalesce(p_datos->>'cuenta', '')) = '' then
      raise exception 'Hacen falta la etiqueta, el titular y el número de cuenta' using errcode = '22023';
    end if;
    -- nace DESACTIVADA y al final de la lista: no entra en ningún desplegable hasta que alguien
    -- compruebe el número con el justificante delante. Lo que diga la pantalla de `activa` no cuenta.
    insert into public.cuentas_bancarias (clave, label, titular, banco, cuenta, codigo, direccion, extra,
                                          es_escrow, activa, orden, es_propia)
    values (v_clave, btrim(p_datos->>'label'), btrim(p_datos->>'titular'), btrim(coalesce(p_datos->>'banco', '')),
            btrim(p_datos->>'cuenta'), btrim(coalesce(p_datos->>'codigo', '')), btrim(coalesce(p_datos->>'direccion', '')),
            v_extra, coalesce((p_datos->>'es_escrow')::boolean, false), false,
            (select coalesce(max(orden), 0) + 10 from public.cuentas_bancarias), v_propia);
  else
    update public.cuentas_bancarias c set
      label     = case when p_datos ? 'label'     then btrim(coalesce(p_datos->>'label', ''))     else c.label end,
      titular   = case when p_datos ? 'titular'   then btrim(coalesce(p_datos->>'titular', ''))   else c.titular end,
      banco     = case when p_datos ? 'banco'     then btrim(coalesce(p_datos->>'banco', ''))     else c.banco end,
      cuenta    = case when p_datos ? 'cuenta'    then btrim(coalesce(p_datos->>'cuenta', ''))    else c.cuenta end,
      codigo    = case when p_datos ? 'codigo'    then btrim(coalesce(p_datos->>'codigo', ''))    else c.codigo end,
      direccion = case when p_datos ? 'direccion' then btrim(coalesce(p_datos->>'direccion', '')) else c.direccion end,
      extra     = case when p_datos ? 'extra'     then v_extra                                    else c.extra end,
      es_escrow = case when p_datos ? 'es_escrow' then coalesce((p_datos->>'es_escrow')::boolean, false) else c.es_escrow end,
      activa    = case when p_datos ? 'activa'    then coalesce((p_datos->>'activa')::boolean, false)    else c.activa end,
      es_propia = case when p_datos ? 'es_propia' then v_propia                                 else c.es_propia end
    where c.clave = v_clave;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Esa cuenta ya no existe' using errcode = 'P0002'; end if;
    -- la etiqueta es lo único por lo que el agente distingue una cuenta de otra en el desplegable
    if exists (select 1 from public.cuentas_bancarias where clave = v_clave and btrim(label) = '') then
      raise exception 'La etiqueta no puede quedar vacía: es lo que se lee en el desplegable del contrato' using errcode = '22023';
    end if;
  end if;
  if p_reparto is not null then perform public._reparto_aplica(p_reparto); end if;
  return v_clave;
end $$;
revoke all on function public.cuenta_bancaria_guarda(text, jsonb, boolean, jsonb) from public, anon;
grant execute on function public.cuenta_bancaria_guarda(text, jsonb, boolean, jsonb) to authenticated;

-- Archivar/desarchivar un tipo de contrato (es un FLAG, nunca un borrado: plantilla_cuentas cuelga con
-- ON DELETE CASCADE) y, opcionalmente, su reparto — en una transacción. Nada más de la fila es escribible.
create or replace function public.plantilla_contrato_guarda(p_slug text, p_archivada boolean default null,
                                                            p_reparto jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform public._super_o_para();
  if not exists (select 1 from public.plantillas_contrato where slug = p_slug) then
    raise exception 'Ese tipo de contrato no existe' using errcode = 'P0002';
  end if;
  if p_archivada is not null then
    update public.plantillas_contrato set archivada = p_archivada where slug = p_slug and archivada is distinct from p_archivada;
  end if;
  if p_reparto is not null then perform public._reparto_aplica(p_reparto); end if;
end $$;
revoke all on function public.plantilla_contrato_guarda(text, boolean, jsonb) from public, anon;
grant execute on function public.plantilla_contrato_guarda(text, boolean, jsonb) to authenticated;

-- Alta o edición de una sociedad emisora. Solo las 16 columnas que antes tenía el GRANT de UPDATE;
-- `clave` no se cambia nunca (además lo para _sociedades_autoria). En el alta, nace activa.
create or replace function public.sociedad_guarda(p_clave text, p_datos jsonb, p_nueva boolean default false)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_clave text := lower(btrim(coalesce(p_clave, '')));
  v_razon text := btrim(coalesce(p_datos->>'razon', ''));
  v_dom text := btrim(coalesce(p_datos->>'domicilio', ''));
  v_tinta jsonb := case when jsonb_typeof(p_datos->'tinta') = 'object' then p_datos->'tinta' end;
  v_n int;
begin
  perform public._super_o_para();
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Faltan los datos de la sociedad' using errcode = '22023'; end if;
  if v_razon = '' or v_dom = '' then
    raise exception 'La razón social y el domicilio son obligatorios: los imprime cada documento' using errcode = '22023';
  end if;
  if p_nueva then
    if v_clave !~ '^[a-z][a-z0-9_]{2,}$' then
      raise exception 'La clave solo admite minúsculas, números y guion bajo, empieza por letra y tiene al menos 3 caracteres' using errcode = '22023';
    end if;
    if exists (select 1 from public.sociedades where clave = v_clave) then
      raise exception 'Ya existe una sociedad con esa clave' using errcode = '23505';
    end if;
    insert into public.sociedades (clave, label, razon, marca, npwp, npwp_label, nib, domicilio, rep, logo, logo_alto,
                                   emisor_debajo, folio, tinta, activa, orden, es_indonesia)
    values (v_clave, coalesce(nullif(btrim(coalesce(p_datos->>'label', '')), ''), v_razon), v_razon,
            btrim(coalesce(p_datos->>'marca', '')), nullif(btrim(coalesce(p_datos->>'npwp', '')), ''),
            coalesce(nullif(btrim(coalesce(p_datos->>'npwp_label', '')), ''), 'NPWP'), nullif(btrim(coalesce(p_datos->>'nib', '')), ''),
            v_dom, nullif(btrim(coalesce(p_datos->>'rep', '')), ''), nullif(btrim(coalesce(p_datos->>'logo', '')), ''),
            nullif(btrim(coalesce(p_datos->>'logo_alto', '')), ''), coalesce((p_datos->>'emisor_debajo')::boolean, false),
            nullif(btrim(coalesce(p_datos->>'folio', '')), ''), v_tinta, true,
            coalesce(nullif(p_datos->>'orden', '')::int, 0), coalesce((p_datos->>'es_indonesia')::boolean, true));
  else
    update public.sociedades s set
      label = coalesce(nullif(btrim(coalesce(p_datos->>'label', '')), ''), v_razon), razon = v_razon,
      marca = btrim(coalesce(p_datos->>'marca', '')), npwp = nullif(btrim(coalesce(p_datos->>'npwp', '')), ''),
      npwp_label = coalesce(nullif(btrim(coalesce(p_datos->>'npwp_label', '')), ''), 'NPWP'),
      nib = nullif(btrim(coalesce(p_datos->>'nib', '')), ''), domicilio = v_dom,
      rep = nullif(btrim(coalesce(p_datos->>'rep', '')), ''), logo = nullif(btrim(coalesce(p_datos->>'logo', '')), ''),
      logo_alto = nullif(btrim(coalesce(p_datos->>'logo_alto', '')), ''),
      emisor_debajo = coalesce((p_datos->>'emisor_debajo')::boolean, false),
      folio = nullif(btrim(coalesce(p_datos->>'folio', '')), ''), tinta = v_tinta,
      activa = case when p_datos ? 'activa' then coalesce((p_datos->>'activa')::boolean, s.activa) else s.activa end,
      orden = coalesce(nullif(p_datos->>'orden', '')::int, s.orden),
      es_indonesia = case when p_datos ? 'es_indonesia' then coalesce((p_datos->>'es_indonesia')::boolean, s.es_indonesia) else s.es_indonesia end
    where s.clave = v_clave;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Esa sociedad ya no existe' using errcode = 'P0002'; end if;
  end if;
  return v_clave;
end $$;
revoke all on function public.sociedad_guarda(text, jsonb, boolean) from public, anon;
grant execute on function public.sociedad_guarda(text, jsonb, boolean) to authenticated;
