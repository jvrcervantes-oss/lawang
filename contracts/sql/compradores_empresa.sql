-- ════════════════════════════════════════════════════════════════════════════
-- UN COMPRADOR PUEDE SER UNA EMPRESA — 19-ago-2026, encargo del owner
-- ════════════════════════════════════════════════════════════════════════════
-- EL FALLO QUE LO DESTAPA. Dar de alta la sociedad de un cliente que ya está
-- fichado como persona reventaba con «ese correo ya se ha usado»: `clients`
-- tenía UNIQUE(email), y una persona y su sociedad comparten correo casi
-- siempre. Con lo cual la sociedad no podía existir como ficha, y su único
-- hueco era la sección «El adquiriente firma como sociedad (PT PMA)» del
-- contrato: cuatro campos tecleados a mano, clavados a Indonesia (NIB, NPWP)
-- cuando el comprador puede ser una S.L. española o una LLC americana.
--
-- CÓMO QUEDA. `clients` distingue PERSONA de EMPRESA, y la empresa es un
-- comprador de pleno derecho: se ficha, se enlaza al contrato y el documento
-- imprime sus datos. El párrafo de «Segunda Parte» tiene ahora dos redacciones
-- —persona y sociedad— y la plantilla elige por `adq1_tipo`.
--
-- POR QUÉ NO HAY COLUMNAS NUEVAS PARA EL NIF NI PARA EL PAÍS. Una empresa
-- guarda su identificación fiscal en `passport_number` y su país de
-- constitución en `nationality`, las mismas columnas que la persona. No es
-- pereza: `contrato_identificadores` (LAW-51, y el guardarraíl de recibís del
-- 19-ago) compara identidad con pasaporte + email, y meter el NIF en una
-- columna aparte lo dejaría fuera de esa comparación — dos sociedades
-- distintas con el mismo correo pasarían por la misma. El campo del contrato
-- ya se llama «Nº pasaporte / identificación fiscal» desde el primer día.

alter table public.clients
  add column if not exists tipo            text not null default 'persona',
  add column if not exists forma_juridica  text,
  add column if not exists registro_num    text,
  add column if not exists rep_nombre      text,
  add column if not exists rep_cargo       text;

-- El CHECK va aparte y con nombre: uno anónimo dentro del ADD COLUMN no se
-- puede quitar ni releer por nombre después (lección de contratos_tipo_check).
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.clients'::regclass and conname = 'clients_tipo_check') then
    alter table public.clients
      add constraint clients_tipo_check check (tipo in ('persona','empresa'));
  end if;
end $$;

comment on column public.clients.tipo is
  'persona | empresa. En una empresa: full_name = razon social, passport_number = identificacion fiscal (NIF/CIF/NPWP/EIN), nationality = pais de constitucion, address = domicilio social.';
comment on column public.clients.forma_juridica is 'S.L., LLC, PT PMA, GmbH... texto libre: el comprador puede ser de cualquier pais';
comment on column public.clients.registro_num  is 'Nº de registro mercantil, NIB/OSS en Indonesia, state file number en EE.UU.';

-- ── el correo deja de ser unico A SECAS ─────────────────────────────────────
-- Una persona y su sociedad comparten correo, y eso es normal, no un duplicado.
-- Lo que sigue estando prohibido es que DOS PERSONAS (o dos sociedades) lo
-- compartan, que es lo que el UNIQUE venia a evitar de verdad — de ahi que la
-- clave pase a ser (correo, tipo) y no desaparezca. `lower()` de paso: el
-- UNIQUE viejo distinguia mayusculas, asi que "A@b.com" y "a@b.com" convivian.
alter table public.clients drop constraint if exists clients_email_key;
create unique index if not exists clients_email_tipo_key
  on public.clients (lower(email), tipo) where email is not null;
