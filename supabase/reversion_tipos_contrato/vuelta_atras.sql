-- Vuelta atras de 20261013015508_contratos_propios_conceder_emitir (13-oct-2026). No toca ningun dato.
-- A. Quita la comprobacion de `usuarios.tipos_contrato` (Permisos vuelve a guardar cualquier texto como tipo).
drop trigger if exists usuarios_tipos_contrato_validos on public.usuarios;
drop function if exists public._trg_usuarios_tipos_contrato_validos();
-- B. Devuelve los tres triggers de contratos a como estaban (con eso un contrato propio vuelve a NO poder guardarse
--    desde la pantalla). Orden: primero los que llaman a la funcion, despues la funcion.
create or replace function public.trg_espejo_proyecto()
returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  v_nombre text;
begin
  if new.proyecto_id is null and nullif(btrim(coalesce(new.proyecto_nombre,'')),'') is not null then
    select p.id into new.proyecto_id from public.proyectos p where p.nombre = new.proyecto_nombre;
  end if;

  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      new.proyecto_nombre := v_nombre;
    end if;
  end if;
  return new;
end
$function$;

create or replace function public._trg_contrato_tipo_valido()
returns trigger language plpgsql security definer set search_path = '' as $function$
declare v_emp text;
begin
  if new.tipo = any (array['reserva_parcela', 'construccion', 'contrato_general', 'commercial_offer', 'carta_reserva', 'carta_reserva_ampliada', 'acuerdo_comercial', 'protocolo_operativo',
                           'ppjb_bonian', 'ppjb_bonian_c2', 'hak_sewa_notario', 'carta_reserva_hak_sewa', 'poa', 'cc00014_timon', 'carta_reserva_pma', 'adenda', 'carta_reserva_investor_deck']::text[]) then
    return new;
  end if;
  v_emp := case when new.proyecto_id is null then null else public.empresa_de_proyecto(new.proyecto_id) end;
  if v_emp is null or not exists (select 1 from public.plantillas_contrato t where t.slug = new.tipo and t.empresa = v_emp) then
    raise exception 'Tipo de contrato no valido para esta empresa: %', new.tipo using errcode = '23514';
  end if;
  return new;
end $function$;

do $vuelta$
declare
  d text := pg_get_functiondef('public._trg_contrato_campos_propios'::regproc);
  marca text := 'emp := public.empresa_de_proyecto(public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre));   -- 13-oct-2026: tambien por el nombre del proyecto (contrato_guarda)';
begin
  if position(marca in d) = 0 then
    raise exception 'vuelta atras: la marca del 13-oct no esta en _trg_contrato_campos_propios';
  end if;
  execute replace(d, marca, 'emp := case when new.proyecto_id is null then null else public.empresa_de_proyecto(new.proyecto_id) end;');
end
$vuelta$;

drop function if exists public._contrato_proyecto_de(uuid, text);
