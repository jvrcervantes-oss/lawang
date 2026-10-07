-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- BLOQUE 11 · 2/2 (7-oct-2026, Datos). LAW-E55: `comprador_ficha` entregaba pasaporte, nacimiento y direccion de CUALQUIER cliente a un agente SIN alcance acotado.
--   Decision del owner (7-oct): cerrarlo «como a los acotados». La ficha basica ya es de todo el equipo (compradores_lista, bloque 11.1); la FICHA ENTERA sigue la regla de los contratos.
--   Quien con alcance acotado (ambito empresa o empresas marcadas): SIN CAMBIO, solo la ve si `cliente_visible` (la misma regla que ya abre el KYC y la fila de `clients`).
--   Quien NO tiene alcance acotado: antes cualquier ficha por id; ahora la ve si `cliente_visible` O si ve algun contrato de ese cliente (`puede_ver_contrato`:
--   el closer que reabre su contrato con la ficha de otro closer, 22-sep, sigue pudiendo). Un administrador global lo sigue viendo todo (es_admin() dentro de cliente_visible).
--   Sin fila = la ficha no se entrega (igual que a los acotados): el front ya lo trata (toast en el editor y el asistente; la ficha basica de Clientes no ofrece «Crear contrato»).
--   El tope de fichas abiertas por 10 minutos y el registro de accesos no cambian. Nada de datos ni de permisos: solo el texto de una funcion de lectura.
-- destructivo-ok: solo reemplaza 1 funcion de lectura (mismo tipo de retorno); no toca datos ni tablas
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_b11_2.sql
create or replace function public.comprador_ficha(p_id uuid)
 returns table(id uuid, full_name text, tipo text, email text, phone text, nationality text, passport_number text, date_of_birth date, address text, forma_juridica text, registro_num text, rep_nombre text, rep_cargo text, kyc_status text, propietario text, created_at timestamp with time zone)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid()); v_n int;
begin
  if not public.es_agente() then return; end if;
  -- la ficha entera (pasaporte, nacimiento, direccion) solo a quien ya ve ese cliente por la regla de los contratos / del KYC
  if not exists (
       select 1 from public.clients c0
        where c0.id = p_id
          and (public.cliente_visible(c0.propietario, c0.id)
               or (not (select public.alcance_restringido())
                   and exists (select 1 from public.contrato_compradores cc
                                where cc.client_id = c0.id and public.puede_ver_contrato(cc.contrato_id))))) then
    return;
  end if;
  if not public.es_admin_en_alguna_empresa() then
    select count(distinct a.client_id) into v_n from public.comprador_ficha_accesos a
     where a.user_id = v_uid and a.en > now() - interval '10 minutes' and a.client_id <> p_id;
    if v_n >= 20 then raise exception 'Demasiadas fichas abiertas seguidas: espera unos minutos' using errcode = '42501'; end if;
  end if;
  if exists (select 1 from public.clients c where c.id = p_id) then
    insert into public.comprador_ficha_accesos(user_id, client_id) values (v_uid, p_id);
  end if;
  return query
    select c.id, c.full_name, c.tipo, c.email, c.phone, c.nationality, c.passport_number, c.date_of_birth, c.address,
           c.forma_juridica, c.registro_num, c.rep_nombre, c.rep_cargo, c.kyc_status, c.propietario, c.created_at
      from public.clients c where c.id = p_id;
end $function$;
