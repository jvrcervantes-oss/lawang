-- destructivo-ok: retira permisos y policies de ESCRITURA directa (el navegador ya escribe por RPC/edge desde 13ecab23); no borra ni cambia ninguna fila.
-- Frontera frontend/backend — bloque 2, CIERRE (27-sep-2026, LAW-336). Plan y revisión previa #125:
-- encargos/20260927_lawang_frontera_b2_compradores_kyc.md
-- Desde aquí `authenticated` solo LEE clients y documents, y en el bucket kyc solo lee. Escriben
-- cliente_guarda, cliente_traspasa, documento_kyc_registra, documento_kyc_retira (SECURITY DEFINER, permiso
-- dentro), la edge ficheros-kyc (service role, solo mueve bytes) y las funciones que ya escribían
-- (borrar_comprador, traspasar_cliente_con_documentos, crm_lead_ficha_crear, resolver_solicitud_cambio).

-- Las 6 filas de una fusión antigua viven en la carpeta de otro comprador (medido 27-sep). Si aparece una
-- séptima, alguien registró una ruta ajena entre la medición y el cierre: se para y se mira.
do $$
declare v_n int;
begin
  select count(*) into v_n from public.documents d
   where d.storage_path not like d.client_id::text || '/%'
     and d.id not in ('af0d8bad-50cb-4d48-9062-9512c370e936', 'c0696a2b-9ebc-4962-84f1-fcf74ad0970a',
                      '2d8f5d49-65ca-46eb-817c-447991612de6', '30349266-e019-45fd-ba17-f5152b996fe6',
                      '2f07ce6e-7165-4782-8fb7-c8d7a1a65832', 'b7cc5194-936d-43d3-811f-cd63492bb451');
  if v_n > 0 then
    raise exception 'Hay % documento(s) nuevos con ruta fuera de la carpeta de su comprador: revisar antes de cerrar', v_n;
  end if;
end $$;

revoke insert, update, delete on public.clients, public.documents from authenticated;
revoke insert, update, delete on public.clients, public.documents from anon;

drop policy if exists "agentes crean clientes" on public.clients;
drop policy if exists "admins actualizan clientes" on public.clients;
drop policy if exists "el autor corrige su ficha mientras no este firmada" on public.clients;
drop policy if exists "agentes crean documentos" on public.documents;
drop policy if exists "agentes actualizan documentos" on public.documents;
drop policy if exists "admins borran documentos" on public.documents;

drop policy if exists "agentes suben kyc" on storage.objects;
drop policy if exists "agentes actualizan kyc" on storage.objects;
drop policy if exists "agentes borran kyc" on storage.objects;
