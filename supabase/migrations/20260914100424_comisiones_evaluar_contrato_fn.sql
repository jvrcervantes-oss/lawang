-- COMISIONES: EL MOTOR — 14-sep-2026.
-- Subtarea del mismo encargo que equipos_venta/equipo_miembros (20260914090000),
-- condiciones_comision/condicion_tramos (20260914100000) y comisiones_devengadas
-- (20260914120000). Esa fila queda vacía hasta hoy: aquí nace la función que la
-- rellena, comisiones_evaluar_contrato(p_contrato_id uuid) SECURITY DEFINER.
--
-- INSPECCIONADO ANTES DE ESCRIBIR NADA (list_tables/execute_sql sobre la base
-- real, no sobre el recuerdo del repo): pg_get_functiondef de
-- public.contrato_cobrado(uuid) y public.unidad_parte_cobrada_split(uuid) tal
-- como viven hoy en producción. Lo que importa de cada una:
--   · contrato_cobrado(p_contrato_id): suma recibi_aplicaciones.importe_aplicado
--     aplicado a facturas de ESE contrato_id exacto (join facturas r on
--     recibi_id, facturas f on factura_id, f.contrato_id = p_contrato_id) MÁS
--     la parte sin aplicar de los recibis con r.contrato_id = p_contrato_id
--     directamente. No sube por la cadena — es de UN contrato, no de la raíz.
--   · unidad_parte_cobrada_split(p_unidad): SÍ sube la cadena (coalesce
--     contrato_padre_id) y reparte el cobrado de la raíz + de los hijos
--     (contrato_padre_id = raíz, UN SOLO NIVEL — el repo no modela nietos)
--     prorateado entre las unidades hermanas (mismo unidades.contrato_id que
--     la unidad de referencia). Es la fuente que ya usa unidades_estado
--     (20260911085553) para "facturado"/"pct_cobrado" — por eso esta función
--     lee el cobrado de AQUÍ, no reimplementando la suma de contrato_cobrado
--     sobre cada contrato de la cadena a mano ("una fórmula de dinero en un
--     solo sitio", norma ya escrita en 20260911085533).
--
-- QUÉ AGREGA, Y DE DÓNDE — contratos.precio_total NO tiene precio_suelo ni
-- precio_construccion (verificado con information_schema: esas dos columnas
-- viven en `unidades`, no en `contratos`). Así que:
--   · precio_total  = suma de contratos.precio_total de la raíz + sus hijos
--     directos (contrato_padre_id = raíz).
--   · precio_suelo / precio_construccion = suma de unidades.precio_suelo /
--     precio_construccion de las unidades con unidades.contrato_id = raíz
--     (las "hermanas" que ya usa unidad_parte_cobrada_split).
--   · cobrado_suelo / cobrado_obra = suma de unidad_parte_cobrada_split(u.id)
--     sobre esas mismas unidades — sumar TODAS las hermanas recupera exacto
--     el pozo entero (raíz + hijos sin doble conteo: la función ya reparte al
--     100% entre hermanas, sumarlas todas deshace el prorrateo).
-- LÍMITE CONOCIDO, a propósito: un contrato sin ninguna unidad enlazada
-- (unidades.contrato_id = raíz) da precio_suelo/precio_construccion/cobrado_*
-- en 0 — nunca dispara un tramo pct_cobrado_suelo/obra/total aunque
-- contrato_cobrado(raíz) sea positivo. Es el precio de leer SIEMPRE la misma
-- fuente que unidades_estado (instrucción explícita del encargo) en vez de
-- reimplementar un segundo camino "por si no hay unidad". Contratos con
-- unidad (la inmensa mayoría — ventas de parcela/villa) no lo sufren.
--
-- OBRA_FIRMADA / CONTRATO_FIRMADO — disparadores binarios, no de %:
--   · obra_firmada  = existe algún hijo (contrato_padre_id = raíz) con
--     bloqueado = true. Mismo criterio que usa unidad_parte_cobrada_split
--     para su columna obra_firmada, pero a nivel de CADENA en vez de por
--     unidad (una construcción firmada lo está para todo el contrato, no
--     unidad a unidad).
--   · contrato_firmado = bloqueado de la RAÍZ. "bloqueado = firmado" es la
--     definición que ya fija el estudio (comentario de
--     20260911020137_crm_atribucion_ventas_y_ranking_closers.sql).
--
-- CLOSER → EQUIPO → CONDICIÓN — contrato_closer.contrato_id es SIEMPRE de la
-- RAÍZ (instrucción del encargo: "resolver el closer via contrato_closer del
-- contrato RAIZ"), nunca de un hijo. equipo_miembros no tiene UNIQUE sobre
-- (equipo_id, closer_email) a propósito (comentario de 20260914090000: "qué
-- pasa si el mismo closer aparece dos veces activo es una regla de negocio de
-- OTRA subtarea"): aquí se resuelve con `order by created_at desc limit 1`
-- — determinista, documentado, no bloqueante. Lo mismo para
-- condiciones_comision cuando un closer tiene override (closer_email = el
-- suyo) Y existe el default del equipo (closer_email is null): el override
-- gana (se busca primero, y solo si falta se cae al default — el propio
-- diseño de la tabla, comentario de 20260914100000: "el desempate lo resuelve
-- quien LEA esta tabla").
--
-- COLCHÓN DE 5 DÍAS — el ancla es el recibi MÁS RECIENTE que toca la cadena
-- (misma unión de fuentes que contrato_cobrado: recibi con contrato_id propio
-- de la cadena, o aplicado vía recibi_aplicaciones a una factura de la
-- cadena), no el recibi concreto que cruzó CADA tramo por separado — reconstruir
-- ese detalle exigiría un libro mayor cronológico que hoy no existe. Efecto
-- práctico: cualquier tramo pendiente de una cadena queda bloqueado 5 días
-- tras el ÚLTIMO movimiento de esa cadena, no solo tras el que lo cruzó. Es
-- conservador (protege más de lo mínimo pedido, nunca menos) y es lo único
-- calculable con las tablas que existen — documentado para que la próxima
-- subtarea que quiera afinarlo sepa qué se decidió y por qué.
--
-- disparado_por_snapshot congela recibi_id + recibi_registrado_en del recibi
-- ancla, y los valores de dinero usados (base, %, importe) -- es lo que lee
-- _comisiones_marca_disputa_por_recibi (siguiente migración) para saber a qué
-- filas de comisiones_devengadas afecta la anulación de un recibi concreto.
--
-- TIPO_CAMBIO_APLICADO — se deja NULL siempre: no existe hoy en el esquema
-- ninguna fuente de tipo de cambio en vivo (grep sobre supabase/migrations:
-- cero resultados fuera de este propio encargo) y condiciones_comision no fija
-- una moneda de cobro distinta a la del contrato. La columna existe para
-- cuando esa pieza exista; esta subtarea no la inventa.
--
-- POR QUÉ NO SE GRANT A authenticated: comisiones_evaluar_contrato calcula y
-- ESCRIBE dinero (comisiones_devengadas + solicitudes_pago) saltándose RLS
-- (SECURITY DEFINER). Dejar que cualquier cuenta con sesión la invoque a mano
-- sobre un contrato_id cualquiera generaría devengos/solicitudes reales sin
-- pasar por ningún control de quién lo pidió. Solo la ejecutan los triggers
-- (siguiente migración) y el propio dueño de la función (postgres, con
-- privilegio implícito de owner) -- ver revoke más abajo. Si en el futuro hace
-- falta un botón admin "recalcular este contrato", esa es otra subtarea con su
-- propio GRANT + policy es_admin().
--
-- destructivo-ok: este fichero solo CREATE OR REPLACE FUNCTION y REVOKE sobre
-- una función que se crea dos líneas más arriba en el mismo fichero (nada que
-- perder). Cero DROP, cero DELETE, cero UPDATE sin WHERE.

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

  -- 5) el recibi ancla del colchón: el más reciente que toca la cadena entera,
  --    por las DOS mismas vías que ya usa contrato_cobrado (recibi con
  --    contrato_id propio de la cadena, o aplicado a una factura de la cadena).
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

  if now() - v_ultimo_recibi_en < interval '5 days' then
    return 0; -- colchón: el recibi más reciente de la cadena aún no lleva 5 días
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
  'Motor de comisiones: dado cualquier contrato de una cadena (raíz o hijo), sube a la raíz, agrega precio/cobrado de toda la cadena + unidades (misma fuente que unidades_estado), resuelve closer->equipo->condiciones_comision con ancla temporal de HOY, y devenga (INSERT en comisiones_devengadas, más solicitudes_pago si nivel=manager) cada tramo de condicion_tramos cuyo disparador se cumple, no está ya devengado, y lleva ≥5 días desde el último recibi vivo que toca la cadena. Devuelve cuántas filas nuevas creó. La invocan los triggers de facturas/recibi_aplicaciones (siguiente migración) — sin GRANT a authenticated, ver comentario de cabecera.';

revoke all on function public.comisiones_evaluar_contrato(uuid) from public, anon, authenticated;
;
