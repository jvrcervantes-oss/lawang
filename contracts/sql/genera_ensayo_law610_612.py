#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genera contracts/sql/ensayo_law610_612_viva.sql: las TRES migraciones de datos de LAW-610/611/612, byte a byte, seguidas de
un bloque que mide lo que el owner pidió y acaba en `raise exception 'RES LAW610-612 …'` (todo se deshace).

    python contracts/sql/genera_ensayo_law610_612.py          (escribe el .sql e imprime su sha256)

Por qué (15-oct-2026, sesión lawang-cola-2): las tres se aplican por el MCP del orquestador; antes se ensayan en la viva con
tools/lanza_ensayo_viva.py (marca «RES LAW610-612»), que exige que el fichero esté en origin/main y PARA si no acaba en el raise.
Cada migración trae sus guardas y PARA por su cuenta («PARADA LAW-61x: …»): si una para, el ensayo no llega al RES y el .txt
dice por qué. El bloque final no escribe nada: lee y resume.
"""
import hashlib
import os

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
MIGRACIONES = ['20261015210000_law610_cc00040_precio.sql',
               '20261015210100_law611_w3c3_bloqueada.sql',
               '20261015210200_law612_inv00173_rec00130_a_cc00088.sql']
SALIDA = os.path.join(AQUI, 'ensayo_law610_612_viva.sql')

INICIO = """
-- Foto de las comisiones de la venta RP00079 (devengos, sus diferencias y el último error del recálculo automático): la
-- reconciliación que dispara LAW-610 es DIFERIDA, así que se compara antes y después de forzarla en el resumen (revisor, 15-oct).
create or replace function pg_temp.e612_comisiones_rp00079() returns text language sql as $f$
  select coalesce((select string_agg(to_jsonb(d)::text, '|' order by d.id) from public.comisiones_devengadas d
                    where d.contrato_raiz_id in ('637f9a44-cd31-47eb-a636-5fe33255eab3', '93d557dc-814b-48df-b127-adc34f6f191e')), '')
      || ' # ' || coalesce((select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.comisiones_diferencias x
                            join public.comisiones_devengadas d on d.id = x.devengo_id
                           where d.contrato_raiz_id = '637f9a44-cd31-47eb-a636-5fe33255eab3'), '')
      || ' # ' || coalesce((select string_agg(coalesce(i.ultimo_error_en::text, '-'), ',') from public.comisiones_interruptor i), '')
$f$;

-- ── ANTES (solo lee; lo guarda en una variable de la transacción para el resumen) ───────────────────────────────────────
do $antes$
declare v text;
begin
  select format('CC00040 por contrato: precio %s, sin precio %s, facturado %s', s.precio, s.sin_precio, s.facturado) into v
    from public._cadena_saldo_en('93d557dc-814b-48df-b127-adc34f6f191e', 'EUR') s;
  v := v || ' · bases 1-nov RP00026 (suelo/obra cobrados firmados · directo suelo/obra): ' ||
       (select b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada || ' · ' || b.cobrado_directo_suelo || '/' || b.cobrado_directo_obra
          from public._comisiones_bases_firmadas('f0d47af2-5749-46eb-ad82-00415a95ef4d') b);
  perform set_config('ensayo_law610_612.antes', v, true);
  perform set_config('ensayo_law610_612.com79', pg_temp.e612_comisiones_rp00079(), true);
end $antes$;
"""

FINAL = """
-- ── RESUMEN (solo lee) ──────────────────────────────────────────────────────────────────────────────────────────────────
do $res$
declare
  v text := '';
  r record;
begin
  -- los disparadores diferidos (historial de unidades) corren aquí y no al confirmar, que en un ensayo no llega
  execute 'set constraints all immediate';
  v := 'ANTES · ' || current_setting('ensayo_law610_612.antes', true) || E'\\n';
  -- LAW-610
  select c.precio_total, c.datos->'fields'->>'precio_total' as campo,
         (select count(*) from public.contrato_vencimientos v where v.contrato_id = c.id) as venc
    into r from public.contratos c where c.id = '93d557dc-814b-48df-b127-adc34f6f191e';
  v := v || format('610 · CC00040 precio_total %s · papel %s · vencimientos %s', r.precio_total, coalesce(r.campo, '(vacío)'), r.venc);
  select u.estado, u.precio, u.precio_suelo, u.precio_construccion, x.obra_precio, x.obra_de_contrato into r
    from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
   where u.contrato_id = '637f9a44-cd31-47eb-a636-5fe33255eab3';
  v := v || format(' · SH-3 %s precio %s = %s + %s · obra cascada %s (de contrato %s)', r.estado, r.precio, r.precio_suelo,
                   r.precio_construccion, r.obra_precio, r.obra_de_contrato);
  v := v || (select format(' · por contrato: precio %s, sin precio %s, facturado %s (cadena %s)', s.precio, s.sin_precio,
                           s.facturado, s.raiz_numero)
               from public._cadena_saldo_en('93d557dc-814b-48df-b127-adc34f6f191e', 'EUR') s);
  -- si cambian, el ensayo PARA aquí y no llega al RES: el lanzador sale con 1 sin que haya que leer el texto (revisor, 2.ª vuelta)
  if pg_temp.e612_comisiones_rp00079() is distinct from current_setting('ensayo_law610_612.com79', true) then
    raise exception 'PARADA ensayo LAW-610: cambian las comisiones de RP00079 al forzar la reconciliación. Antes «%» después «%»',
      left(current_setting('ensayo_law610_612.com79', true), 400), left(pg_temp.e612_comisiones_rp00079(), 400);
  end if;
  v := v || ' · comisiones RP00079 (devengos, diferencias, error del recálculo) tras forzar la reconciliación: IGUALES';
  -- LAW-611
  select u.id, u.estado, x.cobrado_suelo, x.suelo_precio into r
    from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
   where u.contrato_id = '40f7bd40-52e5-431e-a7ab-0f8f3752ff52';
  v := v || format(E'\\n611 · W3 - C3 %s (suelo cobrado %s de %s) · historial de hoy: %s', r.estado, r.cobrado_suelo, r.suelo_precio,
                   (select string_agg(coalesce(l.motivo, '(sin motivo)') || ' [' || coalesce(l.via, '') || ']', ' | ')
                      from public.unidades_log l where l.unidad_id = r.id and l.en = now()));
  -- LAW-612
  select u.estado, x.cobrado_suelo, x.cobrado_obra, x.suelo_precio,
         public.unidad_cumple_estado(u.id, 'vendida', u.precio, u.precio_suelo) as cumple into r
    from public.unidades u cross join lateral public._unidad_cobro_cascada_v2(u.id) x
   where u.contrato_id = 'f0d47af2-5749-46eb-ad82-00415a95ef4d';
  v := v || format(E'\\n612 · D4 %s · suelo cobrado %s de %s · obra cobrada %s · cumple vendida %s', r.estado, r.cobrado_suelo,
                   r.suelo_precio, r.cobrado_obra, r.cumple);
  v := v || ' · docs: ' || (select string_agg(f.numero || '→' || c.numero || ' (' || coalesce(f.contrato_numero, '') || ')', ', ' order by f.numero)
                             from public.facturas f join public.contratos c on c.id = f.contrato_id
                            where f.id in ('9c69f301-566f-4c6c-9c60-5d87e60f97fd', 'c0babc5f-7dea-47b4-8cdf-65dad9a0e9e3'));
  v := v || ' · cobrado por contrato: ' || (select string_agg(c.numero || ' ' || public._contrato_cobrado_interno(c.id), ', ' order by c.numero)
                                             from public.contratos c
                                            where c.id in ('f0d47af2-5749-46eb-ad82-00415a95ef4d', '54030d81-972f-4da1-9e16-643d033c5fe8'));
  v := v || ' · bases 1-nov: ' ||
       (select b.cobrado_suelo_firmado || '/' || b.cobrado_obra_firmada || ' · ' || b.cobrado_directo_suelo || '/' || b.cobrado_directo_obra
          from public._comisiones_bases_firmadas('f0d47af2-5749-46eb-ad82-00415a95ef4d') b);
  v := v || ' · línea admin de REC00130: ' ||
       coalesce((select string_agg(l.tipo_linea || ' ' || l.importe || ' contrato ' || coalesce(c.numero, '?') || case when l.anulada then ' anulada' else '' end, ', ')
                   from public.comision_admin_lineas l left join public.contratos c on c.id = l.contrato_id
                  where l.recibi_id = 'c0babc5f-7dea-47b4-8cdf-65dad9a0e9e3'), '(ninguna)');
  v := v || ' · comisiones: ' || coalesce((select string_agg(d.nivel || ' ' || d.estado || ' ' || d.importe || ' ' || d.moneda, ', ')
                                            from public.comisiones_devengadas d
                                           where d.contrato_raiz_id = 'f0d47af2-5749-46eb-ad82-00415a95ef4d'), '(ninguna)');
  raise exception E'RES LAW610-612 · las tres aplicadas y deshechas\\n%', v;
end $res$;
"""


def main():
    partes = ['-- ENSAYO DESHECHO de LAW-610, LAW-611 y LAW-612 en la viva de Lawang (15-oct-2026, lawang-cola-2).\n'
              '-- GENERADO por contracts/sql/genera_ensayo_law610_612.py: no se edita a mano.\n'
              '-- Se lanza con tools/lanza_ensayo_viva.py (begin … rollback, nunca confirma), marca «RES LAW610-612».\n',
              INICIO]
    for m in MIGRACIONES:
        datos = open(os.path.join(RAIZ, 'supabase', 'migrations', m), 'rb').read()
        partes.append('-- ── %s · sha256 %s ──\n' % (m, hashlib.sha256(datos).hexdigest()))
        partes.append(datos.decode('utf-8'))
    partes.append(FINAL)
    texto = ''.join(partes)
    with open(SALIDA, 'w', encoding='utf-8', newline='\n') as f:
        f.write(texto)
    print('%s · sha256 %s · %d bytes' % (os.path.relpath(SALIDA, RAIZ), hashlib.sha256(texto.encode('utf-8')).hexdigest(),
                                         len(texto.encode('utf-8'))))


if __name__ == '__main__':
    main()
