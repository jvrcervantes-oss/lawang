-- Auditor de la firma electronica — 15-ago-2026
--
-- POR QUE EXISTE. El 15-ago aparecieron dos contratos firmados por el comprador
-- que llevaban semanas sin cerrarse, y nadie lo sabia:
--   · CC00007 (Juan Ramon Sanchez Garcia) firmado el 1-ago
--   · CR00020 (Jorge Miguel Domingo Berenguer) firmado el 14-ago
-- Los dos son contratos de DOS compradores. El primero firmo, y la cadena se
-- paro sin que el segundo llegara a recibir su enlace:
--   · en CR00020 la segunda compradora (Mayka Nunez Saez) NO TIENE EMAIL en el
--     contrato, asi que `firma-submit` no pudo generarle el enlace. La funcion
--     hace exactamente lo que debe -- lo mete en `avisosCadena` y responde
--     ok:true con avisos -- pero ese aviso viaja al NAVEGADOR DEL COMPRADOR y a
--     `console.error`. El equipo no lo ve en ningun sitio.
--   · CC00007 es anterior al 7-ago, cuando el enlace del siguiente firmante lo
--     generaba un operador a mano. Nadie lo genero.
--
-- El diseno de `firma-submit` ya preveia este estado: marca la firma ANTES de
-- bloquear el contrato a proposito, y su comentario dice que si algo falla
-- «queda una firma registrada sin contrato bloqueado — DETECTABLE Y REPARABLE».
-- La decision es correcta. Lo que faltaba era el detector. Esto es el detector.
--
-- MIENTRAS UNA CADENA ESTA PARADA el contrato sigue EDITABLE, asi que el texto
-- que el primer comprador ya firmo se puede modificar. Ese es el riesgo real, no
-- el PDF que falta.
--
-- CRITERIO: preciso antes que exhaustivo. Un auditor que grita por cosas
-- normales se ignora, y entonces es peor que no tenerlo. Se descartaron a
-- proposito tres «anomalias» que al medirlas eran ruido:
--   · firma `firmado` sin `pdf_path` -> normal en las firmas INTERMEDIAS de una
--     cadena: el PDF solo se sella con la ULTIMA. Se probo a avisar cuando el
--     contrato ya estaba cerrado y aun asi faltaba, y salieron 6 contratos: los
--     SEIS con su PDF en su sitio y solo la firma intermedia sin ruta propia,
--     o sea 100% falsos positivos. Regla retirada el mismo dia que se escribio.
--     `pdf_path` por firma es informativo; la prueba es `contratos.pdf_firmado_path`.
--   · contrato bloqueado sin ninguna firma electronica -> normal: es «Subir
--     firmado» a mano, con el PDF en su sitio. Hoy son 3 y los 3 son legitimos.
--   · enlaces pendientes -> una cadena a medias es un estado sano mientras el
--     enlace siga vivo.

create or replace function public.auditoria_firmas()
returns table (
  severidad  text,     -- 'critica' | 'aviso'
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
  -- 1. CADENA PARADA: alguien firmo, no queda ningun enlace vivo y el contrato
  --    sigue abierto. Nadie va a cerrarlo y nadie lo sabe. Es la que importa.
  select 'critica', 'cadena_parada', c.numero, c.id, c.comprador_nombre,
         'Firmo ' || f.firmadas || ' de los compradores y no queda ningun enlace vivo. '
         || 'El contrato sigue EDITABLE: el texto que ya firmaron se puede cambiar. '
         || 'Genera el enlace del siguiente firmante desde Contratos.',
         f.ultima_firma
    from public.contratos c join f on f.contrato_id = c.id
   where not coalesce(c.bloqueado, false) and f.firmadas > 0 and f.pendientes = 0

  union all
  -- 2. FIRMANTE SIN EMAIL: predice la anterior. Si un adquiriente de la cadena
  --    no tiene email valido, el dia que firme el anterior la cadena se parara
  --    en seco. Solo se mira en contratos que ya estan en juego (con alguna
  --    firma creada), no en cualquier borrador.
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
  -- 3. ENLACE CADUCADO: el comprador ya no puede firmar aunque quiera.
  select 'aviso', 'enlace_caducado', c.numero, c.id, c.comprador_nombre,
         f.caducadas || ' enlace(s) de firma caducados. El comprador no puede firmar: hay que regenerarlo.',
         c.created_at
    from public.contratos c join f on f.contrato_id = c.id
   where f.caducadas > 0 and not coalesce(c.bloqueado, false)

  union all
  -- 4. CERRADO SIN DOCUMENTO: el contrato se dio por firmado y no hay PDF. Es el
  --    escenario probatorio inverso y el peor de todos. Hoy: 0.
  select 'critica', 'cerrado_sin_documento', c.numero, c.id, c.comprador_nombre,
         'El contrato esta bloqueado como firmado pero NO tiene PDF firmado guardado.',
         c.created_at
    from public.contratos c
   where coalesce(c.bloqueado, false) and c.pdf_firmado_path is null

  order by 1, 7 nulls last
$$;

comment on function public.auditoria_firmas() is
  'Anomalias de la firma electronica. Preciso a proposito: solo avisa de estados que nadie va a resolver solo.';

grant execute on function public.auditoria_firmas() to authenticated;

-- Comprobacion despues de aplicar (15-ago-2026 debe dar 2 criticas
-- `cadena_parada`: CC00007 y CR00020, y 1 aviso `firmante_sin_email` en CR00020):
--   select severidad, tipo, contrato, detalle from public.auditoria_firmas();
