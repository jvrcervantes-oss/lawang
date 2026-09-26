-- LAW-342, ampliación (26-sep-2026, consulta de deploy de Legal: ALTA es_escrow, MEDIA nota y domicilio).
-- Una cuenta verificada tampoco cambia `es_escrow` (decide la cláusula de depósito en garantía de un
-- contrato firmado al reimprimirse), `extra` (la «Nota» impresa en Datos bancarios: texto libre donde
-- cabe otra instrucción de pago) ni `direccion` (domicilio del banco impreso). Editables siguen solo
-- los que no se imprimen: label, activa, es_propia, orden. Aplicada por MCP.
create or replace function public._cuenta_bancaria_blinda() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.verificada_en := coalesce(old.verificada_en, new.verificada_en);
    if new.clave is distinct from old.clave then
      raise exception 'La clave de una cuenta no se cambia: va dentro de cada contrato y factura emitidos' using errcode = '42501';
    end if;
    if old.verificada_en is not null and (
         new.cuenta    is distinct from old.cuenta    or new.titular   is distinct from old.titular or
         new.banco     is distinct from old.banco     or new.codigo    is distinct from old.codigo  or
         new.direccion is distinct from old.direccion or new.extra     is distinct from old.extra   or
         new.es_escrow is distinct from old.es_escrow) then
      raise exception 'Esta cuenta ya se ha usado (verificada el %): lo que imprime el contrato (titular, banco, número, Swift, domicilio, nota y ESCROW) no se cambia, porque los contratos firmados la reimprimen. Crea una cuenta nueva con otra clave y cámbiala en el reparto.',
        to_char(old.verificada_en, 'DD-MM-YYYY') using errcode = '42501';
    end if;
  end if;
  if new.activa and new.verificada_en is null then new.verificada_en := now(); end if;
  return new;
end $$;
