-- RELLENO DEL DUENO DE 32 FICHAS DE COMPRADOR. 11-sep-2026, autorizado por el owner.
--
-- Cierra la mitad de LAW-180. De las 171 fichas de `clients`, 52 se quedaron sin `propietario`
-- (creadas entre el 28-jul y el 3-sep, antes del trigger `trg_clients_pone_dueno` del mismo dia).
-- Sin dueno solo las ve direccion: para quien las trabaja es como si no existieran.
--
-- DE DONDE SALE EL DUENO, y por que NO es `contratos.creado_por`. Esa era la via aprobada al
-- principio y hubo que descartarla: se midio y **cubria 1 de las 52**, porque los contratos de
-- esas fichas tienen el autor tambien vacio (son justo los de LAW-174). La via que si cubre es
-- **quien subio sus documentos**: `storage.objects.owner` guarda el uid del que sube cada
-- fichero, y `documents.storage_path` los enlaza con la ficha. Ademas es MEJOR evidencia que
-- `creado_por` — quien sube el pasaporte de un comprador es quien lo lleva, mientras que
-- `creado_por` es solo quien pulso «crear» (el reparo de LAW-170, que aqui no aplica).
-- Se suman dos vias menores por si acaso: `portal_accesos.creado_por` y
-- `contratos`/`facturas.creado_por`. Si las vias discrepan, la ficha NO se toca.
--
-- LO QUE ESTA MIGRACION NO HACE, por decision del owner (11-sep):
--   · 19 fichas no dejan rastro en ningun sitio (ni documento, ni portal, ni contrato, ni
--     factura) y 1 es ambigua entre dos personas. Se quedan SIN DUENO a proposito. «Sin dueno»
--     es la verdad: no hay dato que diga de quien son, y ponerle uno a ojo seria inventarlo —
--     y ademas se lo quitaria de la vista a quien de verdad la lleva. Siguen en LAW-180 para
--     reasignarlas cuando alguien pregunte por una.
--
-- REVERSIBLE FILA A FILA: cada cambio deja su linea en `correcciones_datos` con el valor
-- anterior (NULL), que es el mecanismo de vuelta atras — importante porque LAW-57 sigue
-- abierto y esta base no tiene copia de seguridad.

-- destructivo-ok: es un UPDATE masivo sobre datos reales de cliente y por eso lo bloquea el
-- guardrail, correctamente. Autorizado por el owner el 11-sep tras ver el reparto medido
-- (Yesy 25, Noelia 4, Javier 2, Jairo 1). Solo escribe en `clients.propietario` y solo donde
-- hoy esta VACIO, asi que no pisa ningun dato existente: no hay valor anterior que perder.
-- Es idempotente (el `where propietario is null` lo hace inerte en una segunda pasada) y cada
-- fila queda registrada en `correcciones_datos` para poder deshacerla una a una.
with candidatos as (
  select c.id,
         array_remove(array(
           -- 1. quien subio sus documentos (la fuerte)
           select distinct u.email
             from public.documents d
             join storage.objects o on o.name = d.storage_path
             join public.usuarios u on u.user_id = o.owner
            where d.client_id = c.id
           union
           -- 2. quien le dio acceso al portal
           select distinct nullif(btrim(p.creado_por), '')
             from public.portal_accesos p where p.client_id = c.id
           union
           -- 3. quien creo su contrato
           select distinct nullif(btrim(coalesce(k.creado_por, '')), '')
             from public.contrato_compradores cc
             join public.contratos k on k.id = cc.contrato_id
            where cc.client_id = c.id
           union
           -- 4. quien creo su factura
           select distinct nullif(btrim(coalesce(f.creado_por, '')), '')
             from public.facturas f where f.client_id = c.id
         ), null) as autores
    from public.clients c
   where c.propietario is null or btrim(c.propietario) = ''
),
-- Un solo candidato o no se toca. Con dos vias que discrepan, la ficha se queda sin dueno:
-- es preferible una ficha que solo ve direccion a una atribuida a quien no es.
elegidas as (
  select id, autores[1] as dueno from candidatos where cardinality(autores) = 1
),
escritas as (
  update public.clients c
     set propietario = e.dueno
    from elegidas e
   where c.id = e.id
     and (c.propietario is null or btrim(c.propietario) = '')
  returning c.id, e.dueno
)
insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
select 'clients', id, 'propietario', null, dueno,
       'Relleno LAW-180: ficha creada sin dueno antes del trigger del 11-sep-2026. '
       || 'Dueno deducido de quien subio sus documentos (storage.objects.owner) / le dio acceso '
       || 'al portal / creo su contrato o factura, con un unico candidato. Autorizado por el owner.',
       'sistema (relleno 11-sep-2026)'
  from escritas;
