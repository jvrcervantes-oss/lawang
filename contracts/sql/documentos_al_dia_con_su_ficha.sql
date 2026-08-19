-- ════════════════════════════════════════════════════════════════════════════
-- UN DOCUMENTO VIVO NO PUEDE CONTRADECIR A SU FICHA — 19-ago-2026
-- ════════════════════════════════════════════════════════════════════════════
-- EL CASO (owner): corrige la ficha de CSP CONCEPTS —el NIF estaba en el campo
-- del domicilio— y la factura INV00037 sigue diciendo lo de antes. Y el
-- contrato RP00044 también. La cadena **ficha → contrato → factura viaja por
-- COPIA**, y nadie vuelve atrás: corregir el origen no arregla lo que ya salió.
--
-- LA DECISIÓN DEL OWNER, y ordena todo lo demás:
--   · Documento VIVO      → sigue a la ficha (se avisa y se traen los datos).
--   · Documento CONGELADO → no se toca NUNCA. Corregirlo es reemitirlo.
-- Vivo/congelado no es un campo nuevo: es lo que cada documento ya dice de sí
-- mismo — un contrato `bloqueado` está firmado; una factura `enviada` está en
-- manos del cliente; una `anulada` es historia.
--
-- ⚠️ `facturas.client_id` va ADEMÁS de `contrato_id`, nunca en su lugar (aviso
-- del owner): los hitos, los vencimientos, `contrato_cobrado`, la facturación
-- automática y el avance de unidades cuelgan del CONTRATO. Aquí solo se añade
-- de QUIÉN es la factura, que hoy no se sabe más que por el texto copiado.

alter table public.facturas
  add column if not exists client_id uuid references public.clients(id);
create index if not exists facturas_client_idx on public.facturas (client_id);

comment on column public.facturas.client_id is
  'Ficha del cliente facturado. ADEMAS de contrato_id, no en su lugar: los hitos y vencimientos cuelgan del contrato. Sirve para saber si los datos impresos siguen siendo los de la ficha.';

-- ── el criterio de "esto ya no coincide", UNA sola vez ──────────────────────
-- Compara ignorando mayúsculas y puntuación, igual que `clave()` en app.html:
-- `+34 600 11 22 33` y `34600112233` son el mismo teléfono, no una divergencia.
-- Y solo mira los campos que la FICHA tiene rellenos: que la ficha no sepa el
-- domicilio no convierte al documento en incorrecto.
create or replace function public.diferencias_con_ficha(p_doc jsonb, p_ficha jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(jsonb_build_object('campo', k, 'documento', coalesce(d,''), 'ficha', f)
                            order by k), '[]'::jsonb)
    from (
      select k,
             nullif(btrim(p_doc->>k), '')   as d,
             nullif(btrim(p_ficha->>k), '') as f
        from jsonb_object_keys(p_ficha) k
    ) t
   where f is not null
     and lower(regexp_replace(coalesce(d,''), '[^a-z0-9@.]', '', 'gi'))
      is distinct from lower(regexp_replace(f, '[^a-z0-9@.]', '', 'gi'));
$$;

-- ── qué documentos están desactualizados, sin abrirlos uno a uno ────────────
-- Hasta hoy la única forma de enterarse era abrir el documento y esperar a que
-- saltara el aviso (y solo existía en Contratos). Esto lo pone en una consulta
-- que puede leer cualquier herramienta y un panel.
create or replace view public.documentos_desactualizados as
select 'contrato'::text as tipo, c.id, c.numero,
       coalesce(c.bloqueado, false) as congelado,
       cl.id as client_id, cl.full_name as ficha,
       public.diferencias_con_ficha(
         jsonb_build_object(
           'nombre',      c.datos->'fields'->>'adq1_nombre',
           'identidad',   c.datos->'fields'->>'adq1_pasaporte',
           'email',       c.datos->'fields'->>'adq1_email',
           'telefono',    c.datos->'fields'->>'adq1_telefono',
           'domicilio',   c.datos->'fields'->>'adq1_domicilio',
           'pais',        c.datos->'fields'->>'adq1_nacionalidad'),
         jsonb_build_object(
           'nombre', cl.full_name, 'identidad', cl.passport_number, 'email', cl.email,
           'telefono', cl.phone, 'domicilio', cl.address, 'pais', cl.nationality)
       ) as diferencias
  from public.contratos c
  join public.clients cl on cl.id = (c.datos->>'adq1_client_id')::uuid
union all
select 'factura', f.id, f.numero,
       coalesce(f.anulada, false) or coalesce(f.enviada, false) as congelado,
       cl.id, cl.full_name,
       public.diferencias_con_ficha(
         jsonb_build_object(
           'nombre',    f.cliente_nombre,
           'identidad', f.datos->'fields'->>'cliente_documento',
           'email',     f.datos->'fields'->>'cliente_email',
           'domicilio', f.datos->'fields'->>'cliente_domicilio'),
         jsonb_build_object(
           'nombre', cl.full_name, 'identidad', cl.passport_number,
           'email', cl.email, 'domicilio', cl.address)
       )
  from public.facturas f
  join public.clients cl on cl.id = f.client_id;

alter view public.documentos_desactualizados set (security_invoker = true);
grant select on public.documentos_desactualizados to authenticated;
