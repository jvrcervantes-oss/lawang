-- destructivo-ok: UPDATE masivo sobre datos reales de cliente, autorizado por el owner el
-- 11-sep-2026 tras ver el reparto medido. Solo escribe donde `propietario` esta VACIO, asi que
-- no pisa ningun dato existente; es idempotente y cada fila queda registrada en
-- `correcciones_datos` con su valor anterior para poder deshacerla una a una.
with candidatos as (
  select c.id,
         array_remove(array(
           select distinct u.email
             from public.documents d
             join storage.objects o on o.name = d.storage_path
             join public.usuarios u on u.user_id = o.owner
            where d.client_id = c.id
           union
           select distinct nullif(btrim(p.creado_por), '')
             from public.portal_accesos p where p.client_id = c.id
           union
           select distinct nullif(btrim(coalesce(k.creado_por, '')), '')
             from public.contrato_compradores cc
             join public.contratos k on k.id = cc.contrato_id
            where cc.client_id = c.id
           union
           select distinct nullif(btrim(coalesce(f.creado_por, '')), '')
             from public.facturas f where f.client_id = c.id
         ), null) as autores
    from public.clients c
   where c.propietario is null or btrim(c.propietario) = ''
),
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
  from escritas;;
