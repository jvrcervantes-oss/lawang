-- LAW-71, cierre — 21-ago-2026, decisión del owner: «solo super admin».
--
-- Qué faltaba. Reasignar el autor de un CONTRATO ya funcionaba: la policy de
-- `contratos` lleva `es_super_admin()` desde LAW-71 y eso se salta el
-- `bloqueado = false`. En `facturas` no: `anulada = false` lo bloquea todo, así
-- que una factura anulada no la puede tocar nadie — ni para corregir a quién
-- se le atribuye.
--
-- Por qué el permiso es MÁS ESTRECHO que en contratos. En un contrato firmado el
-- super admin puede editar de verdad, y está bien: cada edición deja evento y el
-- documento que vale es el PDF firmado, que no se toca. Una factura anulada es
-- otra cosa: su número y sus importes son a lo que apunta la que la reemplazó.
-- Cambiarlos rompería la cadena contable en silencio. Así que aquí el poder es
-- uno solo — reasignar el autor — y lo impone un trigger, porque Postgres no
-- sabe limitar una policy a UNA columna. Sin ese trigger, «reasignar el autor»
-- sería en realidad «editar una factura anulada».
--
-- El rastro no es opcional: `assets/autoria.js` escribe primero en
-- `correcciones_datos` (autor viejo, autor nuevo y MOTIVO) y solo entonces
-- actualiza. Si el rastro falla, no cambia nada.

drop policy if exists "el autor o un admin editan facturas no anuladas" on public.facturas;
create policy "el autor o un admin editan facturas no anuladas" on public.facturas
  for update to authenticated
  using (
    public.es_super_admin()
    or (anulada = false and public.es_agente() and public.puede('facturas') and public.es_suyo(creado_por))
  )
  with check (
    public.es_super_admin()
    or (public.es_agente() and public.puede('facturas'))
  );

create or replace function public.factura_anulada_solo_cambia_autor()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Sin sesión no hay JWT: es mantenimiento (MCP, cron, service_role), no la
  -- pantalla. Ahí no se aplica — si no, un backfill legítimo sobre una columna
  -- nueva chocaría contra esto y el síntoma no señalaría la causa.
  if (select auth.uid()) is null then
    return new;
  end if;
  if coalesce(old.anulada, false)
     and (to_jsonb(new) - 'creado_por') is distinct from (to_jsonb(old) - 'creado_por') then
    raise exception 'Una factura anulada es inmutable: lo unico que se puede cambiar es su autor'
      using errcode = '42501';
  end if;
  return new;
end
$$;

revoke execute on function public.factura_anulada_solo_cambia_autor() from public;

drop trigger if exists trg_factura_anulada_solo_autor on public.facturas;
create trigger trg_factura_anulada_solo_autor
  before update on public.facturas
  for each row execute function public.factura_anulada_solo_cambia_autor();;
