-- The Collection v2 · F3a-bis (5-oct-2026): ficha_publica_guarda EXIGE la versión cuando la ficha ya existe.
--
-- PORQUÉ. En 20261005120000, con p_version NULL y el slug YA existente, guarda no daba error: editaba esa ficha (de cualquier proyecto, publicada o no)
-- sin control de concurrencia, y un «alta» que llevara proyecto_id REASIGNARÍA la ficha ajena. Lo cazó Desarrollo al construir la pantalla F3b.
-- Regla: un servidor no puede depender de que la pantalla se acuerde de mandar la versión.
--
-- QUÉ CAMBIA (un solo bloque, en la rama «la fila existe»): fila existente + p_version null → 22023 «Ya existe una ficha con esa dirección; ábrela para editarla».
-- Camino normal intacto: inexistente + null = alta · existente + versión vigente = edición · existente + versión distinta = 40001 «Otra persona cambió…» ·
-- inexistente + versión = 40001 «Esa ficha ya no existe…» (la sonda de la pantalla depende de esos textos de 40001: NO se tocan).
-- El resto del cuerpo es idéntico al de 20261005120000. Misma firma → create or replace; mismos grants y comment actualizado. Llamador: pestaña Ficha pública (F3b).
--
-- ROLLBACK: volver a aplicar la función de 20261005120000 (su sección «4. ficha_publica_guarda v2», con su comment/revoke/grant).
-- Pruebas: contracts/sql/prueba_ficha_publica_editor.sql (casos n1–n3) y prueba_ficha_publica.sql.

create or replace function public.ficha_publica_guarda(p_slug text, p_cambios jsonb, p_version timestamptz default null)
  returns jsonb
  language plpgsql security definer set search_path to ''
  as $$
declare
  v_ok  text[] := array['linea', 'region_key', 'region', 'publicada_web', 'en_coleccion', 'destacada', 'destacada_home', 'orden',
                        'proyecto_id', 'modelo_id', 'unidad_id', 'precio_modo', 'precio_eur', 'tenure', 'lease_years', 'estado_obra',
                        'dormitorios', 'banos', 'construido_m2', 'parcela_m2', 'textos', 'ficha'];
  v_old    public.fichas_publicas%rowtype;
  v_new    public.fichas_publicas%rowtype;
  v_slug   text := lower(btrim(coalesce(p_slug, '')));
  v_nueva  boolean := false;
  v_textos jsonb;
  v_ficha  jsonb;
  v_m      jsonb;
  v_ver    timestamptz;
  k text; w jsonb; l text; x jsonb;
  v_c text;
begin
  if not public.es_admin() then
    raise exception 'La ficha pública la edita administración' using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(v_slug) not between 3 and 60 then
    raise exception 'La dirección solo admite minúsculas, números y guiones (de 3 a 60)' using errcode = '22023';
  end if;
  if jsonb_typeof(p_cambios) is distinct from 'object' then
    raise exception 'Datos de la ficha no válidos' using errcode = '22023';
  end if;
  if char_length(p_cambios::text) > 200000 then
    raise exception 'La ficha es demasiado grande' using errcode = '22023';
  end if;
  for k in select jsonb_object_keys(p_cambios) loop
    if not (k = any (v_ok)) then
      raise exception 'Ese dato de la ficha no se edita desde aquí: %', k using errcode = '22023';
    end if;
  end loop;
  for k in select e.key from jsonb_each(p_cambios) e where jsonb_typeof(e.value) = 'null'
                                                       and e.key in ('linea', 'region_key', 'publicada_web', 'en_coleccion', 'destacada', 'destacada_home', 'orden', 'precio_modo', 'textos', 'ficha') loop
    raise exception 'Ese dato de la ficha no puede quedar vacío: %', k using errcode = '22023';
  end loop;
  if p_cambios ? 'textos' and jsonb_typeof(p_cambios->'textos') <> 'object' then
    raise exception 'Los textos se envían como un objeto con las claves a cambiar' using errcode = '22023';
  end if;
  if p_cambios ? 'ficha' and jsonb_typeof(p_cambios->'ficha') <> 'object' then
    raise exception 'Los datos de ficha se envían como un objeto con las claves a cambiar' using errcode = '22023';
  end if;

  select * into v_old from public.fichas_publicas f where f.slug = v_slug for update;
  if not found then
    if p_version is not null then
      raise exception 'Esa ficha ya no existe; recarga la pantalla' using errcode = '40001';
    end if;
    if not (p_cambios ? 'linea' and p_cambios ? 'region_key') then
      raise exception 'Una ficha nueva necesita línea y región (bali o sumba)' using errcode = '22023';
    end if;
    if p_cambios ? 'publicada_web' and (p_cambios->>'publicada_web') is distinct from 'false' then
      raise exception 'Una ficha nueva nace sin publicar: créala y publícala después' using errcode = '22023';
    end if;
    begin
      insert into public.fichas_publicas (slug, linea, region_key)
      values (v_slug, p_cambios->>'linea', p_cambios->>'region_key')
      returning * into v_old;
    exception
      when unique_violation then
        raise exception 'Otra persona acaba de crear esa ficha; recárgala' using errcode = '40001';
      when check_violation then
        raise exception 'La línea debe ser signature, villa o land y la región bali o sumba' using errcode = '23514';
    end;
    v_nueva := true;
  elsif p_version is null then
    -- una ficha que ya existe solo se edita con la versión que la pantalla leyó: sin ella no hay control de concurrencia y un «alta» con
    -- proyecto_id reasignaría la ficha de otro proyecto. El servidor no depende de que el cliente se acuerde de mandarla.
    raise exception 'Ya existe una ficha con esa dirección; ábrela para editarla' using errcode = '22023';
  elsif v_old.actualizado_en is distinct from p_version then
    raise exception 'Otra persona cambió esta ficha; recárgala' using errcode = '40001';
  end if;

  -- MEZCLA POR CLAVE (en el servidor, nunca reemplazo entero). Un valor null en el parche borra esa clave.
  v_textos := v_old.textos;
  if p_cambios ? 'textos' then
    for k, w in select * from jsonb_each(p_cambios->'textos') loop
      if jsonb_typeof(w) = 'null' then
        v_textos := v_textos - k;
      elsif jsonb_typeof(w) = 'object' then
        v_m := case when jsonb_typeof(v_textos->k) = 'object' then v_textos->k else '{}'::jsonb end;
        for l, x in select * from jsonb_each(w) loop
          v_m := case when jsonb_typeof(x) = 'null' then v_m - l else v_m || jsonb_build_object(l, x) end;
        end loop;
        v_textos := case when v_m = '{}'::jsonb then v_textos - k else v_textos || jsonb_build_object(k, v_m) end;
      else
        v_textos := v_textos || jsonb_build_object(k, w);   -- el validador lo rechaza con su mensaje
      end if;
    end loop;
  end if;
  v_ficha := v_old.ficha;
  if p_cambios ? 'ficha' then
    for k, w in select * from jsonb_each(p_cambios->'ficha') loop
      v_ficha := case when jsonb_typeof(w) = 'null' then v_ficha - k else v_ficha || jsonb_build_object(k, w) end;
    end loop;
  end if;
  perform public._ficha_valida(v_textos, v_ficha);

  -- columnas escalares: las ausentes conservan su valor, las presentes lo sustituyen
  begin
    v_new := jsonb_populate_record(v_old, p_cambios - 'textos' - 'ficha');
  exception
    when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch or invalid_parameter_value then
      raise exception 'Algún dato de la ficha tiene un formato no válido (números, fechas o identificadores)' using errcode = '22023';
  end;
  v_new.textos := v_textos;
  v_new.ficha  := v_ficha;
  v_new.region := nullif(btrim(v_new.region), '');
  -- `region` es una columna escalar y no pasa por _ficha_valida: texto plano también aquí (el servidor no depende del escape del cliente)
  if v_new.region ~ '[<>]' then
    raise exception 'La región es texto plano: no admite < ni >' using errcode = '22023';
  end if;
  -- un solo dueño del «desde»: con 'desde' o 'consultar' no se guarda importe (coleccion_publica() lo deriva de las unidades)
  if v_new.precio_modo in ('desde', 'consultar') then v_new.precio_eur := null; end if;

  -- vínculos
  if v_new.proyecto_id is not null and not exists (select 1 from public.proyectos p where p.id = v_new.proyecto_id) then
    raise exception 'Ese proyecto no existe' using errcode = '22023';
  end if;
  -- unidad/modelo solo se comprueban si el vínculo CAMBIA: una ficha que perdió el proyecto por ON DELETE SET NULL debe poder despublicarse
  if v_new.unidad_id is not null
     and (v_new.unidad_id is distinct from v_old.unidad_id or v_new.proyecto_id is distinct from v_old.proyecto_id) then
    if v_new.proyecto_id is null or not exists (select 1 from public.unidades u where u.id = v_new.unidad_id and u.proyecto_id = v_new.proyecto_id) then
      raise exception 'La unidad elegida no pertenece al proyecto de la ficha' using errcode = '22023';
    end if;
    if exists (select 1 from public.fichas_publicas o where o.unidad_id = v_new.unidad_id and o.id <> v_old.id) then
      raise exception 'Esa unidad ya tiene otra ficha pública' using errcode = '22023';
    end if;
  end if;
  if v_new.modelo_id is not null
     and (v_new.modelo_id is distinct from v_old.modelo_id or v_new.proyecto_id is distinct from v_old.proyecto_id)
     and (v_new.proyecto_id is null
          or not exists (select 1 from public.modelos_villa mv where mv.proyecto_id = v_new.proyecto_id and mv.modelo_id = v_new.modelo_id)) then
    raise exception 'El modelo elegido no está entre los modelos de villa del proyecto de la ficha' using errcode = '22023';
  end if;

  -- reglas de lo que ve el cliente (con mensaje legible antes de que salte el CHECK de la base)
  if v_new.precio_modo = 'fijo' and v_new.linea <> 'signature' then
    raise exception 'El precio fijo solo existe en la línea Signature' using errcode = '23514';
  end if;
  if v_new.publicada_web then
    if not v_old.publicada_web and v_new.proyecto_id is null then
      raise exception 'Para publicar la ficha hace falta vincularla a un proyecto' using errcode = '23514';
    end if;
    if nullif(btrim(v_new.textos #>> '{title,en}'), '') is null then
      raise exception 'Para publicar la ficha hace falta el título en inglés' using errcode = '23514';
    end if;
    if not v_old.publicada_web and nullif(btrim(v_new.textos #>> '{title,es}'), '') is null then
      raise exception 'Para publicar la ficha hace falta el título en español' using errcode = '23514';
    end if;
    if v_new.precio_modo = 'fijo' and coalesce(v_new.precio_eur, 0) <= 0 then
      raise exception 'Para publicar con precio fijo hace falta un importe mayor que 0' using errcode = '23514';
    end if;
  end if;

  begin
    update public.fichas_publicas f set
      linea = v_new.linea, region_key = v_new.region_key, region = v_new.region,
      publicada_web = v_new.publicada_web, en_coleccion = v_new.en_coleccion, destacada = v_new.destacada,
      destacada_home = v_new.destacada_home, orden = v_new.orden,
      proyecto_id = v_new.proyecto_id, modelo_id = v_new.modelo_id, unidad_id = v_new.unidad_id,
      precio_modo = v_new.precio_modo, precio_eur = v_new.precio_eur, tenure = v_new.tenure, lease_years = v_new.lease_years,
      estado_obra = v_new.estado_obra, dormitorios = v_new.dormitorios, banos = v_new.banos,
      construido_m2 = v_new.construido_m2, parcela_m2 = v_new.parcela_m2,
      textos = v_new.textos, ficha = v_new.ficha
    where f.id = v_old.id;
  exception
    when unique_violation then
      raise exception 'Otra persona cambió esta ficha a la vez; recárgala' using errcode = '40001';
    when check_violation then
      get stacked diagnostics v_c = constraint_name;
      raise exception 'Algún dato está fuera de rango o falta para guardar la ficha (regla %)', v_c using errcode = '23514';
  end;

  select f.actualizado_en into v_ver from public.fichas_publicas f where f.id = v_old.id;
  return jsonb_build_object('id', v_old.id, 'slug', v_slug,
                            'version', to_char(v_ver at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
end $$;
comment on function public.ficha_publica_guarda(text, jsonb, timestamptz) is
  'Alta/edición de una ficha pública (The Collection v2, F3a). Solo admin/super_admin (comprobado dentro). Lista blanca de claves; el slug no se cambia. textos y ficha son PARCHES mezclados en el servidor por clave (null borra). p_version = actualizado_en leído: obligatoria si la ficha ya existe (sin ella, 22023; si no coincide, 40001); sin versión solo se crea una ficha NUEVA. Valida forma (_ficha_valida), vínculos y publicación. Devuelve {id, slug, version}. Llamador: pestaña Ficha pública de intranet/v4/proyectos (F3b).';
revoke all on function public.ficha_publica_guarda(text, jsonb, timestamptz) from public, anon, service_role;
grant execute on function public.ficha_publica_guarda(text, jsonb, timestamptz) to authenticated;
