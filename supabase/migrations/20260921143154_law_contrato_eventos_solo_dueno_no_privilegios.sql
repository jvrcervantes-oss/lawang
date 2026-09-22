-- destructivo-ok: DROP POLICY de una policy de SELECT que se sustituye en la
-- misma sentencia por otra mas estricta (mismo patron que el resto del repo,
-- p.ej. registro_eventos.sql). No borra filas, no afecta a escritura (esta
-- tabla nunca tuvo policy de INSERT/UPDATE/DELETE -- solo escriben triggers
-- definer) y no toca RLS ni el esquema auth.
drop policy if exists "agentes leen eventos" on public.contrato_eventos;
create policy "super_admin ve todo, el resto solo eventos normales de sus contratos"
  on public.contrato_eventos
  for select to authenticated
  using (
    public.es_super_admin()
    or (
      public.es_agente()
      and evento not in (
        'editado_estando_firmado','desbloqueado','factura_sin_bloquear',
        'cobro_a_factura_huerfana','cobro_a_otro_comprador','comprador_sin_ficha'
      )
      and exists (
        select 1 from public.contratos c
         where c.id = contrato_eventos.contrato_id
           and (public.es_suyo(c.creado_por) or public.es_manager_de(c.proyecto_id))
      )
    )
  );;
