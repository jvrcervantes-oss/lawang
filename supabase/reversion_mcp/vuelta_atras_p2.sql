-- destructivo-ok: VUELTA ATRÁS de 20261016073333_mcp_f1_p2_herramientas.sql (las 10 herramientas de lectura del MCP de Lawang).
-- No borra datos: P2 solo crea funciones. Antes, retirar la edge `mcp` o apagar en Ajustes › IA. Deja privado.ia_despacha
-- como el stub de P1 (ninguna herramienta), con su dueño y su ACL vacía. Va ANTES de vuelta_atras_p1.sql si se quita todo.
begin;
create or replace function privado.ia_despacha(p_herramienta text, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$ begin return jsonb_build_object('error', 'herramienta_desconocida'); end $$;
drop function if exists privado.mcp_parcelas_libres(uuid), privado.mcp_comisiones_pendientes(),
  privado.mcp_cobros_por_proyecto_mes(date), privado.mcp_cambios_estado_semana(date),
  privado.mcp_contratos_sin_firmar(uuid), privado.mcp_resumen_semana(date), privado.mcp_facturas_no_cobradas(text),
  privado.mcp_recibis_sin_aplicar(text), privado.mcp_ventas_facturadas_de_mas(),
  privado.mcp_movimientos_mes_sociedad(date, text);
drop function if exists public.mcp_parcelas_libres_lee(uuid), public.mcp_comisiones_pendientes_lee(),
  public.mcp_cobros_por_proyecto_mes_lee(date, date), public.mcp_contratos_sin_firmar_lee(uuid),
  public.mcp_resumen_semana_lee(date, date), public.mcp_facturas_no_cobradas_lee(text),
  public.mcp_recibis_sin_aplicar_lee(text),
  public.mcp_movimientos_mes_sociedad_lee(date, date, text, boolean, boolean, boolean, boolean);
revoke execute on function public.facturas_pendiente_equipo() from lw_lector;
revoke execute on function public.factura_aplicado(uuid) from lw_lector;
commit;
