-- VUELTA ATRÁS de 20261017210000_unidades_busca (H6, tren 6, 17-oct-2026). NO se aplica sola: la decide quien orquesta.
-- Orden: indiferente. Sin la función el buscador de la cabecera recibe PGRST202 y esconde solo el grupo «Unidades»
-- (nav.js, sinPermisoONoExiste); herramientas, clientes y contratos siguen. No vuelve la lectura directa de la tabla: esa no aterrizó.
-- destructivo-ok: retira una función de lectura (no guarda datos); sin llamador no se queda expuesta (§1.ter)
set local lock_timeout = '5s';

drop function if exists public.unidades_busca(text);

do $c$
begin
  if to_regprocedure('public.unidades_busca(text)') is not null then
    raise exception 'unidades_busca sigue existiendo tras la vuelta atrás';
  end if;
end $c$;
