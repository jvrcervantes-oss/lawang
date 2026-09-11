/* INVESTOR DECK — el dosier descargable sale de la documentacion del proyecto. 11-sep-2026.

   POR QUE. El owner pidio que el CTA de cabecera del deck pasara de "pedir dossier" (un
   formulario) a "descargar dosier", y que el documento **salga de la documentacion adjunta
   al proyecto en la intranet; si no hay ninguno, que no se enseñe nada**.

   POR QUE UNA COLUMNA NUEVA Y NO REUTILIZAR LAS QUE YA HAY. `documentos_proyecto` ya tiene
   dos flags, y NINGUNO significa "publico":
     · `confidencial`   = "no compartir fuera del estudio".
     · `visible_portal` = lo ven los compradores CON CONTRATO en esa promocion. Lo dice la
                          propia pantalla de Documentacion, y ademas pide confirmacion antes
                          de marcarlo.
   Colgar de cualquiera de los dos un data room ANONIMO seria publicar a internet algo que
   la intranet describe como interno o como restringido a clientes con contrato.

   Y hay un motivo mas concreto: esta misma tabla guarda, con `categoria='faq'`, las
   preguntas de due diligence que un inversor real mando sobre Palm Field ("Se presenta como
   freehold. Que derecho adquirira exactamente...", "Hemos visto referencias a una posible
   tributacion del 0%..."). Son notas internas del equipo. Un filtro generico las habria
   sacado a la pagina publica.

   Asi que opt-in explicito, el mismo patron que ya usa `unidades.publicado_investor_deck`
   (migracion 20260910025145) y que la revision previa de Seguridad respaldo hoy para los
   modelos: default false, nada se publica solo.

   DOBLE LLAVE. El RPC exige `publicado_investor_deck = true` Y `confidencial = false` Y que
   el proyecto tenga unidades abiertas al deck. La regla "confidencial manda sobre publicado"
   vive tambien en el formulario de la intranet (v4/assets/editores.js), pero se repite aqui
   a proposito: una casilla del navegador no es un permiso.

   HOY DEVUELVE CERO FILAS para todos los proyectos, que es justo lo que se pedia: nada esta
   marcado todavia, y el deck esconde el boton cuando no hay nada que descargar. El owner lo
   enciende desde Proyectos -> Nuevo enlace, marcando la casilla nueva.

   ⚠️ Los enlaces de esta tabla son de Google Drive. Que la fila este publicada NO implica
   que el fichero este compartido en abierto: si no lo esta, el inversor se choca con la
   pantalla de permisos de Drive. Por eso la confirmacion del formulario lo dice.

   No borra nada: ADD COLUMN con default y CREATE FUNCTION. */

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
  'Documentos que un proyecto ofrece para descarga en el data room publico de inversores. Doble llave: el documento lleva publicado_investor_deck=true Y confidencial=false, y el proyecto tiene unidades abiertas al deck. Nunca devuelve `path` (ficheros del bucket privado) ni `creado_por`. Hoy devuelve CERO filas para todos los proyectos: nada esta opt-in todavia, y el deck esconde el boton cuando no hay nada.';
