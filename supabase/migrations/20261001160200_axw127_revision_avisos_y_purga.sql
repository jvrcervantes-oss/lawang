-- destructivo-ok: añade una columna a la tabla NUEVA copias_firmadas_envios y redefine su función de purga (retención 90 días y 180 días para errores); no borra ni modifica datos existentes.
-- AXW-127 — arreglos de la revisión de código (1-oct-2026): ninguna fila pasa a «error» en silencio.
-- La edge, al final de CADA pasada, pide las filas en error sin avisar (cualquier causa: agotado,
-- pdf_no_encontrado, comprador fuera del portal con PDF grande…), avisa al admin y las marca.
alter table public.copias_firmadas_envios add column if not exists avisado boolean not null default false;

create or replace function public.copias_firmadas_sin_avisar()
returns table (id uuid, numero text, error text)
language sql stable security definer set search_path = '' as $$
  select e.id, c.numero, e.error
    from public.copias_firmadas_envios e
    join public.contratos c on c.id = e.contrato_id
   where e.estado = 'error' and not e.avisado
   order by e.encolado_en limit 20
$$;

create or replace function public.copias_firmadas_marca_avisadas(p_ids uuid[])
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.copias_firmadas_envios e set avisado = true where e.id = any (p_ids) and e.estado = 'error';
  get diagnostics n = row_count;
  return n;
end $$;

-- las filas en error guardan email y nombre de un comprador: plazo largo (180 días) en vez de «nunca»
create or replace function public.copias_firmadas_purga()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.copias_firmadas_envios e
   where (e.estado in ('ok', 'cancelado', 'obsoleto') and coalesce(e.enviado_en, e.encolado_en) < now() - interval '90 days')
      or (e.estado = 'error' and e.encolado_en < now() - interval '180 days');
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function public.copias_firmadas_sin_avisar() from public, anon, authenticated;
revoke execute on function public.copias_firmadas_marca_avisadas(uuid[]) from public, anon, authenticated;
revoke execute on function public.copias_firmadas_purga() from public, anon, authenticated;
grant execute on function public.copias_firmadas_sin_avisar() to service_role;
grant execute on function public.copias_firmadas_marca_avisadas(uuid[]) to service_role;
grant execute on function public.copias_firmadas_purga() to service_role;
