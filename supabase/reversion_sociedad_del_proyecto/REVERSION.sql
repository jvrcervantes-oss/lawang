-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- REVERSION de 20261015150000_contrato_sociedad_del_proyecto.sql (15-oct-2026, sesion sociedad-por-proyecto).
-- ORDEN: da igual respecto al front (contracts/app.html sigue bloqueando el campo en pantalla aunque la base deje de exigirlo);
-- si se revierte todo, primero el front (git revert) y luego ESTE fichero, en una transaccion.
-- contrato_sociedad_existe vuelve LITERAL a la viva del 15-oct (pg_get_functiondef, md5(prosrc) 9656f0750eb354e2a0992473bbd2ed69);
-- el CREATE OR REPLACE conserva sus grants. Precondicion: que la viva sea la que dejo la migracion, para no pisar un cambio posterior.
-- destructivo-ok: solo repone el cuerpo anterior de una funcion de trigger; no toca datos
set local lock_timeout = '5s';

do $pre$
begin
  if position('la del proyecto (15-oct-2026)' in pg_get_functiondef('public.contrato_sociedad_existe()'::regprocedure)) = 0 then
    raise exception 'contrato_sociedad_existe viva no es la que dejo 20261015150000: alguien la cambio despues; revertir a mano';
  end if;
end $pre$;

CREATE OR REPLACE FUNCTION public.contrato_sociedad_existe()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_clave  text := nullif(btrim(coalesce(new.datos->'fields'->>'sociedad_firmante','')), '');
  v_old    text;
  v_padre  text;
  v_activa boolean;
  v_cambia boolean;
begin
  if tg_op = 'UPDATE' then
    v_old := nullif(btrim(coalesce(old.datos->'fields'->>'sociedad_firmante','')), '');
  end if;
  v_cambia := (tg_op = 'INSERT') or v_clave is distinct from v_old;

  -- herencia: una construcción/carta colgada de una reserva con sociedad explícita
  if new.contrato_padre_id is not null and jsonb_typeof(new.datos->'fields') = 'object' then
    select nullif(btrim(coalesce(p.datos->'fields'->>'sociedad_firmante','')), '') into v_padre
      from public.contratos p where p.id = new.contrato_padre_id;
    if v_padre is not null then
      if v_clave is null and tg_op = 'INSERT' then
        new.datos := jsonb_set(new.datos, '{fields,sociedad_firmante}', to_jsonb(v_padre));
        v_clave := v_padre; v_cambia := true;
      elsif v_clave is not null and v_cambia and v_clave <> v_padre then
        raise exception 'La sociedad firmante «%» no coincide con la del contrato del que cuelga («%»).', v_clave, v_padre
          using errcode = '23514';
      end if;
    end if;
  end if;

  if v_clave is not null then
    select s.activa into v_activa from public.sociedades s where s.clave = v_clave;
    if not found then
      raise exception 'La sociedad firmante «%» no existe en public.sociedades.', v_clave;   -- mensaje original
    end if;
    if v_cambia and not v_activa then
      raise exception 'La sociedad firmante «%» está desactivada: elige una activa.', v_clave using errcode = '23514';
    end if;
  end if;
  return new;
end $function$;
