-- Corregir la sociedad de un BORRADOR tiene que recalcular su emisor congelado.
--
-- Hallazgo ALTA de otra sesion en la consulta de deploy del 17-sep-2026, sobre
-- la migracion de hace un rato. La rama de UPDATE restauraba
-- `old.datos->'emisor'` SIEMPRE que existiera, sin mirar si la sociedad habia
-- cambiado. Pero `factura_enviada_no_cambia_emisor` permite a proposito cambiar
-- `sociedad` mientras la factura NO esta enviada.
--
-- Resultado: un agente corregia la sociedad de un borrador, la columna y el
-- desplegable pasaban a San Dal Woods, y `datos.emisor` seguia diciendo Tepi Sun
-- Gai. Como el PDF que se manda por correo imprime el congelado
-- (`paginaParaEmail` usa `SAVED.emisor`), el comprador habria recibido un
-- documento de la empresa vieja mientras la pantalla ensenaba la corregida. Es
-- exactamente la familia de fallo que todo este trabajo viene a cerrar, metida
-- por la puerta de atras.
--
-- Ahora: sociedad igual -> se preserva; sociedad distinta (o INSERT) -> se
-- (re)congela desde la tabla. Verificado con bloque de rollback en los dos casos.
create or replace function public.congela_emisor_factura()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare s public.sociedades%rowtype;
begin
  if tg_op = 'UPDATE' and new.sociedad is not distinct from old.sociedad then
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
    coalesce(new.datos, '{}'::jsonb), '{emisor}',
    jsonb_build_object('clave', s.clave, 'razon', s.razon, 'marca', s.marca,
      'npwp', s.npwp, 'npwp_label', s.npwp_label, 'nib', s.nib,
      'domicilio', s.domicilio, 'rep', s.rep, 'congelado_en', to_jsonb(now())),
    true);
  return new;
end; $$;

revoke execute on function public.congela_emisor_factura() from anon, authenticated;
