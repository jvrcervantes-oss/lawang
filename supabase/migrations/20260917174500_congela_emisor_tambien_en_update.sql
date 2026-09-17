-- El emisor congelado tambien sobrevive a una EDICION.
--
-- Hallazgo de Administracion en la consulta de deploy del 17-sep-2026:
-- `congela_emisor_factura` era BEFORE INSERT, y la pantalla de facturas manda
-- `datos` ENTERO tambien en el UPDATE (`{fields, lineas, totales}`), sin la
-- clave `emisor`. Asi que corregir una linea antes de cobrar borraba el
-- congelado y el documento volvia a leer la identidad viva, en silencio.
-- `factura_enviada_no_cambia_emisor` no lo tapaba: vigila `sociedad` y `numero`,
-- no `datos`.
--
-- Se PRESERVA en vez de rechazar, a proposito. Quien edita no esta intentando
-- cambiar el emisor: esta reenviando el blob sin esa clave. Rechazar romperia
-- toda edicion de factura. Lo que no puede pasar es que se pierda.
--
-- Una factura de las 412 anteriores al congelado NO se congela al editarla: se
-- queda como historico, que es la decision del owner del 17-sep. Por eso la
-- rama de UPDATE solo actua `if old.datos ? 'emisor'`.
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
    coalesce(new.datos, '{}'::jsonb), '{emisor}',
    jsonb_build_object('clave', s.clave, 'razon', s.razon, 'marca', s.marca,
      'npwp', s.npwp, 'npwp_label', s.npwp_label, 'nib', s.nib,
      'domicilio', s.domicilio, 'rep', s.rep, 'congelado_en', to_jsonb(now())),
    true);
  return new;
end; $$;

revoke execute on function public.congela_emisor_factura() from anon, authenticated;

drop trigger trg_congela_emisor on public.facturas;
-- destructivo-ok: se recrea inmediatamente para ampliarlo a UPDATE. Mismo
-- trigger, misma funcion; no se pierde ningun dato.
create trigger trg_congela_emisor
  before insert or update on public.facturas
  for each row execute function public.congela_emisor_factura();
