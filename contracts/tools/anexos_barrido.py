#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Barrido del archivo de anexos de contrato (LAW-78, 27-sep-2026). PREPARADO, NO PROGRAMADO.

QUÉ RECOGE. Lo que lista `contrato_anexos_huerfanos(p_horas)` (migración 20260927220500), con más de 48 h:
  · objetos del bucket `contratos-anexos` sin fila (subida que no llegó a registrarse, contrato borrado);
  · filas cuyo anexo no nombra nadie en `datos.annexes` de su contrato (subida a medias, anexo quitado y
    guardado, paso al archivo que no terminó) — solo en contratos sin bloquear y sin firma viva.
POR QUÉ ASÍ. El borrado en caliente se descartó en la revisión previa (Datos + Seguridad): un anexo
recién subido aún no está en `datos` hasta que el comercial pulsa Guardar, y borrar «lo que no está en
datos» en el momento se llevaría por delante una subida válida. 48 h después, lo que no se guardó sobra.
ORDEN (consulta de deploy de Datos, 27-sep):
  1. objetos sin fila → se borran por la API de Storage (SQL no puede borrar ficheros);
  2. filas sobrantes → las borra la BASE (`contrato_anexos_barre_filas`), con los contratos bloqueados
     `for update` para no cruzarse con un contrato_guarda, y devuelve sus rutas;
  3. esos objetos → por la API de Storage. Si este paso falla, quedan objetos sin fila, que el paso 1 de la
     siguiente pasada recoge. Nunca queda una fila apuntando a un objeto borrado.

    python contracts/tools/anexos_barrido.py              # por defecto: SOLO cuenta, no borra nada
    python contracts/tools/anexos_barrido.py --aplicar    # borra
    python contracts/tools/anexos_barrido.py --horas 72   # ventana (mínimo 24; lo impone también la base)

Entorno: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY (ver _supabase_srv.py). No imprime rutas ni nombres:
solo cuántos. Para programarlo (cron diario, o una Edge con pg_cron) hace falta el OK del owner: hoy no
lo está.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _supabase_srv as s  # noqa: E402


def lista(horas):
    return s.rpc('contrato_anexos_huerfanos', {'p_horas': horas}) or []


def main():
    a = sys.argv
    horas = int(a[a.index('--horas') + 1]) if '--horas' in a else 48
    aplicar = '--aplicar' in a
    h = lista(horas)
    objetos = [x['path'] for x in h if x['tipo'] == 'objeto']
    filas = [x for x in h if x['tipo'] == 'fila']
    print('Sobrante con más de %d h: %d objeto(s) sin fila, %d fila(s) sin anexo que las nombre.' % (horas, len(objetos), len(filas)))
    if not aplicar:
        print('Modo prueba: no se ha borrado nada. --aplicar para borrar.')
        return 0
    if objetos:
        print('Objetos sin fila borrados: %d' % s.borra_objetos(objetos))
    if filas:
        # la base decide otra vez, con los contratos bloqueados: solo lo que SIGUE sobrando
        rutas = [x['path'] for x in (s.rpc('contrato_anexos_barre_filas', {'p_horas': horas}) or [])]
        print('Filas sobrantes borradas: %d' % len(rutas))
        try:
            print('Sus objetos borrados: %d' % s.borra_objetos(rutas))
        except s.ErrorSupabase as e:
            print('Los objetos de esas filas no se han podido borrar (%s): la siguiente pasada los recoge como objetos sin fila.' % str(e)[:120])
    return 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    try:
        sys.exit(main())
    except s.ErrorSupabase as e:
        sys.exit('El barrido se ha parado: %s' % e)
