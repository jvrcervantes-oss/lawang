-- Dos cosas que faltaban en axisworks_facturas:
-- 1) `idioma`: se anadio en cuentas.html (7-ago) pero facturas_crear() nunca lo escribia
--    en la fila -- se perdia en el momento de guardar, aunque abrirHoja() ya sabia leerlo.
-- 2) `emisor_id`: que nombre comercial (AxisWorks / PT Mahkota Property Global) emitio
--    esa factura. Se guarda por factura y no se relee de una constante actual, porque
--    una factura ya emitida tiene que imprimir siempre el mismo nombre con el que salio,
--    aunque el dia de manana cambie cual es el emisor por defecto.
alter table public.axisworks_facturas
  add column idioma text not null default 'es',
  add column emisor_id text not null default 'axisworks';
;
