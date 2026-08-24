-- destructivo-ok: el DELETE es el arreglo (roles fantasma que el documento ya no nombra),
-- acotado a UN contrato y a roles ausentes de el. Verificado antes: nada referencia
-- contrato_compradores por clave ajena. Porques completos en
-- proyectos/Lawang/contracts/sql/compradores_sin_fantasmas.sql
create or replace function public.sincronizar_compradores(p_contrato uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_datos  jsonb;
  v_gente  jsonb;
  p        jsonb;
  v_nombre text; v_rol text; v_pas text; v_mail text; v_cid text;
  v_client uuid;
  v_enlaces int := 0;
  v_sin_id text[] := '{}';
  v_sin_ficha text[] := '{}';
  v_roles_vivos text[] := '{}';
  v_borrados int := 0;
begin
  select datos into v_datos from public.contratos where id = p_contrato;
  if v_datos is null then return jsonb_build_object('error', 'contrato inexistente o sin datos'); end if;

  v_gente := jsonb_build_array(jsonb_build_object(
      'rol','adquiriente_1',
      'client_id',    v_datos->>'adq1_client_id',
      'nombre',       v_datos->'fields'->>'adq1_nombre',
      'pasaporte',    v_datos->'fields'->>'adq1_pasaporte',
      'email',        v_datos->'fields'->>'adq1_email',
      'telefono',     v_datos->'fields'->>'adq1_telefono',
      'nacionalidad', v_datos->'fields'->>'adq1_nacionalidad',
      'domicilio',    v_datos->'fields'->>'adq1_domicilio'))
    || coalesce((
      select jsonb_agg(jsonb_build_object(
               'rol','adquiriente_' || (ord + 1),
               'client_id', e->>'client_id',
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
    -- Este rol EXISTE en el documento. Se apunta aunque luego no se consiga
    -- enlazar: lo que decide si una fila sobra es el documento, no el enlace.
    v_roles_vivos := v_roles_vivos || v_rol;
    v_pas  := nullif(btrim(coalesce(p->>'pasaporte','')), '');
    v_mail := lower(nullif(btrim(coalesce(p->>'email','')), ''));
    v_cid  := nullif(btrim(coalesce(p->>'client_id','')), '');

    v_client := null;

    if v_cid is not null then
      begin
        select id into v_client from public.clients where id = v_cid::uuid;
      exception when invalid_text_representation then
        v_client := null;
      end;
    end if;

    if v_client is null then
      if v_pas is null and v_mail is null then
        v_sin_id := v_sin_id || v_nombre;
        continue;
      end if;
      if v_pas is not null then
        select id into v_client from public.clients
         where lower(btrim(passport_number)) = lower(v_pas) limit 1;
      end if;
      if v_client is null and v_mail is not null then
        select id into v_client from public.clients
         where lower(email) = v_mail
         order by (tipo = 'persona') desc, created_at
         limit 1;
      end if;
    end if;

    if v_client is null then
      v_sin_ficha := v_sin_ficha || v_nombre;
      continue;
    end if;

    insert into public.contrato_compradores (contrato_id, client_id, rol)
    values (p_contrato, v_client, v_rol)
    on conflict (contrato_id, rol) do update set client_id = excluded.client_id;
    v_enlaces := v_enlaces + 1;
  end loop;

  /* LOS FANTASMAS. Un contrato que paso de cuatro compradores a dos dejaba
     adquiriente_3 y adquiriente_4 enlazados a las personas de la version
     anterior, y Operaciones los seguia enseñando. Se borran los roles que el
     documento YA NO NOMBRA. Si el documento no nombra a NADIE no se borra nada:
     eso es casi siempre un `datos` a medio escribir, y vaciar la tabla por eso
     convertiria un guardado intermedio en una perdida de enlaces. */
  if array_length(v_roles_vivos, 1) is not null then
    delete from public.contrato_compradores
     where contrato_id = p_contrato
       and rol <> all(v_roles_vivos);
    get diagnostics v_borrados = row_count;
  end if;

  return jsonb_build_object('altas', 0, 'enlaces', v_enlaces,
                            'retirados', v_borrados,
                            'sin_identificador', to_jsonb(v_sin_id),
                            'sin_ficha',         to_jsonb(v_sin_ficha));
end $function$;;
