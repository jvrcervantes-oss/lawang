-- Conversión con la MISMA regla que la interfaz. Un `::numeric` a secas habría
-- leído '22.250' como 22,25 y dividido por mil ocho importes sin dar error.
alter table public.contrato_vencimientos
  alter column monto type numeric using public.lw_importe(monto),
  alter column pct   type numeric using public.lw_importe(pct);

comment on column public.contrato_vencimientos.monto is
  'Importe del hito, NUMERIC desde el 19-ago-2026. Era text y convivian «5000» y «22.250»: que significaba ese punto dependia de quien lo leyera. Lo escribe el trigger sincroniza_vencimientos leyendo el hito del contrato con public.lw_importe(), la gemela de lwParseImporte.';

-- El trigger es el único que escribe estas columnas (no hay GRANT de INSERT ni
-- de UPDATE sobre ellas para nadie), así que aquí es donde se aplica la regla:
-- el hito del contrato lo teclea una persona y sigue siendo texto.
create or replace function public.sincroniza_vencimientos()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  hitos jsonb := coalesce(new.datos->'hitos', '[]'::jsonb);
begin
  if tg_op = 'UPDATE' and new.datos->'hitos' is not distinct from old.datos->'hitos' then
    return new;
  end if;

  delete from public.contrato_vencimientos v
   where v.contrato_id = new.id and not v.ajustado;

  insert into public.contrato_vencimientos
         (contrato_id, orden, descripcion, pct, monto, fecha)
  select new.id,
         h.ordinality,
         nullif(btrim(coalesce(h.value->>'es', h.value->>'en', h.value->>'id', '')), ''),
         public.lw_importe(h.value->>'pct'),
         public.lw_importe(h.value->>'monto'),
         case when h.value->>'fecha' ~ '^\d{4}-\d{2}-\d{2}$'
              then (h.value->>'fecha')::date end
    from jsonb_array_elements(hitos) with ordinality h
   where not exists (select 1 from public.contrato_vencimientos v2
                      where v2.contrato_id = new.id and v2.orden = h.ordinality)
  on conflict (contrato_id, orden) do nothing;

  return new;
end;
$$;;
