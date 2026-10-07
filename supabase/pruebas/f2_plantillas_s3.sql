-- Prueba de la S3 de plantillas por empresa (7-oct-2026): validador en servidor `plantilla_cuerpo_valida` / `plantilla_cuerpo_valida_semilla`.
-- Se ejecuta DESPUES de la migracion 20261008990000 (o pegada tras ella para ensayarla sin rastro). Termina en raise (rollback). Debe acabar con «FALLOS=0».
-- Parte A (los 20 HTML originales de contracts/templates/ + bateria de mutacion): necesita leer ficheros del servidor (pg_read_file, superusuario) y se activa con
--     psql -c "select set_config('plantillas.dir','C:/ruta/a/contracts/templates',false)" -f f2_plantillas_s3.sql      (el set_config y el script, en la MISMA sesion)
--   Sin esa ruta la parte A se OMITE y el informe lo dice en voz alta («OMITIDO», OMITIDAS=1): no cuenta como aprobada.
-- Partes B (cargas hostiles), C (rendimiento sintetico), D (permisos y pureza) corren en cualquier base, tambien pegadas por MCP (execute_sql); no usa metacomandos de psql.
-- destructivo-ok: prueba en transaccion que termina en raise; sin drop de nada que no sea temporal

create or replace function pg_temp.sin_notas(p_txt text) returns text language plpgsql as $f$
declare c text; t text := p_txt;
begin
  for c in select (regexp_matches(p_txt, '<!--.*?-->', 'g'))[1] loop
    if c !~ '^<!--(if:[a-z0-9_]+=[a-z0-9_]*|opt:[a-z0-9_]+|/(if|opt):[a-z0-9_]+|/?seccion-hitos|/?seccion-extras-construccion|extra-clauses|firmas-adquirientes|compradores-extra|datos-bancarios|datos-bancarios-sin-titulo|hitos|extras-construccion|cuenta:[a-z0-9_]+)-->$' then
      t := replace(t, c, '');
    end if;
  end loop;
  return t;
end $f$;

do $t$
declare
  r text := ''; fallos int := 0; omit int := 0; nprueba int := 0;
  dir text := nullif(current_setting('plantillas.dir', true), '');
  nombres text[] := string_to_array('adenda,anexo_x_bonian_c2,anexo_y_bonian_c2,carta_reserva,carta_reserva_ampliada,carta_reserva_hak_sewa,carta_reserva_investor_deck,carta_reserva_pma,cc00014_timon,colaborador_operativo,commercial_collaboration,commercial_offer,estatutos_sw,hak_sewa_notario,poa_notario,ppjb_bonian,ppjb_bonian_c2,ppjb_construccion,ppjb_parcela,ppjb_reserva', ',');
  nm text; txt text; ssn text; v jsonb; v2 jsonb; mut text; expct text; mutado text; n_ap int; n_rech int; n_skip int; t0 timestamptz; ms numeric;
  m1 text := (public._plantilla_marcadores())[1];
  base text;
  hostil record; ok boolean; hit boolean; i int;
  muts text[][] := array[
    ['script',        '</body>',                                  '<script>alert(1)</script></body>',                                   'etiqueta prohibida <script>'],
    ['onclick',       '<p ',                                      '<p onclick="x" ',                                                   'manejador de evento prohibido'],
    ['quitar cierre if', '<!--/if:[a-z0-9_]+-->',                 '',                                                                  'sin su apertura|desbalanceados|cruzado|esqueleto cambia'],
    ['marcador falso','\{\{[a-z0-9_]+\}\}',                       '{{zzz_no_existe}}',                                                 'zzz_no_existe'],
    ['quitar fila',   '<tr[ >].*?</tr>',                          '',                                                                  'esqueleto cambia'],
    ['tocar style',   '<style>',                                  '<style> ',                                                          'bloques <style>'],
    ['cambiar img',   'assets/brand/',                            'assets/brand/x',                                                    'imagenes|<img src> fuera'],
    ['quitar comentario motor', '<!--(extra-clauses|firmas-adquirientes|compradores-extra|hitos|datos-bancarios|cuenta:[a-z0-9_]+)-->', '', 'comentarios del motor'],
    ['style nuevo',   '<p data-lang',                             '<p style="margin:7px" data-lang',                                   'style en linea|atributo repetido'],
    ['a javascript',  '</body>',                                  '<a href="javascript:alert(1)">x</a></body>',                        'etiqueta prohibida <a>'],
    ['entidad lt',    '<p data-lang="es">',                       '<p data-lang="es">&#60;script',                                     'decodifica'],
    ['bidi',          '<p data-lang="es">',                       '<p data-lang="es">'||chr(8238),                                      'bidireccional'],
    ['class ajena',   '<p data-lang="es">',                       '<p data-lang="es" class="evil">',                                   'class fuera'],
    ['comentario ajeno', '</html>',                               '</html><!-- hola -->',                                              'comentario no permitido'],
    ['data-lang fr',  '<p data-lang="es">',                       '<p data-lang="fr">',                                                'data-lang'],
    ['img extra',     '</body>',                                  '<img src="assets/brand/firma-lawang.png" alt=""></body>',          'imagenes'],
    ['style extra',   '</head>',                                  '<style>p{color:red}</style></head>',                                'bloques <style>'],
    ['iframe',        '</body>',                                  '<iframe src="x"></iframe></body>',                                  'etiqueta prohibida <iframe>'],
    ['svg',           '</body>',                                  '<svg onload="x"></svg></body>',                                     'etiqueta prohibida <svg>'],
    ['llave suelta',  '<p data-lang="es">',                       '<p data-lang="es">{{',                                              'llave suelta'],
    ['entidad bidi',  '<p data-lang="es">',                       '<p data-lang="es">&#x202E;',                                        'entidad no permitida'],
    ['ancho cero',    '<p data-lang="es">',                       '<p data-lang="es">Te'||chr(8203)||'pi',                              'invisible'],
    ['style copiado a un parrafo', '<h2 ',                        '<p style="max-height:20mm;max-width:100%">x</p><h2 ',              'style en linea|style de <p>']
  ];
  hostiles jsonb;
begin
  -- ============================================================ PARTE A: los 20 originales
  if dir is null then
    omit := omit + 1;
    r := r || E'OMITIDO  Parte A (20 originales + mutacion): no se paso plantillas.dir; NO cuenta como aprobada' || E'\n';
  else
    -- A1: las 20 originales pasan como semilla (copia exacta, con sus notas de autor) y sin los fallos que el encargo temia
    for i in 1 .. cardinality(nombres) loop
      nm := nombres[i]; txt := pg_read_file(dir || '/' || nm || '.html');
      t0 := clock_timestamp();
      v := public.plantilla_cuerpo_valida_semilla(txt, null);
      ms := extract(epoch from clock_timestamp() - t0) * 1000;
      nprueba := nprueba + 1;
      if (v->>'ok')::boolean then
        r := r || 'OK    A1 semilla ' || nm || ' (' || (v->>'n_marcadores') || ' marcadores, ' || (v->>'n_notas') || ' notas, ' || round(ms) || ' ms)' || E'\n';
      else
        r := r || 'FALLO A1 semilla ' || nm || ': ' || (v->'errores')::text || E'\n'; fallos := fallos + 1;
      end if;
      -- A2: la version "activada" (sin notas de autor) parte de la semilla como esqueleto y pasa el validador NORMAL
      ssn := pg_temp.sin_notas(txt);
      v := public.plantilla_cuerpo_valida(ssn, txt);
      nprueba := nprueba + 1;
      if (v->>'ok')::boolean then r := r || 'OK    A2 activar sin notas ' || nm || E'\n';
      else r := r || 'FALLO A2 activar sin notas ' || nm || ': ' || (v->'errores')::text || E'\n'; fallos := fallos + 1; end if;
      -- A3: sin notas pasa tambien como semilla, y la semilla no admite una sola nota de mas en el modo normal
      v := public.plantilla_cuerpo_valida(txt, txt);
      nprueba := nprueba + 1;
      if ssn <> txt then
        if not (v->>'ok')::boolean and exists (select 1 from jsonb_array_elements_text(v->'errores') e where e like 'comentario no permitido%') then
          r := r || 'OK    A3 el modo normal rechaza las notas de autor de ' || nm || E'\n';
        else
          r := r || 'FALLO A3 el modo normal acepto las notas de autor de ' || nm || ': ' || left(v::text, 200) || E'\n'; fallos := fallos + 1;
        end if;
      end if;
    end loop;

    -- A4: bateria de mutacion sobre cada original (la mutacion se rechaza SIEMPRE que se pueda aplicar; se cuentan las que no aplican)
    n_ap := 0; n_rech := 0; n_skip := 0;
    for i in 1 .. cardinality(nombres) loop
      nm := nombres[i]; ssn := pg_temp.sin_notas(pg_read_file(dir || '/' || nm || '.html'));
      for j in 1 .. array_length(muts, 1) loop
        mutado := regexp_replace(ssn, muts[j][2], muts[j][3]);
        if mutado = ssn then n_skip := n_skip + 1; continue; end if;
        n_ap := n_ap + 1;
        v := public.plantilla_cuerpo_valida(mutado, ssn);
        if not (v->>'ok')::boolean and exists (select 1 from jsonb_array_elements_text(v->'errores') e where e ~* muts[j][4]) then
          n_rech := n_rech + 1;
        else
          fallos := fallos + 1;
          r := r || 'FALLO A4 mutacion «' || muts[j][1] || '» sobre ' || nm || ' no se rechazo con «' || muts[j][4] || '»: ' || left(v::text, 300) || E'\n';
        end if;
      end loop;
    end loop;
    nprueba := nprueba + n_ap;
    r := r || 'INFO  A4 bateria de mutacion: ' || n_ap || ' aplicadas, ' || n_rech || ' rechazadas con el error esperado, ' || n_skip || ' no aplicables (la plantilla no tiene ese elemento)' || E'\n';
  end if;

  -- ============================================================ PARTE B: cargas hostiles sobre un esqueleto pequeno y controlado
  base := '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><title>T</title><style>.f{color:red}</style></head><body><div class="doc">'
       || '<div class="doc-watermark" aria-hidden="true">W</div><h2 data-lang="es">Titulo</h2><p data-lang="es">Hola {{' || m1 || '}} &amp; &nbsp; fin</p>'
       || '<!--if:adq1_tipo=empresa--><p data-lang="es">Empresa</p><!--/if:adq1_tipo--><!--opt:' || m1 || '--><p data-lang="es">Opcional</p><!--/opt:' || m1 || '-->'
       || '<table class="pays"><tbody><tr><td class="f">x</td><td colspan="2">y</td></tr></tbody></table><ul data-lang="es"><li>uno</li></ul>'
       || '<!--extra-clauses--><img src="assets/brand/firma-lawang.png" alt="" style="max-height:20mm;max-width:100%"></div></body></html>';
  -- el propio esqueleto, con otro texto, otro parrafo y los atributos reordenados, es valido
  select (public.plantilla_cuerpo_valida(base, base)->>'ok')::boolean into ok; nprueba := nprueba + 1;
  if ok then r := r || E'OK    B0 el esqueleto pasa contra si mismo\n'; else r := r || 'FALLO B0 el esqueleto no pasa contra si mismo: ' || public.plantilla_cuerpo_valida(base, base)::text || E'\n'; fallos := fallos + 1; end if;
  for hostil in select * from jsonb_to_recordset(jsonb_build_array(
    jsonb_build_object('n','E1 editar texto, anadir parrafo y reordenar atributos', 'ok', true, 'x', null,
      'c', replace(replace(base, 'Hola {{', 'Estimado/a {{'), '<h2 data-lang="es">Titulo</h2>', '<h2 data-lang="es">Otro titulo</h2><p data-lang="id">Paragraf baru &ldquo;dua&rdquo;</p>')),
    jsonb_build_object('n','E2 reordenar atributos de td', 'ok', true, 'x', null, 'c', replace(base, '<td colspan="2">', '<td  colspan="2" >')),
    jsonb_build_object('n','E3 "&" suelto antes de espacio', 'ok', true, 'x', null, 'c', replace(base, 'fin', 'A & B fin')),
    jsonb_build_object('n','H1 script', 'x', 'etiqueta prohibida <script>', 'c', replace(base, '</div>', '<script>alert(1)</script></div>')),
    jsonb_build_object('n','H2 script en mayusculas', 'x', 'etiqueta prohibida <script>', 'c', replace(base, '</div>', '<SCRIPT>alert(1)</SCRIPT></div>')),
    jsonb_build_object('n','H3 iframe', 'x', 'etiqueta prohibida <iframe>', 'c', replace(base, '</div>', '<iframe src="https://x.test"></iframe></div>')),
    jsonb_build_object('n','H4 object', 'x', 'etiqueta prohibida <object>', 'c', replace(base, '</div>', '<object data="x"></object></div>')),
    jsonb_build_object('n','H5 embed', 'x', 'etiqueta prohibida <embed>', 'c', replace(base, '</div>', '<embed src="x"></div>')),
    jsonb_build_object('n','H6 svg con onload', 'x', 'etiqueta prohibida <svg>', 'c', replace(base, '</div>', '<svg onload="alert(1)"></svg></div>')),
    jsonb_build_object('n','H7 math', 'x', 'etiqueta prohibida <math>', 'c', replace(base, '</div>', '<math><mi>x</mi></math></div>')),
    jsonb_build_object('n','H8 link css externo', 'x', 'etiqueta prohibida <link>', 'c', replace(base, '</head>', '<link rel="stylesheet" href="https://x.test/a.css"></head>')),
    jsonb_build_object('n','H9 meta refresh', 'x', 'atributo no permitido en <meta>', 'c', replace(base, '<meta charset="utf-8">', '<meta charset="utf-8"><meta http-equiv="refresh" content="0;url=https://x.test">')),
    jsonb_build_object('n','H10 base href', 'x', 'etiqueta prohibida <base>', 'c', replace(base, '</head>', '<base href="https://x.test/"></head>')),
    jsonb_build_object('n','H11 form+input+button', 'x', 'etiqueta prohibida <form>', 'c', replace(base, '</div>', '<form action="https://x.test"><input name="a"><button>ok</button></form></div>')),
    jsonb_build_object('n','H12 a javascript:', 'x', 'etiqueta prohibida <a>', 'c', replace(base, '</div>', '<a href="javascript:alert(1)">pulsa</a></div>')),
    jsonb_build_object('n','H13 onclick', 'x', 'manejador de evento prohibido', 'c', replace(base, '<h2 data-lang="es">', '<h2 onclick="alert(1)" data-lang="es">')),
    jsonb_build_object('n','H14 onerror sin comillas', 'x', 'etiqueta mal formada', 'c', replace(base, '</div>', '<img src=x onerror=alert(1)></div>')),
    jsonb_build_object('n','H15 style con url()', 'x', 'style de <p>', 'c', replace(base, '<h2 data-lang="es">', '<p style="background:url(https://x.test/a.png)">x</p><h2 data-lang="es">')),
    jsonb_build_object('n','H16 style nuevo position:fixed', 'x', 'propiedad CSS no permitida', 'c', replace(base, '<h2 data-lang="es">', '<p style="position:fixed;top:0">x</p><h2 data-lang="es">')),
    jsonb_build_object('n','H17 style legitimo pero nuevo', 'x', 'style en linea', 'c', replace(base, '<h2 data-lang="es">', '<p style="margin:3px">x</p><h2 data-lang="es">')),
    jsonb_build_object('n','H18 img data: extra', 'x', 'imagenes', 'c', replace(base, '</div>', '<img src="data:image/png;base64,AAAA" alt=""></div>')),
    jsonb_build_object('n','H19 &lt; entidad', 'x', 'decodifica', 'c', replace(base, 'fin', '&lt;script&gt;fin')),
    jsonb_build_object('n','H20 &#60; numerica', 'x', 'decodifica', 'c', replace(base, 'fin', '&#60;fin')),
    jsonb_build_object('n','H21 &#x3C; hex con ceros', 'x', 'decodifica', 'c', replace(base, 'fin', '&#x0003C;fin')),
    jsonb_build_object('n','H22 &lt sin punto y coma', 'x', 'decodifica', 'c', replace(base, 'fin', '&ltscript fin')),
    jsonb_build_object('n','H23 marcador fuera de la lista', 'x', 'marcador desconocido', 'c', replace(base, 'fin', '{{__proto__}} fin')),
    jsonb_build_object('n','H24 marcador con espacios/expresion', 'x', 'forma no permitida', 'c', replace(base, 'fin', '{{ ' || m1 || ' }} {{a.b}} fin')),
    jsonb_build_object('n','H25 triple llave', 'x', 'llave suelta', 'c', replace(base, 'fin', '{{{' || m1 || '}}} fin')),
    jsonb_build_object('n','H26 if sin cierre', 'x', 'sin cerrar', 'c', replace(base, '<!--/if:adq1_tipo-->', '')),
    jsonb_build_object('n','H27 if anidado del mismo campo', 'x', 'anidado', 'c', replace(base, '<p data-lang="es">Empresa</p>', '<!--if:adq1_tipo=persona--><p data-lang="es">Empresa</p><!--/if:adq1_tipo-->')),
    jsonb_build_object('n','H28 if/opt cruzados', 'x', 'sin su apertura', 'c', replace(replace(base, '<!--/if:adq1_tipo-->', '<!--/opt:' || m1 || '-->'), '<!--/opt:' || m1 || '--></div>', '<!--/if:adq1_tipo--></div>')),
    jsonb_build_object('n','H29 if sobre campo desconocido', 'x', 'campo desconocido', 'c', replace(base, 'adq1_tipo=empresa', 'zzz_campo=empresa')),
    jsonb_build_object('n','H30 comentario ajeno', 'x', 'comentario no permitido', 'c', replace(base, '</div>', '<!-- TODO borrar --></div>')),
    jsonb_build_object('n','H31 comentario condicional IE', 'x', 'comentario no permitido', 'c', replace(base, '</div>', '<!--[if IE]><script>x</script><![endif]--></div>')),
    jsonb_build_object('n','H32 comentario degenerado', 'x', 'comentario degenerado', 'c', replace(base, '</div>', '<!--><script>alert(1)</script></div>')),
    jsonb_build_object('n','H33 cierre alternativo --!>', 'x', 'comentario', 'c', replace(base, '</div>', '<!-- x --!><script>alert(1)</script> --></div>')),
    jsonb_build_object('n','H34 CDATA', 'x', 'declaracion no permitida', 'c', replace(base, '</div>', '<![CDATA[x]]></div>')),
    jsonb_build_object('n','H35 instruccion <?', 'x', 'instruccion de proceso', 'c', replace(base, '</div>', '<?php echo 1 ?></div>')),
    jsonb_build_object('n','H36 < suelto en el texto', 'x', 'suelto', 'c', replace(base, 'fin', 'a < b fin')),
    jsonb_build_object('n','H37 etiqueta partida <scr<script>ipt>', 'x', 'etiqueta', 'c', replace(base, '</div>', '<scr<script>ipt>alert(1)</scr</script>ipt></div>')),
    jsonb_build_object('n','H38 p/onclick sin espacio', 'x', 'etiqueta mal formada', 'c', replace(base, '</div>', '<p/onclick=alert(1)>x</p></div>')),
    jsonb_build_object('n','H39 atributo repetido', 'x', 'atributo repetido', 'c', replace(base, '<h2 data-lang="es">', '<h2 data-lang="es" data-lang="en">')),
    jsonb_build_object('n','H40 data-lang fuera de lista', 'x', 'data-lang debe ser', 'c', replace(base, '<h2 data-lang="es">', '<h2 data-lang="xx">')),
    jsonb_build_object('n','H41 class fuera de lista', 'x', 'class fuera de la lista fija', 'c', replace(base, '<td class="f">', '<td class="f admin-only">')),
    jsonb_build_object('n','H42 data-campo desconocido', 'x', 'data-campo desconocido', 'c', replace(base, '<h2 data-lang="es">', '<h2 data-campo="evil" data-lang="es">')),
    jsonb_build_object('n','H43 cierre cruzado', 'x', 'sin su apertura', 'c', replace(base, '</ul>', '</div>')),
    jsonb_build_object('n','H44 autocierre en etiqueta no vacia', 'x', 'autocierre', 'c', replace(base, '<h2 data-lang="es">', '<p/><h2 data-lang="es">')),
    jsonb_build_object('n','H45 </style/> con script detras', 'x', 'etiqueta prohibida <script>', 'c', replace(base, '.f{color:red}</style>', '.f{color:red}</style/><script>alert(1)</script><style>')),
    jsonb_build_object('n','H46 cambio de estructura: fila de mas', 'x', 'esqueleto cambia', 'c', replace(base, '</tr>', '</tr><tr><td class="f">nueva</td></tr>')),
    jsonb_build_object('n','H47 cambio de estructura: colspan', 'x', 'esqueleto cambia', 'c', replace(base, 'colspan="2"', 'colspan="3"')),
    jsonb_build_object('n','H48 quitar comentario del motor', 'x', 'esqueleto cambia', 'c', replace(base, '<!--extra-clauses-->', '')),
    jsonb_build_object('n','H49 cambiar el valor de un if', 'x', 'esqueleto cambia', 'c', replace(base, 'adq1_tipo=empresa', 'adq1_tipo=persona')),
    jsonb_build_object('n','H50 cambiar el <style>', 'x', 'bloques <style>', 'c', replace(base, 'color:red', 'color:blue')),
    jsonb_build_object('n','H51 style con @import', 'x', 'bloques <style>', 'c', replace(base, '.f{color:red}', '@import url(https://x.test/a.css);.f{color:red}')),
    jsonb_build_object('n','H52 cambiar la ruta de una imagen', 'x', 'imagenes', 'c', replace(base, 'firma-lawang.png', 'firma-otra.png')),
    jsonb_build_object('n','H53 bidi override (Trojan Source)', 'x', 'bidireccional', 'c', replace(base, 'fin', 'fin ' || chr(8238) || '1.000')),
    jsonb_build_object('n','H54 caracter de control', 'x', 'control', 'c', replace(base, 'fin', 'fi' || chr(1) || 'n')),
    jsonb_build_object('n','H55 cuerpo demasiado grande', 'x', 'demasiado grande', 'c', base || repeat('x', 600001)),
    jsonb_build_object('n','H56 demasiados marcadores', 'x', 'demasiados marcadores', 'c', replace(base, 'fin', repeat('{{' || m1 || '}}', 601))),
    jsonb_build_object('n','H57 demasiadas etiquetas', 'x', 'demasiadas etiquetas', 'c', replace(base, 'fin', repeat('<b>x</b>', 41000))),
    jsonb_build_object('n','H58 anidamiento profundo', 'x', 'profundo', 'c', replace(base, 'fin', repeat('<span>', 200) || 'x' || repeat('</span>', 200))),
    jsonb_build_object('n','H59 etiqueta sin cerrar', 'x', 'sin cerrar', 'c', replace(base, 'fin', '<b>fin')),
    jsonb_build_object('n','H60 colspan hostil', 'x', 'colspan', 'c', replace(base, 'colspan="2"', 'colspan="99999"')),
    jsonb_build_object('n','H61 lang de html fuera de lista', 'x', 'lang de <html>', 'c', replace(base, 'lang="es"', 'lang="xx"')),
    jsonb_build_object('n','H62 vacio', 'x', 'vacio', 'c', ''),
    jsonb_build_object('n','H63 style en un <b> (no admite style)', 'x', 'atributo no permitido', 'c', replace(base, '<h2 data-lang="es">', '<b style="margin:0">x</b><h2 data-lang="es">')),
    jsonb_build_object('n','H64 src de img con marcador ajeno', 'x', 'imagenes', 'c', replace(base, 'src="assets/brand/firma-lawang.png"', 'src="{{' || m1 || '}}"')),
    jsonb_build_object('n','H66 entidad numerica bidi &#x202E;', 'x', 'entidad no permitida', 'c', replace(base, 'fin', '&#x202E;fin')),
    jsonb_build_object('n','H67 entidad numerica decimal &#8238;', 'x', 'entidad no permitida', 'c', replace(base, 'fin', '&#8238;fin')),
    jsonb_build_object('n','H68 entidad con nombre &rlm;', 'x', 'entidad no permitida', 'c', replace(base, 'fin', '&rlm;fin')),
    jsonb_build_object('n','H69 entidad de control &#1;', 'x', 'entidad no permitida', 'c', replace(base, 'fin', '&#1;fin')),
    jsonb_build_object('n','H70 ancho cero en crudo (U+200B)', 'x', 'invisible', 'c', replace(base, 'fin', 'Te' || chr(8203) || 'pi Sun Gai fin')),
    jsonb_build_object('n','H71 guion blando (U+00AD)', 'x', 'invisible', 'c', replace(base, 'fin', 'Te' || chr(173) || 'pi fin')),
    jsonb_build_object('n','H72 style del esqueleto copiado a otro elemento', 'x', 'style en linea', 'c', replace(base, '<h2 data-lang="es">', '<p style="max-height:20mm;max-width:100%">oculto</p><h2 data-lang="es">')),
    jsonb_build_object('n','H73 doc-watermark en un parrafo nuevo', 'x', 'doc-watermark', 'c', replace(base, '<h2 data-lang="es">', '<p class="doc-watermark">x</p><h2 data-lang="es">')),
    jsonb_build_object('n','H74 quitar el doc-watermark', 'x', 'esqueleto cambia', 'c', replace(base, '<div class="doc-watermark" aria-hidden="true">W</div>', '')),
    jsonb_build_object('n','H75 entidad permitida si pasa', 'ok', true, 'x', null, 'c', replace(base, 'fin', '&ldquo;fin&rdquo; &#x27; &#39; &euro; &hellip;')),
    jsonb_build_object('n','H65 marcador en un atributo', 'x', 'llaves en un atributo', 'c', replace(base, 'alt=""', 'alt="{{' || m1 || '}}"'))
  )) as x(n text, ok boolean, x text, c text) loop
    nprueba := nprueba + 1;
    v := public.plantilla_cuerpo_valida(hostil.c, base);
    if coalesce(hostil.ok, false) then
      if (v->>'ok')::boolean then r := r || 'OK    B ' || hostil.n || E'\n';
      else r := r || 'FALLO B ' || hostil.n || ' deberia pasar: ' || left((v->'errores')::text, 300) || E'\n'; fallos := fallos + 1; end if;
    else
      hit := exists (select 1 from jsonb_array_elements_text(v->'errores') e where position(lower(hostil.x) in lower(e)) > 0);
      if not (v->>'ok')::boolean and hit then r := r || 'OK    B ' || hostil.n || E'\n';
      else r := r || 'FALLO B ' || hostil.n || ' no se rechazo con «' || hostil.x || '»: ' || left(v::text, 300) || E'\n'; fallos := fallos + 1; end if;
    end if;
  end loop;
  -- sin esqueleto, el modo normal no valida nada (solo la carga v1 va sin esqueleto)
  v := public.plantilla_cuerpo_valida(base, null); nprueba := nprueba + 1;
  if not (v->>'ok')::boolean and (v->'errores'->>0) like 'falta el esqueleto%' then r := r || E'OK    B sin esqueleto el modo normal rechaza\n';
  else r := r || E'FALLO B sin esqueleto el modo normal no rechazo\n'; fallos := fallos + 1; end if;
  -- una semilla con una nota de autor pasa; la misma con <script> en la nota... tambien (es un comentario) pero con --!> no
  v := public.plantilla_cuerpo_valida_semilla(replace(base, '</div>', '<!-- nota de Legal: ver proyectos/x < y --></div>'), null); nprueba := nprueba + 1;
  if (v->>'ok')::boolean and (v->>'n_notas')::int >= 1 then r := r || E'OK    B semilla acepta una nota de autor con "<" dentro\n';
  else r := r || 'FALLO B semilla con nota: ' || v::text || E'\n'; fallos := fallos + 1; end if;
  v := public.plantilla_cuerpo_valida_semilla(replace(base, '</div>', '<!-- nota --!><script>x</script> --></div>'), null); nprueba := nprueba + 1;
  if not (v->>'ok')::boolean then r := r || E'OK    B semilla rechaza nota con --!>\n'; else r := r || E'FALLO B semilla acepto --!>\n'; fallos := fallos + 1; end if;
  v := public.plantilla_cuerpo_valida_semilla(replace(base, '</div>', '<script>x</script></div>'), null); nprueba := nprueba + 1;
  if not (v->>'ok')::boolean then r := r || E'OK    B semilla tambien rechaza <script>\n'; else r := r || E'FALLO B semilla acepto script\n'; fallos := fallos + 1; end if;
  v := public.plantilla_cuerpo_valida_semilla(replace(base, 'src="assets/brand/firma-lawang.png"', 'src="https://x.test/a.png"'), null); nprueba := nprueba + 1;
  if not (v->>'ok')::boolean then r := r || E'OK    B semilla rechaza una imagen externa\n'; else r := r || E'FALLO B semilla acepto img externa\n'; fallos := fallos + 1; end if;

  -- ============================================================ PARTE C: rendimiento
  t0 := clock_timestamp();
  txt := '<html><body>' || repeat('<p data-lang="es">Texto de una clausula con {{' || m1 || '}} y &amp; entidad. ' || repeat('Lorem ipsum dolor sit amet consectetur. ', 14) || '</p><!--if:adq1_tipo=empresa--><span>a</span><!--/if:adq1_tipo-->', 450) || '</body></html>';
  v := public.plantilla_cuerpo_valida_semilla(txt, null);
  ms := extract(epoch from clock_timestamp() - t0) * 1000; nprueba := nprueba + 1;
  if (v->>'ok')::boolean and ms < 3000 then r := r || 'OK    C1 ' || (octet_length(txt) / 1000) || ' KB sintetico de 450 clausulas en ' || round(ms) || ' ms' || E'\n';
  else r := r || 'FALLO C1 rendimiento ' || round(ms) || ' ms: ' || left(v::text, 200) || E'\n'; fallos := fallos + 1; end if;
  t0 := clock_timestamp();
  v := public.plantilla_cuerpo_valida(txt, txt);
  ms := extract(epoch from clock_timestamp() - t0) * 1000; nprueba := nprueba + 1;
  if (v->>'ok')::boolean and ms < 6000 then r := r || 'OK    C2 contra esqueleto (dos analisis) ' || round(ms) || ' ms' || E'\n';
  else r := r || 'FALLO C2 rendimiento contra esqueleto ' || round(ms) || ' ms: ' || left(v::text, 200) || E'\n'; fallos := fallos + 1; end if;
  -- peor caso tolerado: 40000 etiquetas hasta el tope, y 590 KB de texto sin una sola etiqueta
  t0 := clock_timestamp();
  txt := '<html><body>' || repeat('<b>x</b>', 39990) || '</body></html>';
  v := public.plantilla_cuerpo_valida_semilla(txt, null);
  ms := extract(epoch from clock_timestamp() - t0) * 1000; nprueba := nprueba + 1;
  if (v->>'ok')::boolean and ms < 6000 then r := r || 'OK    C3 casi 80000 etiquetas en ' || round(ms) || ' ms' || E'\n';
  else r := r || 'FALLO C3 80000 etiquetas ' || round(ms) || ' ms: ' || left(v::text, 200) || E'\n'; fallos := fallos + 1; end if;
  t0 := clock_timestamp();
  v := public.plantilla_cuerpo_valida_semilla('<p>' || repeat('texto largo sin etiquetas &amp; ', 18000) || '</p>', null);
  ms := extract(epoch from clock_timestamp() - t0) * 1000; nprueba := nprueba + 1;
  if (v->>'ok')::boolean and ms < 3000 then r := r || 'OK    C4 570 KB de texto en ' || round(ms) || ' ms' || E'\n';
  else r := r || 'FALLO C4 texto largo ' || round(ms) || ' ms: ' || left(v::text, 200) || E'\n'; fallos := fallos + 1; end if;
  if dir is not null then
    t0 := clock_timestamp();
    txt := pg_read_file(dir || '/estatutos_sw.html');
    v := public.plantilla_cuerpo_valida_semilla(txt, null);
    ms := extract(epoch from clock_timestamp() - t0) * 1000; nprueba := nprueba + 1;
    if (v->>'ok')::boolean and ms < 3000 then r := r || 'OK    C5 estatutos_sw real (' || (octet_length(txt) / 1000) || ' KB) semilla en ' || round(ms) || ' ms' || E'\n';
    else r := r || 'FALLO C5 estatutos_sw ' || round(ms) || ' ms: ' || left(v::text, 200) || E'\n'; fallos := fallos + 1; end if;
    t0 := clock_timestamp();
    v := public.plantilla_cuerpo_valida(pg_temp.sin_notas(txt), txt);
    ms := extract(epoch from clock_timestamp() - t0) * 1000; nprueba := nprueba + 1;
    if (v->>'ok')::boolean and ms < 6000 then r := r || 'OK    C6 estatutos_sw real activando contra su esqueleto en ' || round(ms) || ' ms' || E'\n';
    else r := r || 'FALLO C6 estatutos_sw contra esqueleto ' || round(ms) || ' ms: ' || left(v::text, 200) || E'\n'; fallos := fallos + 1; end if;
  end if;

  -- ============================================================ PARTE D: permisos y pureza
  for hostil in select p.oid::regprocedure::text as f, p.provolatile, p.prosecdef, p.proconfig, p.proname
                from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['_plantilla_marcadores','_plantilla_campos_if','_plantilla_clases','_plantilla_texto','_plantilla_style_valido','_plantilla_analiza','_plantilla_valida','plantilla_cuerpo_valida','plantilla_cuerpo_valida_semilla']) loop
    nprueba := nprueba + 1;
    ok := not has_function_privilege('anon', hostil.f, 'execute') and not has_function_privilege('authenticated', hostil.f, 'execute') and not has_function_privilege('service_role', hostil.f, 'execute')
          and hostil.provolatile = 'i' and not hostil.prosecdef and coalesce(hostil.proconfig::text like '%search_path=%', false);
    if ok then r := r || 'OK    D ' || hostil.f || ' sin execute para anon/authenticated, IMMUTABLE, search_path fijo' || E'\n';
    else r := r || 'FALLO D ' || hostil.f || ' (permisos o pureza)' || E'\n'; fallos := fallos + 1; end if;
  end loop;
  nprueba := nprueba + 1;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['_plantilla_marcadores','_plantilla_campos_if','_plantilla_clases','_plantilla_texto','_plantilla_style_valido','_plantilla_analiza','_plantilla_valida','plantilla_cuerpo_valida','plantilla_cuerpo_valida_semilla'])) = 9 then
    r := r || E'OK    D las 9 funciones esperadas existen\n';
  else r := r || E'FALLO D no estan las 9 funciones\n'; fallos := fallos + 1; end if;

  raise exception E'\n%\nPRUEBAS=% OMITIDAS=% FALLOS=%', r, nprueba, omit, fallos;
end $t$;
