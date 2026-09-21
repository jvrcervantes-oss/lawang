create or replace function public.set_factura_numero()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.numero is null then
    new.numero := case new.tipo
      when 'proforma' then 'PRO' || lpad(nextval('public.facturas_proforma_seq')::text, 5, '0')
      when 'recibi'   then 'REC' || lpad(nextval('public.facturas_recibi_seq')::text, 5, '0')
      else                 'INV' || lpad(nextval('public.facturas_seq')::text, 5, '0')
    end;
  end if;
  return new;
end; $function$;

revoke execute on function public.set_factura_numero() from anon, authenticated;

revoke all on sequence public.facturas_seq          from anon, authenticated;
revoke all on sequence public.facturas_proforma_seq from anon, authenticated;
revoke all on sequence public.facturas_recibi_seq   from anon, authenticated;

create or replace function public.congela_emisor_factura()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare s public.sociedades%rowtype;
begin
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

create trigger trg_congela_emisor
  before insert on public.facturas
  for each row execute function public.congela_emisor_factura();

create or replace function public.factura_enviada_no_cambia_emisor()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if coalesce(old.enviada, false) then
    if new.sociedad is distinct from old.sociedad then
      raise exception 'La factura % ya se envio: no se puede cambiar la sociedad emisora. Anulala y emite una nueva.', old.numero;
    end if;
    if new.numero is distinct from old.numero then
      raise exception 'La factura % ya se envio: su numero no se cambia.', old.numero;
    end if;
  end if;
  return new;
end; $$;

revoke execute on function public.factura_enviada_no_cambia_emisor() from anon, authenticated;

create trigger trg_factura_enviada_no_cambia_emisor
  before update on public.facturas
  for each row execute function public.factura_enviada_no_cambia_emisor();

alter table public.facturas
  alter column sociedad set not null;

alter table public.facturas
  add constraint facturas_sociedad_fkey
  foreign key (sociedad) references public.sociedades (clave);

create or replace function public.contrato_sociedad_existe()
returns trigger
language plpgsql
set search_path to ''
as $$
declare clave text := new.datos->'fields'->>'sociedad_firmante';
begin
  if clave is not null and clave <> ''
     and not exists (select 1 from public.sociedades s where s.clave = clave) then
    raise exception 'La sociedad firmante «%» no existe en public.sociedades.', clave;
  end if;
  return new;
end; $$;

revoke execute on function public.contrato_sociedad_existe() from anon, authenticated;

create trigger trg_contrato_sociedad_existe
  before insert or update on public.contratos
  for each row execute function public.contrato_sociedad_existe();

revoke all on public.facturas from anon;
revoke insert, update on public.facturas from authenticated;

grant insert (id, tipo, sociedad, cliente_nombre, proyecto_nombre, proyecto_id,
              contrato_numero, contrato_id, client_id, total, moneda,
              fecha_emision, datos, justificantes, anulada, enviada,
              fecha_envio, creado_por, created_at)
  on public.facturas to authenticated;

grant update (tipo, sociedad, cliente_nombre, proyecto_nombre, proyecto_id,
              contrato_numero, contrato_id, client_id, total, moneda,
              fecha_emision, datos, justificantes, anulada, enviada,
              fecha_envio, creado_por)
  on public.facturas to authenticated;;
