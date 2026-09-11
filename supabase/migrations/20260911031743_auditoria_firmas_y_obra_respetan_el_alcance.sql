-- Las dos hermanas del mismo fallo — 11-sep-2026
--
-- Barrido tras corregir las *_equipo(): se buscaron TODAS las funciones
-- SECURITY DEFINER cuyo único gate fuera `es_agente()`, sin mirar de quién ni de
-- qué proyecto es la fila. Aparecieron tres. `uso_almacenamiento()` devuelve
-- métricas agregadas del almacenamiento, sin datos de nadie: se deja. Las otras
-- dos son éstas. Cerrar una salida y dejar las hermanas abiertas es cómo vuelve
-- el mismo incidente con otro nombre.

-- 1) auditoria_firmas() — el carril de "firmas que necesitan atención" de la
--    portada de /intranet/, que ve TODO el equipo. Es DEFINER con `where
--    es_agente()` al final, así que a cualquier agente le listaba el número de
--    contrato y el NOMBRE DEL COMPRADOR de los 223 contratos del estudio.
--    Ya se tocó una vez (24-ago) para que no la pudiera llamar un comprador
--    logueado: se le puso el gate `es_agente()`, que era el arreglo correcto
--    para ESE agujero y no cubre éste.
--    A INVOKER, mismo criterio que las *_equipo(): lee `contratos` y
--    `contrato_firmas`, las dos con RLS ya alineada, así que cada uno ve las
--    anomalías de sus contratos y el admin seguirá viéndolas todas. El gate
--    `es_agente()` del final se queda tal cual.
--    Verificado: admin 12 anomalías (sin cambio), Andrea 0.
create or replace function public.auditoria_firmas()
returns table(severidad text, tipo text, contrato text, contrato_id uuid,
              comprador text, detalle text, desde timestamptz)
language sql
stable security invoker
set search_path to public
as $function$
  select * from (
    with f as (
      select cf.contrato_id,
             count(*) filter (where cf.estado = 'firmado')   as firmadas,
             count(*) filter (where cf.estado = 'pendiente') as pendientes,
             count(*) filter (where cf.estado = 'pendiente' and cf.expira_en < now()) as caducadas,
             max(cf.firmado_en) filter (where cf.estado = 'firmado') as ultima_firma
        from public.contrato_firmas cf
       group by cf.contrato_id
    )
    select 'critica', 'cadena_parada', c.numero, c.id, c.comprador_nombre,
           'Firmo ' || f.firmadas || ' de los compradores y no queda ningun enlace vivo. '
           || 'El contrato sigue EDITABLE: el texto que ya firmaron se puede cambiar. '
           || 'Genera el enlace del siguiente firmante desde Contratos.',
           f.ultima_firma
      from public.contratos c join f on f.contrato_id = c.id
     where not coalesce(c.bloqueado, false) and f.firmadas > 0 and f.pendientes = 0
    union all
    select 'aviso', 'firmante_sin_email', c.numero, c.id, c.comprador_nombre,
           'El adquiriente ' || (x.i + 1) || ' (' || coalesce(nullif(btrim(x.e->>'nombre'),''), 'sin nombre')
           || ') no tiene email en el contrato. Cuando firme el anterior, la cadena se parara '
           || 'porque no se le puede mandar su enlace.',
           c.created_at
      from public.contratos c
      join lateral (
        select e, (ord - 1) as i
          from jsonb_array_elements(
                 case when jsonb_typeof(c.datos->'compradores') = 'array'
                      then c.datos->'compradores' else '[]'::jsonb end) with ordinality t(e, ord)
      ) x on true
     where exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id)
       and not coalesce(c.bloqueado, false)
       and nullif(btrim(coalesce(x.e->>'nombre','')), '') is not null
       and coalesce(btrim(x.e->>'email'), '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    union all
    select 'aviso', 'enlace_caducado', c.numero, c.id, c.comprador_nombre,
           f.caducadas || ' enlace(s) de firma caducados. El comprador no puede firmar: hay que regenerarlo.',
           c.created_at
      from public.contratos c join f on f.contrato_id = c.id
     where f.caducadas > 0 and not coalesce(c.bloqueado, false)
    union all
    select 'critica', 'cerrado_sin_documento', c.numero, c.id, c.comprador_nombre,
           'El contrato esta bloqueado como firmado pero NO tiene PDF firmado guardado.',
           c.created_at
      from public.contratos c
     where coalesce(c.bloqueado, false) and c.pdf_firmado_path is null
    union all
    select 'critica', 'firma_atascada', c.numero, c.id, c.comprador_nombre,
           'La firma de ' || coalesce(nullif(btrim(cf.firmante_nombre), ''), 'este firmante')
           || ' lleva ' || (extract(epoch from (now() - cf.creado_en)) / 3600)::int
           || ' h reclamada y sin cerrarse. El comprador NO puede reintentar: le sale '
           || '«este enlace ya no esta disponible». Si ya existe su PDF firmado, la firma se '
           || 'completo y hay que marcarla; si no, hay que devolverla a pendiente.',
           cf.creado_en
      from public.contrato_firmas cf join public.contratos c on c.id = cf.contrato_id
     where cf.estado = 'procesando' and cf.creado_en < now() - interval '15 minutes'
  ) t
  where public.es_agente()
  order by 1, 7 nulls last
$function$;

-- 2) obra_actualizar() — ESCRITURA, no lectura. Comprobaba `es_agente() and
--    puede('obra')` y actualizaba la unidad por id, sin mirar de qué proyecto es.
--    Es decir: la herramienta sí, el proyecto no. Hoy la tienen solo cuatro
--    fichas (dos admin, un project_manager y el super_admin), así que no hay
--    exposición real — pero el día que se le dé 'obra' a un agente de un
--    proyecto, podría mover la fase de obra de cualquier otro. Se cierra ahora,
--    que es barato, y no cuando ese día llegue.
--    `puede_proyecto()` es la misma función que ya usan las policies de
--    contratos: admin pasa siempre, y el agente pasa si la unidad es de un
--    proyecto suyo.
create or replace function public.obra_actualizar(p_unidad uuid, p_fase text, p_fecha date)
returns void
language plpgsql
security definer
set search_path to public
as $function$
declare v_proyecto text;
begin
  if not (es_agente() and puede('obra')) then
    raise exception 'sin permiso para obra' using errcode = '42501';
  end if;
  select u.proyecto into v_proyecto from unidades u where u.id = p_unidad;
  if not found then
    raise exception 'unidad inexistente';
  end if;
  if not puede_proyecto(v_proyecto) then
    raise exception 'esa unidad es de un proyecto que no tienes asignado' using errcode = '42501';
  end if;
  update unidades
     set obra_fase = nullif(btrim(coalesce(p_fase, '')), ''),
         obra_fecha_entrega = p_fecha,
         obra_actualizado = now()
   where id = p_unidad;
end
$function$;
