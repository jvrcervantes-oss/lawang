-- destructivo-ok: solo AÑADE: una fila de config_instancia (el interruptor, apagado), una función de lectura y una rama nueva en auditoria_firmas() (create or replace que conserva las 5 ramas vivas tal cual). No borra ni cambia datos ni objetos existentes.
-- ============================================================================
-- AXW-202 C2 — firma-submit encola el correo del enlace de la cadena (5-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261002_estudio_cola_de_correos.md → C2 y «Plan revisado», puntos 15 y 16.
--
-- 1) INTERRUPTOR por llamante: config_instancia.correo_cola_firma_submit.
--      'directo' (o ausente, o ilegible) → firma-submit manda el correo en su petición, como la v63.
--      'cola'                            → firma-submit solo anota «hay que mandar enlace_firma_cadena de ESTA firma».
--    Lo lee firma-submit UNA vez por firma, al encolar. Solo escribe service_role/postgres (nadie desde la app).
--    Nace en 'directo'. El owner lo enciende con:
--      update public.config_instancia set valor = '"cola"'::jsonb, actualizado_en = now() where clave = 'correo_cola_firma_submit';
--    y lo apaga con 'directo'. El cron `correos-cola-envio` es una RED: encolar ya despierta a la edge por pg_net.
--
-- 2) AVISO FUERA DEL SMTP (punto 16): un enlace de firma que se generó y cuyo correo no ha salido es justo la
--    avería que auditoria_firmas() no veía (la firma pendiente existe, así que no hay «cadena parada»). Rama nueva
--    `enlace_sin_enviar` (crítica): firma pendiente cuya fila de la cola está en `error`, o sigue pendiente/enviando
--    pasados 15 min (el reintento normal tarda 1, 2, 4, 8 min). Sale en el carril «Firmas que necesitan atención» de
--    /intranet/ — un canal que no es el SMTP que falló.
--    auditoria_firmas() sigue siendo INVOKER (11-sep: cada agente ve solo lo de su alcance por la RLS de contratos y
--    contrato_firmas). correos_cola no tiene grants para authenticated, así que la lectura va por una función DEFINER
--    mínima que solo contesta «¿desde cuándo está sin enviar ESTA firma?» y solo a un agente: el id que le pasa
--    auditoria_firmas() ya es una firma que el llamante ve por RLS, y no devuelve ni destinatario ni texto.
--    LLAMADOR CON NOMBRE: correo_cola_firma_sin_enviar ← auditoria_firmas() (authenticated, gate es_agente() dentro).
-- ============================================================================

insert into public.config_instancia (clave, valor, descripcion)
values ('correo_cola_firma_submit', '"directo"'::jsonb,
        'AXW-202 C2. «cola»: firma-submit encola el correo del enlace de la cadena (lo manda la cola de correos, con reintentos). «directo» o ausente: lo manda en su propia petición, como antes. Se lee una vez por firma. No editable desde Ajustes.')
on conflict (clave) do nothing;

create or replace function public.correo_cola_firma_sin_enviar(p_firma uuid)
returns timestamptz
language sql stable security definer set search_path = '' as $$
  select q.encolado_en
    from public.correos_cola q
   where public.es_agente()
     and q.firma_id = p_firma and q.clave = 'enlace_firma_cadena'
     and (q.estado = 'error'
          or (q.estado in ('pendiente', 'enviando') and q.encolado_en < now() - interval '15 minutes'))
   order by q.encolado_en desc
   limit 1
$$;
revoke execute on function public.correo_cola_firma_sin_enviar(uuid) from public, anon;
grant  execute on function public.correo_cola_firma_sin_enviar(uuid) to authenticated, service_role;

create or replace function public.auditoria_firmas()
returns table(severidad text, tipo text, contrato text, contrato_id uuid, comprador text, detalle text, desde timestamptz)
language sql stable security invoker
set search_path to 'public'
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
    union all
    -- AXW-202 C2: el enlace existe pero el correo con el enlace no ha salido (cola en error o atascada)
    select 'critica', 'enlace_sin_enviar', c.numero, c.id, c.comprador_nombre,
           'El enlace de firma de ' || coalesce(nullif(btrim(cf.firmante_nombre), ''), 'este firmante')
           || ' esta generado pero el correo que lo lleva NO ha salido. La cola de correos lo reintenta; '
           || 'si sigue aqui, algo falla en el envio. Para mandarlo ya: «Enviar a firma» → Enviar por email '
           || '(genera un enlace nuevo).',
           s.desde
      from public.contrato_firmas cf
      join public.contratos c on c.id = cf.contrato_id
      cross join lateral (select public.correo_cola_firma_sin_enviar(cf.id) as desde) s
     where cf.estado = 'pendiente' and cf.anulado_en is null and s.desde is not null
       and not coalesce(c.bloqueado, false)
  ) t
  where public.es_agente()
  order by 1, 7 nulls last
$function$;
