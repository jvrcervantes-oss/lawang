-- Hallazgo de Legal en la consulta de deploy de la migración anterior
-- (20260922130000_facturas_contrato_obligatorio_exime_anuladas): contrato_numero
-- es el ÚNICO rastro que sobrevive a un contrato_id puesto a NULL por el
-- ON DELETE SET NULL de facturas_contrato_id_fkey (vía borrar_operacion()), pero
-- no estaba garantizado por esquema — solo por disciplina de la UI de
-- /intranet/facturas/ (verificado 27-ago-2026: 279/279 casos reales coinciden,
-- pero ninguna base de datos lo obligaba). Antes de hoy esto nunca se notaba
-- porque el CHECK fallaba primero y abortaba el borrado entero; con el fix de
-- hoy el borrado sí completa, así que el hueco pasa a ser alcanzable de verdad.
--
-- Verificado antes de escribir esto: 0 facturas reales tienen hoy contrato_id
-- sin contrato_numero — no hace falta backfill, solo cerrar el hueco hacia
-- adelante para cualquier camino de escritura que no sea el formulario de
-- /intranet/facturas/ (RPCs, migraciones, futuras pantallas).
--
-- Solo rellena cuando contrato_numero llega NULL y hay contrato_id: nunca
-- pisa un valor ya puesto (aunque hoy siempre coincide con el del contrato).
-- No actúa cuando contrato_id se pone a NULL (el SET NULL de la FK): esa rama
-- no toca contrato_numero, así que el valor ya congelado se queda tal cual.
create or replace function public._facturas_congela_contrato_numero()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.contrato_id is not null and new.contrato_numero is null then
    select c.numero into new.contrato_numero
      from public.contratos c
     where c.id = new.contrato_id;
  end if;
  return new;
end;
$$;

comment on function public._facturas_congela_contrato_numero() is
  'Congela contrato_numero desde contratos.numero en cuanto una factura recibe un contrato_id, si no llega ya puesto -- garantiza que el vinculo factura->contrato sea reconstruible aunque contrato_id se ponga a NULL despues (ON DELETE SET NULL via borrar_operacion). Nunca pisa un valor ya presente ni actua cuando contrato_id se vacia.';

drop trigger if exists trg_facturas_congela_contrato_numero on public.facturas;
create trigger trg_facturas_congela_contrato_numero
  before insert or update on public.facturas
  for each row execute function public._facturas_congela_contrato_numero();

revoke all on function public._facturas_congela_contrato_numero() from public, anon, authenticated;
