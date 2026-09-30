-- destructivo-ok: no destruye nada. «delete» aparece solo en la cláusula de un trigger que IMPIDE borrar sociedades; no hay drop, truncate ni update/delete masivo.
-- AJUSTES DEL ERP · S2 + S3: sociedades emisoras editables con la identidad fiscal BLOQUEADA si ya tiene documentos. 30-sep-2026.
-- Encargo: encargos/20260930_erp_ajustes_pantalla.md (S2, S3 y la «Revisión previa» de Legal, Seguridad y Datos). Decisión del owner
-- (30-sep): «identidad fiscal BLOQUEADA si la sociedad ya tiene documentos; un cambio real lo hace el estudio».
-- Solo Lawang: la pareja del maestro (erp/migraciones/) se hace después; su `sociedad_guarda` difiere (prefijo_serie, series fiscales).
--
-- POR QUÉ. Hasta hoy `sociedad_guarda` dejaba a un super admin reescribir razón social, NPWP o domicilio de una sociedad que ya
-- había emitido documentos: las 412+ facturas anteriores al 17-sep y TODOS los contratos se reimprimen con los datos VIVOS de
-- `sociedades` (las facturas nuevas congelan el emisor en `datos->emisor`). Un clic en Ajustes reescribiría lo ya firmado.
--
-- El dato tiene un dueño: la fila de `sociedades` es de la sociedad (una por clave). Cada documento la lee (contratos y facturas
-- antiguas: referencia viva) o la copia congelada (facturas nuevas: `datos->emisor`). Este cambio no toca ninguna copia.
--
-- Qué hay antes (verificado en Lawang el 30-sep con MCP): `sociedades` con 3 filas (tepi_sungai, san_dal_woods, sandal_woods_ltd);
-- authenticated solo tiene SELECT (la escritura va por `sociedad_guarda`, LAW-336 pieza 4); triggers `trg_sociedades_autoria`
-- (la clave no se mueve: ya lanza) y `trg_sociedades_log`. Ninguna migración anterior se edita.
--
-- Qué hace esta migración (todo aditivo, ninguna fila de sociedades/facturas/contratos se toca):
--   1. `_sociedad_docs_filas` / `_sociedad_docs`: UNA sola definición de «tiene documentos» y «abiertos», que usan el trigger y el
--      lector. Dueño postgres y DEFINER a propósito: un lector con RLS contaría 0 facturas y pintaría editable lo que el servidor
--      bloquea. Fuentes = TODAS las FK a `sociedades` (facturas, gastos, comision_admin_fees, socios, solicitudes_pago_retencion)
--      + `comision_admin_lineas` (sin FK) + contratos (JSON, sin FK: `datos_fields->>'sociedad_firmante'`, espejo por trigger que
--      se verificó idéntico a `datos->'fields'` en las 282 filas). Los contratos SIN sociedad elegida (14 hoy) se atribuyen a la
--      que imprimen: SOCIEDAD_DEFAULT de contracts/assets/entities.js (ppjb_reserva → san_dal_woods, el resto → tepi_sungai);
--      esa regla está duplicada aquí y la fija contracts/sociedad_docs.test.js.
--   2. `trg_sociedades_identidad` (BEFORE UPDATE OR DELETE): con documentos, cambiar razón, identificador fiscal y su etiqueta, NIB,
--      domicilio, representante, marca o es_indonesia se RECHAZA; desactivar con documentos abiertos, también; borrar, siempre.
--      Comparación NORMALIZADA (`coalesce(nullif(btrim(x),''),'')`): sandal_woods_ltd guarda nib '' y la pantalla lo manda como null,
--      y un guardado sin cambios no puede contar como cambio de identidad.
--      VÍA DEL ESTUDIO: el trigger deja pasar SOLO si no hay `request.jwt.claims` (SQL directo o MCP, es decir, el propietario de la
--      base). Todo lo que llega por PostgREST lleva claims —una RPC DEFINER o service_role incluidas— y no pasa. La clave
--      sigue siendo inmutable para TODOS (trg_sociedades_autoria, sin excepción).
--   3. `sociedad_guarda` (misma firma, mismos permisos): pasa a «cambia solo lo que viene» (la pantalla vieja manda la fila entera,
--      así que su comportamiento no cambia) y valida en servidor: longitudes, tinta/folio/alto como colores y medidas, y `logo`
--      solo NULL, el valor que ya tiene, la ruta heredada /contracts/assets/brand/*.(png|jpg|webp) o la URL PÚBLICA del bucket
--      `sociedades` para ESA clave (sin SVG: acaba en un <img src> de cada documento). Hasta hoy aceptaba cualquier texto.
--   4. Registro: `sociedades_ajustes_log` (AFTER INSERT OR UPDATE) escribe en `ajustes_log` (S1) solo las columnas que cambian,
--      antes y después; `sociedades_log` sigue con su historia. Función propia: la de S1 lee `new.valor`, que `sociedades` no tiene.
--   5. `sociedades_ajustes_datos()`: lector para administración con `documentos` por sociedad. `instancia_marca()`: el nombre del ERP
--      para todo el equipo (título del navegador y menú). Ninguna columna nueva en `sociedades` (el GRANT de tabla la haría
--      legible por un comprador).
--   6. Bucket público `sociedades` (png, jpeg, webp, 512 KB) SIN policies de escritura: solo lo escribe la edge `ficheros` con
--      service_role. Público a propósito: el renderizador de PDF carga el HTML desde fuera y una URL firmada guardada caduca
--      (AXW-66); el logo ya va impreso en cada documento que el comprador tiene en la mano.
--
-- Lo que NO hace: el banco. `cuentas_bancarias` no tiene columna ni FK hacia `sociedades` (se ligan por plantilla o proyecto), así
-- que «el banco de una sociedad» no existe como dato: queda fuera de esta ronda (bitácora del encargo).
-- Lo que NO aplica todavía: recortar las columnas de `sociedades` legibles por un comprador (contracts/sql/propuesta_sociedades_columnas_comprador.sql).

-- ── 1. «Tiene documentos» ──────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._sociedad_docs_filas(p_clave text default null)
returns table (clave text, tabla text, total integer, abiertos integer)
language sql stable security definer set search_path to ''
as $$
  select x.clave, x.tabla, x.total, x.abiertos from (
    select f.sociedad as clave, 'facturas'::text as tabla, count(*)::int as total,
           (count(*) filter (where not coalesce(f.anulada, false) and not coalesce(f.enviada, false)))::int as abiertos
      from public.facturas f group by f.sociedad
    union all
    select c.soc, 'contratos', count(*)::int, (count(*) filter (where c.pdf_firmado_path is null and c.liberado_en is null))::int
      from (select coalesce(nullif(btrim(coalesce(k.datos_fields, k.datos -> 'fields') ->> 'sociedad_firmante'), ''),
                            case k.tipo when 'ppjb_reserva' then 'san_dal_woods' else 'tepi_sungai' end) as soc,
                   k.pdf_firmado_path, k.liberado_en
              from public.contratos k) c
     group by c.soc
    union all
    select g.sociedad, 'gastos', count(*)::int, (count(*) filter (where g.estado = 'pendiente'))::int
      from public.gastos g group by g.sociedad
    union all
    -- una tarifa de comisión de administración vigente es una obligación viva con esa sociedad: todas cuentan como abiertas
    select e.sociedad, 'comision_admin_fees', count(*)::int, count(*)::int
      from public.comision_admin_fees e group by e.sociedad
    union all
    select l.sociedad, 'comision_admin_lineas', count(*)::int,
           (count(*) filter (where not coalesce(l.anulada, false) and l.estado = 'pendiente'))::int
      from public.comision_admin_lineas l where l.sociedad is not null group by l.sociedad
    union all
    -- el bukti potong (retención de PPh) es un documento fiscal emitido a nombre de la entidad que retiene
    select r.pemotong_entidad, 'solicitudes_pago_retencion', count(*)::int,
           (count(*) filter (where r.estado <> 'batal' and not coalesce(r.sustituida, false) and r.djp_ingresado_el is null))::int
      from public.solicitudes_pago_retencion r where r.pemotong_entidad is not null group by r.pemotong_entidad
    union all
    select s.sociedad, 'socios', count(*)::int, (count(*) filter (where s.activo))::int
      from public.socios s group by s.sociedad
  ) x
  where p_clave is null or x.clave = p_clave
$$;
revoke all on function public._sociedad_docs_filas(text) from public, anon, authenticated, service_role;

create or replace function public._sociedad_docs(p_clave text)
returns jsonb
language sql stable security definer set search_path to ''
as $$
  select jsonb_build_object(
    'total',    coalesce(sum(d.total), 0)::int,
    'abiertos', coalesce(sum(d.abiertos), 0)::int,
    'detalle',  coalesce(jsonb_object_agg(d.tabla, jsonb_build_object('total', d.total, 'abiertos', d.abiertos)), '{}'::jsonb))
    from public._sociedad_docs_filas(p_clave) d
$$;
revoke all on function public._sociedad_docs(text) from public, anon, authenticated, service_role;

-- «187 facturas, 268 contratos» — para el mensaje de error. `solo_abiertos` mira la columna `abiertos`.
create or replace function public._sociedad_docs_texto(p_detalle jsonb, p_solo_abiertos boolean)
returns text
language sql immutable set search_path to ''
as $$
  select coalesce(string_agg((case when p_solo_abiertos then e.value ->> 'abiertos' else e.value ->> 'total' end) || ' ' || e.key,
                             ', ' order by e.key), '')
    from jsonb_each(p_detalle) e
   where (case when p_solo_abiertos then e.value ->> 'abiertos' else e.value ->> 'total' end)::int > 0
$$;
revoke all on function public._sociedad_docs_texto(jsonb, boolean) from public, anon, authenticated, service_role;

-- ── 2. El candado en la TABLA, no solo en la RPC ──────────────────────────────────────────────────────────────────
create or replace function public._trg_sociedades_proteccion()
returns trigger
language plpgsql security definer set search_path to ''
as $$
declare
  v_claims text := nullif(current_setting('request.jwt.claims', true), '');
  v_docs   jsonb;
  v_cambia boolean;
begin
  -- Vía del estudio: SQL directo o MCP (sin claims) = el propietario de la base, que puede hacer un cambio real a propósito.
  if v_claims is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    raise exception 'La sociedad «%» no se borra: se desactiva. Sus documentos emitidos siguen apuntando a ella.', old.clave
      using errcode = 'P0001', hint = 'sociedad_no_se_borra';
  end if;

  v_cambia :=
       coalesce(nullif(btrim(old.razon), ''), '')      is distinct from coalesce(nullif(btrim(new.razon), ''), '')
    or coalesce(nullif(btrim(old.marca), ''), '')      is distinct from coalesce(nullif(btrim(new.marca), ''), '')
    or coalesce(nullif(btrim(old.npwp), ''), '')       is distinct from coalesce(nullif(btrim(new.npwp), ''), '')
    or coalesce(nullif(btrim(old.npwp_label), ''), '') is distinct from coalesce(nullif(btrim(new.npwp_label), ''), '')
    or coalesce(nullif(btrim(old.nib), ''), '')        is distinct from coalesce(nullif(btrim(new.nib), ''), '')
    or coalesce(nullif(btrim(old.domicilio), ''), '')  is distinct from coalesce(nullif(btrim(new.domicilio), ''), '')
    or coalesce(nullif(btrim(old.rep), ''), '')        is distinct from coalesce(nullif(btrim(new.rep), ''), '')
    or old.es_indonesia is distinct from new.es_indonesia;

  if v_cambia then
    v_docs := public._sociedad_docs(old.clave);
    if (v_docs ->> 'total')::int > 0 then
      raise exception 'La identidad fiscal de «%» no se puede cambiar: ya tiene documentos (%). Para cambiarla, pídeselo al estudio.',
        old.clave, public._sociedad_docs_texto(v_docs -> 'detalle', false)
        using errcode = 'P0001', hint = 'identidad_bloqueada';
    end if;
  end if;

  if old.activa and not new.activa then
    v_docs := public._sociedad_docs(old.clave);
    if (v_docs ->> 'abiertos')::int > 0 then
      raise exception 'No se puede desactivar «%»: tiene documentos abiertos o en curso (%). Ciérralos o anúlalos antes.',
        old.clave, public._sociedad_docs_texto(v_docs -> 'detalle', true)
        using errcode = 'P0001', hint = 'desactivar_bloqueado';
    end if;
  end if;
  return new;
end $$;
revoke all on function public._trg_sociedades_proteccion() from public, anon, authenticated, service_role;
-- Nombre elegido para que corra entre trg_sociedades_autoria (clave) y trg_sociedades_log (rastro), en orden alfabético.
create or replace trigger trg_sociedades_identidad before update or delete on public.sociedades
  for each row execute function public._trg_sociedades_proteccion();

-- ── 3. Registro de cambios de sociedades en ajustes_log (S1) ─────────────────────────────────────────────────────────
create or replace function public._trg_ajustes_log_sociedades()
returns trigger
language plpgsql security definer set search_path to ''
as $$
declare
  v_ignora constant text[] := array['actualizado_en', 'actualizado_por', 'creado_en', 'creado_por'];
  v_old jsonb;
  v_new jsonb := to_jsonb(new) - v_ignora;
  v_a   jsonb;
  v_d   jsonb;
begin
  if tg_op = 'INSERT' then
    v_d := v_new;
  else
    v_old := to_jsonb(old) - v_ignora;
    select jsonb_object_agg(k, v_old -> k), jsonb_object_agg(k, v_new -> k)
      into v_a, v_d
      from jsonb_object_keys(v_new) k
     where (v_old -> k) is distinct from (v_new -> k);
    if v_d is null then return null; end if;   -- solo cambiaron la autoría o la hora
  end if;
  insert into public.ajustes_log (tabla, clave, antes, despues, motivo, quien)
  values ('sociedades', new.clave, v_a, v_d,
          nullif(left(coalesce(current_setting('axw.ajustes_motivo', true), ''), 500), ''),
          coalesce(public._quien_actua(),
                   'sistema:' || coalesce(nullif((nullif(current_setting('request.jwt.claims', true), '')::jsonb) ->> 'role', ''), 'sql')));
  return null;
end $$;
revoke all on function public._trg_ajustes_log_sociedades() from public, anon, authenticated, service_role;
create or replace trigger sociedades_ajustes_log after insert or update on public.sociedades
  for each row execute function public._trg_ajustes_log_sociedades();

-- ── 4. Escribir: sociedad_guarda, ahora «cambia solo lo que viene» y validada ─────────────────────────────────────────
-- Misma firma y mismos permisos que la de LAW-336 (20260926190000): la pantalla vieja sigue funcionando. Lo nuevo: el motivo
-- (`p_datos.motivo`, opcional, va al registro), validación de cada campo y de `logo`, y que un campo AUSENTE conserve su valor.
create or replace function public.sociedad_guarda(p_clave text, p_datos jsonb, p_nueva boolean default false)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_clave text := lower(btrim(coalesce(p_clave, '')));
  s       public.sociedades%rowtype;
  v_n     int;
  v_motivo text;
  n_label text; n_razon text; n_marca text; n_npwp text; n_npwp_label text; n_nib text; n_dom text; n_rep text;
  n_logo text; n_logo_alto text; n_folio text; n_tinta jsonb; n_debajo boolean; n_orden int; n_activa boolean; n_indo boolean;
  v_url_logo constant text := '^https://[a-z0-9]{20}\.supabase\.co/storage/v1/object/public/sociedades/';
  v_hex constant text := '^#[0-9A-Fa-f]{6}$';
  v_k text;
begin
  perform public._super_o_para();
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Faltan los datos de la sociedad' using errcode = '22023'; end if;

  if p_nueva then
    if v_clave !~ '^[a-z][a-z0-9_]{2,39}$' then
      raise exception 'La clave solo admite minúsculas, números y guion bajo, empieza por letra y va de 3 a 40 caracteres' using errcode = '22023';
    end if;
    if exists (select 1 from public.sociedades where clave = v_clave) then
      raise exception 'Ya existe una sociedad con esa clave' using errcode = '23505';
    end if;
    s.clave := v_clave; s.marca := ''; s.npwp_label := 'NPWP'; s.emisor_debajo := false; s.activa := true; s.orden := 0; s.es_indonesia := true;
  else
    select * into s from public.sociedades where clave = v_clave for update;
    if not found then raise exception 'Esa sociedad ya no existe' using errcode = 'P0002'; end if;
  end if;

  -- Cada campo: si viene, se normaliza; si no, conserva el actual. JSON null = vacío.
  n_razon := case when p_datos ? 'razon' then btrim(coalesce(p_datos ->> 'razon', '')) else s.razon end;
  n_dom   := case when p_datos ? 'domicilio' then btrim(coalesce(p_datos ->> 'domicilio', '')) else s.domicilio end;
  if coalesce(n_razon, '') = '' or coalesce(n_dom, '') = '' then
    raise exception 'La razón social y el domicilio son obligatorios: los imprime cada documento' using errcode = '22023';
  end if;
  n_label := case when p_datos ? 'label' then coalesce(nullif(btrim(coalesce(p_datos ->> 'label', '')), ''), n_razon) else coalesce(s.label, n_razon) end;
  n_marca := case when p_datos ? 'marca' then btrim(coalesce(p_datos ->> 'marca', '')) else s.marca end;
  n_npwp  := case when p_datos ? 'npwp' then nullif(btrim(coalesce(p_datos ->> 'npwp', '')), '') else s.npwp end;
  n_npwp_label := case when p_datos ? 'npwp_label' then coalesce(nullif(btrim(coalesce(p_datos ->> 'npwp_label', '')), ''), 'NPWP') else s.npwp_label end;
  n_nib   := case when p_datos ? 'nib' then nullif(btrim(coalesce(p_datos ->> 'nib', '')), '') else s.nib end;
  n_rep   := case when p_datos ? 'rep' then nullif(btrim(coalesce(p_datos ->> 'rep', '')), '') else s.rep end;
  n_logo  := case when p_datos ? 'logo' then nullif(btrim(coalesce(p_datos ->> 'logo', '')), '') else s.logo end;
  n_logo_alto := case when p_datos ? 'logo_alto' then nullif(btrim(coalesce(p_datos ->> 'logo_alto', '')), '') else s.logo_alto end;
  n_folio := case when p_datos ? 'folio' then nullif(btrim(coalesce(p_datos ->> 'folio', '')), '') else s.folio end;

  -- tinta: objeto {primary, deep} con colores #RRGGBB (o vacíos), o nada. Nunca {primary:'',deep:''}: eso es «hereda la de marca».
  if p_datos ? 'tinta' then
    if jsonb_typeof(p_datos -> 'tinta') = 'object' then
      for v_k in select jsonb_object_keys(p_datos -> 'tinta') loop
        if v_k not in ('primary', 'deep') then raise exception 'La tinta solo admite «primary» y «deep»' using errcode = '22023'; end if;
        if jsonb_typeof(p_datos -> 'tinta' -> v_k) <> 'string'
           or ((p_datos -> 'tinta' ->> v_k) <> '' and (p_datos -> 'tinta' ->> v_k) !~ v_hex) then
          raise exception 'La tinta «%» tiene que ser un color #RRGGBB', v_k using errcode = '22023';
        end if;
      end loop;
      n_tinta := case when coalesce(p_datos -> 'tinta' ->> 'primary', '') = '' and coalesce(p_datos -> 'tinta' ->> 'deep', '') = ''
                      then null else p_datos -> 'tinta' end;
    elsif jsonb_typeof(p_datos -> 'tinta') = 'null' then
      n_tinta := null;
    else
      raise exception 'La tinta es un objeto {primary, deep}' using errcode = '22023';
    end if;
  else
    n_tinta := s.tinta;
  end if;

  if p_datos ? 'emisor_debajo' then
    if jsonb_typeof(p_datos -> 'emisor_debajo') <> 'boolean' then raise exception '«emisor_debajo» es sí o no' using errcode = '22023'; end if;
    n_debajo := (p_datos ->> 'emisor_debajo')::boolean;
  else n_debajo := s.emisor_debajo; end if;
  if p_datos ? 'es_indonesia' then
    if jsonb_typeof(p_datos -> 'es_indonesia') <> 'boolean' then raise exception '«es_indonesia» es sí o no' using errcode = '22023'; end if;
    n_indo := (p_datos ->> 'es_indonesia')::boolean;
  else n_indo := s.es_indonesia; end if;
  if p_datos ? 'activa' and not p_nueva then
    if jsonb_typeof(p_datos -> 'activa') <> 'boolean' then raise exception '«activa» es sí o no' using errcode = '22023'; end if;
    n_activa := (p_datos ->> 'activa')::boolean;
  else n_activa := s.activa; end if;   -- en el alta nace activa siempre (lo impone el servidor)
  if p_datos ? 'orden' and coalesce(p_datos ->> 'orden', '') <> '' then
    if (p_datos ->> 'orden') !~ '^-?[0-9]{1,4}$' then raise exception 'El orden es un número entero' using errcode = '22023'; end if;
    n_orden := (p_datos ->> 'orden')::int;
  else n_orden := s.orden; end if;

  -- Validación de lo que CAMBIA (un valor histórico que ya no cumpliera la regla de hoy no impide editar el resto)
  if n_razon is distinct from s.razon and (char_length(n_razon) > 200 or n_razon ~ '[[:cntrl:]]') then
    raise exception 'La razón social va en una línea, de 1 a 200 caracteres' using errcode = '22023'; end if;
  if n_dom is distinct from s.domicilio and (char_length(n_dom) > 500 or regexp_replace(n_dom, '[\n\r\t]', '', 'g') ~ '[[:cntrl:]]') then
    raise exception 'El domicilio admite hasta 500 caracteres' using errcode = '22023'; end if;
  if n_label is distinct from s.label and (char_length(n_label) > 200 or n_label ~ '[[:cntrl:]]') then
    raise exception 'El nombre en el desplegable va en una línea, hasta 200 caracteres' using errcode = '22023'; end if;
  if n_marca is distinct from s.marca and (char_length(n_marca) > 120 or n_marca ~ '[[:cntrl:]]') then
    raise exception 'La marca va en una línea, hasta 120 caracteres' using errcode = '22023'; end if;
  if n_npwp is distinct from s.npwp and (char_length(n_npwp) > 60 or n_npwp ~ '[[:cntrl:]]') then
    raise exception 'La identificación fiscal va en una línea, hasta 60 caracteres' using errcode = '22023'; end if;
  if n_npwp_label is distinct from s.npwp_label and (char_length(n_npwp_label) > 20 or n_npwp_label ~ '[[:cntrl:]]') then
    raise exception 'La etiqueta fiscal va en una línea, hasta 20 caracteres' using errcode = '22023'; end if;
  if n_nib is distinct from s.nib and (char_length(n_nib) > 40 or n_nib ~ '[[:cntrl:]]') then
    raise exception 'El NIB va en una línea, hasta 40 caracteres' using errcode = '22023'; end if;
  if n_rep is distinct from s.rep and (char_length(n_rep) > 200 or n_rep ~ '[[:cntrl:]]') then
    raise exception 'El representante va en una línea, hasta 200 caracteres' using errcode = '22023'; end if;
  if n_logo_alto is distinct from s.logo_alto and n_logo_alto !~ '^[0-9]{1,3}(\.[0-9]{1,2})?mm$' then
    raise exception 'El alto del logo va en milímetros, por ejemplo 24mm' using errcode = '22023'; end if;
  if n_folio is distinct from s.folio and n_folio !~ v_hex then
    raise exception 'El folio es un color #RRGGBB' using errcode = '22023'; end if;
  if n_logo is distinct from s.logo and n_logo is not null and not (
       n_logo ~* '^/contracts/assets/brand/[A-Za-z0-9._-]{1,80}\.(png|jpe?g|webp)$'
       or n_logo ~ (v_url_logo || v_clave || '/[0-9a-f]{64}\.(png|jpg|webp)$')) then
    raise exception 'El logo tiene que ser una imagen PNG, JPEG o WebP subida desde Ajustes (nunca un SVG ni una dirección cualquiera)'
      using errcode = '22023', hint = 'logo_no_admitido';
  end if;

  v_motivo := nullif(left(btrim(coalesce(p_datos ->> 'motivo', '')), 500), '');
  perform set_config('axw.ajustes_motivo', coalesce(v_motivo, ''), true);

  if p_nueva then
    insert into public.sociedades (clave, label, razon, marca, npwp, npwp_label, nib, domicilio, rep, logo, logo_alto,
                                   emisor_debajo, folio, tinta, activa, orden, es_indonesia)
    values (v_clave, n_label, n_razon, n_marca, n_npwp, n_npwp_label, n_nib, n_dom, n_rep, n_logo, n_logo_alto,
            n_debajo, n_folio, n_tinta, true, n_orden, n_indo);
  else
    update public.sociedades x set
      label = n_label, razon = n_razon, marca = n_marca, npwp = n_npwp, npwp_label = n_npwp_label, nib = n_nib, domicilio = n_dom,
      rep = n_rep, logo = n_logo, logo_alto = n_logo_alto, emisor_debajo = n_debajo, folio = n_folio, tinta = n_tinta,
      activa = n_activa, orden = n_orden, es_indonesia = n_indo
    where x.clave = v_clave;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Esa sociedad ya no existe' using errcode = 'P0002'; end if;
  end if;
  perform set_config('axw.ajustes_motivo', '', true);
  return v_clave;
end $$;
revoke all on function public.sociedad_guarda(text, jsonb, boolean) from public, anon;
grant execute on function public.sociedad_guarda(text, jsonb, boolean) to authenticated;

-- ── 5. Leer ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Dueño postgres (DEFINER), no lw_lector: cuenta documentos en tablas cuya RLS un lector no ve. El permiso se comprueba aquí:
-- administración. Devuelve la fila de cada sociedad y lo que tiene detrás (`documentos`); nada más sale.
create or replace function public.sociedades_ajustes_datos()
returns jsonb
language plpgsql stable security definer set search_path to ''
as $$
declare
  v jsonb;
begin
  if public.uid_sesion() is null then
    raise exception 'sociedades_ajustes_datos: sin sesión' using errcode = '42501';
  end if;
  if not public.es_admin() then
    raise exception 'Las sociedades emisoras son de administración.' using errcode = '42501';
  end if;
  with d as (
    select f.clave, jsonb_build_object('total', sum(f.total)::int, 'abiertos', sum(f.abiertos)::int,
             'detalle', jsonb_object_agg(f.tabla, jsonb_build_object('total', f.total, 'abiertos', f.abiertos))) as j
      from public._sociedad_docs_filas(null) f group by f.clave)
  select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('documentos',
           coalesce(d.j, jsonb_build_object('total', 0, 'abiertos', 0, 'detalle', '{}'::jsonb))) order by s.orden, s.clave), '[]'::jsonb)
    into v
    from public.sociedades s left join d on d.clave = s.clave;
  return jsonb_build_object('puede_escribir', public.es_super_admin(), 'sociedades', v);
end $$;
revoke all on function public.sociedades_ajustes_datos() from public, anon, service_role;
grant execute on function public.sociedades_ajustes_datos() to authenticated;

-- El nombre del ERP (config_instancia.marca) para todo el equipo: lo leen el título del navegador y el menú. No es secreto (ya va
-- en la ficha pública instancia.js) y solo devuelve esa clave; sin sesión, null. Un comprador con sesión también puede pedirlo.
create or replace function public.instancia_marca()
returns text
language sql stable security definer set search_path to ''
as $$
  select case when public.uid_sesion() is null then null
              else (select c.valor #>> '{}' from public.config_instancia c where c.clave = 'marca') end
$$;
revoke all on function public.instancia_marca() from public, anon, service_role;
grant execute on function public.instancia_marca() to authenticated;

-- ── 6. Bucket de logos ──────────────────────────────────────────────────────────────────────────────────────────────
-- Sin policies sobre storage.objects: nadie con sesión escribe aquí; solo la edge `ficheros` (service_role), que valida los bytes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sociedades', 'sociedades', true, 524288, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;
