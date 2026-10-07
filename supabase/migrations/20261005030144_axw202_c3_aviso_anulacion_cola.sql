-- destructivo-ok: solo AÑADE: una fila de config_instancia (el interruptor, apagado), dos funciones nuevas y una rama nueva en auditoria_firmas() (create or replace que conserva las 6 ramas vivas tal cual). No borra ni cambia datos ni objetos existentes.
-- (La migración se aplicó el 5-oct con la versión 20261005030144, la que registra Supabase; el nombre del fichero es esa versión.)
-- ============================================================================
-- AXW-202 C3 — el aviso de anulación de firma puede ir por la cola de correos (5-oct-2026)
-- ----------------------------------------------------------------------------
-- Encargo: encargos/20261002_estudio_cola_de_correos.md → C3 y «Plan revisado», puntos 3, 5, 15 y 16.
--
-- Quién lo manda hoy: el NAVEGADOR (contracts/app.html → avisaAnulacion) compone el texto y lo pasa a la edge
-- send-contract-email con via:'aviso_anulacion'. Esa edge es la que ahora, SI el interruptor está en «cola», pide a la base
-- que anote «hay que mandar el aviso de anulación de ESTA firma» (correo_aviso_anulacion_encolar) y se olvida del texto del
-- navegador: lo compone la edge de la cola con la plantilla `aviso_anulacion` (correo_plantillas), con el destinatario y el
-- motivo leídos del dueño (contrato_firmas.firmante_email / anulado_justificacion). Sin tocar app.html.
--
-- EL DATO TIENE UN DUEÑO: destinatario y motivo → contrato_firmas (la cola no los copia). La firma que ancla el aviso la elige
-- ESTA función, no el navegador: la última anulación «editar» de ese email en ese contrato, de los últimos 30 min
-- (el navegador avisa justo después de anular). Elegir una firma de una anulación anterior —que ya tiene fila `ok`— haría que
-- correo_encolar contestara «nuevo:false» y el aviso nuevo se perdiera sin error.
--
-- INTERRUPTOR: config_instancia.correo_cola_aviso_anulacion. Nace 'directo'. Lo lee correo_aviso_anulacion_encolar UNA vez por
-- aviso, al encolar; 'directo', ausente o cualquier otro valor → devuelve {modo:'directo'} y la edge manda el correo de siempre
-- (el texto del navegador). Si encolar falla por cualquier causa, también {modo:'directo'}: el aviso sale por la rama antigua.
--   Encender:  update public.config_instancia set valor = '"cola"'::jsonb, actualizado_en = now() where clave = 'correo_cola_aviso_anulacion';
--   Apagar:    ... valor = '"directo"'::jsonb ...   (efecto en el siguiente aviso, sin desplegar nada)
--
-- AVISO FUERA DEL SMTP (punto 16): un aviso en `error` (o pendiente/enviando más de 15 min) sale en el carril «Firmas que
-- necesitan atención» de /intranet/ (rama nueva `aviso_anulacion_sin_enviar` de auditoria_firmas()). Antes el agente veía un
-- toast «falló con: x» en el momento; en modo cola ese fallo llega después y no tiene pantalla donde verse.
--
-- LLAMADORES CON NOMBRE (seguridad_2026 §1.ter — lo nuevo nace cerrado):
--   correo_aviso_anulacion_encolar  ← edge send-contract-email (service_role). Sin grants a anon/authenticated.
--   correo_cola_aviso_sin_enviar    ← auditoria_firmas() (authenticated, gate es_agente() dentro).
-- Repo público: ningún email ni uuid literal.
-- ============================================================================

insert into public.config_instancia (clave, valor, descripcion)
values ('correo_cola_aviso_anulacion', '"directo"'::jsonb,
        'AXW-202 C3. «cola»: el aviso de anulación de firma lo manda la cola de correos (plantilla aviso_anulacion, con reintentos). «directo» o ausente: sale en la propia petición de send-contract-email con el texto del navegador, como antes. Se lee una vez por aviso. No editable desde Ajustes.')
on conflict (clave) do nothing;

-- ── encolar el aviso de UNA firma anulada (la elige la base, no el navegador) ───────────────────────────────
-- Devuelve {modo:'directo'[, motivo]} o {modo:'cola', id, estado, nuevo, reabierto}. Nunca lanza: ante cualquier fallo, 'directo'.
create or replace function public.correo_aviso_anulacion_encolar(p_contrato uuid, p_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_sw    text;
  v_firma uuid;
  r       jsonb;
begin
  select g.valor #>> '{}' into v_sw from public.config_instancia g where g.clave = 'correo_cola_aviso_anulacion';
  if v_sw is distinct from 'cola' then
    return jsonb_build_object('modo', 'directo');
  end if;

  select f.id into v_firma
    from public.contrato_firmas f
   where f.contrato_id = p_contrato
     and lower(btrim(f.firmante_email)) = lower(btrim(coalesce(p_email, '')))
     and f.anulado_en is not null and f.anulado_motivo = 'editar'
     and f.anulado_en > now() - interval '30 minutes'
   order by f.anulado_en desc, (f.firmado_en is not null) desc, f.id
   limit 1;
  if v_firma is null then
    return jsonb_build_object('modo', 'directo', 'motivo', 'sin_anulacion_reciente');
  end if;

  r := public.correo_encolar('aviso_anulacion', p_firma := v_firma);
  return jsonb_build_object('modo', 'cola') || r;
exception when others then
  raise warning 'correo_aviso_anulacion_encolar: no se pudo encolar (%): sale directo', sqlstate;
  return jsonb_build_object('modo', 'directo', 'motivo', 'error');
end $$;

revoke execute on function public.correo_aviso_anulacion_encolar(uuid, text) from public, anon, authenticated;
grant  execute on function public.correo_aviso_anulacion_encolar(uuid, text) to service_role;

-- ── ¿desde cuándo lleva ESTA firma sin que salga su aviso de anulación? ─────────────────────────────────────
-- Misma forma que correo_cola_firma_sin_enviar (C2): DEFINER mínima, solo a un agente, solo una fecha; el id que le pasa
-- auditoria_firmas() ya es una firma que el llamante ve por RLS. `error` solo cuenta 7 días (el aviso tiene tope de 72 h:
-- una alarma sin fecha se queda en rojo para siempre y se acaba ignorando).
create or replace function public.correo_cola_aviso_sin_enviar(p_firma uuid)
returns timestamptz
language sql stable security definer set search_path = '' as $$
  select q.encolado_en
    from public.correos_cola q
   where public.es_agente()
     and q.firma_id = p_firma and q.clave = 'aviso_anulacion'
     and ((q.estado = 'error' and q.encolado_en > now() - interval '7 days')
          or (q.estado in ('pendiente', 'enviando') and q.encolado_en < now() - interval '15 minutes'))
   order by q.encolado_en desc
   limit 1
$$;
revoke execute on function public.correo_cola_aviso_sin_enviar(uuid) from public, anon;
grant  execute on function public.correo_cola_aviso_sin_enviar(uuid) to authenticated, service_role;

-- ── auditoria_firmas(): las seis ramas de antes, tal cual, + la séptima ──────────────────────────────────────
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
    union all
    -- AXW-202 C3: el aviso de anulación de una firma no ha salido (cola en error o atascada). El enlace antiguo ya no
    -- funciona y el firmante no sabe por qué: hay que avisarle por otra vía.
    select 'aviso', 'aviso_anulacion_sin_enviar', c.numero, c.id, c.comprador_nombre,
           'El aviso de anulacion para ' || coalesce(nullif(btrim(cf.firmante_nombre), ''), 'este firmante')
           || ' NO ha salido. La cola de correos lo reintenta; si sigue aqui, avisale por otra via '
           || '(telefono, WhatsApp): su enlace antiguo ya no funciona y no sabe por que.',
           s.desde
      from public.contrato_firmas cf
      join public.contratos c on c.id = cf.contrato_id
      cross join lateral (select public.correo_cola_aviso_sin_enviar(cf.id) as desde) s
     where cf.anulado_en is not null and s.desde is not null
  ) t
  where public.es_agente()
  order by 1, 7 nulls last
$function$;
