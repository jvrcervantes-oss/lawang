-- ════════════════════════════════════════════════════════════════════════════
-- UNA FACTURA, SOLO SOBRE UN CONTRATO BLOQUEADO — 19-ago-2026, encargo del owner
-- ════════════════════════════════════════════════════════════════════════════
-- «Facturar un contrato no debe ser posible hasta que estuviese bloqueado».
-- Bloqueado = firmado y cerrado, que es cuando hay algo que cobrar de verdad.
-- Hasta hoy bastaba con que el contrato estuviera GUARDADO, y guardado no es
-- nada: un borrador a medias, con el precio por cerrar, ya se podía facturar.
--
-- SOLO `factura`, y es deliberado. La PROFORMA es la petición del depósito de
-- reserva y el RECIBÍ es la prueba de que ese dinero entró: las dos ocurren
-- ANTES de firmar nada. Prohibirlas rompería la venta por su principio — de
-- hecho la proforma automática del depósito nace al guardar un contrato NUEVO.
--
-- ⚠️ LO QUE HABÍA ANTES, medido antes de aplicar: de 29 facturas, **22 están
-- emitidas sobre contratos sin firmar**. O sea, la práctica de hasta hoy es la
-- contraria a esta regla. Por eso el trigger NO mira las filas que ya existen:
-- en UPDATE solo comprueba si cambia el tipo o el contrato, así que esas 22 se
-- siguen pudiendo editar, anular y cobrar. Lo que no se puede es crear una
-- nueva ni mover una a un contrato sin firmar.
--
-- Un CHECK no vale: la condición vive en OTRA tabla (`contratos.bloqueado`) y
-- un CHECK es por fila. De ahí el trigger.

create or replace function public.trg_factura_exige_contrato_bloqueado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bloqueado boolean;
  v_numero    text;
begin
  if new.tipo is distinct from 'factura' then return new; end if;

  -- Las facturas ya emitidas no se congelan: solo se comprueba cuando la fila
  -- NACE como factura o cuando cambia de contrato. Anular, corregir importes o
  -- marcar enviada siguen funcionando igual sobre las 22 antiguas.
  if tg_op = 'UPDATE'
     and old.tipo is not distinct from new.tipo
     and old.contrato_id is not distinct from new.contrato_id then
    return new;
  end if;

  -- sin contrato no es asunto de esta regla: de eso se ocupa
  -- `facturas_contrato_obligatorio` (LAW-38)
  if new.contrato_id is null then return new; end if;

  select c.bloqueado, c.numero into v_bloqueado, v_numero
    from public.contratos c where c.id = new.contrato_id;

  if not coalesce(v_bloqueado, false) then
    raise exception 'el contrato % no esta bloqueado: una factura se emite cuando el contrato esta firmado y cerrado. Para cobrar antes, emite una proforma y su recibi',
      coalesce(v_numero, '?') using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists trg_factura_exige_contrato_bloqueado on public.facturas;
create trigger trg_factura_exige_contrato_bloqueado
  before insert or update of tipo, contrato_id on public.facturas
  for each row execute function public.trg_factura_exige_contrato_bloqueado();

-- La otra mitad vive en `facturas/index.html`: el desplegable de contrato deja
-- los no firmados a la vista pero deshabilitados y con el motivo escrito. No se
-- quitan de la lista: un contrato que existe y no aparece manda al agente a
-- buscar por qué.
