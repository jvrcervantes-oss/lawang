-- F6 de «primero la parcela, luego la obra» (encargo de la agencia encargos/20261014_lawang_cobro_primero_parcela.md;
-- LAW-590). Decisión del owner del 14-oct-2026 (~21:10, vía el orquestador agencia-81): BORRAR las dos funciones que se
-- quedaron sin uso cuando la regla pasó a vivir solo en _unidad_cobro_cascada / unidad_cobro_reparto.
-- Por qué: «si no hay quien la llame, se quita» (reducir la exposición). Medido el 14-oct antes de borrar: solo
-- service_role puede ejecutarlas; 0 vistas, 0 policies y 0 crons las nombran; la única función que nombra a
-- unidad_parte_cobrada_split es unidad_parte_cobrada, que también se borra; en el repo de Lawang solo salen en
-- comentarios y documentos históricos. Las entradas de erp/modulos.py (agencia) NO se quitan: son del maestro del ERP,
-- donde las dos siguen existiendo.
-- Es un borrado: lo frena la guardia hasta que el owner pone la marca ~/.axisworks/destructivo-ok.
-- Vuelta atrás: vuelta_f6.sql de esta carpeta (las dos definiciones tal como estaban el 14-oct, con sus permisos).

drop function public.unidad_parte_cobrada(uuid);
drop function public.unidad_parte_cobrada_split(uuid);
