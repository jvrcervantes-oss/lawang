-- Arreglo del mismo dia, cazado por la prueba de camino completo ANTES de desplegar.
--
-- EL MOTOR REVENTABA LLAMADO POR R13, en cada lead. `crm_repartir_lead` esta pensada para
-- admitir la identidad de maquina (service_role, sin sesion) y asi estaba escrita... pero por
-- dentro hacia `left join public.crm_ranking_closers()`, y ESA funcion revalida
-- `puede('ranking') or puede('leads')`, que con `auth.uid()` nulo devuelve false y lanza
-- 'Sin permiso'. O sea: la puerta de fuera estaba bien y la de dentro no.
-- Sintoma exacto de la prueba: "1. motor como R13 -> REVIENTA: Sin permiso".
--
-- Es la misma familia de fallo que Datos habia avisado en la revision previa ("si
-- crm_repartir_lead copia ese patron, revienta en cada lead") — solo que no estaba en el
-- patron de la funcion, estaba en una llamada anidada. De no probarlo, habria fallado en
-- produccion en cada lead y en silencio: R13 no mira el valor de retorno.
--
-- ARREGLO: el puesto se calcula AQUI DENTRO, con la misma regla que `crm_ranking_closers`
-- (orden por dinero cobrado, desempate por firmado) pero sin pasar por su comprobacion de
-- permiso. Es correcto y no abre nada: esta funcion ya es SECURITY DEFINER y no devuelve
-- cifras de nadie — solo las usa para ordenar, y lo unico que sale es a quien le toca.
-- ⚠️ Si algun dia cambia la regla del ranking, hay que cambiarla en los DOS sitios. Se acepta
-- la duplicacion a proposito: la alternativa era relajar el permiso de `crm_ranking_closers`,
-- y eso si abriria las cifras de todos a cualquiera que sepa llamarla.
--
-- VERIFICADO tras el arreglo, con todo revertido (produccion intacta):
--   · motor como R13 -> asigna, ya no revienta
--   · segunda pasada sobre el mismo lead -> 'ya_tenia_dueno' (R13 pasa cada 4 h)
--   · sesgo por cuota con tope alto -> Carmen 20 / Yesy 10 = 2,00:1 exacto
--   · con tope 4 -> ambas se llenan y el resto cae a 'todos_al_tope', que es lo correcto
--   · humano sin permiso `reparto` -> PT403
create or replace function public.crm_repartir_lead(p_lead uuid)
returns table (elegido text, motivo text)
language plpgsql volatile security definer set search_path to ''
as $$
declare
  v_humano  text := coalesce((select auth.email()), '');
  v_autor   text;
  v_src     text;
  v_actual  text;
  v_cfg     record;
  v_elegido text;
  v_motivo  text;
  v_detalle jsonb := '[]'::jsonb;
  c         record;
  v_mejor   numeric;
begin
  -- O es una sesion humana con permiso, o es la maquina (sin sesion). Nunca un `if
  -- current_user = 'service_role' then saltarse la comprobacion`: eso convierte el atajo en
  -- una API de asignacion sin rastro para cualquiera que tenga la service key (Seguridad).
  if v_humano <> '' then
    if not public.puede('reparto') then
      raise exception 'Sin permiso para repartir leads' using errcode = 'PT403';
    end if;
    v_autor := v_humano;
  else
    v_autor := 'R13';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_lead::text, 0));

  select l.source into v_src from public.leads l where l.id = p_lead;
  if v_src is null then
    raise exception 'Ese lead no existe' using errcode = 'PT404';
  end if;

  -- IDEMPOTENTE POR CONSTRUCCION: solo actua si el lead no tiene dueno. R13 pasa cada 4 h
  -- sobre los mismos leads; sin esto, reasignaria en cada vuelta y el lead cambiaria de
  -- manos solo. Y de paso impide que el reparto le quite un lead a nadie.
  select e.responsable into v_actual from public.lead_estado e where e.lead_id = p_lead;
  if v_actual is not null then
    return query select v_actual, 'ya_tenia_dueno'::text;
    return;
  end if;

  select * into v_cfg from public.reparto_origen o where o.source = v_src;
  if v_cfg is null or not v_cfg.activo then
    insert into public.reparto_log (lead_id, source, elegido, motivo, autor, detalle)
         values (p_lead, v_src, null, 'origen_sin_configurar', v_autor, '{}'::jsonb);
    return query select null::text, 'origen_sin_configurar'::text;
    return;
  end if;

  v_mejor := null;
  for c in
    with puestos as (
      select lower(k2.closer_email) as quien,
             rank() over (order by coalesce(sum(public.contrato_cobrado(c2.id)), 0) desc,
                                   coalesce(sum(c2.precio_total), 0) desc) as puesto
        from public.contrato_closer k2
        join public.contratos c2 on c2.id = k2.contrato_id
       where coalesce(c2.bloqueado, false) and c2.precio_total is not null
       group by lower(k2.closer_email)
    )
    select k.closer_email as quien,
           coalesce(p.puesto, 999) as puesto,
           case when coalesce(p.puesto, 999) = 1 then 2 else 1 end as cuota,
           -- OCUPACION: leads suyos aun sin trabajar. "Sin trabajar" NO es "en estado nuevo"
           -- (eso se vacia arrastrando la tarjeta, sin haber llamado a nadie — hallazgo de
           -- Seguridad): es no haber pedido todavia su contacto, que es el hecho que si deja
           -- rastro. Y los que llevan mas de `dias_caducidad` parados dejan de ocupar hueco,
           -- o el tope se atasca y todo cae a "sin dueno" (hallazgo de Datos).
           (select count(*) from public.lead_estado e2
            where lower(e2.responsable) = k.closer_email
              and e2.estado = 'nuevo'
              and e2.asignado_en > now() - make_interval(days => v_cfg.dias_caducidad)
              and not exists (select 1 from public.lead_acceso_log g
                               where g.lead_id = e2.lead_id and lower(g.quien) = k.closer_email)
           ) as ocupados,
           (select count(*) from public.reparto_log rl
             where lower(rl.elegido) = k.closer_email and rl.motivo = 'asignado'
               and rl.cuando > now() - interval '30 days') as recibidos,
           (select max(rl.cuando) from public.reparto_log rl
             where lower(rl.elegido) = k.closer_email and rl.motivo = 'asignado') as ultimo
      from public.reparto_closer k
      left join puestos p on p.quien = k.closer_email
     where k.source = v_src
       and exists (select 1 from public.usuarios u
                    where lower(u.email) = k.closer_email and u.activo
                      and ('leads' = any(u.herramientas) or u.rol = 'super_admin'))
  loop
    if c.ocupados >= v_cfg.tope_sin_contactar then
      v_detalle := v_detalle || jsonb_build_object('quien', c.quien, 'descartado', 'al_tope',
                     'ocupados', c.ocupados, 'tope', v_cfg.tope_sin_contactar);
    else
      -- DEUDA = recibidos / cuota. El #1 tiene cuota 2, asi que con el doble de leads sigue
      -- empatado a deuda: por eso recibe el doble a la larga sin que nadie lleve una ronda
      -- a mano. Empate -> el que lleva mas tiempo sin recibir. Medido: 2,00:1 exacto.
      v_detalle := v_detalle || jsonb_build_object('quien', c.quien, 'puesto', c.puesto,
                     'cuota', c.cuota, 'recibidos_30d', c.recibidos, 'ocupados', c.ocupados,
                     'deuda', round(c.recibidos::numeric / c.cuota, 3));
      if v_mejor is null
         or (c.recibidos::numeric / c.cuota) < v_mejor
         or ((c.recibidos::numeric / c.cuota) = v_mejor and c.ultimo is null) then
        v_mejor := c.recibidos::numeric / c.cuota;
        v_elegido := c.quien;
      end if;
    end if;
  end loop;

  if v_elegido is null then
    v_motivo := case when jsonb_array_length(v_detalle) = 0
                     then 'sin_candidatos' else 'todos_al_tope' end;
    insert into public.reparto_log (lead_id, source, elegido, motivo, autor, detalle)
         values (p_lead, v_src, null, v_motivo, v_autor,
                 jsonb_build_object('candidatos', v_detalle));
    return query select null::text, v_motivo;
    return;
  end if;

  update public.lead_estado e
     set responsable = v_elegido, asignado_por = v_autor, asignado_en = now(), actualizado = now()
   where e.lead_id = p_lead;
  if not found then
    insert into public.lead_estado (lead_id, estado, estado_desde, actualizado,
                                    responsable, asignado_por, asignado_en)
         values (p_lead, 'nuevo',
                 (select l.created_at from public.leads l where l.id = p_lead),
                 now(), v_elegido, v_autor, now());
  end if;

  insert into public.lead_dueno_log (lead_id, de, a, autor)
       values (p_lead, null, v_elegido, v_autor);
  insert into public.reparto_log (lead_id, source, elegido, motivo, autor, detalle)
       values (p_lead, v_src, v_elegido, 'asignado', v_autor,
               jsonb_build_object('candidatos', v_detalle, 'tope', v_cfg.tope_sin_contactar,
                                  'dias_caducidad', v_cfg.dias_caducidad));

  return query select v_elegido, 'asignado'::text;
end;
$$;

revoke execute on function public.crm_repartir_lead(uuid) from public, anon;
-- Lo pueden llamar los dos: la maquina (R13, sin sesion) y una persona con `reparto` desde la
-- pantalla. Cada una queda firmada distinto en `reparto_log`.
grant execute on function public.crm_repartir_lead(uuid) to authenticated, service_role;
