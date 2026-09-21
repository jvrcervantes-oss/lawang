create or replace function public.congela_emisor_factura()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare s public.sociedades%rowtype;
begin
  if tg_op = 'UPDATE' then
    if old.datos ? 'emisor' then
      new.datos := jsonb_set(coalesce(new.datos, '{}'::jsonb), '{emisor}', old.datos->'emisor', true);
    end if;
    return new;
  end if;

  if new.sociedad is null then
    raise exception 'Una factura no puede emitirse sin sociedad emisora.';
  end if;

  select * into s from public.sociedades where clave = new.sociedad;
  if not found then
    raise exception 'La sociedad emisora «%» no existe en public.sociedades.', new.sociedad;
  end if;

  new.datos := jsonb_set(
    coalesce(new.datos, '{}'::jsonb),
    '{emisor}',
    jsonb_build_object(
      'clave',        s.clave,
      'razon',        s.razon,
      'marca',        s.marca,
      'npwp',         s.npwp,
      'npwp_label',   s.npwp_label,
      'nib',          s.nib,
      'domicilio',    s.domicilio,
      'rep',          s.rep,
      'congelado_en', to_jsonb(now())
    ),
    true
  );
  return new;
end; $$;

revoke execute on function public.congela_emisor_factura() from anon, authenticated;

drop trigger trg_congela_emisor on public.facturas;
-- destructivo-ok: se recrea en la linea siguiente para ampliarlo a UPDATE. Es el
-- mismo trigger, no se pierde nada: sin esto, editar una factura ya numerada
-- borraba su emisor congelado (la pantalla manda `datos` entero en el UPDATE y
-- el trigger solo actuaba en INSERT), y el documento volvia a leer la tabla viva
-- en silencio. Hallazgo de Administracion en la consulta de deploy del 17-sep.
create trigger trg_congela_emisor
  before insert or update on public.facturas
  for each row execute function public.congela_emisor_factura();;
