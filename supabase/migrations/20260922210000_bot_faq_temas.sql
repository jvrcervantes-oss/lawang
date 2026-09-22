-- destructivo-ok: el unico UPDATE de filas reales es sobre las 7 filas de
-- bot_bloqueos y solo rellena la columna NUEVA y nullable tema_clave (no cambia
-- patron, patron_salida, motivo ni ref; se limita a `where tema_clave is null`,
-- asi que es idempotente y reversible con un `set tema_clave = null`). Los DROP
-- son "drop policy / drop trigger if exists" sobre las TRES TABLAS NUEVAS de
-- esta migracion (idempotencia). No hay drop table/column, ni delete, ni RLS
-- apagada. El prompt (bot_fuentes) NO se toca: eso es S2.
--
-- Bot de apoyo a agentes — temas, FAQ aprobadas y respuestas copiadas
-- (encargo 20260922_lawang_bot_apoyo_agentes). Construye sobre
-- 20260922012840_bot_agentes.sql: 3 tablas nuevas, 2 columnas nuevas, 5
-- funciones, RLS, grants y seed de 9 temas. Sin datos de comprador.
--
-- Por que cada pieza:
--  * bot_temas: las preguntas de los compradores se repiten por TEMA (quien
--    cobra, retencion, plazo...). Un tema es una regex ES/EN/ID sobre la
--    pregunta, validada al guardarla (un patron roto tumbaria el resumen y el
--    edge). `procedimiento` marca el unico tema que admite FAQ sin proyecto ni
--    tipo de contrato: el de "que documento existe / donde esta", que no
--    depende del ejemplar.
--  * bot_bloqueos.tema_clave: cada freno del servidor cuelga de un tema. Asi
--    "este tema esta frenado" se sabe con una consulta y una FAQ no puede
--    tapar un hueco del contrato: un freno se resuelve con adenda, no con FAQ.
--  * bot_consultas.descarte_motivo: por que el SERVIDOR descarto el borrador
--    (caida del proveedor, rehuso, truncado, cifra ajena, patron de salida).
--    Sin el, "respuesta is null" mezclaba un freno con una caida de Anthropic.
--  * bot_faq: respuestas APROBADAS por super_admin, acotadas a un proyecto o a
--    un tipo de contrato (contratos.tipo, no el slug de plantilla: son dos
--    vocabularios y el slug ya causo una plantilla equivocada — ver
--    contracts/sql/adenda.sql). Una FAQ no se edita: se retira (activo=false)
--    y nace otra con sustituye_a, para que lo que el agente leyo un dia siga
--    siendo rastreable. aprobado_por/aprobado_en los pone el servidor, siempre.
--  * bot_respuestas_copiadas: lo que el agente COPIA para mandar al comprador,
--    guardado tal cual. El freno de cifras (>= 8 digitos seguidos tras
--    colapsar separadores: cuentas, telefonos, pasaportes) compara contra el
--    borrador del asistente: un numero que el bot no escribio no sale por
--    aqui. Una fila por agente y consulta.
--  * bot_temas_resumen(): que se pregunta, que se retira y que se descarta por
--    tema en una ventana de dias. security invoker: cada agente ve el resumen
--    de SUS consultas (la RLS de bot_consultas sigue al contrato), el
--    super_admin el de todas. Devuelve tambien los temas con 0 consultas para
--    que el panel no pierda filas.
--  * Grants: el GRANT manda antes que la policy. La policy FOR ALL de
--    super_admin sobre bot_fuentes/bot_bloqueos (20260922012840) no servia de
--    nada sin INSERT/UPDATE concedidos a authenticated: se corrige aqui.

-- ---------------------------------------------------------------------------
-- 1. bot_temas + validacion del patron
-- ---------------------------------------------------------------------------
create table if not exists public.bot_temas (
  clave         text primary key,
  nombre_es     text not null,
  nombre_en     text not null,
  patron        text not null check (char_length(patron) <= 300),
  procedimiento boolean default false,
  orden         int,
  activo        boolean default true
);
comment on table public.bot_temas is
  'Temas del bot de apoyo a agentes: regex (insensible a mayusculas, ES/EN/ID, dialecto ARE sin lookbehind) sobre la pregunta del comprador. procedimiento=true admite FAQ sin proyecto ni tipo.';

-- Un patron invalido revienta en el INSERT/UPDATE, no en la primera consulta
-- del panel. Se prueba ejecutandolo contra la cadena vacia dentro de un
-- bloque protegido: cualquier error de compilacion de la regex cae aqui.
create or replace function public.bot_temas_valida_patron()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  begin
    perform '' ~* new.patron;
  exception when others then
    raise exception 'patrón de tema inválido: %', new.patron using errcode = '23514';
  end;
  return new;
end;
$fn$;

drop trigger if exists bot_temas_valida_patron on public.bot_temas;
create trigger bot_temas_valida_patron
  before insert or update on public.bot_temas
  for each row execute function public.bot_temas_valida_patron();

-- Seed: 9 temas. Dollar-quoting para que los backslashes lleguen enteros.
-- \y = frontera de palabra en ARE. Se siembra una sola vez por clave.
insert into public.bot_temas (clave, nombre_es, nombre_en, patron, procedimiento, orden)
select v.clave, v.nombre_es, v.nombre_en, v.patron, v.procedimiento, v.orden
  from (values
    ('quien_cobra', 'Quién cobra / cuenta de pago', 'Who gets paid / payment account',
     $t$\y(cuentas?|titular(es)?|escrow|beneficiari[oa]s?|rekening|payee)\y|a (qu[eé]|cu[aá]l) cuenta|qui[eé]n (cobra|recibe el pago)|(d[oó]nde|a qui[eé]n) (se )?(pago|pagamos|transfiero)|who (do|should) (i|we) pay|bank account|account (holder|number|name|details)|nomor rekening$t$,
     false, 10),
    ('retencion', 'Retención de un porcentaje', 'Retention / holdback',
     $t$retenci[oó]n|retener|retenid[oa]s?|retengo|retenemos|\yretain(ed|s)?\y|retention|holdback|hold back|withh?olds?|withheld|\ypotongan\y$t$,
     false, 20),
    ('plazo_entrega', 'Plazo y fecha de entrega', 'Delivery / completion date',
     $t$\yplazos?\y|fecha (de )?entrega|cu[aá]ndo (se entrega|estar[aá] (lista|terminada|acabada))|(delivery|completion|handover) date|when (is|will).{0,25}(deliver|complet|ready|finish)|kapan (selesai|serah terima|diserahkan)$t$,
     false, 30),
    ('penalizacion', 'Penalización por retraso', 'Late penalty / liquidated damages',
     $t$penalizaci[oó]n|penalidad|penalizar|\ypenalt(y|ies)\y|penali[sz]e|\ymulta\y|liquidated damages|(compensaci|indemnizaci)[oó]n por (retraso|demora)|late (delivery|completion) (fee|charge|compensation)|\ydenda\y$t$,
     false, 40),
    ('anexos_planos', 'Anexos, planos y especificaciones', 'Annexes, drawings and specifications',
     $t$\yanexos?\y|ap[eé]ndices?|\yplanos?\y|calidades|especificaciones|\yannex(es)?\y|\yappendi(x|ces)\y|\ydrawings?\y|specifications?|\yspecs?\y|lampiran|\ygambar\y|spesifikasi$t$,
     false, 50),
    ('titulo_leasehold', 'Título, certificado y régimen (leasehold/freehold)', 'Title, certificate and tenure (leasehold/freehold)',
     $t$t[ií]tulos?\y|certificad[oa]s?|sertifikat|\yshm\y|\yhgb\y|hak (milik|sewa|pakai|guna)|leasehold|freehold|renovaci[oó]n|renovar|\yrenew(al|ed|s)?\y|30 ?\+ ?30|title deed|land certificate|perpanjangan$t$,
     false, 60),
    ('comunidad_gastos', 'Comunidad, normas y gastos', 'Community, rules and fees',
     $t$\ycomunidad\y|\ynormas\y|estatutos|gastos (comunes|de (la )?comunidad|de mantenimiento)|cuota (mensual|anual|de (la )?(comunidad|mantenimiento))|mantenimiento|\yhoa\y|community (rules|fees?)|maintenance fees?|service charge|\yiuran\y|biaya (pemeliharaan|perawatan|bulanan)$t$,
     false, 70),
    ('pago_hitos', 'Hitos y calendario de pagos', 'Milestones and payment schedule',
     $t$\yhitos?\y|milestones?|calendario de pagos?|forma de pago|\ycuotas?\y|instal?lments?|payment (schedule|plan|terms)|cu[aá]ndo (pago|se paga|hay que pagar)|when (do|should) (i|we) pay|jadwal pembayaran|\ycicilan\y|\yangsuran\y|cara pembayaran$t$,
     false, 80),
    ('documentos_expediente', 'Documentos del expediente', 'File documents (receipts, invoices, signed copies)',
     $t$\ydocumentos?\y|justificantes?|\yrecibos?\y|\yfacturas?\y|copia firmada|\ydocuments?\y|\yreceipts?\y|\yinvoices?\y|signed copy|\ydokumen\y|\ykwitansi\y|bukti (bayar|pembayaran|transfer)|\yfaktur\y$t$,
     true, 90)
  ) as v(clave, nombre_es, nombre_en, patron, procedimiento, orden)
 where not exists (select 1 from public.bot_temas t where t.clave = v.clave);

-- ---------------------------------------------------------------------------
-- 2. bot_bloqueos.tema_clave: cada freno cuelga de un tema. El UPDATE asigna
--    tema a los 7 frenos sembrados en 20260922012840 por su ref o por una
--    subcadena inequivoca del motivo (sin acentos en el patron ILIKE para no
--    depender de la codificacion con la que viaje este fichero). Solo toca
--    filas sin tema: reejecutar no cambia nada.
-- ---------------------------------------------------------------------------
alter table public.bot_bloqueos
  add column if not exists tema_clave text references public.bot_temas(clave);
create index if not exists bot_bloqueos_tema_idx on public.bot_bloqueos (tema_clave);

update public.bot_bloqueos
   set tema_clave = case
     when ref = 'LAW-124' or motivo ilike 'Destino del pago%'             then 'quien_cobra'
     when motivo ilike 'Estructura de titularidad simulada%'              then 'titulo_leasehold'
     when motivo ilike 'T_tulo, certificado, escrow%'                     then 'titulo_leasehold'
     when motivo ilike 'Retenci_n de un porcentaje%'                      then 'retencion'
     when motivo ilike 'Penalizaci_n o compensaci_n por retraso%'         then 'penalizacion'
     when motivo ilike 'Cambio de hito, plazo, precio%'                   then 'pago_hitos'
     when motivo ilike 'Fecha m_xima o fija de entrega%'                  then 'plazo_entrega'
   end
 where tema_clave is null;

-- ---------------------------------------------------------------------------
-- 3. bot_consultas.descarte_motivo
-- ---------------------------------------------------------------------------
alter table public.bot_consultas
  add column if not exists descarte_motivo text;
comment on column public.bot_consultas.descarte_motivo is
  'Por que el SERVIDOR descarto el borrador (modelo_no_disponible, modelo_rehuso, respuesta_truncada, respuesta_vacia, cifra_ajena_al_contexto, patron_salida). Lo escribe la edge; el agente no escribe aqui (sin policy de UPDATE). respuesta is null = descartada.';

-- ---------------------------------------------------------------------------
-- 4. bot_faq: respuestas aprobadas. Inmutables salvo retirarlas.
-- ---------------------------------------------------------------------------
create table if not exists public.bot_faq (
  id            uuid primary key default gen_random_uuid(),
  tema_clave    text not null references public.bot_temas(clave),
  proyecto_id   uuid null references public.proyectos(id),
  tipo_contrato text null,
  pregunta      text not null check (char_length(pregunta)  <= 1000),
  respuesta     text not null check (char_length(respuesta) <= 4000),
  sustituye_a   uuid null references public.bot_faq(id),
  activo        boolean default true,
  aprobado_por  text,
  aprobado_en   timestamptz,
  creado_en     timestamptz default now()
);
comment on table public.bot_faq is
  'FAQ aprobadas por super_admin para el bot de apoyo a agentes. Acotadas a proyecto o tipo de contrato (contratos.tipo). No se editan: se retiran (activo=false) y se crea otra con sustituye_a.';
create index if not exists bot_faq_tema_idx      on public.bot_faq (tema_clave);
create index if not exists bot_faq_proyecto_idx  on public.bot_faq (proyecto_id);
create index if not exists bot_faq_sustituye_idx on public.bot_faq (sustituye_a);

-- Freno de entrada. security invoker: el exists sobre contratos corre con la
-- RLS de quien inserta (solo super_admin puede, y ve todos los contratos).
-- Los RAISE reutilizan 23514 (check_violation) para que lwErrorHumano deje
-- pasar el texto en castellano.
create or replace function public.bot_faq_frena()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  txt text;
begin
  -- (1) cifras: >= 8 digitos seguidos tras quitar espacios, puntos, comas y
  --     guiones. Una cuenta, un telefono o un pasaporte no entran en una FAQ.
  txt := regexp_replace(coalesce(new.pregunta, '') || ' ' || coalesce(new.respuesta, ''), '[ .,-]', '', 'g');
  if txt ~ '\d{8,}' then
    raise exception 'La FAQ contiene una cifra de 8 o más dígitos seguidos (cuenta, teléfono, pasaporte): no se guarda'
      using errcode = '23514';
  end if;

  -- (2) tema frenado: un freno del servidor es un hueco del contrato
  if exists (select 1 from public.bot_bloqueos b where b.activo and b.tema_clave = new.tema_clave) then
    raise exception 'Este tema está frenado por el asistente: es un hueco del contrato, se resuelve con adenda, no con FAQ'
      using errcode = '23514';
  end if;

  -- (3) alcance: proyecto o tipo, salvo temas de procedimiento
  if new.proyecto_id is null and new.tipo_contrato is null
     and not exists (select 1 from public.bot_temas t where t.clave = new.tema_clave and t.procedimiento) then
    raise exception 'Una FAQ necesita proyecto o tipo de contrato (solo los temas de procedimiento valen para todos)'
      using errcode = '23514';
  end if;

  -- (4) tipo_contrato es el vocabulario de contratos.tipo, no el slug de plantilla
  if new.tipo_contrato is not null
     and not exists (select 1 from public.contratos c where c.tipo = new.tipo_contrato) then
    raise exception 'tipo de contrato desconocido: usa el valor de contratos.tipo, no el slug de plantilla'
      using errcode = '23514';
  end if;

  -- (5) quien aprueba lo dice la sesion, nunca el cliente
  new.aprobado_por := (select auth.email());
  new.aprobado_en  := now();
  return new;
end;
$fn$;

drop trigger if exists bot_faq_frena on public.bot_faq;
create trigger bot_faq_frena
  before insert on public.bot_faq
  for each row execute function public.bot_faq_frena();

-- Inmutabilidad: lo unico que cambia es activo, y solo hacia false.
create or replace function public.bot_faq_inmutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  if (new.activo = true and old.activo = false)
     or row(new.id, new.tema_clave, new.proyecto_id, new.tipo_contrato, new.pregunta, new.respuesta,
            new.sustituye_a, new.aprobado_por, new.aprobado_en, new.creado_en)
        is distinct from
        row(old.id, old.tema_clave, old.proyecto_id, old.tipo_contrato, old.pregunta, old.respuesta,
            old.sustituye_a, old.aprobado_por, old.aprobado_en, old.creado_en) then
    raise exception 'una FAQ no se edita: se retira (activo=false) y se crea otra con sustituye_a'
      using errcode = '42501';
  end if;
  return new;
end;
$fn$;

drop trigger if exists bot_faq_inmutable on public.bot_faq;
create trigger bot_faq_inmutable
  before update on public.bot_faq
  for each row execute function public.bot_faq_inmutable();

-- ---------------------------------------------------------------------------
-- 5. bot_respuestas_copiadas: lo que el agente copia, con freno de cifras
--    contra el borrador del asistente.
-- ---------------------------------------------------------------------------
create table if not exists public.bot_respuestas_copiadas (
  id          uuid primary key default gen_random_uuid(),
  -- on delete cascade: sigue a bot_consultas, que ya cae con su contrato y
  -- con la retencion de 90 dias.
  consulta_id uuid not null references public.bot_consultas(id) on delete cascade,
  texto       text not null check (char_length(texto) <= 6000),
  copiado_por text not null,
  copiado_en  timestamptz default now(),
  unique (consulta_id, copiado_por)
);
comment on table public.bot_respuestas_copiadas is
  'Texto que el agente copio para el comprador a partir de un borrador del bot. Una fila por agente y consulta. Ninguna cifra de 8+ digitos que no estuviera en el borrador.';

-- security invoker: la lectura de bot_consultas corre con la RLS del agente;
-- si no ve la consulta, el borrador es '' y cualquier cifra larga para.
create or replace function public.bot_copia_frena()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  t_copiado text;
  t_borrador text;
  cifra text;
begin
  if tg_op = 'UPDATE' and (new.consulta_id is distinct from old.consulta_id
                           or new.copiado_por is distinct from old.copiado_por) then
    raise exception 'una respuesta copiada no cambia de consulta ni de autor'
      using errcode = '42501';
  end if;

  t_copiado  := regexp_replace(coalesce(new.texto, ''), '[ .,-]', '', 'g');
  t_borrador := regexp_replace(
                  coalesce((select q.respuesta from public.bot_consultas q where q.id = new.consulta_id), ''),
                  '[ .,-]', '', 'g');
  for cifra in select m[1] from regexp_matches(t_copiado, '(\d{8,})', 'g') as m loop
    if position(cifra in t_borrador) = 0 then
      raise exception 'El texto copiado contiene una cifra que no está en el borrador del asistente: no se guarda ni se copia'
        using errcode = '23514';
    end if;
  end loop;

  new.copiado_en := now();
  return new;
end;
$fn$;

drop trigger if exists bot_copia_frena on public.bot_respuestas_copiadas;
create trigger bot_copia_frena
  before insert or update on public.bot_respuestas_copiadas
  for each row execute function public.bot_copia_frena();

-- ---------------------------------------------------------------------------
-- 6. RLS
-- ---------------------------------------------------------------------------
alter table public.bot_temas               enable row level security;
alter table public.bot_faq                 enable row level security;
alter table public.bot_respuestas_copiadas enable row level security;

-- bot_temas: lee cualquier agente, escribe solo super_admin
drop policy if exists "bot_temas: agentes leen" on public.bot_temas;
create policy "bot_temas: agentes leen"
  on public.bot_temas for select to authenticated
  using (public.es_agente());
drop policy if exists "bot_temas: solo super_admin escribe" on public.bot_temas;
create policy "bot_temas: solo super_admin escribe"
  on public.bot_temas for all to authenticated
  using (public.es_super_admin()) with check (public.es_super_admin());

-- bot_faq: lee cualquier agente; inserta y retira solo super_admin; SIN DELETE
-- (la historia de lo aprobado no se borra; se retira con activo=false).
drop policy if exists "bot_faq: agentes leen" on public.bot_faq;
create policy "bot_faq: agentes leen"
  on public.bot_faq for select to authenticated
  using (public.es_agente());
drop policy if exists "bot_faq: solo super_admin aprueba" on public.bot_faq;
create policy "bot_faq: solo super_admin aprueba"
  on public.bot_faq for insert to authenticated
  with check (public.es_super_admin());
drop policy if exists "bot_faq: solo super_admin retira" on public.bot_faq;
create policy "bot_faq: solo super_admin retira"
  on public.bot_faq for update to authenticated
  using (public.es_super_admin()) with check (public.es_super_admin());

-- bot_respuestas_copiadas: SELECT con EXACTAMENTE la condicion de la policy
-- SELECT de bot_consultas (que a su vez es la de contratos); INSERT solo como
-- uno mismo y solo sobre una consulta que uno mismo hizo; UPDATE solo lo
-- propio; SIN DELETE.
drop policy if exists "bot_respuestas_copiadas: quien ve la consulta ve la copia" on public.bot_respuestas_copiadas;
create policy "bot_respuestas_copiadas: quien ve la consulta ve la copia"
  on public.bot_respuestas_copiadas for select to authenticated
  using (
    exists (
      select 1
        from public.bot_consultas q
        join public.contratos c on c.id = q.contrato_id
       where q.id = bot_respuestas_copiadas.consulta_id
         and public.es_agente()
         and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))
    )
  );
drop policy if exists "bot_respuestas_copiadas: cada uno copia lo suyo" on public.bot_respuestas_copiadas;
create policy "bot_respuestas_copiadas: cada uno copia lo suyo"
  on public.bot_respuestas_copiadas for insert to authenticated
  with check (
    copiado_por = (select auth.email())
    and exists (select 1 from public.bot_consultas q
                 where q.id = consulta_id
                   and q.preguntado_por = (select auth.email()))
  );
drop policy if exists "bot_respuestas_copiadas: cada uno corrige lo suyo" on public.bot_respuestas_copiadas;
create policy "bot_respuestas_copiadas: cada uno corrige lo suyo"
  on public.bot_respuestas_copiadas for update to authenticated
  using (copiado_por = (select auth.email()))
  with check (copiado_por = (select auth.email()));

-- ---------------------------------------------------------------------------
-- 7. bot_temas_resumen(p_dias): consultas, retiradas y descartadas por tema.
--    security invoker: cuenta solo las consultas que la RLS deja ver al que
--    pregunta. Todo cualificado: las columnas de RETURNS TABLE entran en el
--    ambito de la funcion y `tema_clave` a secas seria ambiguo con
--    bot_bloqueos.tema_clave. LEFT JOIN para devolver tambien los temas a 0.
-- ---------------------------------------------------------------------------
create or replace function public.bot_temas_resumen(p_dias int)
returns table (
  tema_clave    text,
  nombre_es     text,
  nombre_en     text,
  frenado       boolean,
  consultas     bigint,
  con_retirados bigint,
  descartadas   bigint
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select t.clave,
         t.nombre_es,
         t.nombre_en,
         exists (select 1 from public.bot_bloqueos b where b.activo and b.tema_clave = t.clave),
         count(q.id)::bigint,
         (count(q.id) filter (where jsonb_typeof(q.bloqueos) = 'array'
                                and jsonb_array_length(q.bloqueos) > 0))::bigint,
         (count(q.id) filter (where q.respuesta is null))::bigint
    from public.bot_temas t
    left join public.bot_consultas q
      on q.creado_en >= now() - make_interval(days => least(greatest(p_dias, 1), 365))
     and q.pregunta ~* t.patron
   where t.activo
   group by t.clave, t.nombre_es, t.nombre_en, t.orden
   order by t.orden nulls last, t.clave;
$fn$;

-- ---------------------------------------------------------------------------
-- 8. Grants. El GRANT manda antes que la policy: se revoca todo lo que
--    Supabase concede por defecto y se concede solo lo que la app usa.
--    Las funciones trigger se cierran a anon/authenticated nombrandolos
--    (la piedra de 20260914092124: `from public` solo no basta).
-- ---------------------------------------------------------------------------
revoke all on public.bot_temas, public.bot_faq, public.bot_respuestas_copiadas from anon, public, authenticated;
grant select                 on public.bot_temas               to authenticated;
grant select, insert, update on public.bot_faq                 to authenticated;
grant select, insert, update on public.bot_respuestas_copiadas to authenticated;
-- hueco heredado de 20260922012840: la policy FOR ALL de super_admin sobre
-- bot_fuentes y bot_bloqueos no valia sin el grant.
grant insert, update on public.bot_fuentes, public.bot_bloqueos to authenticated;
-- service_role (edge) por si las default privileges no lo cubren
grant all on public.bot_temas, public.bot_faq, public.bot_respuestas_copiadas to service_role;

revoke all on function public.bot_temas_resumen(int) from public, anon;
grant  execute on function public.bot_temas_resumen(int) to authenticated, service_role;

revoke all on function public.bot_temas_valida_patron() from public, anon, authenticated;
revoke all on function public.bot_faq_frena()           from public, anon, authenticated;
revoke all on function public.bot_faq_inmutable()       from public, anon, authenticated;
revoke all on function public.bot_copia_frena()         from public, anon, authenticated;
