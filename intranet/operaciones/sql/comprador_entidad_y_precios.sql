-- Lawang · el comprador pasa a ser entidad + corrección de 4 precios corrompidos
-- 28-jul-2026
--
-- Ejecutar UNA vez, entero y sin seleccionar nada, en Lawang BD:
--   https://supabase.com/dashboard/project/vtulllundrfennhjddhc/sql/new
-- Es idempotente.

-- ═══════════════════════════════════════════════════════════════
-- PARTE 1 · Registro de correcciones de datos
-- ═══════════════════════════════════════════════════════════════
-- Antes de tocar dinero de un contrato firmado se guarda el valor anterior.
-- No es una columna de respaldo en `contratos` (quedaría ahí para siempre sin
-- servir a nadie): es una tabla de rastro, reutilizable la próxima vez.

create table if not exists public.correcciones_datos (
  id             bigint generated always as identity primary key,
  tabla          text not null,
  fila_id        uuid not null,
  campo          text not null,
  valor_anterior text,
  valor_nuevo    text,
  motivo         text,
  corregido_en   timestamptz not null default now(),
  corregido_por  text default auth.email()
);

alter table public.correcciones_datos enable row level security;
drop policy if exists "agentes leen correcciones"  on public.correcciones_datos;
drop policy if exists "agentes crean correcciones" on public.correcciones_datos;
create policy "agentes leen correcciones"  on public.correcciones_datos for select to authenticated using (public.es_agente());
create policy "agentes crean correcciones" on public.correcciones_datos for insert to authenticated with check (public.es_agente());

comment on table public.correcciones_datos is
  'Rastro de correcciones manuales sobre datos ya guardados. Se escribe ANTES de actualizar.';

-- ═══════════════════════════════════════════════════════════════
-- PARTE 2 · Los 4 precios que el bug del separador dejó mal
-- ═══════════════════════════════════════════════════════════════
-- Causa: los campos de dinero eran <input type="number"> (donde el punto ES
-- decimal) y `contractPayload()` reparseaba con un replace que quitaba la coma
-- pero dejaba el punto. "136.215" acabó como 136,215 en la columna.
-- El valor bueno es el del jsonb: es el texto que se imprimió en el PDF que
-- firmó el cliente. Se escriben literales, uno por contrato, a propósito: una
-- consulta genérica sobre toda la tabla podría "arreglar" un decimal legítimo.

insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo)
select 'contratos', c.id, 'precio_total', c.precio_total::text, v.nuevo::text,
       'Separador de miles leido como decimal (input type=number + parseo a mano en contractPayload)'
from public.contratos c
join (values
  ('CG00004', 136215::numeric),
  ('CG00005', 136995::numeric),
  ('RP00007',  80660::numeric),
  ('RP00012',  42215::numeric)
) as v(numero, nuevo) on v.numero = c.numero
where c.precio_total is distinct from v.nuevo          -- si ya se corrigió, no vuelve a registrar
  and not exists (                                      -- ni duplica el rastro
    select 1 from public.correcciones_datos d
    where d.tabla='contratos' and d.fila_id=c.id and d.campo='precio_total'
  );

update public.contratos c
set precio_total = v.nuevo
from (values
  ('CG00004', 136215::numeric),
  ('CG00005', 136995::numeric),
  ('RP00007',  80660::numeric),
  ('RP00012',  42215::numeric)
) as v(numero, nuevo)
where v.numero = c.numero and c.precio_total is distinct from v.nuevo;

-- ═══════════════════════════════════════════════════════════════
-- PARTE 3 · El comprador pasa a ser entidad, con relación N:M
-- ═══════════════════════════════════════════════════════════════
-- Hoy la persona vive dentro de `contratos.datos` y se reteclea en cada
-- documento: 19 contratos para 9 personas. Un cambio de pasaporte obliga a
-- repetirlo N veces y el KYC no se puede enganchar a nada.
--
-- N:M y no `contratos.client_id` porque los contratos a varios nombres ya
-- existen (`datos.compradores[]`, y `contrato_firmas` ya soporta
-- adquiriente_1/2/3). Con una FK simple, el segundo y el tercero se quedarían
-- solo en el jsonb y volveríamos a tener dos sitios para lo mismo.

create table if not exists public.contrato_compradores (
  contrato_id uuid not null references public.contratos(id) on delete cascade,
  client_id   uuid not null references public.clients(id)   on delete restrict,
  rol         text not null default 'adquiriente_1',
  creado_en   timestamptz not null default now(),
  primary key (contrato_id, rol)
);

do $$ begin
  alter table public.contrato_compradores add constraint contrato_compradores_rol_check
    check (rol in ('adquiriente_1','adquiriente_2','adquiriente_3','representante'));
exception when duplicate_object then null; end $$;

create index if not exists contrato_compradores_client_idx on public.contrato_compradores(client_id);

comment on table public.contrato_compradores is
  'Que personas firman que contrato, y con que rol. N:M a proposito: un contrato puede ir a varios nombres y una persona firma varios contratos.';
comment on column public.contrato_compradores.rol is
  'Mismos roles que contrato_firmas, para poder cruzarlos.';

alter table public.contrato_compradores enable row level security;
drop policy if exists "agentes leen contrato_compradores"       on public.contrato_compradores;
drop policy if exists "agentes crean contrato_compradores"      on public.contrato_compradores;
drop policy if exists "agentes actualizan contrato_compradores" on public.contrato_compradores;
drop policy if exists "agentes borran contrato_compradores"     on public.contrato_compradores;
create policy "agentes leen contrato_compradores"       on public.contrato_compradores for select to authenticated using (public.es_agente());
create policy "agentes crean contrato_compradores"      on public.contrato_compradores for insert to authenticated with check (public.es_agente());
create policy "agentes actualizan contrato_compradores" on public.contrato_compradores for update to authenticated using (public.es_agente()) with check (public.es_agente());
create policy "agentes borran contrato_compradores"     on public.contrato_compradores for delete to authenticated using (public.es_agente());

-- Clave de deduplicación: el pasaporte, insensible a mayúsculas y espacios.
-- Sin esto, "PAG123" y "pag123 " serían dos personas y volveríamos al punto de
-- partida. Parcial (`where ... is not null`) porque hay compradores sin
-- pasaporte todavía y no deben bloquearse entre sí.
create unique index if not exists clients_pasaporte_uniq
  on public.clients (lower(btrim(passport_number)))
  where passport_number is not null and btrim(passport_number) <> '';

-- ═══════════════════════════════════════════════════════════════
-- COMPROBACIÓN
-- ═══════════════════════════════════════════════════════════════
select
  (select count(*) from public.correcciones_datos)                              as correcciones_registradas,
  (select count(*) from public.contratos
     where numero in ('CG00004','CG00005','RP00007','RP00012')
       and precio_total in (136215,136995,80660,42215))                         as precios_corregidos,
  to_regclass('public.contrato_compradores')::text                              as tabla_enlace,
  (select count(*) from pg_policies where tablename='contrato_compradores')     as policies_enlace,
  (select count(*) from pg_indexes where indexname='clients_pasaporte_uniq')    as indice_pasaporte;
-- esperado: 4 · 4 · contrato_compradores · 4 · 1
