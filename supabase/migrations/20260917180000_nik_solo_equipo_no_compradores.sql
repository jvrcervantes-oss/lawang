-- Los catalogos con NIK y pasaporte en claro dejan de verlos los COMPRADORES.
--
-- Hallazgo de Seguridad en la consulta de deploy del 17-sep-2026. La deuda que
-- se cerro el 12-ago se cerro contra `anon`, no contra clientes con sesion: los
-- compradores del portal entran con signInWithPassword al MISMO proyecto de
-- Supabase, asi que son `authenticated` y las dos policies decian `using (true)`.
-- Medido: 58 cuentas en auth.users y solo 30 con ficha en public.usuarios; los
-- otros 28 son compradores. Ningun camino del portal lee estas dos tablas.
--
-- `es_agente()` es la barrera correcta: exige fila activa en public.usuarios, y
-- para quien no la tiene mira el claim `agente` del JWT, que un comprador no
-- lleva. ALTER POLICY y no DROP+CREATE, para no tirar nada.
alter policy "firmantes cred: solo con sesion" on public.firmantes_cred
  using (public.es_agente());

alter policy "apoderados hak sewa: solo con sesion" on public.apoderados_hak_sewa
  using (public.es_agente());

-- Y el GRANT, que manda antes que la policy: `firmantes_cred` conservaba el ACL
-- completo de una relacion recien creada — anon con DELETE, INSERT, UPDATE y
-- TRUNCATE sobre la tabla de los NIK. Una sonda anonima devolvia `200 []` en vez
-- de 401, y un vector vacio no es un aprobado: solo significa que la policy
-- filtro. `sociedades` si recibio su revoke hoy; esta nunca lo tuvo.
revoke all on public.firmantes_cred from anon, authenticated;
grant select on public.firmantes_cred to authenticated;

revoke all on public.apoderados_hak_sewa from anon, authenticated;
grant select on public.apoderados_hak_sewa to authenticated;
