-- REVERSION de 20261014220000_facturas_conservan_parcela (14-oct-2026): los dos textos vivos de antes, tal cual (leidos del vivo
--   en la sesion 1014-2147, md5 6ddd6fbe892437e14c8d5af6347f196a y f3a96bfd14b9ab63406eedd3a61e01eb). Vuelve a pisar la parcela al editar.
set local lock_timeout = '5s';
CREATE OR REPLACE FUNCTION public.trg_espejo_proyecto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_nombre text;
begin
  -- la regla del proyecto vive en _contrato_proyecto_de (13-oct-2026): la usan tambien _trg_contrato_tipo_valido y
  -- _trg_contrato_campos_propios, que se disparan antes que este trigger
  new.proyecto_id := public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre);

  if new.proyecto_id is not null then
    select p.nombre into v_nombre from public.proyectos p where p.id = new.proyecto_id;
    if v_nombre is not null then
      new.proyecto_nombre := v_nombre;
    end if;
  end if;
  return new;
end
$function$

;
CREATE OR REPLACE FUNCTION public.renombrar_proyecto(p_antiguo text, p_nuevo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_unidades int; v_contratos int; v_facturas int; v_documentos int; v_modelos int;
begin
  if not public.es_admin_de((select pr.empresa from public.proyectos pr where pr.nombre = p_antiguo)) then
    raise exception 'Solo un administrador puede renombrar un proyecto' using errcode = '42501';
  end if;
  if p_antiguo is null or trim(p_antiguo) = '' or p_nuevo is null or trim(p_nuevo) = '' then
    raise exception 'Nombre de proyecto vacío';
  end if;
  if p_antiguo = p_nuevo then
    return jsonb_build_object('sin_cambios', true);
  end if;
  if length(btrim(p_nuevo)) > 120 then raise exception 'El nombre no puede pasar de 120 caracteres' using errcode = '22023'; end if;
  if btrim(p_nuevo) ~ '^[=+\-@]' then raise exception 'El nombre no puede empezar por = + - @' using errcode = '22023'; end if;
  if exists (select 1 from public.proyectos where nombre = p_nuevo) then
    raise exception 'Ya existe un proyecto llamado "%"', p_nuevo;
  end if;

  update public.proyectos set nombre = p_nuevo where nombre = p_antiguo;

  update public.unidades set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_unidades = row_count;

  update public.contratos set proyecto_nombre = p_nuevo where proyecto_nombre = p_antiguo;
  get diagnostics v_contratos = row_count;
  update public.contratos c
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and bloqueado = false
     and datos #>> '{fields,proyecto_nombre}' = p_antiguo
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  update public.facturas set proyecto_nombre = p_nuevo where proyecto_nombre = p_antiguo;
  get diagnostics v_facturas = row_count;
  update public.facturas
     set datos = jsonb_set(datos, '{fields,proyecto_nombre}', to_jsonb(p_nuevo))
   where proyecto_nombre = p_nuevo and not anulada and not enviada
     and datos #>> '{fields,proyecto_nombre}' = p_antiguo;

  update public.documentos_proyecto set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_documentos = row_count;

  update public.modelos_villa set proyecto = p_nuevo where proyecto = p_antiguo;
  get diagnostics v_modelos = row_count;

  return jsonb_build_object(
    'unidades', v_unidades, 'contratos', v_contratos, 'facturas', v_facturas,
    'documentos_proyecto', v_documentos, 'modelos_villa', v_modelos
  );
end;
$function$

;
