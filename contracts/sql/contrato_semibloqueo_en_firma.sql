-- SEMIBLOQUEO: un contrato enviado a firma no se edita por accidente
-- 15-ago-2026, propuesta del owner.
--
-- EL HUECO, verificado contra las policies de produccion. La RLS de `contratos`
-- solo mira una cosa:
--     UPDATE ... USING (bloqueado = false AND es_agente() AND ... es_suyo(...))
-- Es decir: un contrato FIRMADO DEL TODO no lo puede editar nadie -- eso ya
-- estaba bien atado. Pero entre «enviado a firma» y «firmado» no habia NADA: un
-- contrato con un enlace de firma vivo, o con una de dos firmas ya recogidas, era
-- tan editable como un borrador en blanco.
--
-- POR QUE IMPORTA, y no es teorico: el 15-ago aparecieron dos contratos con la
-- cadena parada (CC00007 desde el 1-ago, CR00020 desde el 14) esperando a su
-- segundo firmante. Durante esas semanas, cualquiera podia cambiarles el texto
-- que el PRIMER comprador ya habia firmado. Nadie lo hizo, pero nada lo impedia.
--
-- LA REGLA. Si el contrato tiene alguna firma viva (`pendiente`) o ya recogida
-- (`firmado`), no se le puede tocar `datos` -- que es donde vive el texto y los
-- campos del documento. Para editarlo hay que ANULAR la firma primero, y eso es
-- una decision explicita que la app pide con un dialogo.
--
-- Y es la semantica correcta, no solo una barrera: si el texto cambia, la firma
-- que alguien dio sobre el texto ANTERIOR ya no vale. Anularla no es un castigo,
-- es lo que de verdad ha pasado.
--
-- LO QUE NO BLOQUEA, a proposito:
--   · `firma-submit` cerrando el contrato -- toca `bloqueado`, `pdf_firmado_path`
--     y `pdf_firmado_hash`, nunca `datos`. Verificado leyendo la funcion.
--   · el propio flujo de anular-y-editar: al anular, las firmas pasan a
--     `anulado`, ya no hay ninguna viva y el update entra sin necesidad de
--     ninguna bandera ni excepcion. Esa es la parte elegante -- no hay puerta
--     trasera que alguien pueda dejarse abierta.
--   · cambiar el color de portada, el nombre del contrato o cualquier otra cosa
--     que NO viva en `datos`... no aplica: todo eso vive en `datos`. Es
--     deliberado: si el documento cambia en algo, la firma anterior deja de
--     corresponder a lo firmado.
--
-- NADA SE BORRA. Las firmas anuladas se quedan como historia con
-- `estado = 'anulado'`, y su `snapshot_path` conserva el documento que el
-- comprador vio y firmo. Esa copia es la prueba, y sobrevive a la edicion.

create or replace function public.contrato_no_editable_en_firma()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  n_vivas    int;
  n_firmadas int;
begin
  -- Solo el CONTENIDO del documento. Un update que no toca `datos` (cerrar la
  -- firma, apuntar el PDF, mover el contrato_padre_id) pasa sin mirar nada.
  if new.datos is not distinct from old.datos then
    return new;
  end if;

  select count(*) filter (where cf.estado = 'pendiente'),
         count(*) filter (where cf.estado = 'firmado')
    into n_vivas, n_firmadas
    from public.contrato_firmas cf
   where cf.contrato_id = new.id;

  if coalesce(n_vivas, 0) = 0 and coalesce(n_firmadas, 0) = 0 then
    return new;
  end if;

  raise exception
    'Este contrato esta enviado a firma (% enlace(s) sin usar, % firma(s) ya recogida(s)) y no se puede editar. Para cambiarlo hay que anular la firma: al guardar, la app te lo ofrece. Anular invalida lo ya firmado y el comprador tendra que firmar de nuevo.',
    coalesce(n_vivas, 0), coalesce(n_firmadas, 0)
    using errcode = '23514';
end $$;

drop trigger if exists trg_contrato_no_editable_en_firma on public.contratos;
create trigger trg_contrato_no_editable_en_firma
  before update on public.contratos
  for each row execute function public.contrato_no_editable_en_firma();

-- Comprobacion despues de aplicar. Con CR00020 (1 firma `firmado`) debe fallar:
--   update public.contratos
--      set datos = jsonb_set(datos, '{fields,nombre_contrato}', '"prueba"')
--    where numero = 'CR00020';
-- y con cualquier borrador sin firmas debe pasar.
