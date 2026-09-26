-- Nº de usuario de la suite (USR-00001, 26-sep-2026, owner). Calco de 20260926031353_numero_cliente.sql:
-- mismo porqué y mismas reglas de la revisión previa #104, aplicadas a `usuarios`.
-- Por qué: un usuario solo se identificaba por email y uuid; hace falta una referencia corta que se pueda citar
-- (soporte, comisiones, un papel) y que no cambie aunque cambie el email o el rol.
-- Un número por persona, nunca por rol: con prefijo por rol, un ascenso rompería el número o lo dejaría mintiendo.
--
--   1. Orden: columna → relleno en UNA sentencia → setval → not null + unique → trigger AL FINAL.
--   2. El número lo pone SIEMPRE la base (BEFORE INSERT, nextval): lo que mande admin-usuarios o una pantalla se ignora.
--   3. Cambiarlo no da error, se ignora (BEFORE UPDATE OF numero_usuario, new := old): el editor de permisos
--      manda `update(patch)` genérico; un `raise` le haría fallar el guardado.
--   4. La secuencia no es de nadie más (revoke), el trigger es SECURITY DEFINER.
--   5. El `grant select` de abajo SOBRA y es inofensivo: se escribió creyendo que `usuarios` solo tenía grants por
--      columna, pero information_schema.column_privileges también lista los de tabla expandidos. Verificado después
--      en relacl: authenticated=arwdDxtm a nivel de TABLA (Seguridad, consulta de deploy 26-sep). Para saber si una
--      tabla tiene grant de tabla se mira `pg_class.relacl`, no column_privileges. Que authenticated pueda hacer
--      UPDATE de la columna no importa: el trigger del punto 3 conserva el valor.
--   6. No choca con `usuarios_candado_rol_herramientas`: el relleno no toca rol ni herramientas.
-- Avisos aceptados: un alta que falla gasta un número (huecos). El orden del relleno es el de alta en la suite
-- (creado_en, desempate por user_id). Un usuario borrado y vuelto a dar de alta recibe número nuevo.
-- Solo añade: ningún drop, ningún dato existente se reescribe (el relleno escribe una columna recién creada).

alter table public.usuarios add column numero_usuario text;

create sequence public.usuarios_numero_usuario_seq as bigint start with 1;
revoke all on sequence public.usuarios_numero_usuario_seq from public, anon, authenticated;

with orden as (
  select user_id, row_number() over (order by creado_en, user_id) as n from public.usuarios
)
update public.usuarios u set numero_usuario = 'USR-' || lpad(o.n::text, 5, '0')
  from orden o where o.user_id = u.user_id;

-- is_called = false con 0 filas: el primero será 1; con N filas, el siguiente será N+1.
select setval('public.usuarios_numero_usuario_seq', greatest((select count(*) from public.usuarios), 1),
              (select count(*) from public.usuarios) > 0);

alter table public.usuarios alter column numero_usuario set not null;
alter table public.usuarios add constraint usuarios_numero_usuario_key unique (numero_usuario);

create function public.usuarios_numero_usuario() returns trigger
  language plpgsql security definer set search_path to ''
  as $$
begin
  if tg_op = 'INSERT' then
    new.numero_usuario := 'USR-' || lpad(nextval('public.usuarios_numero_usuario_seq')::text, 5, '0');
  else
    new.numero_usuario := old.numero_usuario;
  end if;
  return new;
end $$;
revoke all on function public.usuarios_numero_usuario() from public, anon, authenticated;

create trigger trg_usuarios_numero_usuario before insert or update of numero_usuario on public.usuarios
  for each row execute function public.usuarios_numero_usuario();

grant select (numero_usuario) on public.usuarios to authenticated;
