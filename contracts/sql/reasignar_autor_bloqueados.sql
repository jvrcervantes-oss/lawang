-- ═══════════════════════════════════════════════════════════════════════
-- OPCIONAL, SIN APLICAR — 30-jul-2026
-- Permitir al super_admin reasignar el AUTOR de un documento ya cerrado
-- (contrato bloqueado o factura anulada).
--
-- Por qué no está aplicado: las policies actuales exigen `bloqueado = false`
-- y `anulada = false`, y esa condición es la que hace inmutable un documento
-- firmado. Ampliarla es una decisión del dueño, no una corrección técnica:
-- abre la puerta a modificar filas que hoy no se pueden tocar.
--
-- Lo que SÍ funciona sin esto: reasignar el autor de cualquier contrato no
-- bloqueado y de cualquier factura no anulada. El panel lo dice cuando no
-- puede, en vez de ofrecer un botón que la RLS rechaza.
--
-- Alcance de estas policies: SOLO la columna `creado_por`. Postgres no filtra
-- columnas en una policy, así que la restricción se impone con un trigger que
-- rechaza cualquier update que cambie otra cosa. Sin ese trigger, "reasignar
-- el autor" sería en realidad "editar un contrato firmado", que es lo que
-- estamos protegiendo.
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u
                  where u.user_id = (select auth.uid()) and u.activo and u.rol = 'super_admin')
$$;

revoke execute on function public.es_super_admin() from public;
grant  execute on function public.es_super_admin() to authenticated, service_role;

-- Trigger compartido: en una fila cerrada, lo único que puede cambiar es el autor.
create or replace function public.solo_cambia_autor()
returns trigger language plpgsql set search_path = '' as $$
begin
  if to_jsonb(new) - 'creado_por' <> to_jsonb(old) - 'creado_por' then
    raise exception 'En un documento cerrado solo se puede cambiar creado_por';
  end if;
  return new;
end
$$;

-- ── contratos bloqueados ────────────────────────────────────────────────
create policy "el super_admin reasigna el autor de un contrato bloqueado"
  on public.contratos for update to authenticated
  using (bloqueado = true and public.es_super_admin())
  with check (bloqueado = true and public.es_super_admin());

create trigger contratos_bloqueado_solo_autor
  before update on public.contratos
  for each row when (old.bloqueado = true)
  execute function public.solo_cambia_autor();

-- ── facturas anuladas ───────────────────────────────────────────────────
create policy "el super_admin reasigna el autor de una factura anulada"
  on public.facturas for update to authenticated
  using (anulada = true and public.es_super_admin())
  with check (anulada = true and public.es_super_admin());

create trigger facturas_anulada_solo_autor
  before update on public.facturas
  for each row when (old.anulada = true)
  execute function public.solo_cambia_autor();

-- ── Cómo comprobar que hace lo que dice, con una fila real ──────────────
-- 1) como super_admin, update de `creado_por` en un contrato bloqueado → 1 fila
-- 2) el mismo update tocando además `precio_total`                     → excepción del trigger
-- 3) como agente, el update del paso 1                                 → 0 filas (la RLS no deja)
-- El rastro de los tres intentos queda en `correcciones_datos` porque la app
-- escribe la traza ANTES de tocar la tabla, y anula la traza si el update falla.
