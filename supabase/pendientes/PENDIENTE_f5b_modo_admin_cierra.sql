-- NO APLICADA (30-sep-2026): el apply_migration de Datos lo denegó el clasificador de permisos; la aplica el owner o la sesión principal
-- con su OK (apply_migration con este contenido, bajarla a migrations/ con su versión real y borrar este fichero).
-- Hasta entonces los casos «modo_admin» de contracts/sql/prueba_f5b_pantallas.sql salen FALLO a propósito.
-- F5b · venta_modo_admin se cierra a lo que tiene llamador (30-sep-2026, hallazgos de Seguridad sobre F5b).
-- Porqué: con el EXECUTE re-concedido en 20260930131454, venta_modo_admin era una escritura sobre dinero abierta aunque
-- el interruptor de F5 siga APAGADO: un admin podía poner «por su cuenta» o «equipo» a cualquier venta firmada que nunca
-- declaró modo, y eso reevalúa comisiones. Su único llamador (editores.js, data-accion="vpc-modo", botón «Pasar al
-- equipo» de la bandeja) solo pasa ventas YA declaradas «por su cuenta» al equipo.
--   · p_modo solo admite 'equipo' ('propia' no tiene llamador) → 22023.
--   · con el interruptor apagado, una venta sin modo declarado no se toca → 22023. Lo ya declarado sí se corrige.
--   · el candado por venta (pg_advisory_xact_lock 'comisiones:'||raiz) pasa al principio, justo tras el permiso y
--     ANTES de mirar la objeción pendiente: sin él, una objeción creada entre la comprobación y el cambio se colaba.
--     Es reentrante en la misma transacción (_venta_modo_aplica lo vuelve a tomar sin bloquearse).
-- Cuerpo VIVO de 20260930074916/20260930082215. Misma firma: create or replace conserva los grants.

create or replace function public.venta_modo_admin(p_raiz uuid, p_modo text, p_motivo text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_modo text;
begin
  if auth.uid() is null or v_yo = '' then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if not (public.es_admin() and public.puede('comisiones_reparto')) then
    raise exception 'El modo de una venta ya firmada lo cambia un administrador' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));
  if p_modo is distinct from 'equipo' then
    raise exception 'Solo se puede pasar una venta al equipo' using errcode = '22023';
  end if;
  if v_mot is null then raise exception 'Cambiar el modo exige un motivo' using errcode = '22023'; end if;
  if not exists (select 1 from public.contratos c where c.id = p_raiz and c.contrato_padre_id is null) then
    raise exception 'Esa venta no existe (o no es la raíz)' using errcode = 'P0002';
  end if;
  select k.modo into v_modo from public.contrato_closer k where k.contrato_id = p_raiz;
  if v_modo is null
     and not coalesce((select i.modo_obligatorio from public.comisiones_interruptor i where i.id), false) then
    raise exception 'Todavía no se declara el modo de las ventas' using errcode = '22023';
  end if;
  if exists (select 1 from public.contrato_closer k where k.contrato_id = p_raiz and lower(k.closer_email) = v_yo) then
    raise exception 'Nadie cambia el modo de su propia venta' using errcode = '42501';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r where r.contrato_raiz_id = p_raiz and r.tipo = 'objecion' and r.estado = 'pendiente') then
    raise exception 'Esta venta tiene una objeción abierta: resuélvela primero' using errcode = '22023';
  end if;
  return public._venta_modo_aplica(p_raiz, p_modo, v_mot);
end $function$;
