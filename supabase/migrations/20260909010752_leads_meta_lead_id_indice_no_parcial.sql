-- El indice de ayer mismo (leads_origen_meta) se creo como UNIQUE ... WHERE meta_lead_id
-- IS NOT NULL. Postgres no puede usar un indice PARCIAL para inferir un ON CONFLICT, asi
-- que el upsert de la recogida (R13 y tools/leads_meta_backfill.py) fallaba entero con
-- 42P10 «there is no unique or exclusion constraint matching the ON CONFLICT
-- specification». Cazado ejecutando el backfill de verdad, no leyendo el SQL.
--
-- La clausula WHERE sobraba desde el principio: en Postgres un UNIQUE trata cada NULL como
-- distinto, asi que un indice unico normal sobre una columna que admite NULL ya permite
-- tantas filas sin `meta_lead_id` como haga falta -- que es justo lo que son las 32 filas
-- del QR y la web. El parcial no daba ninguna garantia extra y rompia el upsert.
create unique index if not exists leads_meta_lead_id_key on public.leads (meta_lead_id);

-- destructivo-ok: se borra un INDICE, no datos ni filas. Es el parcial que acaba de
-- sustituirse en la linea de arriba; dejar los dos significaria mantener dos definiciones
-- de la misma unicidad y que la proxima persona no sepa cual manda.
drop index if exists public.leads_meta_lead_id_uniq;;
