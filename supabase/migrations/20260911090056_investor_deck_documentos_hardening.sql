create or replace function public.investor_deck_documentos(p_proyecto text)
returns table(titulo text, descripcion text, url text, categoria text)
language sql
security definer
stable
set search_path = public
as $$
  select d.titulo, d.descripcion, d.url, d.categoria
    from public.documentos_proyecto d
   where d.proyecto = p_proyecto
     and d.publicado_investor_deck
     and d.confidencial = false          -- cinturon y tirantes: publicado nunca gana a confidencial
     -- La categoria 'faq' guarda notas internas del equipo. La declaracion de
     -- rls_publico.txt ya prometia que nunca salen; hasta ahora caian solo de
     -- rebote (por confidencial y por no tener url), que no es lo mismo que
     -- estar excluidas. Ahora la garantia escrita esta aplicada de verdad.
     and d.categoria <> 'faq'
     -- El esquema se valida AQUI y no solo en el formulario: `url` es una columna
     -- que un agente con permiso de documentacion puede PATCHear por PostgREST,
     -- y el deck la mete tal cual en un href. Sin este predicado, un
     -- `javascript:` guardado ahi es XSS almacenada en una pagina publica sin
     -- login. El propio comentario de esta funcion decia que una casilla del
     -- navegador no es un permiso; esto es cumplirlo.
     and d.url ~* '^https?://'
     -- el proyecto tambien tiene que estar abierto al data room, igual que los modelos
     and exists (
           select 1 from public.unidades u
            where u.proyecto = d.proyecto
              and u.publicado_investor_deck
         )
   order by d.creado_en desc;
$$;

revoke all on function public.investor_deck_documentos(text) from public;
grant execute on function public.investor_deck_documentos(text) to anon, authenticated;

comment on function public.investor_deck_documentos is
  'Documentos que un proyecto ofrece para descarga en el data room publico de inversores. Cuatro llaves: publicado_investor_deck=true, confidencial=false, categoria distinta de faq (notas internas), y url con esquema http(s) -- esto ultimo porque el deck la usa como href y un javascript: guardado seria XSS almacenada. Ademas el proyecto tiene que tener unidades abiertas al deck. Nunca devuelve path (bucket privado) ni creado_por.';;
