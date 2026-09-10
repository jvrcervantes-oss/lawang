-- Kanban de leads (9-sep-2026). Revision previa con Datos y Diseño antes de escribir nada.

-- ── Por que el estado NO va en `leads` ────────────────────────────────────────────────
-- R13 (`_vigila_leads`) hace un upsert sobre `leads` cada 4h con merge-duplicates, y
-- PostgREST compone la parte de actualizacion de ese upsert **con las claves presentes en
-- el payload**. Hoy el estado sobreviviria porque esas claves no estan en el dict -- pero
-- por casualidad de forma, no por diseño: basta con que alguien las meta al reutilizar una
-- plantilla de fila para que cada pasada resetee los 101 leads EN SILENCIO, y el estado
-- comercial no se puede reconstruir de ninguna otra fuente (hallazgo de Datos). El dueño
-- del estado es la persona que trabaja el lead; el de `leads`, la recogida automatica.
-- Dos dueños, dos tablas.
create table if not exists public.lead_estado (
    lead_id       uuid primary key references public.leads(id) on delete cascade,
    estado        text not null default 'nuevo'
                  check (estado in ('nuevo','contactado','visita','reserva','contrato','perdido')),
    responsable   text,
    -- Sirve para dos cosas a la vez: pintar la antiguedad en la tarjeta (Diseño: con 97
    -- tarjetas, abrir cada una para ver cual lleva 3 semanas parada no es "de un vistazo")
    -- y como testigo de concurrencia -- el cambio solo se aplica si sigue valiendo lo que
    -- vio el operador, asi el segundo recibe un 409 en vez de pisar al primero sin enterarse.
    estado_desde  timestamptz not null default now(),
    actualizado   timestamptz not null default now()
);

-- Append-only: quien movio que y cuando. Aunque la concurrencia se previniera del todo,
-- sin rastro no se puede reconstruir un movimiento discutido.
create table if not exists public.lead_estado_log (
    id        bigserial primary key,
    lead_id   uuid not null,
    de        text,
    a         text not null,
    autor     text,
    cuando    timestamptz not null default now()
);
create index if not exists lead_estado_log_lead on public.lead_estado_log (lead_id, cuando desc);

-- Una nota no se sobrescribe nunca: es el historial de la conversacion comercial.
create table if not exists public.lead_notas (
    id         bigserial primary key,
    lead_id    uuid not null references public.leads(id) on delete cascade,
    texto      text not null,
    autor      text,
    created_at timestamptz not null default now()
);
create index if not exists lead_notas_lead on public.lead_notas (lead_id, created_at desc);

-- ── Que tipo de contrato corresponde a que columna ───────────────────────────────────
-- Es una TABLA y no una lista dentro del codigo a proposito. Hay once tipos de contrato
-- vivos, y `coherencia.py` ya avisa en cada arranque (LAW-48) de que al alta de un tipo
-- "le faltan sitios": una lista escrita a mano dentro de la logica dejaria un tipo nuevo
-- fuera del tablero sin que nadie se entere. Asi, un tipo sin fila aqui sale como
-- «tipo sin etapa» y obliga a decidir, que es justo lo que debe pasar.
create table if not exists public.contrato_tipo_etapa (
    tipo  text primary key,
    etapa text not null check (etapa in ('reserva','contrato','ninguna')),
    nota  text
);
insert into public.contrato_tipo_etapa (tipo, etapa, nota) values
    ('reserva_parcela',        'reserva',  'Reserva de parcela'),
    ('carta_reserva',          'reserva',  'Carta de Reserva (serie CR)'),
    ('carta_reserva_pma',      'reserva',  'Carta Condicionada via PT PMA (serie CP)'),
    ('carta_reserva_hak_sewa', 'reserva',  'Carta de Reserva sobre hak sewa (serie CH)'),
    ('construccion',           'contrato', 'Contrato de construccion'),
    ('hak_sewa_notario',       'contrato', 'Hak Sewa ante notario'),
    ('ppjb_bonian_c2',         'contrato', 'PPJB'),
    ('contrato_general',       'contrato', 'Contrato general'),
    ('cc00014_timon',          'contrato', 'Contrato de compra (ejemplar propio)'),
    ('poa',                    'ninguna',  'Poder: no es una etapa de la venta'),
    ('commercial_offer',       'ninguna',  'Oferta comercial: no compromete a nadie')
on conflict (tipo) do nothing;

-- ── La SUGERENCIA, que no mueve nada sola ────────────────────────────────────────────
-- Datos tumbo la idea de que estas dos columnas se rellenaran solas, y con un caso real de
-- hoy mismo: en LAW-133 el comprador constituye una PT PMA y es esta la que compra, asi que
-- su email personal NO cruza con el contrato. Un comprador de verdad se habria quedado mudo
-- en «Nuevo» para siempre, en una columna que nadie revisa porque "se rellena sola". Y al
-- reves, dos personas de una familia comparten email y una saldria como que ya compro.
-- Asi que esto SUGIERE y una persona confirma con un clic. Sigue sin haber que teclearlo.
create or replace view public.lead_sugerencia as
select l.id as lead_id,
       case when bool_or(e.etapa = 'contrato') then 'contrato'
            when bool_or(e.etapa = 'reserva')  then 'reserva' end as etapa,
       min(c.numero) as contrato_numero
from public.leads l
join public.contratos c on c.fecha_firma is not null
join lateral unnest(public.contrato_identificadores(c.datos)) as ident on true
join public.contrato_tipo_etapa e on e.tipo = c.tipo and e.etapa <> 'ninguna'
where nullif(trim(l.email), '') is not null
  and lower(trim(ident)) = lower(trim(l.email))
group by l.id;

-- Las cuatro tablas viven detras del panel, que entra con la service key. Ningun anonimo
-- tiene que poder leerlas: RLS activa y CERO policies = solo service_role.
alter table public.lead_estado     enable row level security;
alter table public.lead_estado_log enable row level security;
alter table public.lead_notas      enable row level security;
alter table public.contrato_tipo_etapa enable row level security;;
