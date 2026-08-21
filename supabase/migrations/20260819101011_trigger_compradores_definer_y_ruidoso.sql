-- El trigger llamaba a sincronizar_compradores con los permisos de QUIEN GUARDA
-- el contrato. Al cerrar esa funcion a anon (auditoria del 19-ago) se revoco el
-- EXECUTE de PUBLIC, que era el unico camino que tenia `authenticated`: desde
-- entonces la llamada moria con «permission denied», el handler la convertia en
-- un WARNING que solo va al log del servidor, y los contratos se guardaban SIN
-- enlazar su ficha de comprador. Siete contratos de hoy salieron asi.
--
-- La solucion no es volver a abrir la funcion: es que el TRIGGER sea definer, y
-- entonces la llamada corre como su dueno (postgres). REST sigue cerrado para
-- anon Y para authenticated, que era el objetivo de la auditoria.
create or replace function public.trg_sincronizar_compradores()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform public.sincronizar_compradores(new.id);
  exception when others then
    -- Se sigue sin tumbar el guardado: un contrato tiene que poder guardarse
    -- aunque el enlace falle. Pero el aviso deja de ser solo un WARNING de log:
    -- la app lo comprueba despues (informarCompradores) y ahora avisa en
    -- pantalla si el contrato trae ficha y no quedo enlazada.
    raise warning 'sincronizar_compradores(%) no pudo completarse: %', new.id, sqlerrm;
  end;
  return new;
end $$;

revoke all on function public.trg_sincronizar_compradores() from public, anon, authenticated;;
