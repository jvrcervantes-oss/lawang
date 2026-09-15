-- Hueco preexistente cazado de paso (get_advisors, 15-sep-2026): deck_audita()
-- es una funcion de TRIGGER (usa TG_OP/TG_TABLE_NAME), nunca pensada para
-- llamarse por REST, pero nacio sin revoke y por eso figuraba invocable por
-- anon/authenticated via /rest/v1/rpc/deck_audita. Llamarla asi fuera de un
-- trigger falla (esas variables no existen), no filtra nada -- pero cerrar la
-- puerta cuesta una linea, ya que se estaba tocando esta funcion en esta
-- misma sesion (fix del bug de proyecto_id, migracion anterior).
revoke all on function public.deck_audita() from public, anon, authenticated;
