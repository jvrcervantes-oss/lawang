-- Cláusulas negociadas (REV03): quién puede ponerlas, en la base.
--
-- 2-oct-2026, owner: un comprador de Carmen revisó los borradores REV02 de
-- Bloqueo de Parcela y Construcción y la comercial le propuso por escrito seis
-- cambios (DNI, HGB vía PT PMA, zonas comunes, aviso de prórroga, garantía desde
-- el acta de entrega). Decisión del owner: son SOLO para ese cliente, van como
-- un selector `clausulas_negociadas` ('' estándar / 'si' REV03) dentro de las
-- dos plantillas, y solo lo ven y lo cambian admin y super_admin.
--
-- La pantalla lo esconde a los demás, pero el navegador no manda: contrato_guarda
-- guarda `datos` tal cual llega. Mismo mecanismo que descuento_comercial_rol
-- (20260925180500): si quien escribe tiene sesión y NO es super_admin/admin,
-- rechaza CAMBIAR datos.fields.clausulas_negociadas (en un insert: ponerlo no
-- vacío). Guardar un contrato que ya lo traía, sin tocarlo, sigue funcionando
-- —un agente puede corregir el teléfono de un contrato REV03 sin apagarlo ni
-- encenderlo—. Sin sesión (auth.uid() null: edge functions con service role)
-- no se aplica.
--
-- Seguro: solo crea función y trigger nuevos.

create or replace function public.clausulas_negociadas_rol()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rol text;
  v_new text := coalesce(nullif(trim(new.datos->'fields'->>'clausulas_negociadas'), ''), '');
  v_old text := '';
begin
  if (select auth.uid()) is null then return new; end if;
  if tg_op = 'UPDATE' then
    v_old := coalesce(nullif(trim(old.datos->'fields'->>'clausulas_negociadas'), ''), '');
  end if;
  if v_new is not distinct from v_old then return new; end if;
  select u.rol into v_rol from public.usuarios u where u.user_id = (select auth.uid()) and u.activo;
  if v_rol in ('super_admin', 'admin') then return new; end if;
  raise exception 'Las cláusulas negociadas solo las activan o retiran dirección (admin).'
    using errcode = '42501';
end
$function$;

revoke execute on function public.clausulas_negociadas_rol() from public, anon, authenticated;

create trigger trg_clausulas_negociadas_rol
  before insert or update on public.contratos
  for each row execute function public.clausulas_negociadas_rol();

comment on function public.clausulas_negociadas_rol() is
  'BEFORE INSERT OR UPDATE en contratos: solo super_admin/admin cambian datos.fields.clausulas_negociadas (REV03 negociado con un comprador). Sin sesión no aplica. 2-oct-2026, owner.';
