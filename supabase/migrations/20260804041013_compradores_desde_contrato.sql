create or replace function public.sincronizar_compradores(p_contrato uuid)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text;
  v_client uuid;
  v_altas int := 0; v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_mail text[] := '{}';
begin
  select datos into v_datos from contratos where id = p_contrato;
  if v_datos is null then return jsonb_build_object('error', 'contrato inexistente o sin datos'); end if;

  v_gente := jsonb_build_array(jsonb_build_object(
      'rol','adquiriente_1',
      'nombre',       v_datos->'fields'->>'adq1_nombre',
      'pasaporte',    v_datos->'fields'->>'adq1_pasaporte',
      'email',        v_datos->'fields'->>'adq1_email',
      'telefono',     v_datos->'fields'->>'adq1_telefono',
      'nacionalidad', v_datos->'fields'->>'adq1_nacionalidad',
      'domicilio',    v_datos->'fields'->>'adq1_domicilio'))
    || coalesce((
      select jsonb_agg(jsonb_build_object(
               'rol','adquiriente_' || (ord + 1),
               'nombre', e->>'nombre', 'pasaporte', e->>'pasaporte', 'email', e->>'email',
               'telefono', e->>'telefono', 'nacionalidad', e->>'nacionalidad',
               'domicilio', e->>'domicilio') order by ord)
      from jsonb_array_elements(
             case when jsonb_typeof(v_datos->'compradores') = 'array'
                  then v_datos->'compradores' else '[]'::jsonb end) with ordinality t(e, ord)
      where ord + 1 <= 9), '[]'::jsonb);

  for p in select value from jsonb_array_elements(v_gente) loop
    v_nombre := btrim(coalesce(p->>'nombre',''));
    continue when v_nombre = '';
    v_rol  := p->>'rol';
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));

    if v_pas is null and v_mail is null then
      v_sin_id := v_sin_id || v_nombre;
      continue;
    end if;

    v_client := null;
    if v_pas is not null then
      select id into v_client from clients
       where lower(btrim(passport_number)) = lower(v_pas) limit 1;
    elsif v_mail is not null then
      select id into v_client from clients where lower(email) = v_mail limit 1;
    end if;

    if v_client is null then
      if v_mail is not null and exists (select 1 from clients where lower(email) = v_mail) then
        v_sin_mail := v_sin_mail || v_nombre;
        v_mail := null;
      end if;
      insert into clients (full_name, email, phone, nationality, passport_number, address, kyc_status)
      values (v_nombre, v_mail,
              nullif(btrim(coalesce(p->>'telefono','')), ''),
              nullif(btrim(coalesce(p->>'nacionalidad','')), ''),
              v_pas,
              nullif(btrim(coalesce(p->>'domicilio','')), ''),
              'pending')
      returning id into v_client;
      v_altas := v_altas + 1;
    end if;

    insert into contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  return jsonb_build_object('altas', v_altas, 'enlaces', v_enlaces,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'ficha_sin_correo',  to_jsonb(v_sin_mail));
end $$;

comment on function public.sincronizar_compradores(uuid) is
  'Crea/enlaza las fichas de comprador de un contrato leyendo datos->fields->adq1_* y datos->compradores. Idempotente: se puede repasar sobre lo ya guardado.';

create or replace function public.trg_sincronizar_compradores()
returns trigger language plpgsql set search_path = public as $$
begin
  begin
    perform public.sincronizar_compradores(new.id);
  exception when others then
    raise warning 'sincronizar_compradores(%) no pudo completarse: %', new.id, sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists trg_compradores_desde_datos on public.contratos;
create trigger trg_compradores_desde_datos
after insert or update of datos on public.contratos
for each row execute function public.trg_sincronizar_compradores();;
