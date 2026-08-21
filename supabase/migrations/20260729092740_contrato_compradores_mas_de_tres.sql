-- El CHECK solo admitía adquiriente_1..3, así que en un contrato a 4 nombres el
-- cuarto se quedaba SIN ficha de comprador (la app lo detectaba y avisaba, pero
-- el dato se perdía igual). Caso real en producción: CC00008, 4 adquirientes y
-- solo 3 fichas.
-- Se pasa a una expresión regular en vez de una lista: así añadir el 5º o el 6º
-- no exige otra migración. Más de 9 firmantes en un contrato privado no es un
-- caso de negocio, es un error de captura, y ahí sí conviene que falle.
alter table public.contrato_compradores drop constraint if exists contrato_compradores_rol_check;
alter table public.contrato_compradores add constraint contrato_compradores_rol_check
  check (rol ~ '^adquiriente_[1-9]$' or rol = 'representante');;
