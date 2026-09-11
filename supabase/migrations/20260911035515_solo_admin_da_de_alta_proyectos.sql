-- Dar de alta un proyecto pasa a ser cosa de dirección — 11-sep-2026
--
-- Decisión del owner, textual: «Un agente no puede crear proyectos. Sólo
-- super_admin o administradores». Cierra LAW-177.
--
-- QUÉ HABÍA. `es_agente() and puede('unidades')`: cualquiera con la herramienta de
-- parcelas marcada podía crear un proyecto. Se quedó así porque un proyecto nacía
-- como una entrada más del catálogo, al vuelo, desde el propio formulario de alta de
-- una parcela — para que no convivieran «Palm Field» y «Palm Field » con un espacio.
--
-- POR QUÉ AHORA NO VALE. Desde esta misma mañana la lectura de `proyectos` exige
-- tenerlo asignado, así que un agente que creara uno lo vería desaparecer en el acto:
-- un botón que deja la base peor y al que lo pulsa sin nada. Y el motivo de fondo es
-- anterior: un proyecto no es una etiqueta de catálogo, es una unidad de negocio con
-- su cartera, su parcelario y sus permisos colgando. Darlo de alta es un acto de
-- dirección.
--
-- `es_admin()` ya cubre admin Y super_admin — es la misma función que usa el resto de
-- la suite para esto, no una comprobación nueva. Se cae `puede('unidades')`: la
-- herramienta decía quién tocaba el parcelario, y esto ya no va de parcelario.
--
-- `tipos_vivienda` NO se toca: un tipo de vivienda sí es una etiqueta de catálogo.
--
-- La policy se renombra porque su nombre viejo («agentes dan de alta proyectos») pasa
-- a decir exactamente lo contrario de lo que hace, y una policy que se llama al revés
-- es la que alguien lee dentro de seis meses para decidir si puede tocarla.
--
-- EL FRENTE, EN EL MISMO CAMBIO. A `altaProyecto()` de intranet/proyectos/ se llega
-- por TRES caminos: el botón de la barra, el «+ Nuevo proyecto…» del formulario de
-- parcela, y `?nuevoproyecto=1` en la URL —que dispara el botón antes de que se sepa
-- el rol—. El botón y la opción se esconden, y el corte va además dentro de la propia
-- función, que es por donde pasan los tres. Uno solo sin tapar deja al agente delante
-- del error crudo de la base.
--
-- VERIFICADO por impersonación, dentro de una transacción con rollback: Ismael
-- (agente con la herramienta «unidades») 42501, Gus (sales_manager) 42501, Fran
-- (admin) pudo crear. Cero filas de prueba en la tabla después.

alter policy "agentes dan de alta proyectos" on public.proyectos
  with check (public.es_admin());

alter policy "agentes dan de alta proyectos" on public.proyectos
  rename to "solo admin da de alta proyectos";
