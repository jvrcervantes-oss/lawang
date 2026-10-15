-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Sociedad firmante = la de la empresa del proyecto (owner, 15-oct-2026: «en contratos de lawang si selecciono un proyecto la
-- sociedad firmante debe quedar bloqueada»). Contratos la bloquea en pantalla (syncSociedadProyecto, contracts/app.html); la base
-- lo exige aquí porque la pantalla no es un candado (máxima: el backend no se cree el frontend).
-- Regla: proyecto del contrato → proyectos.empresa → empresas.sociedad_clave. El proyecto se resuelve con _contrato_proyecto_de,
--   igual que trg_espejo_proyecto, porque este trigger (trg_contrato_sociedad_existe) corre ANTES que el espejo y un alta que
--   solo trae el nombre todavía no tiene proyecto_id.
-- Solo se rechaza cuando CAMBIA la sociedad o el proyecto: el trigger salta en cada UPDATE (firma-submit, edges, bloqueo) y un
--   contrato viejo descuadrado no puede reventar al firmarse. Medidos el 15-oct: 15 sin firmar y 5 firmados descuadrados; no se
--   tocan aquí (owner, «corregir al reabrir»: la pantalla les pone la que toca al abrirlos y así se guardan).
-- PRECEDENCIA (la misma que la pantalla; revisor de código y owner, 15-oct):
--   1) Documentos vivos del contrato (facturas, proformas, recibís sin anular): la sociedad no se cambia a otra que la suya
--      (owner: 12 de los 15 descuadrados tienen documentos de Tepi Sun Gai y se quedan así; cambiarla obliga a anular y
--      reemitir). Con documentos no aplica la regla del proyecto: mandan ellos.
--   2) El contrato del que cuelga, si tiene sociedad (regla del padre, ya existía). Con padre tampoco aplica la del proyecto:
--      sin esto un hijo de un padre descuadrado no se podía guardar de ninguna forma, y con el padre firmado no había salida.
--   3) El proyecto.
-- Una sociedad que ya tenía valor no se puede VACIAR (23514; Seguridad, 15-oct). Una sociedad VACÍA no se rellena (decisión por defecto del CEO, 15-oct): rellenarla cambiaría con qué sociedad salen las
--   proformas de las plantillas que no tienen el campo (lwSociedadContrato cae a SOCIEDAD_DEFAULT). Revertir: añadir el relleno.
-- Proyecto sin empresa o empresa sin sociedad: no se exige nada (no hay con qué comparar), como antes.
-- destructivo-ok: solo cambia el cuerpo de una función de trigger; no toca filas, permisos ni triggers.
-- REVERTIR: supabase/reversion_sociedad_del_proyecto/REVERSION.sql (cuerpo anterior literal, md5(prosrc) 9656f0750eb354e2a0992473bbd2ed69).
set local lock_timeout = '5s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = 'public.contrato_sociedad_existe()'::regprocedure) <> '9656f0750eb354e2a0992473bbd2ed69' then
    raise exception 'contrato_sociedad_existe viva no es la de 20261006143748 (md5 9656f075…): alguien la cambió después; revisar a mano';
  end if;
end $pre$;

create or replace function public.contrato_sociedad_existe() returns trigger
language plpgsql security definer set search_path to '' as $$
declare
  v_clave    text := nullif(btrim(coalesce(new.datos->'fields'->>'sociedad_firmante','')), '');
  v_old      text;
  v_padre    text;
  v_activa   boolean;
  v_cambia   boolean;
  v_proy     uuid;
  v_proy_nom text;
  v_soc_proy text;
  v_ndocs    int := 0;
  v_soc_doc  text;
begin
  if tg_op = 'UPDATE' then
    v_old := nullif(btrim(coalesce(old.datos->'fields'->>'sociedad_firmante','')), '');
  end if;
  v_cambia := (tg_op = 'INSERT') or v_clave is distinct from v_old;
  -- vaciar una sociedad que ya tenía valor se saltaba las reglas de abajo (todo cuelga de v_clave not null) y las proformas
  -- siguientes salían con SOCIEDAD_DEFAULT: se rechaza (consulta de Seguridad, 15-oct). Lo que nació vacío sigue pudiendo serlo.
  if tg_op = 'UPDATE' and v_old is not null and v_clave is null then
    raise exception 'La sociedad firmante no se puede dejar vacía (era «%»).', v_old using errcode = '23514';
  end if;

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

    -- la del proyecto (15-oct-2026): solo si cambia la sociedad o el proyecto, y con la precedencia de la cabecera
    v_proy := public._contrato_proyecto_de(new.proyecto_id, new.proyecto_nombre);
    if tg_op = 'UPDATE' and (v_cambia or v_proy is distinct from old.proyecto_id) then
      select count(distinct f.sociedad), min(f.sociedad) into v_ndocs, v_soc_doc
        from public.facturas f where f.contrato_id = new.id and not f.anulada;
      if v_ndocs > 0 and v_cambia and (v_ndocs > 1 or v_clave <> v_soc_doc) then
        raise exception 'La sociedad firmante «%» no es la de sus facturas o recibís emitidos («%»): para cambiarla hay que anularlos y reemitirlos.',
          v_clave, v_soc_doc using errcode = '23514';
      end if;
    end if;
    if v_ndocs = 0 and v_padre is null and v_proy is not null and (v_cambia or v_proy is distinct from old.proyecto_id) then
      select p.nombre, e.sociedad_clave into v_proy_nom, v_soc_proy
        from public.proyectos p join public.empresas e on e.clave = p.empresa
       where p.id = v_proy;
      if v_soc_proy is not null and v_clave <> v_soc_proy then
        raise exception 'La sociedad firmante «%» no es la del proyecto «%», que firma con «%».', v_clave, v_proy_nom, v_soc_proy
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end $$;
