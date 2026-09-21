alter table public.documentos_proyecto
  add column if not exists publicado_investor_deck boolean not null default false;

comment on column public.documentos_proyecto.publicado_investor_deck is
  'Opt-in explicito: si este documento se ofrece para descarga en el data room PUBLICO de inversores (sin login). Default false a proposito -- nada se publica solo. NO se reutiliza `confidencial` ni `visible_portal`: ninguno de los dos significa publico. `visible_portal` es para compradores CON CONTRATO en esa promocion (lo dice la propia pantalla de Documentacion), y esta tabla guarda ademas filas internas -- las preguntas de due diligence que mando un inversor -- que no pueden salir jamas.';

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
     and d.url is not null
     and d.url <> ''
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
  'Documentos que un proyecto ofrece para descarga en el data room publico de inversores. Doble llave: el documento lleva publicado_investor_deck=true Y confidencial=false, y el proyecto tiene unidades abiertas al deck. Nunca devuelve `path` (ficheros del bucket privado) ni `creado_por`. Hoy devuelve CERO filas para todos los proyectos: nada esta opt-in todavia, y el deck esconde el boton cuando no hay nada.';;
