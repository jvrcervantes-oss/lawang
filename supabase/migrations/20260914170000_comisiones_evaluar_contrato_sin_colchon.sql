-- COMISIONES: SE QUITA EL COLCHÓN DE 5 DÍAS — 14-sep-2026.
-- Decisión explícita del owner: los tramos deben dispararse en cuanto se
-- cumple el umbral, sin ninguna espera desde el recibi. Reemplaza
-- public.comisiones_evaluar_contrato(uuid), creada en
-- 20260914160000_comisiones_evaluar_contrato_fn.sql.
--
-- VERIFICADO ANTES DE TOCAR NADA (execute_sql sobre pg_get_functiondef en
-- producción, no sobre el recuerdo del repo): el nombre exacto de la función
-- es public.comisiones_evaluar_contrato(p_contrato_id uuid), y la variable
-- del ancla es v_ultimo_recibi_en (timestamptz), fijada un bloque antes del
-- colchón:
--   if now() - v_ultimo_recibi_en < interval '5 days' then
--     return 0; -- colchón: el recibi más reciente de la cadena aún no lleva 5 días
--   end if;
-- Ese bloque se retira íntegro y NO se sustituye por ninguna otra espera. El
-- resto del cuerpo de la función es un calco exacto del de 20260914160000:
-- resolución de raíz/closer/equipo/manager, agregación de precio/cobrado vía
-- unidad_parte_cobrada_split (misma fuente que unidades_estado), la
-- resolución de condición con override de closer, el bucle de tramos con su
-- UNIQUE (on conflict do nothing sobre contrato_raiz_id/tramo_id/
-- beneficiario_email), el snapshot disparado_por_snapshot (que sigue
-- congelando recibi_id + recibi_registrado_en del recibi ancla — eso es lo
-- que _comisiones_marca_disputa_por_recibi usa para marcar en_disputa si se
-- anula ese recibi; esa función no se toca en esta migración) y la creación
-- de la solicitud de pago del manager. Cero cambios ahí.
--
-- destructivo-ok: este fichero solo CREATE OR REPLACE FUNCTION y REVOKE sobre
-- la misma función que ya no tenía GRANT a authenticated (nada que perder).
-- Cero DROP, cero DELETE, cero UPDATE sin WHERE.

create or replace function public.comisiones_evaluar_contrato(p_contrato_id uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_raiz_id              uuid;
  v_moneda               text;
  v_proyecto_id          uuid;
  v_contrato_firmado     boolean := false;
  v_obra_firmada         boolean := false;
  v_precio_total         numeric := 0;
  v_precio_suelo         numeric := 0;
  v_precio_construccion  numeric := 0;
  v_cobrado_suelo        numeric := 0;
  v_cobrado_obra         numeric := 0;
  v_cobrado_total        numeric := 0;
  v_closer_email         text;
  v_equipo_id            uuid;
  v_manager_email        text;
  v_ultimo_recibi_id     uuid;
  v_ultimo_recibi_en     timestamptz;
  v_nivel                text;
  v_beneficiario         text;
  v_condicion            record;
  v_tramo                record;
  v_base                 numeric;
  v_importe              numeric;
  v_devengo_id           uuid;
  v_sp_id                uuid;
  v_creado_por           uuid;
  v_creados              integer := 0;
begin
  if p_contrato_id is null then
    return 0;
  end if;

  -- 1) la RAÍZ, subiendo un nivel (p_contrato_id puede ser ya la raíz o un hijo)
  select coalesce(c.contrato_padre_id, c.id) into v_raiz_id
    from public.contratos c
   where c.id = p_contrato_id;

  if v_raiz_id is null then
    return 0; -- el contrato no existe
  end if;

  select c.moneda, c.proyecto_id, c.bloqueado
    into v_moneda, v_proyecto_id, v_contrato_firmado
    from public.contratos c
   where c.id = v_raiz_id;

  -- 2) precio_total de la cadena entera (raíz + hijos directos)
  select coalesce(sum(x.precio_total), 0)
    into v_precio_total
    from public.contratos x
   where x.id = v_raiz_id or x.contrato_padre_id = v_raiz_id;

  v_obra_firmada := exists (
    select 1 from public.contratos h
     where h.contrato_padre_id = v_raiz_id and h.bloqueado
  );

  -- 3) precio_suelo/precio_construccion y cobrado_suelo/cobrado_obra: SIEMPRE
  --    la misma fuente que unidades_estado (unidad_parte_cobrada_split), sobre
  --    todas las unidades enlazadas a la raíz.
  select coalesce(sum(u.precio_suelo), 0),
         coalesce(sum(u.precio_construccion), 0),
         coalesce(sum(cp.cobrado_suelo), 0),
         coalesce(sum(cp.cobrado_obra), 0)
    into v_precio_suelo, v_precio_construccion, v_cobrado_suelo, v_cobrado_obra
    from public.unidades u
    left join lateral public.unidad_parte_cobrada_split(u.id) cp on true
   where u.contrato_id = v_raiz_id;

  v_cobrado_total := v_cobrado_suelo + v_cobrado_obra;

  -- 4) closer de la RAÍZ, su equipo vigente HOY, y el manager de ese equipo
  select k.closer_email into v_closer_email
    from public.contrato_closer k
   where k.contrato_id = v_raiz_id;

  if v_closer_email is null then
    return 0; -- sin closer atribuido: nada que devengar todavía
  end if;

  select em.equipo_id into v_equipo_id
    from public.equipo_miembros em
    join public.equipos_venta ev on ev.id = em.equipo_id
   where em.closer_email = v_closer_email
     and ev.activo
     and em.desde <= current_date
     and (em.hasta is null or em.hasta >= current_date)
   order by em.created_at desc
   limit 1;

  if v_equipo_id is null or v_proyecto_id is null or v_moneda is null then
    return 0; -- sin equipo vigente, sin proyecto o sin moneda: no hay sobre qué evaluar
  end if;

  select ev.manager_email into v_manager_email
    from public.equipos_venta ev
   where ev.id = v_equipo_id;

  -- 5) el recibi ancla: el más reciente que toca la cadena entera, por las DOS
  --    mismas vías que ya usa contrato_cobrado (recibi con contrato_id propio
  --    de la cadena, o aplicado a una factura de la cadena). SIN colchón de
  --    espera desde aquí en adelante: en cuanto hay recibi ancla y un tramo
  --    cumple su umbral, se devenga en la misma evaluación.
  select r.id, r.created_at
    into v_ultimo_recibi_id, v_ultimo_recibi_en
    from public.facturas r
   where r.tipo = 'recibi'
     and not coalesce(r.anulada, false)
     and (
       r.contrato_id = v_raiz_id
       or r.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id)
       or exists (
            select 1
              from public.recibi_aplicaciones ra
              join public.facturas f on f.id = ra.factura_id
             where ra.recibi_id = r.id
               and not coalesce(f.anulada, false)
               and (f.contrato_id = v_raiz_id
                    or f.contrato_id in (select h.id from public.contratos h where h.contrato_padre_id = v_raiz_id))
          )
     )
   order by r.created_at desc
   limit 1;

  if v_ultimo_recibi_id is null then
    return 0; -- ningún recibi vivo sostiene todavía un devengo
  end if;

  -- 6) manager y closer, cada uno con su condición y sus tramos
  foreach v_nivel in array array['manager', 'closer']
  loop
    if v_nivel = 'closer' then
      v_beneficiario := v_closer_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and c.proyecto_id = v_proyecto_id
         and c.nivel = 'closer'
         and c.activo
         and c.closer_email = v_closer_email
       limit 1;

      if not found then
        select * into v_condicion
          from public.condiciones_comision c
         where c.equipo_id = v_equipo_id
           and c.proyecto_id = v_proyecto_id
           and c.nivel = 'closer'
           and c.activo
           and c.closer_email is null
         limit 1;
      end if;
    else
      v_beneficiario := v_manager_email;

      select * into v_condicion
        from public.condiciones_comision c
       where c.equipo_id = v_equipo_id
         and c.proyecto_id = v_proyecto_id
         and c.nivel = 'manager'
         and c.activo
         and c.closer_email is null
       limit 1;
    end if;

    if v_condicion.id is null or v_beneficiario is null then
      continue; -- sin condición configurada (o sin manager_email): nada que devengar en este nivel
    end if;

    v_base := case v_condicion.base_calculo
      when 'precio_total'        then v_precio_total
      when 'precio_suelo'        then v_precio_suelo
      when 'precio_construccion' then v_precio_construccion
      else null
    end;

    for v_tramo in
      select * from public.condicion_tramos
       where condicion_id = v_condicion.id
       order by orden
    loop
      -- ya devengado para este beneficiario en esta raíz: nada que hacer. El
      -- UNIQUE de comisiones_devengadas lo protegería igual (on conflict de
      -- abajo), pero comprobarlo antes evita reevaluar tramos ya cerrados en
      -- CADA disparo del trigger (facturas/recibi_aplicaciones cambian a menudo).
      if exists (
        select 1 from public.comisiones_devengadas d
         where d.contrato_raiz_id = v_raiz_id
           and d.tramo_id = v_tramo.id
           and d.beneficiario_email = v_beneficiario
      ) then
        continue;
      end if;

      if not (case v_tramo.disparador_tipo
        when 'pct_cobrado_suelo' then
          v_precio_suelo > 0 and (v_cobrado_suelo / v_precio_suelo * 100) >= v_tramo.umbral
        when 'pct_cobrado_obra' then
          v_precio_construccion > 0 and (v_cobrado_obra / v_precio_construccion * 100) >= v_tramo.umbral
        when 'pct_cobrado_total' then
          v_precio_total > 0 and (v_cobrado_total / v_precio_total * 100) >= v_tramo.umbral
        when 'obra_firmada' then v_obra_firmada
        when 'contrato_firmado' then v_contrato_firmado
        else false
      end) then
        continue;
      end if;

      if v_condicion.base_calculo = 'importe_fijo' then
        v_importe := v_condicion.importe_fijo * v_tramo.pct_tramo / 100;
      else
        if v_base is null then
          continue;
        end if;
        v_importe := (v_condicion.pct_comision / 100) * v_base * (v_tramo.pct_tramo / 100);
      end if;

      v_devengo_id := null;

      insert into public.comisiones_devengadas (
        contrato_raiz_id, tramo_id, condicion_id, beneficiario_email, nivel,
        importe, moneda, tipo_cambio_aplicado, disparado_por_snapshot
      ) values (
        v_raiz_id, v_tramo.id, v_condicion.id, v_beneficiario, v_nivel,
        v_importe, v_moneda, null,
        jsonb_build_object(
          'recibi_id', v_ultimo_recibi_id,
          'recibi_registrado_en', v_ultimo_recibi_en,
          'disparador_tipo', v_tramo.disparador_tipo,
          'umbral', v_tramo.umbral,
          'pct_tramo', v_tramo.pct_tramo,
          'base_calculo', v_condicion.base_calculo,
          'base_valor', v_base,
          'pct_comision', v_condicion.pct_comision,
          'precio_total', v_precio_total,
          'precio_suelo', v_precio_suelo,
          'precio_construccion', v_precio_construccion,
          'cobrado_suelo', v_cobrado_suelo,
          'cobrado_obra', v_cobrado_obra,
          'cobrado_total', v_cobrado_total,
          'obra_firmada', v_obra_firmada,
          'contrato_firmado', v_contrato_firmado
        )
      )
      on conflict (contrato_raiz_id, tramo_id, beneficiario_email) do nothing
      returning id into v_devengo_id;

      if v_devengo_id is null then
        continue; -- una sesión concurrente lo devengó primero (choque de UNIQUE evitado)
      end if;

      v_creados := v_creados + 1;

      if v_nivel = 'manager' then
        v_creado_por := coalesce(
          auth.uid(),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_beneficiario) limit 1),
          (select u.user_id from public.usuarios u where lower(u.email) = lower(v_closer_email) limit 1)
        );

        if v_creado_por is null then
          raise warning 'comisiones_evaluar_contrato: sin creado_por resoluble para la solicitud del manager % (raiz %) -- devengo % queda sin solicitud_id, pendiente de generarla a mano',
            v_beneficiario, v_raiz_id, v_devengo_id;
        else
          v_sp_id := null;
          begin
            insert into public.solicitudes_pago (
              contrato_id, concepto, importe, moneda, origen, beneficiario_email, creado_por
            ) values (
              v_raiz_id,
              'Comisión manager — tramo ' || v_tramo.orden || ' (' || v_tramo.disparador_tipo || ')',
              v_importe, v_moneda, 'comision_automatica', v_beneficiario, v_creado_por
            )
            returning id into v_sp_id;

            update public.comisiones_devengadas
               set solicitud_id = v_sp_id
             where id = v_devengo_id;
          exception when others then
            raise warning 'comisiones_evaluar_contrato: fallo creando la solicitud de pago del manager % (raiz %, tramo %): % -- devengo % queda sin solicitud_id',
              v_beneficiario, v_raiz_id, v_tramo.id, sqlerrm, v_devengo_id;
          end;
        end if;
      end if;
    end loop;
  end loop;

  return v_creados;
end;
$$;

comment on function public.comisiones_evaluar_contrato(uuid) is
  'Motor de comisiones: dado cualquier contrato de una cadena (raíz o hijo), sube a la raíz, agrega precio/cobrado de toda la cadena + unidades (misma fuente que unidades_estado), resuelve closer->equipo->condiciones_comision con ancla temporal de HOY, y devenga (INSERT en comisiones_devengadas, más solicitudes_pago si nivel=manager) cada tramo de condicion_tramos cuyo disparador se cumple y no está ya devengado -- SIN colchón de días desde el último recibi vivo (retirado 14-sep-2026, decisión explícita del owner; hasta entonces exigía ≥5 días, ver 20260914160000). Devuelve cuántas filas nuevas creó. La invocan los triggers de facturas/recibi_aplicaciones -- sin GRANT a authenticated, ver comentario de cabecera de 20260914160000.';

revoke all on function public.comisiones_evaluar_contrato(uuid) from public, anon, authenticated;
