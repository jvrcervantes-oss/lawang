create or replace function public.congela_emisor_factura()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare s public.sociedades%rowtype;
begin
  -- UPDATE que NO cambia de sociedad: se preserva el congelado y nada mas.
  -- La pantalla manda `datos` entero sin la clave `emisor`, asi que sin esto
  -- una correccion de linea borraria la identidad del documento.
  if tg_op = 'UPDATE' and new.sociedad is not distinct from old.sociedad then
    if old.datos ? 'emisor' then
      new.datos := jsonb_set(coalesce(new.datos, '{}'::jsonb), '{emisor}', old.datos->'emisor', true);
    end if;
    return new;
  end if;

  -- INSERT, o UPDATE que SI cambia de sociedad: se (re)congela desde la tabla.
  -- Cambiar la sociedad solo es posible en un borrador — en una enviada lo
  -- impide `factura_enviada_no_cambia_emisor` — y ahi es una correccion
  -- deliberada del agente: preservar el emisor viejo dejaria `facturas.sociedad`
  -- diciendo una empresa y el documento impreso otra.
  if new.sociedad is null then
    raise exception 'Una factura no puede emitirse sin sociedad emisora.';
  end if;

  select * into s from public.sociedades where clave = new.sociedad;
  if not found then
    raise exception 'La sociedad emisora «%» no existe en public.sociedades.', new.sociedad;
  end if;

  new.datos := jsonb_set(
    coalesce(new.datos, '{}'::jsonb), '{emisor}',
    jsonb_build_object('clave', s.clave, 'razon', s.razon, 'marca', s.marca,
      'npwp', s.npwp, 'npwp_label', s.npwp_label, 'nib', s.nib,
      'domicilio', s.domicilio, 'rep', s.rep, 'congelado_en', to_jsonb(now())),
    true);
  return new;
end; $$;

revoke execute on function public.congela_emisor_factura() from anon, authenticated;;
