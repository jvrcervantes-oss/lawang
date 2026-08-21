create or replace function public.auditoria_firmas()
returns table (
  severidad text, tipo text, contrato text, contrato_id uuid,
  comprador text, detalle text, desde timestamptz
)
language sql
security definer
set search_path = ''
as $$
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
  order by 1, 7 nulls last
$$;

revoke all on function public.auditoria_firmas() from public;
revoke all on function public.auditoria_firmas() from anon;
grant execute on function public.auditoria_firmas() to authenticated;;
