-- Portal: un ticket de soporte puede referirse a UNA factura o a UN contrato (7-oct-2026, owner).
--
-- Diseño (revisión previa Datos + Seguridad, 7-oct):
--  · Dos columnas con FK REAL (factura_id, contrato_id), no un referencia_id polimórfico: así no
--    hay huérfanos posibles. Como mucho una rellena (CHECK). on delete set null: borrar el
--    documento no borra la conversación.
--  · NO se guarda número ni rótulo de la factura en el hilo: el dato vive en la factura y se lee
--    con join al pintar («el dato tiene un dueño»).
--  · La propiedad se comprueba EN LA RPC por la misma vía que portal_situacion (el comprador es
--    el de contrato_compradores, no un client_id suelto de facturas) y con la misma visibilidad
--    (factura no anulada y, si es proforma, ya enviada). Un id ajeno o inexistente da el MISMO
--    error que «esa ficha no es tuya»: no se revela si existe.
--  · La firma vieja (uuid,text,text) se ELIMINA: si no, quedaban dos sobrecargas ejecutables.
--  · Tope de longitud del texto y de tickets abiertos por comprador: ese texto sale por correo
--    al equipo desde _trg_aviso_mensaje_comprador.
--  · Sin RPC nueva: se amplía portal_abrir_ticket y portal_situacion devuelve la referencia.

alter table public.hilo_soporte
  add column if not exists factura_id  uuid references public.facturas(id)  on delete set null,
  add column if not exists contrato_id uuid references public.contratos(id) on delete set null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'hilo_soporte_una_referencia') then
    alter table public.hilo_soporte
      add constraint hilo_soporte_una_referencia check (factura_id is null or contrato_id is null);
  end if;
end $$;

create index if not exists hilo_soporte_factura_idx  on public.hilo_soporte (factura_id)  where factura_id  is not null;
create index if not exists hilo_soporte_contrato_idx on public.hilo_soporte (contrato_id) where contrato_id is not null;

-- destructivo-ok: owner autorizó el 7-oct-2026 eliminar la firma vieja (uuid,text,text) de portal_abrir_ticket; la reemplaza la de 5 parámetros y no borra datos
drop function if exists public.portal_abrir_ticket(uuid, text, text);

create or replace function public.portal_abrir_ticket(
  p_client_id   uuid,
  p_categoria   text,
  p_texto       text,
  p_factura_id  uuid default null,
  p_contrato_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hilo_id uuid;
  v_email   text := lower(coalesce(auth.email(), ''));
begin
  if not public.es_portal() then raise exception 'sin permiso' using errcode = '42501'; end if;
  if not exists (select 1 from public.portal_accesos pa
                  where pa.activo and pa.email = v_email and pa.client_id = p_client_id) then
    raise exception 'esa ficha no es tuya' using errcode = '42501';
  end if;
  if btrim(coalesce(p_texto,'')) = '' then raise exception 'mensaje vacío' using errcode = '22023'; end if;
  if length(btrim(p_texto)) > 4000 then raise exception 'mensaje demasiado largo' using errcode = '22023'; end if;
  if p_categoria is null or p_categoria not in ('Pagos','Documentación','Obra','Otro') then
    raise exception 'categoría no válida' using errcode = '22023';
  end if;
  if p_factura_id is not null and p_contrato_id is not null then
    raise exception 'una sola referencia' using errcode = '22023';
  end if;
  if (select count(*) from public.hilo_soporte hs
       where hs.client_id = p_client_id and hs.estado = 'abierto') >= 10 then
    raise exception 'demasiados tickets abiertos' using errcode = '22023';
  end if;

  -- Propiedad de la referencia: los contratos del comprador son los de contrato_compradores
  -- de TODAS sus fichas con acceso (igual que portal_situacion).
  if p_contrato_id is not null then
    if not exists (
      select 1 from public.contrato_compradores cc
        join public.portal_accesos pa on pa.client_id = cc.client_id
       where cc.contrato_id = p_contrato_id and pa.activo and pa.email = v_email) then
      raise exception 'esa ficha no es tuya' using errcode = '42501';
    end if;
  end if;
  if p_factura_id is not null then
    if not exists (
      select 1 from public.facturas f
        join public.contrato_compradores cc on cc.contrato_id = f.contrato_id
        join public.portal_accesos pa on pa.client_id = cc.client_id
       where f.id = p_factura_id
         and pa.activo and pa.email = v_email
         and not coalesce(f.anulada, false)
         and (f.tipo <> 'proforma' or f.enviada)) then
      raise exception 'esa ficha no es tuya' using errcode = '42501';
    end if;
  end if;

  insert into public.hilo_soporte (id, client_id, categoria, estado, actualizado_en, factura_id, contrato_id)
    values (gen_random_uuid(), p_client_id, p_categoria, 'abierto', now(), p_factura_id, p_contrato_id)
    returning id into v_hilo_id;

  insert into public.mensajes_comprador (client_id, de, autor, texto, hilo_id)
    values (p_client_id, 'cliente', null, btrim(p_texto), v_hilo_id);

  return v_hilo_id;
end
$function$;

revoke all on function public.portal_abrir_ticket(uuid, text, text, uuid, uuid) from public, anon;
grant execute on function public.portal_abrir_ticket(uuid, text, text, uuid, uuid) to authenticated;

-- portal_situacion: cada ticket devuelve su referencia (id + número vivo por join).
-- Parche con marca de código puro, idempotente, y raise si no la encuentra
-- (la definición viva no es la del .sql del repo: ver reference_parchear_funcion_viva_con_marca).
do $$
declare
  v_def  text := pg_get_functiondef('public.portal_situacion()'::regprocedure);
  v_marca text := '''estado'',        hs.estado,';
  v_nuevo text :=
    '''estado'',        hs.estado,' || chr(10) ||
    '        ''factura_id'',     hs.factura_id,' || chr(10) ||
    '        ''contrato_id'',    hs.contrato_id,' || chr(10) ||
    '        ''ref_numero'',     coalesce((select f.numero from public.facturas f where f.id = hs.factura_id),' ||
                                          ' (select c.numero from public.contratos c where c.id = hs.contrato_id)),';
begin
  if position('''ref_numero''' in v_def) > 0 then return; end if;
  if position(v_marca in v_def) = 0 then
    raise exception 'portal_situacion: no encuentro la marca de tickets; no se parchea';
  end if;
  execute replace(v_def, v_marca, v_nuevo);
end $$;
