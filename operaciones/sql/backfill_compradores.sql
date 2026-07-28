-- Lawang · rellenar `clients` y `contrato_compradores` con los contratos que ya existen
-- 28-jul-2026
--
-- Ejecutar UNA vez, entero y sin seleccionar nada, en Lawang BD:
--   https://supabase.com/dashboard/project/vtulllundrfennhjddhc/sql/new
-- Idempotente: correrlo dos veces no duplica personas ni enlaces.
--
-- Sin esto, la alta automática solo funciona hacia adelante y `/compradores/`
-- se queda vacía aunque haya 19 contratos firmados.
--
-- MISMA REGLA QUE EL CÓDIGO: la identidad es el pasaporte normalizado y, si no
-- lo hay, el email. Sin ninguno de los dos NO se crea ficha. Emparejar por
-- nombre parecido es justo como se fabrican los duplicados, y limpiarlos
-- después cuesta más que dejar 5 contratos sin enlazar.
--
-- Alcance medido antes de escribirlo: 19 contratos, 14 enlazables, 8 personas.
-- Los 5 restantes: 4 sin nombre (borradores y una oferta) y CC00004, que tiene
-- "Jose Pedro" sin identificador — probablemente Jose Pedro Oton Urbano, pero
-- eso lo confirma una persona, no una consulta.

-- ── 0. Ampliar los tipos de documento admitidos ───────────────────────
-- El CHECK original solo permitía passport / proof_of_address /
-- signed_contract / other. En Indonesia hacen falta NPWP y visado, y el
-- justificante de fondos es parte del KYC: sin esto, /compradores/ no puede
-- subirlos. Se AMPLÍA la lista, no se sustituye: los valores viejos siguen
-- siendo válidos.
alter table public.documents drop constraint if exists documents_doc_type_check;
alter table public.documents add  constraint documents_doc_type_check
  check (doc_type in ('passport','npwp','visa','proof_of_funds',
                      'proof_of_address','signed_contract','other'));

-- ── 1. La persona de cada contrato, con su clave de identidad ──────────
create temporary table _p on commit drop as
select
  c.id                                                        as contrato_id,
  c.created_at,
  nullif(btrim(c.datos->'fields'->>'adq1_nombre'),'')         as nombre,
  nullif(btrim(c.datos->'fields'->>'adq1_pasaporte'),'')      as pasaporte,
  lower(nullif(btrim(c.datos->'fields'->>'adq1_email'),''))   as email,
  nullif(btrim(c.datos->'fields'->>'adq1_telefono'),'')       as telefono,
  nullif(btrim(c.datos->'fields'->>'adq1_domicilio'),'')      as domicilio,
  nullif(btrim(c.datos->'fields'->>'adq1_nacionalidad'),'')   as nacionalidad
from public.contratos c;

alter table _p add column clave text;
update _p set clave = coalesce(lower(btrim(pasaporte)), email);
delete from _p where clave is null or nombre is null;

-- ── 2. Una fila por persona: la del contrato MÁS RECIENTE ──────────────
-- Los datos de contacto cambian; el último contrato es el más fiable.
create temporary table _persona on commit drop as
select distinct on (clave)
  clave, nombre, pasaporte, email, telefono, domicilio, nacionalidad
from _p
order by clave, created_at desc;

-- ── 3. Alta de las que no existen todavía ──────────────────────────────
insert into public.clients (full_name, email, phone, nationality, passport_number, address, kyc_status)
select p.nombre, p.email, p.telefono, p.nacionalidad, p.pasaporte, p.domicilio, 'pending'
from _persona p
where not exists (
  select 1 from public.clients c
  where (p.pasaporte is not null and lower(btrim(c.passport_number)) = lower(btrim(p.pasaporte)))
     or (p.pasaporte is null and p.email is not null and lower(btrim(c.email)) = p.email)
);

-- ── 4. Enlace contrato ↔ persona ───────────────────────────────────────
insert into public.contrato_compradores (contrato_id, client_id, rol)
select p.contrato_id, c.id, 'adquiriente_1'
from _p p
join public.clients c
  on (p.pasaporte is not null and lower(btrim(c.passport_number)) = lower(btrim(p.pasaporte)))
  or (p.pasaporte is null and p.email is not null and lower(btrim(c.email)) = p.email)
on conflict (contrato_id, rol) do nothing;

-- ── COMPROBACIÓN ───────────────────────────────────────────────────────
select
  (select count(*) from public.clients)                               as personas,
  (select count(*) from public.contrato_compradores)                  as enlaces,
  (select count(*) from public.contratos)                             as contratos,
  (select count(*) from public.contratos c
     where not exists (select 1 from public.contrato_compradores x where x.contrato_id = c.id))
                                                                      as contratos_sin_enlazar;
-- esperado: 8 personas · 14 enlaces · 19 contratos · 5 sin enlazar
