-- destructivo-ok: revoca únicamente un privilegio de ejecución sobre una
-- función creada en la migración anterior de esta misma sesión
-- (20260914121500); no toca filas. get_advisors(security) marcó
-- _equipo_de_condicion_comision como ejecutable por anon vía RPC -- revoke
-- from public no basta, hay que nombrar anon/authenticated explícitamente
-- (misma piedra documentada 3 veces antes en el repo).
revoke all on function public._equipo_de_condicion_comision(uuid) from public, anon, authenticated;
grant execute on function public._equipo_de_condicion_comision(uuid) to authenticated;
;
