-- Reversion del bloque 5 (USUARIOS, EQUIPO Y EDGES) de la Fase 2 (8-oct-2026).
-- Deja la base como estaba justo antes de las migraciones 20261008500000..20261008504000:
--   1. reaplica, desde public._f2_b5_originales (instantanea tomada por la migracion 0 con pg_get_functiondef / pg_policies en vivo), las 5 funciones
--      (usuario_guarda_permisos, usuario_supervisa_proyecto, usuario_da_alcance y los triggers usuarios_bloquea_cambio_rol_herramientas / usuarios_candado_alta)
--      y la policy «el equipo se ve entre si» de `usuarios`;
--   2. borra las funciones nuevas del bloque (con su llamador: edge admin-usuarios y la policy de `usuarios`);
--   3. borra la tabla de registro `usuarios_cambios_alcance` SOLO si esta vacia (si tiene filas la deja y avisa: es el rastro de quien dio que nivel).
-- Valida mientras nadie use un rol de empresa para gestionar personas. Si ya hay fichas dadas de alta por un rol de empresa (ambito global con empresas), la reversion NO las toca (son datos):
-- la base vuelve a no dejar que un rol de empresa cree mas.
-- LAS EDGES NO SE REVIERTEN AQUI: `admin-usuarios` y `lawang-bot-proxy` se redespliegan desde `git` del commit anterior al bloque (con --no-verify-jwt y la receta del estudio). Si se revierte la base y NO la edge,
-- un rol de empresa recibiria 403/500 al dar de alta (inocuo: la puerta se cierra), y el candado «solo el propietario cambia su clave» seguiria puesto (es independiente de la base).
-- La tabla auxiliar public._f2_b5_originales NO se borra aqui (la instantanea es la fuente de esta reversion): se retira cuando el bloque lleve una semana estable (ultima linea).
-- destructivo-ok: reaplica definiciones, borra funciones propias del bloque (no datos) y, solo si esta vacia, la tabla de registro
begin;
set local lock_timeout = '8s';

do $r$
declare x record;
begin
  if (select count(*) from public._f2_b5_originales) < 6 then
    raise exception 'La instantanea public._f2_b5_originales no esta completa: no se revierte nada';
  end if;
  for x in select ddl from public._f2_b5_originales order by tipo desc loop   -- primero la policy, luego las funciones
    execute x.ddl;
  end loop;
end $r$;

drop function if exists public.usuario_alta_empresa(uuid, text, text, text, text[], text[], text[]);
drop function if exists public.usuario_puede_poner_clave(uuid);
drop function if exists public._gestor_puede_dar(uuid, text[], text[]);
drop function if exists public._alta_empresa_permitida(text, text, text[], text[], uuid[], boolean);
drop function if exists public._usuario_gestionable(uuid);
drop function if exists public._gestor_herramientas();
drop function if exists public._gestor_empresas();
drop function if exists public.mis_empresas();

do $r$
begin
  if (select count(*) from public.usuarios_cambios_alcance) = 0 then
    drop table public.usuarios_cambios_alcance;
  else
    raise notice 'usuarios_cambios_alcance tiene filas: se conserva (es el registro de quien dio que nivel)';
  end if;
end $r$;

commit;
-- Cuando el bloque lleve una semana estable: drop table public._f2_b5_originales;
