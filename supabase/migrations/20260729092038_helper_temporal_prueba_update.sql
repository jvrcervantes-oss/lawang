-- Segundo helper temporal: intenta un UPDATE INOCUO (asigna una columna a su
-- propio valor, no cambia ni un byte) sobre un contrato concreto asumiendo el
-- rol authenticated, y devuelve cuántas filas dejó tocar la RLS.
-- 0 = la política lo impidió · 1 = lo permitió. Se borra al terminar.
create or replace function public._prueba_update(p_uid text, p_email text, p_id uuid)
returns integer language plpgsql security invoker as $$
declare n integer;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'email', p_email, 'role','authenticated')::text, true);
  set local role authenticated;
  update public.contratos set comprador_nombre = comprador_nombre where id = p_id;
  get diagnostics n = row_count;
  return n;
end $$;;
