-- ═══════════════════════════════════════════════════════════════════════════
-- QUÉ CUENTA SE OFRECE EN CADA PLANTILLA — sale del JS y pasa a ser un dato
-- 14-sep-2026, encargo del owner: «tenemos muchas cuentas bancarias y no son
-- editables ni marcables lo que quiero que aparezca en cada una».
--
-- Hasta hoy eso vivía en CUATRO listas escritas a mano en JavaScript
-- (BANCO_UNICO, BANCOS_CONSTRUCCION, BANCOS_CC00014_TIMON en
-- assets/entidades_pago.js, y CUENTA_DEFAULT en contracts/app.html). Cambiar
-- qué cuenta cobra la Carta de Reserva exigía un despliegue. Y este repo ya
-- tiene escrito que una lista a mano ES el bug.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. La cuenta sabe SOLA si es escrow ──────────────────────────────────────
-- `tablaCuentaHTML` decidía si imprimir la declaración «depósito en garantía»
-- mirando si la clave empieza por `notario_`. Esa convención se sostenía
-- mientras las cuentas las creaba alguien escribiendo SQL a mano. En cuanto una
-- persona puede crearlas desde un panel, el prefijo deja de estar garantizado —
-- y el fallo silencioso es una cláusula de escrow que no sale, o que sale donde
-- nadie la pactó.
alter table public.cuentas_bancarias
  add column if not exists es_escrow       boolean     not null default false,
  add column if not exists actualizado_en  timestamptz,
  -- lo pone el trigger desde auth.uid(): si lo mandara el cliente, mentiría
  add column if not exists actualizado_por uuid;

update public.cuentas_bancarias set es_escrow = true where left(clave, 8) = 'notario_';

-- ── 2. Catálogo de plantillas que cobran ─────────────────────────────────────
-- Son las que traen <!--datos-bancarios--> (o su variante sin título) y por
-- tanto pintan un selector de cuenta. Tabla y no lista en JS: el panel necesita
-- saber qué plantillas existen, y una segunda lista a mano en la herramienta
-- nueva sería repetir exactamente lo que esta migración viene a quitar.
create table if not exists public.plantillas_pago (
  slug       text primary key,
  nombre     text not null,
  orden      int  not null default 100,
  creado_en  timestamptz not null default now()
);

-- ── 3. El mapeo: qué cuentas se ofrecen en cada plantilla, y cuál precargada ──
create table if not exists public.plantilla_cuentas (
  slug            text not null references public.plantillas_pago(slug)  on update cascade on delete cascade,
  -- ON UPDATE CASCADE por si algún día se renombra una clave; ON DELETE
  -- RESTRICT porque una cuenta NO se borra (se desactiva con activa=false):
  -- su clave va guardada dentro de cada contrato ya emitido.
  clave           text not null references public.cuentas_bancarias(clave) on update cascade on delete restrict,
  es_default      boolean not null default false,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid,
  primary key (slug, clave)
);

-- Un solo default por plantilla, con TRIGGER y no con índice único parcial:
-- un `unique … where` no sirve para `ON CONFLICT` (error 42P10), y el panel
-- guarda con upsert. Además así marcar el nuevo default desmarca el anterior
-- solo, en vez de fallar y obligar al panel a mandar dos sentencias en orden.
create or replace function public.un_solo_default_por_plantilla()
returns trigger language plpgsql security invoker as $$
begin
  if new.es_default then
    update public.plantilla_cuentas
       set es_default = false
     where slug = new.slug and clave <> new.clave and es_default;
  end if;
  new.actualizado_en  := now();
  new.actualizado_por := auth.uid();
  return new;
end $$;

create trigger trg_un_solo_default
  before insert or update on public.plantilla_cuentas
  for each row execute function public.un_solo_default_por_plantilla();

-- Misma firma de autoría en las cuentas: la pone la base, no la pantalla.
create or replace function public.sella_cuenta_bancaria()
returns trigger language plpgsql security invoker as $$
begin
  new.actualizado_en  := now();
  new.actualizado_por := auth.uid();
  return new;
end $$;

create trigger trg_sella_cuenta
  before insert or update on public.cuentas_bancarias
  for each row execute function public.sella_cuenta_bancaria();

-- ── 4. RLS ───────────────────────────────────────────────────────────────────
-- Leer: cualquier sesión del equipo, igual que las cuentas (el generador de
-- contratos necesita el mapeo para pintar su selector).
-- Escribir: SOLO el super admin. Ni un admin normal decide adónde va el dinero.
alter table public.plantillas_pago   enable row level security;
alter table public.plantilla_cuentas enable row level security;

create policy "plantillas de pago: solo con sesion"
  on public.plantillas_pago for select to authenticated using (true);

create policy "plantillas de pago: solo super admin escribe"
  on public.plantillas_pago for all to authenticated
  using (es_super_admin()) with check (es_super_admin());

create policy "mapeo cuentas: solo con sesion"
  on public.plantilla_cuentas for select to authenticated using (true);

create policy "mapeo cuentas: solo super admin escribe"
  on public.plantilla_cuentas for all to authenticated
  using (es_super_admin()) with check (es_super_admin());

-- `cuentas_bancarias` tenía SELECT y NADA más: se editaba por SQL. Ahora el
-- super admin puede darlas de alta y corregirlas desde el panel.
-- Sin política de DELETE a propósito: una cuenta referenciada por contratos
-- emitidos no se borra, se desactiva.
create policy "cuentas: solo super admin crea"
  on public.cuentas_bancarias for insert to authenticated with check (es_super_admin());

create policy "cuentas: solo super admin edita"
  on public.cuentas_bancarias for update to authenticated
  using (es_super_admin()) with check (es_super_admin());;
