-- La PARCELA MÁSTER de cada proyecto — el terreno entero sobre el que se
-- promueve, no la subparcela que se vende. Vivía en tokens.json
-- (`parcelaPorProyecto`) con SEIS entradas escritas a mano y con los nombres
-- VIEJOS de los proyectos: «Palm Field» cuando la tabla dice «Palm Field W5»,
-- «Mejan» cuando dice «Mejan Village S7». Mientras el desplegable leía la misma
-- lista a mano coincidían; en cuanto pasa a leer la tabla, dejan de casar y el
-- autorrelleno se queda mudo. Así que el dato se muda con el resto.
alter table public.proyectos add column if not exists parcela_master text;

comment on column public.proyectos.parcela_master is
  'Codigo de la parcela MASTER del proyecto (el terreno entero, no la subparcela que se vende). Lo imprime el contrato en «el PROMOTOR es titular de la parcela master {{parcela_master}}».';

update public.proyectos set parcela_master = v.cod
  from (values ('Bonian Village','W8'), ('Palm Field W5','W5'), ('Horizon S1','S1'),
               ('Mejan Village S7','S7'), ('Tamarind Rise W3, 3.1 y 3.2','W3'),
               ('Java Sunset S2','S2')) as v(nom, cod)
 where proyectos.nombre = v.nom and proyectos.parcela_master is null;

select nombre, parcela_master, resort from public.proyectos
 where parcela_master is not null order by nombre;;
