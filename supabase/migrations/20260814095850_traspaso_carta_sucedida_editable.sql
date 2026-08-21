create or replace function public.sincroniza_unidad_contrato()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  cod          text := nullif(btrim(new.datos->'fields'->>'parcela_codigo'), '');
  proy         text := coalesce(nullif(btrim(new.datos->'fields'->>'proyecto_nombre'), ''), new.proyecto_nombre);
  cod_ant      text;
  ocupada      text;
  ocupada_id   uuid;
  ocupada_tipo text;
  traspaso_ok  boolean;
  ids_nuevo    text[];
  ids_ocupa    text[];
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1
     and new.datos     is not distinct from old.datos
     and new.tipo      is not distinct from old.tipo
     and new.bloqueado is not distinct from old.bloqueado then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    cod_ant := nullif(btrim(old.datos->'fields'->>'parcela_codigo'), '');
    if cod_ant is distinct from cod then
      update public.unidades u set contrato_id = null
       where u.contrato_id = new.id;
    end if;
  end if;

  if cod is null or proy is null then return new; end if;

  select c.id, c.numero, c.tipo, public.contrato_identificadores(c.datos)
    into ocupada_id, ocupada, ocupada_tipo, ids_ocupa
    from public.unidades u join public.contratos c on c.id = u.contrato_id
   where u.proyecto = proy and u.codigo = cod and u.contrato_id <> new.id;

  if ocupada_id is not null then
    ids_nuevo := public.contrato_identificadores(new.datos);
  end if;

  if ocupada_id is not null
     and new.tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa')
     and ocupada_tipo = 'reserva_parcela'
     and ids_nuevo && ids_ocupa then
    return new;
  end if;

  traspaso_ok := new.tipo = 'reserva_parcela'
             and ocupada_tipo in ('carta_reserva', 'carta_reserva_ampliada', 'carta_reserva_hak_sewa');

  if ocupada is not null and not traspaso_ok then
    raise exception 'La parcela % de % ya esta asignada al contrato %', cod, proy, ocupada
      using errcode = '23505';
  end if;

  if ocupada is not null and traspaso_ok then
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

  if traspaso_ok and ocupada_id is not null then
    update public.contratos c
       set contrato_padre_id = new.id
     where c.id = ocupada_id and c.contrato_padre_id is null;
  end if;

  return new;
end $$;;
