-- destructivo-ok: `create or replace function`, no borra filas ni objetos.
-- ════════════════════════════════════════════════════════════════════════════
-- auditoria_firmas() NO COMPROBABA PERMISO — 24-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Hallazgo de Desarrollo (auditoría pedida por el owner): a diferencia de sus
-- hermanas `contratos_equipo()`, `facturas_equipo()`, `contrato_firmas_equipo()`,
-- `facturas_pendiente_equipo()` y `uso_almacenamiento()` (todas con
-- `where public.es_agente()` o un `raise exception` si no lo es),
-- `auditoria_firmas()` no llevaba NINGÚN gate. Es `security definer`, así que
-- corre saltándose la RLS de `contratos`/`contrato_firmas` por diseño — sin el
-- gate, cualquier sesión `authenticated` podía llamarla directamente
-- (`POST /rest/v1/rpc/auditoria_firmas`), incluida la de un COMPRADOR logueado
-- en `/portal/` (que sí es `authenticated`, solo que con
-- `app_metadata.portal=true` en vez de agente) — y recibir número de contrato,
-- nombre del comprador y estado de firma de TODOS los contratos del estudio,
-- de cualquier cliente. Confirmado con `get_advisors(security)`:
-- `has_function_privilege` daba `true` para `authenticated` sin más filtro.
--
-- Es `language sql` (no plpgsql), así que no hay `if/raise` de por medio: se
-- envuelve la consulta entera y se filtra el resultado por `es_agente()` —
-- una sesión que no lo es recibe CERO filas, igual que ya hacen las funciones
-- hermanas. No se toca ni una línea de las cinco reglas de auditoría.

create or replace function public.auditoria_firmas()
returns table(severidad text, tipo text, contrato text, contrato_id uuid, comprador text, detalle text, desde timestamptz)
language sql
security definer
set search_path = ''
as $$
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
    -- REGLA 5 (17-ago-2026): una firma que se quedo reclamada y nunca se cerro.
    -- `firma-submit` pasa el token a 'procesando' antes de trabajar; si la funcion
    -- muere ahi (timeout, render caido, reinicio), su catch no corre y la fila se
    -- queda asi para siempre. El comprador no tiene salida: cada reintento recibe
    -- 409 y la pagina le dice «este enlace ya no esta disponible».
    -- 15 minutos de umbral: el ciclo normal tarda segundos.
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
$$;

revoke all on function public.auditoria_firmas() from public, anon;
grant execute on function public.auditoria_firmas() to authenticated;
