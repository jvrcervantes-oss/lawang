-- REVERSION de 20261015055003_facturas_conservan_parcela (14/15-oct-2026): el texto vivo de antes de trg_espejo_proyecto, tal cual
--   (leido del vivo en la sesion 1014-2147, md5 6ddd6fbe892437e14c8d5af6347f196a). Vuelve a pisar la parcela al editar.
--   renombrar_proyecto ya no lo toca la migracion (2.a version, 15-oct): no hay nada que revertir de ella.
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
