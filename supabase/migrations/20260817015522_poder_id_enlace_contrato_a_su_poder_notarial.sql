-- ═══════════════════════════════════════════════════════════════════════════
--  poder_id — de que Poder Notarial cuelga la representacion de un contrato
--  17-ago-2026
--  ---------------------------------------------------------------------------
--  Un Poder Notarial de Lawang lo otorga el COMPRADOR (nuestro cliente, en
--  España) a una persona en Indonesia para que compre en su nombre ante notario.
--  Decision del cliente el 17-ago: UN solo poder vale para todos sus contratos,
--  no hace falta uno por escritura.
--
--  Por que una columna y no `contrato_padre_id`:
--    · la direccion correcta es MUCHOS contratos -> UN poder, y `padre` solo
--      admite uno por fila;
--    · `contrato_padre_id` ya sirve para otra jerarquia (Carta de Reserva ->
--      Bloqueo de Parcela) y la leen tres sitios que asumen un solo nivel.
--
--  Para que sirve de verdad: hoy el nombre del apoderado del comprador y la
--  fecha de su poder se TECLEAN a mano en cada Hak Sewa, copiando datos que
--  viven en el poder. Con el enlace se leen de su origen y dejan de copiarse.
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.contratos
  add column if not exists poder_id uuid references public.contratos(id) on delete set null;

comment on column public.contratos.poder_id is
  'Poder Notarial (tipo=poa) bajo el que actua el apoderado DEL COMPRADOR en este contrato. Un poder cubre varios contratos.';

create index if not exists contratos_poder_id_idx on public.contratos(poder_id);

-- ── Guardas ────────────────────────────────────────────────────────────────
-- Mismo criterio que el traspaso de parcela (LAW-51): no basta con que apunte a
-- algo, tiene que apuntar al poder del MISMO comprador. Enlazar un Hak Sewa al
-- poder de otra persona significaria decir en el documento que a este comprador
-- le representa alguien a quien el no ha apoderado.
create or replace function public.valida_poder_id()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  poder     record;
  ids_mios  text[];
  ids_poder text[];
begin
  if new.poder_id is null then
    return new;
  end if;

  if new.poder_id = new.id then
    raise exception 'Un contrato no puede ser su propio poder notarial.'
      using errcode = '23514';
  end if;

  select id, tipo, numero, datos into poder
    from public.contratos where id = new.poder_id;

  if poder is null then
    raise exception 'El poder notarial enlazado no existe.' using errcode = '23503';
  end if;

  if poder.tipo <> 'poa' then
    raise exception 'El documento % no es un Poder Notarial (es %), asi que no puede figurar como el poder de este contrato.',
      poder.numero, poder.tipo using errcode = '23514';
  end if;

  -- Mismo otorgante. Se comparan pasaporte y email —lo que crea la ficha de
  -- comprador— y NO el nombre: el nombre se escribe a mano y una tilde o un
  -- segundo apellido de mas darian un bloqueo falso. Con que coincida uno vale.
  ids_mios  := public.contrato_identificadores(new.datos);
  ids_poder := public.contrato_identificadores(poder.datos);

  if array_length(ids_mios, 1) is null or array_length(ids_poder, 1) is null then
    raise exception 'Falta el pasaporte y el email del comprador en % para poder afirmar que el poder % es suyo. Completa la ficha del comprador en el documento que este incompleto.',
      coalesce(new.numero, 'este contrato'), poder.numero using errcode = '23514';
  end if;

  if not (ids_mios && ids_poder) then
    raise exception 'El poder % es de otro comprador. Un poder solo cubre los contratos de quien lo otorga.',
      poder.numero using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists contratos_valida_poder_id on public.contratos;
create trigger contratos_valida_poder_id
  before insert or update of poder_id, datos on public.contratos
  for each row execute function public.valida_poder_id();;
