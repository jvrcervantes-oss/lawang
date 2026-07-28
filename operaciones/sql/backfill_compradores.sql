-- Lawang · rellenar `clients` y `contrato_compradores` desde los contratos existentes
-- 28-jul-2026 · v2 (sin tablas temporales)
--
-- Ejecutar en Lawang BD:
--   https://supabase.com/dashboard/project/vtulllundrfennhjddhc/sql/new
-- Idempotente: correrlo dos veces no duplica personas ni enlaces.
--
-- ⚠️ POR QUÉ NO HAY TABLAS TEMPORALES (la v1 no llegó a hacer nada):
-- llevaba `create temporary table ... on commit drop`, y el editor de Supabase
-- ejecuta cada sentencia en su propia transacción: la tabla se destruía justo
-- después de crearse y los inserts siguientes no encontraban nada. El
-- constraint de la parte 0 sí se aplicó, así que el fallo pasó desapercibido y
-- solo se vio al contar filas después. Con CTEs cada sentencia se basta a sí
-- misma. Bonus: ya no salta el aviso de "Run without RLS".
--
-- MISMA REGLA QUE EL CÓDIGO: la identidad es el pasaporte normalizado y, si no
-- lo hay, el email. Sin ninguno de los dos NO se crea ficha: emparejar por
-- nombre parecido es como se fabrican los duplicados.
--
-- Alcance medido: 19 contratos, 14 enlazables, 8 personas. Los 5 restantes son
-- 4 sin nombre (borradores y una oferta comercial) y CC00004, con "Jose Pedro"
-- sin identificador — probablemente Jose Pedro Oton Urbano, pero eso lo
-- confirma una persona, no una consulta.

-- ── 0. Ajustes de esquema previos ─────────────────────────────────────
-- (a) Tipos de documento: el CHECK original no admitía NPWP ni visado, que en
--     Indonesia hacen falta. Se AMPLÍA, no se sustituye.
alter table public.documents drop constraint if exists documents_doc_type_check;
alter table public.documents add  constraint documents_doc_type_check
  check (doc_type in ('passport','npwp','visa','proof_of_funds',
                      'proof_of_address','signed_contract','other'));

-- (b) `clients.email` era NOT NULL. Un comprador identificado por PASAPORTE y
--     sin email es legítimo y existe de verdad: Jose Luis Pinilla Rocha
--     (PAW317343) no tiene email en ningún contrato. Con la columna obligatoria
--     habría que inventarle uno, y un email inventado en la ficha de un cliente
--     acaba recibiendo un correo real algún día.
--     Relajar un NOT NULL no destruye datos: las filas que ya tienen email
--     siguen igual. El nombre sí sigue siendo obligatorio.
alter table public.clients alter column email drop not null;

-- ── 1. Alta de las personas que faltan ────────────────────────────────
with p as (
  select c.id as contrato_id, c.created_at,
         nullif(btrim(c.datos->'fields'->>'adq1_nombre'),'')       as nombre,
         nullif(btrim(c.datos->'fields'->>'adq1_pasaporte'),'')    as pasaporte,
         lower(nullif(btrim(c.datos->'fields'->>'adq1_email'),'')) as email,
         nullif(btrim(c.datos->'fields'->>'adq1_telefono'),'')     as telefono,
         nullif(btrim(c.datos->'fields'->>'adq1_domicilio'),'')    as domicilio,
         nullif(btrim(c.datos->'fields'->>'adq1_nacionalidad'),'') as nacionalidad
  from public.contratos c
),
q as (
  select p.*, coalesce(lower(btrim(p.pasaporte)), p.email) as clave
  from p
  where p.nombre is not null
    and coalesce(lower(btrim(p.pasaporte)), p.email) is not null
),
-- una fila por persona: la del contrato MÁS RECIENTE, que es el dato de
-- contacto más fiable
persona as (
  select distinct on (clave) clave, nombre, pasaporte, email, telefono, domicilio, nacionalidad
  from q
  order by clave, created_at desc
)
insert into public.clients (full_name, email, phone, nationality, passport_number, address, kyc_status)
select pe.nombre, pe.email, pe.telefono, pe.nacionalidad, pe.pasaporte, pe.domicilio, 'pending'
from persona pe
where not exists (
  select 1 from public.clients c
  where (pe.pasaporte is not null and lower(btrim(c.passport_number)) = lower(btrim(pe.pasaporte)))
     or (pe.pasaporte is null and pe.email is not null and lower(btrim(c.email)) = pe.email)
);

-- ── 2. Enlace contrato ↔ persona ──────────────────────────────────────
with p as (
  select c.id as contrato_id,
         nullif(btrim(c.datos->'fields'->>'adq1_nombre'),'')       as nombre,
         nullif(btrim(c.datos->'fields'->>'adq1_pasaporte'),'')    as pasaporte,
         lower(nullif(btrim(c.datos->'fields'->>'adq1_email'),'')) as email
  from public.contratos c
)
insert into public.contrato_compradores (contrato_id, client_id, rol)
select p.contrato_id, c.id, 'adquiriente_1'
from p
join public.clients c
  on (p.pasaporte is not null and lower(btrim(c.passport_number)) = lower(btrim(p.pasaporte)))
  or (p.pasaporte is null and p.email is not null and lower(btrim(c.email)) = p.email)
where p.nombre is not null
on conflict (contrato_id, rol) do nothing;

-- ── COMPROBACIÓN ──────────────────────────────────────────────────────
select
  (select count(*) from public.clients)              as personas,
  (select count(*) from public.contrato_compradores) as enlaces,
  (select count(*) from public.contratos)            as contratos,
  (select count(*) from public.contratos c
     where not exists (select 1 from public.contrato_compradores x where x.contrato_id = c.id))
                                                     as contratos_sin_enlazar;
-- esperado: 8 · 14 · 19 · 5
