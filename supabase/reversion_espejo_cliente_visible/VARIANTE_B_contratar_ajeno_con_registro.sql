-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- VARIANTE B — NO ES UNA MIGRACION, NO ESTA APLICADA NI PROBADA (14-oct-2026, Backend). Sin numero a proposito.
-- Solo se usa si el owner decide que «un agente puede hacer un contrato al cliente que dio de alta otra persona» es un uso
-- legitimo. Va ENCIMA de la migracion 20261014101500_espejo_cliente_visible (variante A), nunca en su lugar. Antes de aplicarla:
-- revision previa de Seguridad y Legal, numero de migracion, su prueba (los casos E2, E3 y M1 de supabase/pruebas/
-- espejo_cliente_visible.sql pasan de NIEGA a ENTRA-con-registro y hay que reescribirlos) y cambio de pantalla (ver punto 5).
--
-- QUE CAMBIA ENTRE A Y B, en 5 lineas:
--   1) A rechaza (42501) el client_id de una ficha que quien guarda no ve. B lo ADMITE si la ficha es de su misma empresa
--      (su propietario comparte empresa con quien guarda), y sigue rechazando las de otra empresa (el muro LAW-E55 del 7-oct no se abre).
--   2) En B cada cliente ajeno que se pone en un contrato GASTA el mismo tope que abrir su ficha (20 fichas distintas cada 10 min)
--      y queda en el mismo registro (comprador_ficha_accesos): se sabe quien se llevo que ficha y cuando.
--   3) En B la ficha de ese cliente SI se espeja en el contrato (pasaporte, domicilio, telefono...): el agente la recibe entera.
--   4) En B el tecleo a mano de un pasaporte/correo que coincide con una ficha ajena SIGUE sin enlazar (como en A): el cliente
--      ajeno se elige por su ficha, con registro; adivinar pasaportes no enlaza.
--   5) B necesita cambio de pantalla (Frontend): hoy el buscador corta en comprador_ficha («Esa ficha es de otra empresa o de otro
--      comercial»); tendria que dejar elegirla y avisar de que queda registrado. A no necesita tocar la pantalla.
-- Efecto lateral que B NO resuelve (Seguridad, 14-oct): enlazar a un contrato de la empresa X un cliente cuyo dueno tambien es de la
--   empresa Y le quita la ficha entera al admin de Y (rama del 14-oct de cliente_visible). Con el muro por empresa solo pasa con
--   personas que estan en las dos empresas, pero pasa.
-- La autorizacion viaja dentro de la transaccion en `app.clientes_contratados` (lista de ids admitidos y registrados por la puerta):
--   el navegador no puede fijarla (PostgREST no expone set_config y cada peticion es su transaccion). Es el punto mas fragil de B y
--   lo primero que debe mirar Seguridad.
-- destructivo-ok: reemplaza funciones; no toca datos

-- Ficha que entra en un contrato: la que quien guarda ve, o la que la puerta admitio y registro en ESTA transaccion.
create or replace function public._cliente_en_contrato(p_client uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select public._cliente_ficha_visible(p_client)
      or p_client::text = any (string_to_array(coalesce(current_setting('app.clientes_contratados', true), ''), ','))
$function$;
revoke all on function public._cliente_en_contrato(uuid) from public, anon, authenticated;

create or replace function public._contrato_clientes_comprueba(p_id uuid, p_datos jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id uuid;
  v_uid uuid := (select auth.uid());
  v_ya uuid[] := '{}'::uuid[];
  v_n int;
  v_admitidos text := '';
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  perform set_config('app.clientes_contratados', '', true);
  if v_uid is null then
    return;
  end if;
  if p_id is not null then
    select coalesce(array_agg(q.x), '{}'::uuid[]) into v_ya
      from (select cc.client_id as x from public.contrato_compradores cc where cc.contrato_id = p_id
            union
            select c.adq1_client_id from public.contratos c where c.id = p_id
            union
            select case when btrim(coalesce(e.v->>'client_id', '')) ~ c_uuid then btrim(e.v->>'client_id')::uuid end
              from public.contratos c
             cross join lateral jsonb_array_elements(case when jsonb_typeof(c.datos->'compradores') = 'array'
                                                          then c.datos->'compradores' else '[]'::jsonb end) e(v)
             where c.id = p_id) q
     where q.x is not null;
  end if;
  for v_id in
    select distinct t.x
      from (select case when btrim(coalesce(p_datos->>'adq1_client_id', '')) ~ c_uuid
                        then btrim(p_datos->>'adq1_client_id')::uuid end as x
            union all
            select case when btrim(coalesce(e.v->>'client_id', '')) ~ c_uuid then btrim(e.v->>'client_id')::uuid end
              from jsonb_array_elements(case when jsonb_typeof(p_datos->'compradores') = 'array'
                                             then p_datos->'compradores' else '[]'::jsonb end) e(v)) t
     where t.x is not null
  loop
    continue when v_id = any (v_ya);
    continue when not exists (select 1 from public.clients c where c.id = v_id);
    continue when public._cliente_ficha_visible(v_id);
    -- ficha AJENA: solo de la misma empresa (o quien guarda no tiene alcance acotado); una ficha sin dueno, solo un admin
    if not exists (select 1
                     from public.clients c
                     join public.usuarios pr on lower(pr.email) = lower(c.propietario) and pr.activo
                     join public.usuarios me on me.user_id = v_uid and me.activo
                    where c.id = v_id
                      and (not (select public.alcance_restringido()) or pr.empresas && me.empresas)) then
      raise exception 'Esa ficha es de otra empresa o de otro comercial: no puedes usarla en un contrato desde tu cuenta. Pídele a un administrador que lo haga.'
        using errcode = '42501';
    end if;
    -- mismo tope y mismo registro que comprador_ficha
    select count(distinct a.client_id) into v_n from public.comprador_ficha_accesos a
     where a.user_id = v_uid and a.en > now() - interval '10 minutes' and a.client_id <> v_id;
    if v_n >= 20 then
      raise exception 'Demasiadas fichas abiertas seguidas: espera unos minutos' using errcode = '42501';
    end if;
    insert into public.comprador_ficha_accesos (user_id, client_id) values (v_uid, v_id);
    v_admitidos := v_admitidos || case when v_admitidos = '' then '' else ',' end || v_id::text;
  end loop;
  perform set_config('app.clientes_contratados', v_admitidos, true);
end $function$;
revoke all on function public._contrato_clientes_comprueba(uuid, jsonb) from public, anon, authenticated;

-- El espejo y el enlace pasan a mirar _cliente_en_contrato en vez de _cliente_ficha_visible (comprador_ficha NO cambia)
do $b$
declare v_def text; v_fn regprocedure;
begin
  foreach v_fn in array array['public.espeja_comprador(jsonb)'::regprocedure, 'public.sincronizar_compradores(uuid)'::regprocedure] loop
    select pg_get_functiondef(v_fn) into v_def;
    if position('public._cliente_en_contrato(' in v_def) = 0 then
      if (length(v_def) - length(replace(v_def, 'public._cliente_ficha_visible(', ''))) / length('public._cliente_ficha_visible(') <> 1 then
        raise exception 'variante B: % no llama exactamente una vez a _cliente_ficha_visible (¿esta aplicada la variante A?)', v_fn;
      end if;
      execute replace(v_def, 'public._cliente_ficha_visible(', 'public._cliente_en_contrato(');
    end if;
  end loop;
end $b$;
