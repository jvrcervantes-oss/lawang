-- Verificación ATÓMICA del código de alta de colaboradores (24-sep-2026).
-- Consulta de deploy de Seguridad sobre 06dcfe5c:
--   · el tope de 5 intentos se leía y se escribía en dos pasos: N peticiones en
--     paralelo leían intentos=0 y comparaban todas. Aquí se compara y se suma en UNA
--     sentencia con FOR UPDATE.
--   · ya no se invalidan los códigos anteriores al pedir otro (un tercero que supiera
--     el email podía anular el código de alguien mientras lo tecleaba): vale cualquiera
--     de los 3 últimos códigos vigentes de ese email.
-- Solo la llama la edge alta-colaborador con service_role.
create or replace function public.colaborador_verifica(p_email text, p_hash text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ok boolean;
begin
  with c as (
    select id from public.colaboradores_verificaciones
     where email = lower(p_email) and not usado and expira_at > now() and intentos < 5
     order by creado_at desc
     limit 3
     for update
  ), u as (
    update public.colaboradores_verificaciones v
       set usado = (v.codigo_hash = p_hash),
           intentos = v.intentos + case when v.codigo_hash = p_hash then 0 else 1 end
      from c where v.id = c.id
    returning v.usado
  )
  select coalesce(bool_or(usado), false) into v_ok from u;
  return v_ok;
end;
$$;
revoke all on function public.colaborador_verifica(text, text) from public, anon, authenticated;
grant execute on function public.colaborador_verifica(text, text) to service_role;
