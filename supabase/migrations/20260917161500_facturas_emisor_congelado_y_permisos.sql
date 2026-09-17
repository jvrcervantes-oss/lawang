-- ============================================================================
-- FACTURAS — el emisor se congela en el documento, y el numero deja de estar
-- al alcance del navegador
--
-- Sale de la revision previa del 17-sep-2026 (Datos + Administracion +
-- Seguridad) sobre el plan de abrir la intranet a mas empresas. Tres de los
-- hallazgos NO son sobre el futuro: son defectos de hoy.
--
-- 1. EL EMISOR NO ESTABA CONGELADO. Razon social, NPWP y domicilio se leen en
--    vivo de `SOCIEDADES` al imprimir, asi que los 412 documentos ya emitidos se
--    reimprimen siempre con la identidad de HOY. Ya paso dos veces: Tepi Sun Gai
--    cambio como se imprime su nombre el 31-jul-2026 y de representante el
--    11-ago-2026. Mientras eso exigia un commit quedaba en git; desde que
--    `public.sociedades` es editable desde un panel, un UPDATE lo haria al
--    instante y sin rastro. A partir de aqui cada documento nace con su emisor
--    dentro, en `datos->'emisor'`.
--    ⚠️ Solo hacia adelante. Los 412 anteriores se quedan como historico
--    documentado (decision del owner, 17-sep-2026): rellenarlos hacia atras es
--    un UPDATE masivo sobre una tabla con cinco triggers de fila, dos de los
--    cuales se tragan los errores, y ademas seria mejor esfuerzo — la identidad
--    anterior al 11-ago ya no se puede reconstruir desde la base.
--
-- 2. CUALQUIER AGENTE PODIA CAMBIAR EL EMISOR DE UNA FACTURA YA ENVIADA. De los
--    doce triggers de `facturas`, ninguno congelaba `sociedad`; el unico que
--    congela algo (`factura_anulada_solo_cambia_autor`) solo actua si la factura
--    ya esta anulada. Un PATCH bastaba para que un documento enviado cambiase de
--    empresa conservando su numero.
--
-- 3. EL NUMERO LO PODIA PONER EL CLIENTE. `set_factura_numero` solo actua si
--    `new.numero is null`, asi que el navegador podia mandar el numero que
--    quisiera y el unico freno era el UNIQUE global.
--
-- Y el marco: verificado en `pg_default_acl` que `anon` tiene hoy INSERT, UPDATE
-- y SELECT sobre las 21 columnas de `facturas`. Lo unico que lo salva es que las
-- policies son todas `{authenticated}`. Eso es «el GRANT manda antes que la
-- policy» con la tabla del dinero delante.
--
-- LO QUE ESTA MIGRACION NO HACE: no separa las series por sociedad. El owner
-- decidio el 17-sep NO hacerlo todavia (LAW-235, necesita contable indonesio).
-- Las tres secuencias globales siguen intactas y no se toca ni un numero.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. El trigger de numeracion pasa a SECURITY DEFINER.
-- Motivo: para poder quitarle a `anon`/`authenticated` el privilegio sobre las
-- secuencias hace falta que `nextval` lo ejecute el dueño de la funcion y no el
-- que inserta. ORDEN IMPORTANTE: primero DEFINER, despues el revoke. Al reves,
-- toda alta de factura desde la pantalla falla.
-- ---------------------------------------------------------------------------
create or replace function public.set_factura_numero()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.numero is null then
    new.numero := case new.tipo
      when 'proforma' then 'PRO' || lpad(nextval('public.facturas_proforma_seq')::text, 5, '0')
      when 'recibi'   then 'REC' || lpad(nextval('public.facturas_recibi_seq')::text, 5, '0')
      else                 'INV' || lpad(nextval('public.facturas_seq')::text, 5, '0')
    end;
  end if;
  return new;
end; $function$;

-- Una funcion DEFINER nace ejecutable por `anon`/`authenticated` (deuda §7 de
-- contexto/seguridad_2026.md). Se revoca y se verifica, no se supone.
revoke execute on function public.set_factura_numero() from anon, authenticated;

revoke all on sequence public.facturas_seq          from anon, authenticated;
revoke all on sequence public.facturas_proforma_seq from anon, authenticated;
revoke all on sequence public.facturas_recibi_seq   from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. El emisor, congelado dentro del documento en el alta.
-- Se guarda lo que el documento DICE (razon, identificacion fiscal, domicilio,
-- representante), no lo cosmetico (logo, folio, tinta): eso puede cambiar sin
-- que cambie lo que el documento afirma, y asi un retoque de marca no obliga a
-- reimprimir nada.
-- Si la sociedad no existe, LANZA. El fallback mudo es justo la familia de fallo
-- que esta revision vino a cerrar: seis sitios del front caian a 'tepi_sungai'
-- en silencio, y eso hacia que San Dal Woods emitiera con NPWP ajeno.
-- ---------------------------------------------------------------------------
create or replace function public.congela_emisor_factura()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare s public.sociedades%rowtype;
begin
  if new.sociedad is null then
    raise exception 'Una factura no puede emitirse sin sociedad emisora.';
  end if;

  select * into s from public.sociedades where clave = new.sociedad;
  if not found then
    raise exception 'La sociedad emisora «%» no existe en public.sociedades.', new.sociedad;
  end if;

  new.datos := jsonb_set(
    coalesce(new.datos, '{}'::jsonb),
    '{emisor}',
    jsonb_build_object(
      'clave',        s.clave,
      'razon',        s.razon,
      'marca',        s.marca,
      'npwp',         s.npwp,
      'npwp_label',   s.npwp_label,
      'nib',          s.nib,
      'domicilio',    s.domicilio,
      'rep',          s.rep,
      'congelado_en', to_jsonb(now())
    ),
    true
  );
  return new;
end; $$;

revoke execute on function public.congela_emisor_factura() from anon, authenticated;

create trigger trg_congela_emisor
  before insert on public.facturas
  for each row execute function public.congela_emisor_factura();

-- ---------------------------------------------------------------------------
-- 3. Una factura ENVIADA no cambia de emisor ni de numero.
-- Para eso esta anular y re-emitir. `anulada` ya la protege
-- `factura_anulada_solo_cambia_autor`; el hueco era la enviada.
-- No se bloquea el borrador a proposito: la pantalla de facturas manda el mismo
-- payload en el alta y en la edicion, y el agente tiene que poder corregir la
-- sociedad de una factura que todavia no ha salido.
-- ---------------------------------------------------------------------------
create or replace function public.factura_enviada_no_cambia_emisor()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if coalesce(old.enviada, false) then
    if new.sociedad is distinct from old.sociedad then
      raise exception 'La factura % ya se envio: no se puede cambiar la sociedad emisora. Anulala y emite una nueva.', old.numero;
    end if;
    if new.numero is distinct from old.numero then
      raise exception 'La factura % ya se envio: su numero no se cambia.', old.numero;
    end if;
  end if;
  return new;
end; $$;

revoke execute on function public.factura_enviada_no_cambia_emisor() from anon, authenticated;

create trigger trg_factura_enviada_no_cambia_emisor
  before update on public.facturas
  for each row execute function public.factura_enviada_no_cambia_emisor();

-- ---------------------------------------------------------------------------
-- 4. La sociedad de una factura tiene que existir de verdad.
-- Verificado antes de aplicar: 0 de las 412 filas tienen `sociedad` nula y 0
-- apuntan a una clave que no este en la tabla. No hace falta ningun UPDATE.
-- Sin NOT NULL, un INSERT sin sociedad caeria en la rama `else` del numerador y
-- quemaria un numero de la serie equivocada.
-- Sin DEFAULT a proposito: un default constante es el mismo fallback mudo del
-- front, mudado a la base, donde se ve todavia menos.
-- ---------------------------------------------------------------------------
alter table public.facturas
  alter column sociedad set not null;

alter table public.facturas
  add constraint facturas_sociedad_fkey
  foreign key (sociedad) references public.sociedades (clave);

-- ---------------------------------------------------------------------------
-- 5. El candado tambien en el CONTRATO, que es donde se ELIGE.
-- La factura hereda `sociedad` del contrato; blindar solo la factura es blindar
-- la copia. La clave vive dentro del jsonb (`datos->'fields'->>'sociedad_firmante'`)
-- y no admite clave ajena, asi que va por trigger.
-- Se permite NULL: 15 de los 251 contratos no la traen y son validos.
-- Verificado: 0 contratos apuntan hoy a una clave inexistente.
-- ---------------------------------------------------------------------------
create or replace function public.contrato_sociedad_existe()
returns trigger
language plpgsql
set search_path to ''
as $$
declare clave text := new.datos->'fields'->>'sociedad_firmante';
begin
  if clave is not null and clave <> ''
     and not exists (select 1 from public.sociedades s where s.clave = clave) then
    raise exception 'La sociedad firmante «%» no existe en public.sociedades.', clave;
  end if;
  return new;
end; $$;

revoke execute on function public.contrato_sociedad_existe() from anon, authenticated;

create trigger trg_contrato_sociedad_existe
  before insert or update on public.contratos
  for each row execute function public.contrato_sociedad_existe();

-- ---------------------------------------------------------------------------
-- 6. PERMISOS de `facturas`.
-- `anon` fuera del todo: hoy tiene INSERT/UPDATE/SELECT sobre las 21 columnas y
-- lo unico que lo frena son las policies. Es la cara literal de «el GRANT manda
-- antes que la policy».
-- Y `numero` sale del alcance de `authenticated`. OJO CON LA FORMA: un
-- `revoke update (numero)` por columna es un NO-OP mientras exista el UPDATE a
-- nivel de tabla — hay que revocar entero y volver a conceder enumerando.
-- `sociedad` SI se queda concedida: la pantalla manda el mismo payload al crear
-- y al editar, asi que quitarla romperia la edicion de un borrador. Quien la
-- protege es el trigger del punto 3, que es donde esta el riesgo real.
-- `justificante_path` tampoco se concede: lo escribe `espejo_justificante` como
-- espejo de la lista, y darselo al navegador le devolveria dos dueños al dato.
-- ---------------------------------------------------------------------------
revoke all on public.facturas from anon;
revoke insert, update on public.facturas from authenticated;

grant insert (id, tipo, sociedad, cliente_nombre, proyecto_nombre, proyecto_id,
              contrato_numero, contrato_id, client_id, total, moneda,
              fecha_emision, datos, justificantes, anulada, enviada,
              fecha_envio, creado_por, created_at)
  on public.facturas to authenticated;

-- `creado_por` entra en el UPDATE: `factura_anulada_solo_cambia_autor` existe
-- justamente porque reasignar el autor de una factura anulada es una operacion
-- soportada (poderes de super_admin, LAW-71).
grant update (tipo, sociedad, cliente_nombre, proyecto_nombre, proyecto_id,
              contrato_numero, contrato_id, client_id, total, moneda,
              fecha_emision, datos, justificantes, anulada, enviada,
              fecha_envio, creado_por)
  on public.facturas to authenticated;
