-- destructivo-ok: DROP POLICY es reemplazo idempotente (no borra filas/tabla); el "UPDATE sin WHERE" es falso positivo del guardrail sobre FOR UPDATE de create policy, no una sentencia UPDATE de datos. Policies = DDL que construye segun CLAUDE.md. Censo de escritores hecho: unico INSERT/UPDATE real sobre clients es compradores/index.html, no afectado.

drop policy if exists "agentes actualizan clientes" on public.clients;

create policy "admins actualizan clientes"
  on public.clients for update to authenticated
  using (public.es_admin())
  with check (public.es_admin());

comment on table public.clients is
  'Fichas de comprador. Cualquier agente lee y da de alta; solo admin/super_admin edita una ya existente (7-ago-2026).';;
