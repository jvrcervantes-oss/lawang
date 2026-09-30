-- F5b · la objeción del Sales Manager avisa TAMBIÉN al closer (30-sep-2026, revisión de código F5b).
-- Porqué: el diálogo de /intranet/v4/equipos-venta/ (editores.js, data-accion="vpc-objetar") dice «el closer y
-- administración reciben el aviso», y venta_objecion_crear solo avisaba a admin/super_admin: el closer veía su
-- comisión parada sin saber por qué. Decisión: avisar al closer (su comisión queda en espera).
-- Cuerpo VIVO de 20260930131454_f5b_venta_pantallas (md5 del def vivo 9e17991651db0e9dc35a7ca06dfd4955) + una
-- notificación al closer. El closer se excluye del aviso a administración para que un closer que además sea admin no
-- reciba dos avisos del mismo hecho. Sin cambio de firma ni de grants (create or replace los conserva).

create or replace function public.venta_objecion_crear(p_raiz uuid, p_motivo text)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_yo  text := lower(coalesce(auth.email(), ''));
  v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
  k     public.contrato_closer;
  v_id  uuid;
  v_num text;
begin
  if auth.uid() is null or v_yo = '' then raise exception 'Sin sesión: vuelve a entrar' using errcode = '42501'; end if;
  if v_mot is null then raise exception 'Explica por qué la venta es del equipo' using errcode = '22023'; end if;
  if length(v_mot) > 2000 then raise exception 'El motivo admite como mucho 2000 caracteres' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtext('comisiones:' || p_raiz::text));
  select * into k from public.contrato_closer where contrato_id = p_raiz for update;
  if not found or k.modo is distinct from 'propia' or k.equipo_id is null then
    raise exception 'Esa venta no está marcada «por su cuenta» dentro de un equipo' using errcode = '22023';
  end if;
  if not public._sm_ve_venta(p_raiz) then
    raise exception 'Solo el Sales Manager del equipo de esa venta puede objetar' using errcode = '42501';
  end if;
  if lower(k.closer_email) = v_yo then raise exception 'No puedes objetar tu propia venta' using errcode = '42501'; end if;
  if k.modo_espera_hasta is null or now() >= k.modo_espera_hasta then
    raise exception 'El plazo para objetar esta venta ya terminó' using errcode = '22023';
  end if;
  if exists (select 1 from public.reclamaciones_venta_propia r where r.contrato_raiz_id = p_raiz and r.tipo = 'objecion' and r.estado = 'pendiente') then
    raise exception 'Ya hay una objeción abierta en esta venta' using errcode = '23505';
  end if;

  insert into public.reclamaciones_venta_propia (contrato_raiz_id, solicitante_email, equipo_id, manager_email, motivo, tipo)
  values (p_raiz, v_yo, k.equipo_id, v_yo, v_mot, 'objecion')
  returning id into v_id;

  select c.numero into v_num from public.contratos c where c.id = p_raiz;
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  select 'venta_objecion', 'Objeción a una venta por su cuenta · ' || coalesce(v_num, '?'),
         'El Sales Manager ' || v_yo || ' objeta que la venta ' || coalesce(v_num, '?') || ' de ' || lower(k.closer_email)
           || ' sea por su cuenta. La comisión queda en espera hasta que la resuelva un administrador.',
         u.email, p_raiz, '/intranet/v4/comisiones/', true
    from public.usuarios u
   where u.activo and u.rol in ('admin', 'super_admin') and lower(u.email) <> lower(k.closer_email);

  -- el closer: su comisión queda en espera (sin cifras ni el motivo del SM; el motivo lo decide administración)
  insert into public.notificaciones (tipo, titulo, detalle, destinatario, contrato_id, enlace, email_pendiente)
  values ('venta_objecion', 'Objeción a tu venta · ' || coalesce(v_num, '?'),
          'Tu Sales Manager ha objetado que la venta ' || coalesce(v_num, '?')
            || ' sea por tu cuenta; la comisión queda en espera hasta que la resuelva administración.',
          lower(k.closer_email), p_raiz, '/intranet/v4/comisiones/', true);
  return v_id;
end $function$;
