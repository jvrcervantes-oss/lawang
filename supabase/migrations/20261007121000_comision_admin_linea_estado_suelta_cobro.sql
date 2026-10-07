-- Si una línea sale de «cobrada» (se corrige con motivo), deja de pertenecer al cobro que la saldó:
-- su cobro_id se pone a null, así la cabecera (importe, n_lineas) no sigue apuntando a una línea que
-- ya no salda. El motivo del cambio queda en comision_admin_lineas_log como siempre.
-- Revisor de código 7-oct. Resto de la función idéntico a 20260926234500.
create or replace function public.comision_admin_linea_estado(p_id uuid, p_estado text, p_nota text,
                                                              p_toca_nota boolean, p_quitar_revisar boolean,
                                                              p_motivo text default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v public.comision_admin_lineas%rowtype;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_avanza boolean;
begin
  if not public.es_super_admin() then raise exception 'Solo un super admin' using errcode = '42501'; end if;
  select * into v from public.comision_admin_lineas l where l.id = p_id for update;
  if not found then raise exception 'Esa comisión no existe' using errcode = 'P0002'; end if;
  if v.anulada then raise exception 'Esa comisión está anulada: su estado no se cambia' using errcode = '22023'; end if;
  if p_estado not in ('pendiente', 'facturada', 'cobrada', 'exenta') then
    raise exception 'Estado no válido' using errcode = '22023';
  end if;
  if p_estado is distinct from v.estado then
    v_avanza := (v.estado = 'pendiente' and p_estado in ('facturada', 'cobrada'))
             or (v.estado = 'facturada' and p_estado = 'cobrada');
    if not v_avanza and (v_motivo is null or length(v_motivo) < 5) then
      raise exception 'Pasar de «%» a «%» necesita un motivo (queda registrado)', v.estado, p_estado using errcode = '22023';
    end if;
    insert into public.comision_admin_lineas_log (linea_id, estado_antes, estado_despues, motivo)
    values (p_id, v.estado, p_estado, v_motivo);
  end if;
  update public.comision_admin_lineas l
     set estado = p_estado,
         cobro_id = case when p_estado <> 'cobrada' then null else l.cobro_id end,
         nota = case when coalesce(p_toca_nota, false) then nullif(btrim(coalesce(p_nota, '')), '') else l.nota end,
         revisar = case when coalesce(p_quitar_revisar, false) then false else l.revisar end,
         actualizado_en = now()
   where l.id = p_id;
  return p_estado;
end $$;
