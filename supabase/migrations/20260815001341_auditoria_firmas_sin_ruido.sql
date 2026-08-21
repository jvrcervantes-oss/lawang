create or replace function public.auditoria_firmas()
returns table (
  severidad  text,
  tipo       text,
  contrato   text,
  contrato_id uuid,
  comprador  text,
  detalle    text,
  desde      timestamptz
)
language sql
stable
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
  order by 1, 7 nulls last
$$;;
