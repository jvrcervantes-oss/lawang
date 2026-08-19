-- ════════════════════════════════════════════════════════════════════════════
-- PASO 2 · EL COMPRADOR SE LEE DE SU FICHA, AL MOMENTO — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- Decisión del owner: «Compradores manda; si corrijo un cliente, toda la suite
-- se actualiza al momento, ni siquiera preguntar». Mismo patrón que el paso 1
-- con los proyectos (ENLACE + ESPEJO), aplicado a la identidad del comprador.
--
-- CÓMO ESTABA. El contrato guardaba una COPIA de los datos del cliente en
-- `datos.fields.adq1_*`. Corregir la ficha no llegaba a ningún sitio: había que
-- abrir el documento y aceptar un aviso. De ahí el caso que lo destapó —CSP
-- CONCEPTS con el NIF corregido y la factura INV00037 diciendo lo de antes—.
--
-- CÓMO QUEDA. Dos espejos encadenados, cada uno de un salto:
--     ficha  →  contrato VIVO  →  factura VIVA
-- Cada guardado reescribe la copia desde su fuente, y corregir la ficha empuja
-- el cambio a todos los documentos vivos que cuelgan de ella.
--
-- ⚠️ VIVO Y SOLO VIVO. Un contrato `bloqueado` o con firmas en curso, y una
-- factura `enviada` o `anulada`, NO se tocan jamás: ese papel ya está en manos
-- de alguien. Para esos sigue el aviso «Ficha ≠», que es su sitio.
--
-- ⚠️ LÍMITE CONOCIDO Y DELIBERADO: la factura solo se refleja cuando su
-- contrato tiene UN comprador con ficha. Con varios, su etiqueta es compuesta
-- («A · B», y «A: P1 · B: P2» en los documentos) y esa composición la define
-- `contracts/assets/compradores.js`. Rehacerla aquí en SQL sería una SEGUNDA
-- definición de «quién compra», que es justo el fallo que este trabajo persigue.
-- Esas facturas se quedan con el aviso «Ficha ≠» hasta que la composición suba
-- a la base o baje una función común.

-- ── de la ficha al contrato ────────────────────────────────────────────────
create or replace function public.espeja_comprador(p_datos jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  -- Devuelve `datos` con los campos del Adquiriente I reescritos desde su ficha.
  -- Si no hay enlace, se devuelve tal cual: no se inventa nada.
  select case
    when cl.id is null then p_datos
    else jsonb_set(p_datos, '{fields}',
           coalesce(p_datos->'fields', '{}'::jsonb) ||
           jsonb_strip_nulls(jsonb_build_object(
             'adq1_nombre',         cl.full_name,
             'adq1_pasaporte',      cl.passport_number,
             'adq1_email',          cl.email,
             'adq1_telefono',       cl.phone,
             'adq1_domicilio',      cl.address,
             'adq1_nacionalidad',   cl.nationality,
             'adq1_forma_juridica', cl.forma_juridica,
             'adq1_registro',       cl.registro_num,
             'adq1_rep_nombre',     cl.rep_nombre,
             'adq1_rep_cargo',      cl.rep_cargo,
             'adq1_tipo',           cl.tipo)))
  end
  from (select 1) x
  left join public.clients cl on cl.id = nullif(p_datos->>'adq1_client_id','')::uuid;
$$;

revoke all on function public.espeja_comprador(jsonb) from public, anon, authenticated;

create or replace function public.trg_espejo_comprador()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- congelado: ni se mira
  if coalesce(new.bloqueado, false) then return new; end if;
  if exists (select 1 from public.contrato_firmas cf where cf.contrato_id = new.id) then return new; end if;
  new.datos := public.espeja_comprador(new.datos);
  return new;
end $$;

revoke all on function public.trg_espejo_comprador() from public, anon, authenticated;

drop trigger if exists trg_espejo_comprador on public.contratos;
create trigger trg_espejo_comprador before insert or update of datos on public.contratos
  for each row execute function public.trg_espejo_comprador();

-- ── corregir la ficha empuja a todos los documentos vivos ──────────────────
create or replace function public.trg_cliente_actualizado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.full_name is not distinct from old.full_name
     and new.passport_number is not distinct from old.passport_number
     and new.email          is not distinct from old.email
     and new.phone          is not distinct from old.phone
     and new.address        is not distinct from old.address
     and new.nationality    is not distinct from old.nationality
     and new.forma_juridica is not distinct from old.forma_juridica
     and new.registro_num   is not distinct from old.registro_num
     and new.rep_nombre     is not distinct from old.rep_nombre
     and new.rep_cargo      is not distinct from old.rep_cargo
     and new.tipo           is not distinct from old.tipo then
    return new;   -- no ha cambiado nada que se imprima
  end if;

  -- contratos VIVOS enlazados a esta ficha
  update public.contratos c
     set datos = public.espeja_comprador(c.datos),
         comprador_nombre = case
           when jsonb_typeof(c.datos->'compradores') = 'array'
                and jsonb_array_length(c.datos->'compradores') > 0
             then c.comprador_nombre          -- varios: la etiqueta la compone la app
           else new.full_name end
   where (c.datos->>'adq1_client_id')::uuid = new.id
     and not coalesce(c.bloqueado, false)
     and not exists (select 1 from public.contrato_firmas cf where cf.contrato_id = c.id);

  -- facturas VIVAS de un contrato con UN solo comprador (ver el límite arriba)
  update public.facturas f
     set cliente_nombre = new.full_name,
         datos = jsonb_set(f.datos, '{fields}',
                   coalesce(f.datos->'fields','{}'::jsonb) ||
                   jsonb_strip_nulls(jsonb_build_object(
                     'cliente_nombre',    new.full_name,
                     'cliente_documento', new.passport_number,
                     'cliente_email',     new.email,
                     'cliente_domicilio', new.address)))
   where f.client_id = new.id
     and not coalesce(f.anulada, false) and not coalesce(f.enviada, false)
     and coalesce(f.cliente_nombre,'') not like '%' || chr(183) || '%'
     and not exists (
       select 1 from public.contratos c
        where c.id = f.contrato_id
          and jsonb_typeof(c.datos->'compradores') = 'array'
          and jsonb_array_length(c.datos->'compradores') > 0);

  return new;
end $$;

revoke all on function public.trg_cliente_actualizado() from public, anon, authenticated;

drop trigger if exists trg_cliente_actualizado on public.clients;
create trigger trg_cliente_actualizado after update on public.clients
  for each row execute function public.trg_cliente_actualizado();

-- ── probado y aplicado el 19-ago-2026 ──────────────────────────────────────
-- Prueba en un `DO` revertido, corrigiendo la ficha como lo haría el owner
-- desde Compradores y sin tocar ningún documento:
--     RP00044  (vivo)    990 BISCAYNE BLVD…  →  EIN 82-1751107 (CORREGIDO)  ✅
--     INV00037 (viva)    EIN 82 1751107      →  EIN 82-1751107 (CORREGIDO)  ✅
--     CR00035  (FIRMADO) ABJ ASENATH…        →  sin cambios                 ✅
--
-- Puesta al día de lo que ya existía (mantenimiento, con
-- `session_replication_role = replica`): de las 11 divergencias que detectaba
-- `documentos_desactualizados` quedan 3, y las 3 son correctas:
--   · PRO00001 y PRO00023 → CONGELADAS. No se tocan; se reemiten si importa.
--   · PRO00002 → su contrato tiene DOS compradores, así que cae en el límite
--     documentado arriba. Se queda con el aviso «Ficha ≠».
--
-- Entre lo arreglado: REC00002 y REC00003, que iban a `cginer@gruposantagema.com`
-- cuando la ficha dice `jcginer@` — dos recibís emitidos a un buzón que no
-- existe. Ese era el caso CR00025 repitiéndose, y ahora no puede repetirse.
