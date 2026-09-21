create or replace function public.sincroniza_unidad_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  cods text[] := (
    select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
      from unnest(string_to_array(coalesce(new.datos->'fields'->>'parcela_codigo',''), ',')) x);
  cods_ant text[];
  proy text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  proy_ant     text;
  cod          text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  ids_nuevo    text[];
  ids_ocupa    text[];
  traspaso_ok  boolean;
  exige        boolean;
  master       text;
  falta        text;
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cods_ant := (
      select coalesce(array_agg(distinct btrim(x)) filter (where btrim(x) <> ''), '{}')
        from unnest(string_to_array(coalesce(old.datos->'fields'->>'parcela_codigo',''), ',')) x);
    if cods_ant is distinct from cods
       or (old.datos->'fields'->>'proyecto_nombre') is distinct from (new.datos->'fields'->>'proyecto_nombre') then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id
         and (u.proyecto is distinct from proy or not (u.codigo = any (cods)));
    end if;
  end if;

  if coalesce(array_length(cods, 1), 0) = 0 or proy is null then

    select true into exige
      from public.contrato_tipo_etapa e
     where e.tipo = new.tipo and e.etapa = 'reserva';

    if coalesce(exige, false) then
      proy_ant := case when tg_op = 'UPDATE'
                  then coalesce(nullif(btrim(old.datos->'fields'->>'proyecto_nombre'), ''), old.proyecto_nombre)
                  end;
      if tg_op = 'UPDATE'
         and cods_ant is not distinct from cods
         and proy_ant is not distinct from proy then
        return new;
      end if;

      falta := case
                 when proy is null and coalesce(array_length(cods, 1), 0) = 0
                   then 'el proyecto y la parcela'
                 when proy is null then 'el proyecto'
                 else 'la parcela'
               end;

      master := nullif(btrim(coalesce(new.datos->'fields'->>'parcela_master','')), '');

      if master is not null and coalesce(array_length(cods, 1), 0) = 0 then
        raise exception
          'Rellena: %. El código «%» está en «Parcela máster» por error — va en el campo «Parcela».',
          falta, master using errcode = '23514';
      end if;

      raise exception
        'Rellena: %.',
        falta using errcode = '23514';
    end if;

    return new;
  end if;

  ids_nuevo := public.contrato_identificadores(new.datos);

  foreach cod in array cods loop
    select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
      into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
      from public.unidades u join public.contratos c on c.id = u.contrato_id
     where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

    if ocupada_id is not null then
      if new.tipo like 'carta_reserva%'
         and ocupada_tipo = 'reserva_parcela'
         and ids_nuevo && ids_ocupa then
        continue;
      end if;

      traspaso_ok := new.tipo = 'reserva_parcela'
                 and ocupada_tipo like 'carta_reserva%';

      if not traspaso_ok then
        raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
          using errcode = '23505';
      end if;

      if coalesce(array_length(ids_nuevo, 1), 0) = 0
         or coalesce(array_length(ids_ocupa, 1), 0) = 0 then
        raise exception 'El traspaso de la parcela % de % no se puede comprobar: falta el pasaporte o el email del comprador en % o en el contrato que estás guardando. Complétalo y vuelve a guardar.',
          cod, proy, ocupada using errcode = '23514';
      end if;
      if not (ids_nuevo && ids_ocupa) then
        raise exception 'El traspaso de la parcela % de % no cuadra: % está a nombre de otro comprador. La parcela solo pasa de una Carta de Reserva a su Bloqueo si coincide el pasaporte o el email.',
          cod, proy, ocupada using errcode = '23514';
      end if;
    end if;

    update public.unidades u
       set contrato_id = new.id,
           estado = case
             when u.estado in ('vendida','cobrada') then u.estado
             when u.estado = 'no_disponible' then u.estado
             when u.estado = 'bloqueada' and not exists (
                    select 1 from public.contratos c2
                     where c2.id = u.contrato_id
                       and c2.tipo = 'reserva_parcela' and coalesce(c2.bloqueado, false)
                  ) then u.estado
             when new.tipo = 'reserva_parcela' and coalesce(new.bloqueado, false) then 'bloqueada'
             when new.tipo = 'construccion' then u.estado
             else 'reservada'
           end
     where u.proyecto = proy and u.codigo = cod;

    if ocupada_id is not null and traspaso_ok then
      update public.contratos c
         set contrato_padre_id = new.id
       where c.id = ocupada_id and c.contrato_padre_id is null;
    end if;

    ocupada_id := null; ocupada := null; ocupada_tipo := null; ids_ocupa := null;
  end loop;

  return new;
end;
$function$;

create or replace function public.contrato_no_editable_en_firma()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  n_vivas    int;
  n_firmadas int;
begin
  if new.datos is not distinct from old.datos then
    return new;
  end if;

  select count(*) filter (where cf.estado = 'pendiente'),
         count(*) filter (where cf.estado = 'firmado')
    into n_vivas, n_firmadas
    from public.contrato_firmas cf
   where cf.contrato_id = new.id;

  if coalesce(n_vivas, 0) = 0 and coalesce(n_firmadas, 0) = 0 then
    return new;
  end if;

  raise exception
    'Contrato enviado a firma: usa «Editar (anula la firma)» para guardar cambios.'
    using errcode = '23514';
end $function$;

create or replace function public.trg_valida_unidad_id_contrato()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_raiz uuid;
  v_unidad_contrato uuid;
begin
  if tg_op = 'UPDATE' and new.unidad_id is distinct from old.unidad_id
     and not public.es_admin() then
    raise exception 'solo un admin puede cambiar la parcela de un contrato ya guardado' using errcode = '42501';
  end if;

  if new.unidad_id is null then return new; end if;

  v_raiz := coalesce(new.contrato_padre_id, new.id);
  select contrato_id into v_unidad_contrato from public.unidades where id = new.unidad_id;
  if v_unidad_contrato is distinct from v_raiz then
    raise exception 'Esta parcela no pertenece a esta reserva.' using errcode = '23514';
  end if;
  return new;
end;
$function$;;
