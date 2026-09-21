-- destructivo-ok: DROP+ADD CONSTRAINT es una reescritura completa de la misma FK en la
-- misma sentencia (patron ya usado en el repo para policies), nunca retirada sin
-- reemplazo. La tabla se creo en ESTA misma sesion, cero filas escritas todavia, nadie
-- depende de ella en produccion.
--
-- La FK a contrato_id no se puede comprobar de inmediato: se escribe DESDE un trigger
-- BEFORE INSERT de la propia `contratos`, en el momento en que new.id ya existe como
-- valor pero la fila aun no esta insertada en la tabla (eso pasa justo DESPUES de que
-- el trigger BEFORE devuelva). Sin diferir, el INSERT en carta_cobrado_aplicado falla
-- con 23503 (probado en real, dentro de BEGIN/ROLLBACK, antes de tocar produccion).
-- La FK a carta_id no se toca: esa fila (la carta_reserva) ya existe de antes, siempre.
alter table public.carta_cobrado_aplicado
  drop constraint carta_cobrado_aplicado_contrato_id_fkey,
  add constraint carta_cobrado_aplicado_contrato_id_fkey
    foreign key (contrato_id) references public.contratos(id) on delete cascade
    deferrable initially deferred;;
