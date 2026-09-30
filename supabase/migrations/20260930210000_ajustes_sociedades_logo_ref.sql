-- sociedad_guarda: el logo subido solo se acepta del bucket `sociedades` de ESTE proyecto (ref vtulllundrfennhjddhc, el de
-- intranet/v4/assets/instancia.js). Antes el regex admitia el ref de CUALQUIER proyecto ([a-z0-9]{20}) y esa URL acaba en un <img src>
-- de cada contrato, factura y PDF que ve el comprador (pixel de rastreo). Es 20260930200000 con UNA sola linea cambiada (v_url_logo);
-- una migracion aplicada no se edita, por eso va nueva. Mismos grants: revoke public/anon, execute a authenticated.
create or replace function public.sociedad_guarda(p_clave text, p_datos jsonb, p_nueva boolean default false)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_clave text := lower(btrim(coalesce(p_clave, '')));
  s       public.sociedades%rowtype;
  v_n     int;
  v_motivo text;
  n_label text; n_razon text; n_marca text; n_npwp text; n_npwp_label text; n_nib text; n_dom text; n_rep text;
  n_logo text; n_logo_alto text; n_folio text; n_tinta jsonb; n_debajo boolean; n_orden int; n_activa boolean; n_indo boolean;
  v_url_logo constant text := '^https://vtulllundrfennhjddhc\.supabase\.co/storage/v1/object/public/sociedades/';
  v_hex constant text := '^#[0-9A-Fa-f]{6}$';
  v_k text;
begin
  perform public._super_o_para();
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Faltan los datos de la sociedad' using errcode = '22023'; end if;

  if p_nueva then
    if v_clave !~ '^[a-z][a-z0-9_]{2,39}$' then
      raise exception 'La clave solo admite minúsculas, números y guion bajo, empieza por letra y va de 3 a 40 caracteres' using errcode = '22023';
    end if;
    if exists (select 1 from public.sociedades where clave = v_clave) then
      raise exception 'Ya existe una sociedad con esa clave' using errcode = '23505';
    end if;
    s.clave := v_clave; s.marca := ''; s.npwp_label := 'NPWP'; s.emisor_debajo := false; s.activa := true; s.orden := 0; s.es_indonesia := true;
  else
    select * into s from public.sociedades where clave = v_clave for update;
    if not found then raise exception 'Esa sociedad ya no existe' using errcode = 'P0002'; end if;
  end if;

  -- Cada campo: si viene, se normaliza; si no, conserva el actual. JSON null = vacío.
  n_razon := case when p_datos ? 'razon' then btrim(coalesce(p_datos ->> 'razon', '')) else s.razon end;
  n_dom   := case when p_datos ? 'domicilio' then btrim(coalesce(p_datos ->> 'domicilio', '')) else s.domicilio end;
  if coalesce(n_razon, '') = '' or coalesce(n_dom, '') = '' then
    raise exception 'La razón social y el domicilio son obligatorios: los imprime cada documento' using errcode = '22023';
  end if;
  n_label := case when p_datos ? 'label' then coalesce(nullif(btrim(coalesce(p_datos ->> 'label', '')), ''), n_razon) else coalesce(s.label, n_razon) end;
  n_marca := case when p_datos ? 'marca' then btrim(coalesce(p_datos ->> 'marca', '')) else s.marca end;
  n_npwp  := case when p_datos ? 'npwp' then nullif(btrim(coalesce(p_datos ->> 'npwp', '')), '') else s.npwp end;
  n_npwp_label := case when p_datos ? 'npwp_label' then coalesce(nullif(btrim(coalesce(p_datos ->> 'npwp_label', '')), ''), 'NPWP') else s.npwp_label end;
  n_nib   := case when p_datos ? 'nib' then nullif(btrim(coalesce(p_datos ->> 'nib', '')), '') else s.nib end;
  n_rep   := case when p_datos ? 'rep' then nullif(btrim(coalesce(p_datos ->> 'rep', '')), '') else s.rep end;
  n_logo  := case when p_datos ? 'logo' then nullif(btrim(coalesce(p_datos ->> 'logo', '')), '') else s.logo end;
  n_logo_alto := case when p_datos ? 'logo_alto' then nullif(btrim(coalesce(p_datos ->> 'logo_alto', '')), '') else s.logo_alto end;
  n_folio := case when p_datos ? 'folio' then nullif(btrim(coalesce(p_datos ->> 'folio', '')), '') else s.folio end;

  -- tinta: objeto {primary, deep} con colores #RRGGBB (o vacíos), o nada. Nunca {primary:'',deep:''}: eso es «hereda la de marca».
  if p_datos ? 'tinta' then
    if jsonb_typeof(p_datos -> 'tinta') = 'object' then
      for v_k in select jsonb_object_keys(p_datos -> 'tinta') loop
        if v_k not in ('primary', 'deep') then raise exception 'La tinta solo admite «primary» y «deep»' using errcode = '22023'; end if;
        if jsonb_typeof(p_datos -> 'tinta' -> v_k) <> 'string'
           or ((p_datos -> 'tinta' ->> v_k) <> '' and (p_datos -> 'tinta' ->> v_k) !~ v_hex) then
          raise exception 'La tinta «%» tiene que ser un color #RRGGBB', v_k using errcode = '22023';
        end if;
      end loop;
      n_tinta := case when coalesce(p_datos -> 'tinta' ->> 'primary', '') = '' and coalesce(p_datos -> 'tinta' ->> 'deep', '') = ''
                      then null else p_datos -> 'tinta' end;
    elsif jsonb_typeof(p_datos -> 'tinta') = 'null' then
      n_tinta := null;
    else
      raise exception 'La tinta es un objeto {primary, deep}' using errcode = '22023';
    end if;
  else
    n_tinta := s.tinta;
  end if;

  if p_datos ? 'emisor_debajo' then
    if jsonb_typeof(p_datos -> 'emisor_debajo') <> 'boolean' then raise exception '«emisor_debajo» es sí o no' using errcode = '22023'; end if;
    n_debajo := (p_datos ->> 'emisor_debajo')::boolean;
  else n_debajo := s.emisor_debajo; end if;
  if p_datos ? 'es_indonesia' then
    if jsonb_typeof(p_datos -> 'es_indonesia') <> 'boolean' then raise exception '«es_indonesia» es sí o no' using errcode = '22023'; end if;
    n_indo := (p_datos ->> 'es_indonesia')::boolean;
  else n_indo := s.es_indonesia; end if;
  if p_datos ? 'activa' and not p_nueva then
    if jsonb_typeof(p_datos -> 'activa') <> 'boolean' then raise exception '«activa» es sí o no' using errcode = '22023'; end if;
    n_activa := (p_datos ->> 'activa')::boolean;
  else n_activa := s.activa; end if;   -- en el alta nace activa siempre (lo impone el servidor)
  if p_datos ? 'orden' and coalesce(p_datos ->> 'orden', '') <> '' then
    if (p_datos ->> 'orden') !~ '^-?[0-9]{1,4}$' then raise exception 'El orden es un número entero' using errcode = '22023'; end if;
    n_orden := (p_datos ->> 'orden')::int;
  else n_orden := s.orden; end if;

  -- Validación de lo que CAMBIA (un valor histórico que ya no cumpliera la regla de hoy no impide editar el resto)
  if n_razon is distinct from s.razon and (char_length(n_razon) > 200 or n_razon ~ '[[:cntrl:]]') then
    raise exception 'La razón social va en una línea, de 1 a 200 caracteres' using errcode = '22023'; end if;
  if n_dom is distinct from s.domicilio and (char_length(n_dom) > 500 or regexp_replace(n_dom, '[\n\r\t]', '', 'g') ~ '[[:cntrl:]]') then
    raise exception 'El domicilio admite hasta 500 caracteres' using errcode = '22023'; end if;
  if n_label is distinct from s.label and (char_length(n_label) > 200 or n_label ~ '[[:cntrl:]]') then
    raise exception 'El nombre en el desplegable va en una línea, hasta 200 caracteres' using errcode = '22023'; end if;
  if n_marca is distinct from s.marca and (char_length(n_marca) > 120 or n_marca ~ '[[:cntrl:]]') then
    raise exception 'La marca va en una línea, hasta 120 caracteres' using errcode = '22023'; end if;
  if n_npwp is distinct from s.npwp and (char_length(n_npwp) > 60 or n_npwp ~ '[[:cntrl:]]') then
    raise exception 'La identificación fiscal va en una línea, hasta 60 caracteres' using errcode = '22023'; end if;
  if n_npwp_label is distinct from s.npwp_label and (char_length(n_npwp_label) > 20 or n_npwp_label ~ '[[:cntrl:]]') then
    raise exception 'La etiqueta fiscal va en una línea, hasta 20 caracteres' using errcode = '22023'; end if;
  if n_nib is distinct from s.nib and (char_length(n_nib) > 40 or n_nib ~ '[[:cntrl:]]') then
    raise exception 'El NIB va en una línea, hasta 40 caracteres' using errcode = '22023'; end if;
  if n_rep is distinct from s.rep and (char_length(n_rep) > 200 or n_rep ~ '[[:cntrl:]]') then
    raise exception 'El representante va en una línea, hasta 200 caracteres' using errcode = '22023'; end if;
  if n_logo_alto is distinct from s.logo_alto and n_logo_alto !~ '^[0-9]{1,3}(\.[0-9]{1,2})?mm$' then
    raise exception 'El alto del logo va en milímetros, por ejemplo 24mm' using errcode = '22023'; end if;
  if n_folio is distinct from s.folio and n_folio !~ v_hex then
    raise exception 'El folio es un color #RRGGBB' using errcode = '22023'; end if;
  if n_logo is distinct from s.logo and n_logo is not null and not (
       n_logo ~* '^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\.(png|jpe?g|webp)$'
       or n_logo ~ (v_url_logo || v_clave || '/[0-9a-f]{64}\.(png|jpg|webp)$')) then
    raise exception 'El logo tiene que ser una imagen PNG, JPEG o WebP subida desde Ajustes (nunca un SVG ni una dirección cualquiera)'
      using errcode = '22023', hint = 'logo_no_admitido';
  end if;

  v_motivo := nullif(left(btrim(coalesce(p_datos ->> 'motivo', '')), 500), '');
  perform set_config('axw.ajustes_motivo', coalesce(v_motivo, ''), true);

  if p_nueva then
    insert into public.sociedades (clave, label, razon, marca, npwp, npwp_label, nib, domicilio, rep, logo, logo_alto,
                                   emisor_debajo, folio, tinta, activa, orden, es_indonesia)
    values (v_clave, n_label, n_razon, n_marca, n_npwp, n_npwp_label, n_nib, n_dom, n_rep, n_logo, n_logo_alto,
            n_debajo, n_folio, n_tinta, true, n_orden, n_indo);
  else
    update public.sociedades x set
      label = n_label, razon = n_razon, marca = n_marca, npwp = n_npwp, npwp_label = n_npwp_label, nib = n_nib, domicilio = n_dom,
      rep = n_rep, logo = n_logo, logo_alto = n_logo_alto, emisor_debajo = n_debajo, folio = n_folio, tinta = n_tinta,
      activa = n_activa, orden = n_orden, es_indonesia = n_indo
    where x.clave = v_clave;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Esa sociedad ya no existe' using errcode = 'P0002'; end if;
  end if;
  perform set_config('axw.ajustes_motivo', '', true);
  return v_clave;
end $$;
revoke all on function public.sociedad_guarda(text, jsonb, boolean) from public, anon;
grant execute on function public.sociedad_guarda(text, jsonb, boolean) to authenticated;
