CREATE OR REPLACE FUNCTION public._trg_condicion_comision_manager()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op in ('INSERT', 'UPDATE') then
    new.created_by := case when tg_op = 'INSERT' then coalesce(auth.email(), new.created_by) else old.created_by end;
  end if;
  if current_user not in ('authenticated', 'anon') or public.es_admin_de(case when tg_op = 'DELETE' then old.empresa else new.empresa end) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'INSERT' then
    if new.vigente_desde < current_date then
      raise exception 'una condición nueva vale desde hoy en adelante: no se puede fechar en el pasado' using errcode = '22023';
    end if;
    return new;
  end if;
  if exists (select 1 from public.comisiones_devengadas d where d.condicion_id = old.id) then
    if tg_op = 'DELETE' then
      raise exception 'esta condición ya ha generado comisiones: desactívala en vez de borrarla' using errcode = '22023';
    end if;
    if (to_jsonb(new) - 'activo') is distinct from (to_jsonb(old) - 'activo') then
      raise exception 'esta condición ya ha generado comisiones: solo se puede desactivar; para otras cifras crea una nueva' using errcode = '22023';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.vigente_desde is distinct from old.vigente_desde and new.vigente_desde < current_date then
    raise exception 'la fecha de vigencia no puede quedar en el pasado' using errcode = '22023';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $function$
