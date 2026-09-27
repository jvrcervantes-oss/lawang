#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Migración MASIVA de los anexos viejos de los contratos a Storage (LAW-78, 27-sep-2026).
PREPARADO Y NO EJECUTADO: lanzarlo es decisión del owner (toca `datos` de contratos reales).

QUÉ HACE. Los anexos subidos a mano antes de LAW-78 guardan sus páginas (JPEG en base64) dentro de
`contratos.datos.annexes`. La pantalla ya los pasa al archivo sola al volver a guardar cada contrato
(migración perezosa); esto hace lo mismo con todos de una vez, desde el servidor:
  0. RESPALDO: exige `--respaldo-hecho <fichero>` (la salida de `python tools/backup_lawang.py` de la
     agencia) y además escribe un JSON por contrato con su `annexes` ORIGINAL en
     private/anexos_respaldo_<fecha>/ (gitignorado y cerrado a la web por private/.htaccess).
     Lánzalo desde el clon principal (proyectos/Lawang) para que ese respaldo no se vaya con una copia
     de sesión.
  1. FASE A (subir y comprobar): cada página se sube a una ruta nueva `<contrato>/<uuid>/<n>.jpg` sin
     sobrescribir, se registra su fila (sha256, bytes) y se DESCARGA otra vez para comparar la huella.
  2. FASE B (quitar páginas): SOLO si la fase A salió entera para ese contrato, se llama a
     `contrato_anexos_pasa_a_archivo`, que con la fila del contrato bloqueada comprueba OTRA VEZ en la
     base que cada fila tiene la huella de la página vieja de `datos`, y entonces deja el anexo como
     ficha {id nuevo, title, on}. Si algo no cuadra no quita nada; lo subido lo recoge el barrido.
NO TOCA: contratos bloqueados o con una firma pendiente o dada (se deciden al ejecutar, no por una
lista: el 27-sep eran 16 bloqueados y 5 con firma en curso de 46 con anexos viejos).
TIEMPO: medido el 27-sep con el rol real y ROLLBACK, guardar RP00180 (5,2 MB en la fila) sin páginas
tardó 402 ms; ninguno de los contratos que se pueden tocar corta por el statement_timeout, así que no
hace falta un camino aparte para los grandes (HS00003, 7,3 MB, está bloqueado y no se toca).

    python contracts/tools/anexos_a_storage.py                   # POR DEFECTO --dry: solo cuenta
    python contracts/tools/anexos_a_storage.py --solo RP00159    # uno solo (también en --dry)
    # PRIMERA ejecución real: UN contrato, y se mira el resultado antes de seguir (Datos, consulta de deploy)
    python contracts/tools/anexos_a_storage.py --aplicar --solo RP00159 --respaldo-hecho <fichero de backup_lawang>
    python contracts/tools/anexos_a_storage.py --aplicar --respaldo-hecho <fichero de backup_lawang>   # el resto
Cada contrato pasado deja un evento `anexos_al_archivo` en contrato_eventos (quien = 'migracion LAW-78').

Entorno: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY. No imprime rutas, títulos ni base64: número de
contrato, cuántos anexos, páginas y MB.
"""
import base64
import datetime
import hashlib
import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _supabase_srv as s  # noqa: E402

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
TOPE_PAGINA = 3 * 1024 * 1024


def viejos(annexes):
    return [a for a in (annexes or []) if isinstance(a, dict) and not a.get('auto')
            and isinstance(a.get('pages'), list) and a['pages']]


def bytes_de(pagina):
    txt = str(pagina)
    return base64.b64decode(txt[txt.index(',') + 1:] if ',' in txt else txt)


def firma_viva(cid):
    return bool(s.rest('GET', 'contrato_firmas?select=id&contrato_id=eq.%s&estado=in.(pendiente,firmado)&limit=1' % cid))


def fase_a(cid, anexo):
    """Sube y registra todas las páginas de UN anexo; devuelve el id nuevo. Lanza si algo falla."""
    nuevo = 'ax-' + str(uuid.uuid4())
    for n, pag in enumerate(anexo['pages'], start=1):
        b = bytes_de(pag)
        if not (len(b) >= 3 and b[0] == 0xff and b[1] == 0xd8 and b[2] == 0xff):
            raise ValueError('la página %d no es un JPEG' % n)
        if len(b) > TOPE_PAGINA:
            raise ValueError('la página %d pesa más de 3 MB' % n)
        sha = hashlib.sha256(b).hexdigest()
        path = '%s/%s/%d.jpg' % (cid, uuid.uuid4(), n)
        s.sube(path, b)
        s.rest('POST', 'contrato_anexo_paginas', {'contrato_id': cid, 'anexo_id': nuevo, 'n': n, 'path': path,
                                                  'sha256': sha, 'bytes': len(b), 'creado_por': 'migracion LAW-78'},
               prefer='return=minimal')
        if hashlib.sha256(s.baja(path)).hexdigest() != sha:
            raise ValueError('la página %d no ha llegado igual al archivo' % n)
    return nuevo


def main():
    a = sys.argv
    aplicar = '--aplicar' in a
    solo = a[a.index('--solo') + 1] if '--solo' in a else None
    if aplicar:
        if '--respaldo-hecho' not in a or not os.path.isfile(a[a.index('--respaldo-hecho') + 1]):
            sys.exit('Antes de aplicar: python tools/backup_lawang.py (agencia) y pasa su fichero con --respaldo-hecho <fichero>.')
        dir_resp = os.path.join(RAIZ, 'private', 'anexos_respaldo_' + datetime.datetime.now().strftime('%Y%m%d_%H%M'))
        os.makedirs(dir_resp, exist_ok=True)
    contratos = s.rest('GET', 'contratos?select=id,numero,bloqueado&order=numero' + ('&numero=eq.' + solo if solo else '')) or []
    tot = {'con_viejos': 0, 'saltados': 0, 'hechos': 0, 'fallidos': 0, 'paginas': 0, 'bytes': 0}
    for c in contratos:
        fila = s.rest('GET', 'contratos?select=annexes:datos->annexes&id=eq.%s' % c['id'])
        annexes = (fila[0] or {}).get('annexes') if fila else None
        vs = viejos(annexes)
        if not vs:
            continue
        tot['con_viejos'] += 1
        pags = sum(len(x['pages']) for x in vs)
        # páginas guardadas sin el prefijo `data:…,` (el 27-sep: ninguna de 340). Se pasan igual —bytes_de y la base
        # las decodifican igual—, pero se dice, por si una no fuera base64 de verdad.
        sin_prefijo = sum(1 for x in vs for p in x['pages'] if not str(p).startswith('data:'))
        peso = sum(len(bytes_de(p)) for x in vs for p in x['pages'])
        if c.get('bloqueado') or firma_viva(c['id']):
            tot['saltados'] += 1
            print('%-10s no se toca (%s): %d anexo(s), %d pág.' % (c['numero'], 'bloqueado' if c.get('bloqueado') else 'firma en curso o dada', len(vs), pags))
            continue
        tot['paginas'] += pags
        tot['bytes'] += peso
        if not aplicar:
            print('%-10s pasaría %d anexo(s), %d pág., %.1f MB%s' % (c['numero'], len(vs), pags, peso / 1048576,
                  (' · %d pág. sin prefijo data:' % sin_prefijo) if sin_prefijo else ''))
            continue
        with open(os.path.join(dir_resp, '%s_%s.json' % (c['numero'], c['id'])), 'w', encoding='utf-8') as fh:
            json.dump({'id': c['id'], 'numero': c['numero'], 'annexes': annexes}, fh, ensure_ascii=False)
        mapa = {}
        try:
            for x in vs:
                mapa[x['id']] = {'id': fase_a(c['id'], x)}
            k = s.rpc('contrato_anexos_pasa_a_archivo', {'p_contrato': c['id'], 'p_mapa': mapa})
            tot['hechos'] += 1
            print('%-10s pasado: %s anexo(s), %d pág.' % (c['numero'], k, pags))
        except (s.ErrorSupabase, ValueError) as e:
            tot['fallidos'] += 1
            # el mensaje de la base nombra el id del anexo, nunca rutas ni base64
            print('%-10s NO pasado, no se ha quitado nada: %s' % (c['numero'], str(e)[:200]))
    print('\n%d contrato(s) con anexos viejos; %d no se tocan; %d pág. y %.1f MB %s; %d hecho(s), %d fallido(s).'
          % (tot['con_viejos'], tot['saltados'], tot['paginas'], tot['bytes'] / 1048576,
             'pasadas' if aplicar else 'se pasarían', tot['hechos'], tot['fallidos']))
    if not aplicar:
        print('Modo prueba (--dry): no se ha tocado nada.')
    return 1 if tot['fallidos'] else 0


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    try:
        sys.exit(main())
    except s.ErrorSupabase as e:
        sys.exit('Parado: %s' % e)
