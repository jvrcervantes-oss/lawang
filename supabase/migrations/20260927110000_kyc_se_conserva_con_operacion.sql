-- destructivo-ok: solo reemplaza documento_kyc_retira (el `delete` es el de siempre, para compradores sin operación); no toca filas al aplicarse.
-- Consulta de deploy (Legal, 27-sep-2026, LAW-336 bloque 2): conservar el KYC solo con contrato FIRMADO era
-- más estrecho que la obligación. Un comprador con Carta de Reserva cobrada y contrato aún sin bloquear no se
-- puede borrar (borrar_comprador lo impide), pero su pasaporte y su prueba de fondos sí se destruían al
-- retirarlos. La conservación contra el blanqueo nace de la operación y del cobro, no de la firma. Se aplica
-- el porqué de la decisión del owner («lo de una compraventa no se destruye») con el mismo criterio que ya usa
-- borrar_comprador: cualquier contrato vinculado o cualquier factura/recibí a su nombre.
create or replace function public.documento_kyc_retira(p_id uuid, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_d public.documents%rowtype; v_c public.clients%rowtype; v_conserva boolean;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not public.es_admin() then raise exception 'Retirar documentos lo hace un administrador' using errcode = '42501'; end if;
  select * into v_d from public.documents d where d.id = p_id and d.retirado_el is null for update;
  if not found then raise exception 'Ese documento ya no está en la ficha' using errcode = '22023'; end if;
  select * into v_c from public.clients c where c.id = v_d.client_id for update;
  v_conserva := exists (select 1 from public.contrato_compradores cc where cc.client_id = v_d.client_id)
             or exists (select 1 from public.facturas f where f.client_id = v_d.client_id);

  if v_conserva then
    if not public.es_super_admin() then
      raise exception 'Este comprador tiene contratos o pagos a su nombre: su documentación KYC solo la retira un super admin, y el fichero se conserva.'
        using errcode = '42501';
    end if;
    if v_motivo is null or length(v_motivo) < 10 then
      raise exception 'Este comprador tiene contratos o pagos a su nombre: escribe por qué se retira el documento (queda registrado y el fichero se conserva)'
        using errcode = '22023';
    end if;
    update public.documents set retirado_el = now(), retirado_por = (select auth.email()), retirado_motivo = v_motivo
     where id = p_id;
  else
    delete from public.documents where id = p_id;
  end if;

  if v_c.kyc_status = 'verified' then
    update public.clients set kyc_status = 'submitted', kyc_verificado_por = null, kyc_verificado_el = null where id = v_c.id;
    insert into public.correcciones_datos (tabla, fila_id, campo, valor_anterior, valor_nuevo, motivo, corregido_por)
    values ('clients', v_c.id, 'kyc_status', 'verified', 'submitted', 'se retiró un documento KYC', (select auth.email()));
  end if;

  return jsonb_build_object('conservado', v_conserva,
                            'borrar_fichero', not v_conserva,
                            'path', case when v_conserva then null else v_d.storage_path end,
                            'kyc_vuelve_a_revision', v_c.kyc_status = 'verified');
end $$;
revoke all on function public.documento_kyc_retira(uuid, text) from public, anon;
grant execute on function public.documento_kyc_retira(uuid, text) to authenticated;
