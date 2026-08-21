-- Carpetas: una ruta de texto dentro del proyecto ("Comercial/Dossiers").
-- El árbol se DERIVA de estas rutas y no hay tabla de carpetas: así no existen
-- carpetas vacías que nadie limpia ni dos verdades sobre dónde está un
-- documento. Una carpeta existe mientras tenga algo dentro.
alter table public.documentos_proyecto add column if not exists carpeta text not null default '';

-- Se normaliza al escribir para que "Comercial/", "/Comercial" y "comercial"
-- no sean tres carpetas distintas en el árbol.
create or replace function public.normaliza_carpeta() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.carpeta := btrim(regexp_replace(coalesce(new.carpeta,''), '/+', '/', 'g'), '/');
  return new;
end $$;
drop trigger if exists trg_normaliza_carpeta on public.documentos_proyecto;
create trigger trg_normaliza_carpeta before insert or update on public.documentos_proyecto
  for each row execute function public.normaliza_carpeta();

create index if not exists documentos_proyecto_carpeta_idx
  on public.documentos_proyecto (proyecto, carpeta);;
