create or replace function public.registrar_salto_de_freno(p_contrato uuid, p_evento text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.es_super_admin() then
    raise exception 'solo un super admin registra un salto de freno' using errcode = '42501';
  end if;
  if p_evento is distinct from 'comprador_sin_ficha' then
    raise exception 'ese evento no se registra por aqui' using errcode = '23514';
  end if;
  perform public.registra_privilegio(p_contrato, p_evento, jsonb_build_object('desde', 'contratos'));
end $$;

revoke all on function public.registrar_salto_de_freno(uuid, text) from public, anon;
grant execute on function public.registrar_salto_de_freno(uuid, text) to authenticated;;
