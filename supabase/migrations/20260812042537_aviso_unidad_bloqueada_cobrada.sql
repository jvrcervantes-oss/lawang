-- Con el flujo nuevo (12-ago), 'bloqueada' ya no es siempre una persona
-- bloqueando a mano: tambien la pone la firma automatica de un Bloqueo de
-- Parcela. Y 'cobrada' (100% pagado) es el aviso mas importante del ciclo de
-- venta, faltaba. `no_disponible` se queda fuera a proposito: esa SI sigue
-- siendo solo de una persona.
create or replace function public.trg_aviso_unidad()
returns trigger language plpgsql security definer set search_path = public as $$
declare c record; v_texto text;
begin
  begin
    if new.estado is not distinct from old.estado then return new; end if;
    v_texto := case new.estado
      when 'reservada'  then 'reservada'
      when 'bloqueada'  then 'bloqueada'
      when 'vendida'    then 'vendida'
      when 'cobrada'    then 'cobrada al 100%'
      when 'disponible' then 'vuelve a estar disponible'
      else null end;
    if v_texto is null then return new; end if;   -- no_disponible la pone una persona

    select numero, creado_por into c from contratos
     where id = coalesce(new.contrato_id, old.contrato_id);

    perform anotar_aviso('unidad_' || new.estado,
      'Parcela ' || coalesce(new.codigo,'sin código') || ' ' || v_texto,
      coalesce(new.proyecto,'') || coalesce(' · ' || c.numero, ''),
      c.creado_por, coalesce(new.contrato_id, old.contrato_id), '/proyectos/');
  exception when others then
    raise warning 'aviso unidad (%) no se pudo anotar: %', new.id, sqlerrm;
  end;
  return new;
end $$;
;
