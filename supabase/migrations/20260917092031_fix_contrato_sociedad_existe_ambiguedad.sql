-- Bug de la migracion de esta misma manana (20260917161500_facturas_emisor_congelado_y_permisos):
-- la variable plpgsql "clave" comparte nombre con sociedades.clave, asi que
-- "s.clave = clave" es ambiguo (42702) y CUALQUIER UPDATE/INSERT sobre un
-- contrato con sociedad_firmante puesto falla, sin relacion con lo que se
-- estuviera editando. Renombrada la variable, misma logica.
create or replace function public.contrato_sociedad_existe()
returns trigger
language plpgsql
set search_path to ''
as $$
declare v_clave text := new.datos->'fields'->>'sociedad_firmante';
begin
  if v_clave is not null and v_clave <> ''
     and not exists (select 1 from public.sociedades s where s.clave = v_clave) then
    raise exception 'La sociedad firmante «%» no existe en public.sociedades.', v_clave;
  end if;
  return new;
end; $$;
