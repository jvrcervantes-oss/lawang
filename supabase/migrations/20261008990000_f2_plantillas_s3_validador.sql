-- erp-ok: Lawang independiente del maestro (owner 28-sep, AXW-68)
-- Plantillas de contrato por empresa · S3 (7-oct-2026): VALIDADOR EN SERVIDOR del cuerpo HTML de una plantilla.
--   Encargo: encargos/20261007_lawang_plantillas_por_empresa.md (S3 + revision previa de Seguridad). Es una pieza PURA: no lee ninguna tabla, no escribe nada,
--   no se aplica a ninguna fila. La usaran las RPC de S2 (guardar borrador y activar version; otro agente, migraciones 20261008980000..980400).
--   Llamador con nombre: las RPC de S2 `plantilla_guarda` / `plantilla_activa` (SECURITY DEFINER, bajo el rol postgres). Sin llamador desde el navegador:
--   NINGUN GRANT a anon ni authenticated (ni a PUBLIC); el navegador no valida nada, pide al backend (frontera front/back, 26-sep).
--
--   QUE HACE (por tokenizacion y comparacion con el esqueleto, no por regex sobre el documento):
--     1. Trocea el cuerpo por '<' y reconoce solo tres cosas: comentario, etiqueta con gramatica estricta (atributos siempre entre comillas dobles, sin '/' ni espacios raros)
--        y texto. Cualquier '<' que no sea una de las tres, o una etiqueta sin cerrar, es un error: no hay dos lecturas posibles del mismo texto (anti mutation-XSS).
--     2. Lista blanca de etiquetas (p br b strong i em u span sub sup ol ul li table thead tbody tfoot tr td th h1-h4 div + img/style solo los del esqueleto + el envoltorio
--        html head body title meta) y de atributos (data-lang es|en|id, class de lista fija, colspan/rowspan, data-campo, aria-hidden; y style SOLO si es el MISMO style, en el mismo tipo de
--        elemento y en el mismo orden que en el esqueleto, y ademas pasa una gramatica de CSS minima sin url()/expression/import: no se anade ni se mueve ninguno). Todo lo demas (script iframe object embed svg math link base form input button a,
--        on*=, javascript:, data: fuera de img...) falla por no estar en la lista, con el nombre concreto en el error.
--     3. Comentarios: solo los del motor (`if:campo=valor`, `opt:campo`, sus cierres, seccion-hitos, seccion-extras-construccion, hitos, extras-construccion, compradores-extra,
--        firmas-adquirientes, extra-clauses, datos-bancarios[-sin-titulo], cuenta:CLAVE). if/opt balanceados con disciplina de pila y SIN anidar el mismo campo (el motor de
--        buildDoc cierra en el primer cierre: anidar el mismo campo rompe el documento). Comentarios degenerados (`<!-->`, `--!>`) rechazados.
--     4. Marcadores {{x}}: solo `{{[a-z0-9_]+}}` con x en la lista cerrada (campos de contracts/tokens.json + los derivados del motor y los prom_* que pone applyPromotor);
--        llave suelta, `{{{x}}}`, `{{ x }}`, marcadores dentro de atributos (salvo `src="{{firma_adquiriente}}"` de la firma remota) = error. Tope de marcadores.
--     5. Entidades: lista blanca (&nbsp; &quot; &amp; &gt; &apos; &ldquo; &rdquo; &lsquo; &rsquo; &ndash; &mdash; &hellip; &laquo; &raquo; &middot; &euro; &#x27; &#39;); cualquier
--        otra, y en particular las que decodifican a '<' (&lt, &#60, &#x3c, con o sin ';') o a un caracter invisible/bidireccional (&#x202E;, &rlm;), se rechaza. Controles C0,
--        bidireccionales (Trojan Source, U+202A-202E, U+2066-2069, LRM/RLM), de ancho cero (U+200B-200D, U+2060), guion blando U+00AD y BOM, rechazados en crudo. Tope de tamano
--        (600000 bytes) y de etiquetas (80000).
--     6. Esqueleto: la version nueva debe tener los MISMOS bloques <style> (por md5), los MISMOS <img>, la MISMA secuencia de comentarios del motor y la MISMA estructura
--        de tablas/div/listas/titulos (con sus atributos), los MISMOS style en linea y la MISMA posicion de las clases doc-foot y doc-watermark (las que en el CSS ocultan o
--        desplazan texto) que la version de la que parte. Un admin de empresa que llame a la RPC a mano no puede cambiar nada
--        de eso: solo el texto de parrafos y celdas.
--     MODO SEMILLA (`plantilla_cuerpo_valida_semilla`): para cargar la v1 (copia EXACTA de los 20 ficheros de contracts/templates/). Acepta ademas las notas de autor (116 medidas en
--        los 20 ficheros con este mismo criterio; el inventario de S1 conto 119; se retiran al activar) y valida <style>/<img> por gramatica en vez de por comparacion (no hay esqueleto del que partir).
--   REQUISITOS PARA S2 Y S4 (el validador no los puede imponer solo; quedan escritos aqui y en el encargo):
--     a) El esqueleto lo busca la RPC EN EL SERVIDOR (cuerpo de la version de la que deriva: misma empresa, mismo slug); nunca se acepta de quien llama. Si lo mandara el navegador
--        la comparacion no probaria nada.
--     b) `plantilla_cuerpo_valida_semilla` solo la llama el cargador de la v1 (S4, con rol de servicio). Relaja <img>/<style> (los valida por gramatica, no por comparacion) y admite
--        notas de autor: ninguna RPC alcanzable por un usuario puede invocarla.
--     c) Quien busque texto de OTRA sociedad (bloqueo de activacion de S2) debe normalizar antes (NFKC, quitar ancho cero y guiones blandos, minusculas, espacios colapsados): este
--        validador rechaza esos caracteres, pero la busqueda no puede depender de ello.
--   LO QUE NO HACE (queda explicito): no valida el CONTENIDO juridico (decision 4 del owner, 7-oct); no detecta texto de otra sociedad (eso es el bloqueo de activacion de S2);
--   los mensajes de error repiten un fragmento del texto recibido: la pantalla debe pintarlos con textContent, nunca como HTML.
--   Cambiar la lista de marcadores o de clases exige una migracion nueva (a proposito: lo nuevo nace cerrado). Fuente de los marcadores: tokens.json (151) + 39 derivados.
-- destructivo-ok: solo crea 9 funciones puras; no toca tablas, filas ni policies
-- REVERTIR: supabase/reversion_f2/REVERSION_f2_plantillas_s3.sql

-- ======================================================================= listas cerradas
create or replace function public._plantilla_marcadores() returns text[]
language sql immutable parallel safe set search_path = ''
as $f$ select array[
    'contrato_num', 'nombre_contrato', 'firmante', 'clausulas_negociadas', 'poder_titular', 'poder_apoderado', 'finca_shm_nib', 'adq1_nombre',
    'adq1_nacionalidad', 'regimen_tenencia', 'adq1_pasaporte', 'adq1_telefono', 'adq1_email', 'adq1_forma_juridica', 'adq1_registro',
    'adq1_rep_nombre', 'adq1_rep_cargo', 'proyecto_nombre', 'resort', 'parcela_codigo', 'tipologia_villa', 'parcela_master', 'modalidad_pago',
    'moneda', 'tipo_cambio_idr', 'precio_m2', 'precio_total', 'precio_total_letras', 'descuento_comercial', 'descuento_comercial_motivo',
    'precio_reserva', 'precio_reserva_letras', 'plazo_meses', 'plazo_pago_final_dias', 'plazo_pago_final_meses', 'fecha_firma', 'precio_kit',
    'fecha_inicio_obras', 'villa_nombre', 'villa_m2', 'villa_terraza_m2', 'tipologia_construccion', 'ubicacion_proyecto', 'num_reserva_vinculada',
    'adenda_contrato', 'adenda_contrato_fecha', 'fecha_pago_reserva', 'validez_dias', 'validez_meses', 'acta_constitucion', 'sk_menkumham',
    'acta_rups', 'arrendador_nombre', 'arrendador_nacionalidad', 'arrendador_id', 'arrendador_domicilio', 'unidad_masterplan', 'masterplan_ref',
    'shm_numero', 'shm_titular', 'superficie_suelo_m2', 'ajb_estado', 'acceso_via_m', 'servicios_incluidos', 'plazo_sewa_anios', 'estructura_sewa',
    'inicio_sewa', 'precio_suelo', 'precio_construccion', 'precio_mobiliario', 'gracia_pago_dias', 'interes_demora_pct', 'plazo_liberacion_dias',
    'plazo_condiciones_meses', 'plazo_akta_meses', 'notario_ppat', 'fecha_entrega_estimada', 'pph_a_cargo', 'gastos_notariales_a_cargo',
    'garantia_estructural_anios', 'garantia_mep_meses', 'garantia_acabados_meses', 'gracia_obra_meses', 'penalizacion_mensual_pct',
    'resolucion_meses', 'compensacion_cancelacion_pct', 'plazo_devolucion_dias', 'cesion_tasa_pct', 'foro_arbitral', 'partner_nombre',
    'partner_domicilio', 'partner_representante', 'partner_comision_pct', 'partner_umbral_pct', 'colaborador_nombre', 'colaborador_domicilio',
    'colaborador_pasaporte', 'area_funcional', 'comision_detalle', 'tramo1_pct', 'tramo2_pct', 'hsn_dia_semana', 'hsn_dia', 'hsn_mes',
    'hsn_fecha_tabanan', 'hsn_apoderado_nombre', 'hsn_apoderado_edad', 'hsn_apoderado_ocupacion', 'hsn_apoderado_direccion', 'hsn_apoderado_nik',
    'hsn_poder_fecha', 'hsn_propietario_nombre', 'hsn_propietario_edad', 'hsn_propietario_ocupacion', 'hsn_propietario_direccion',
    'hsn_propietario_pasaporte', 'adq_apoderado_nombre', 'adq_apoderado_nik', 'adq_poder_fecha', 'hsn_nib', 'hsn_superficie_m2',
    'hsn_superficie_letras', 'hsn_village', 'hsn_distrito', 'hsn_regencia', 'hsn_precio_rp', 'hsn_precio_letras', 'hsn_anios', 'hsn_anios_letras',
    'hsn_anio_inicio', 'hsn_anio_fin', 'crh_ubicacion', 'crh_cert_matriz', 'crh_superficie_are_m2', 'crh_superficie_edificable', 'crh_zonificacion',
    'crh_plazo_hak_sewa', 'crh_precio_prorroga', 'crh_acceso', 'crh_edificabilidad_min', 'crh_penalidad_incumplimiento', 'crp_ubicacion',
    'crp_cert_matriz', 'crp_titular_registral', 'crp_superficie_total', 'crp_precio_m2', 'crp_zonificacion', 'crp_plazo_dias', 'crp_titular_cuenta',
    'crp_titulo_perceptor', 'crp_penalidad_incumplimiento',
    'adq1_domicilio', 'adq1_registro_num', 'adq2_firmante_nombre', 'c2_adq1_domicilio', 'c2_adq1_domicilio_id', 'c2_adq1_email', 'c2_adq1_pasaporte',
    'c2_adq1_telefono', 'c2_adq2_domicilio', 'c2_adq2_domicilio_id', 'c2_adq2_email', 'c2_adq2_pasaporte', 'c2_adq2_telefono', 'c2_rep_npwp',
    'carta_cobrado_importe', 'carta_cobrado_numeros', 'cc00014_ktp', 'comp_domicilio', 'comp_nib', 'comp_npwp', 'comp_razon', 'fecha_solicitud',
    'firma_adquiriente', 'jurisdiccion', 'precio_lista_construccion', 'precio_lista_suelo', 'prom_cred_en', 'prom_cred_es', 'prom_cred_id',
    'prom_domicilio', 'prom_ktp', 'prom_marca', 'prom_nib', 'prom_npwp', 'prom_razon', 'prom_rep', 'prom_rep_npwp', 'techo_nombre',
    'unidad_construccion_codigo'
]::text[] $f$;

create or replace function public._plantilla_campos_if() returns text[]
language sql immutable parallel safe set search_path = ''
as $f$ select public._plantilla_marcadores() || array[
    'adq1_tipo', 'adq_representacion', 'clausula_pago', 'cuenta_es_escrow', 'descuento_comercial_aplica', 'rev03_dni', 'rev03_hgb',
    'sociedad_firmante'
]::text[] $f$;

create or replace function public._plantilla_clases() returns text[]
language sql immutable parallel safe set search_path = ''
as $f$ select array[
    'adenda-ref', 'bold', 'cat', 'doc', 'doc-aviso', 'doc-date', 'doc-foot', 'doc-title', 'doc-watermark', 'f', 'f-lg', 'f-md', 'f-num6', 'f-sm', 'f-xs',
    'firmas', 'id-proyecto', 'kv', 'light', 'n', 'nota-hitos', 'party', 'pays', 'pct', 'role', 'sig-grid', 'sig-line', 'sigs', 'term'
]::text[] $f$;

-- ======================================================================= texto (y valores de atributo): marcadores, entidades, caracteres
-- p_attr = true: valor de atributo (no admite marcadores). Devuelve {"e": [errores], "m": n_marcadores}.
create or replace function public._plantilla_texto(p_txt text, p_attr boolean)
returns jsonb language plpgsql immutable parallel safe set search_path = ''
as $f$
declare
  e text[] := '{}'; m int := 0; mk text; r text;
begin
  if p_txt ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]' then e := e || 'caracter de control en el texto'::text; end if;
  if p_txt ~ '[\u202a-\u202e\u2066-\u2069\u200e\u200f\u061c\ufeff\u2028\u2029\u200b-\u200d\u2060\u00ad\u180e]' then
    e := e || 'caracter bidireccional o invisible (U+202A-202E, U+2066-2069, LRM/RLM, ancho cero U+200B-200D/2060, guion blando U+00AD, BOM, U+2028/9): puede hacer que el texto firmado no sea el que se lee'::text;
  end if;
  if p_txt ~ '[{}]' then
    if p_attr then
      e := e || ('llaves en un atributo: ' || left(p_txt, 60));
    else
      for mk in select (regexp_matches(p_txt, '\{\{([^{}]*)\}\}', 'g'))[1] loop
        m := m + 1;
        if mk !~ '^[a-z0-9_]+$' then
          e := e || ('marcador con forma no permitida {{' || left(mk, 40) || '}} (solo {{nombre_en_minusculas}}, sin espacios ni expresiones)');
        elsif not (mk = any (public._plantilla_marcadores())) then
          e := e || ('marcador desconocido {{' || mk || '}}: no esta en tokens.json ni en la lista de derivados del motor');
        end if;
      end loop;
      r := regexp_replace(p_txt, '\{\{[^{}]*\}\}', '', 'g');
      if r ~ '[{}]' then e := e || 'llave suelta o marcador mal cerrado ({{ sin }}, }} sin {{ o {{{x}}})'::text; end if;
    end if;
  end if;
  if position('&' in p_txt) > 0 then
    if p_txt ~* '&(lt|#0*60(?![0-9])|#x0*3c(?![0-9a-f]))' then
      e := e || 'entidad que decodifica a "<" (&lt, &#60, &#x3c): se usa para colar etiquetas'::text;
    end if;
    -- lista blanca de entidades (las que usan los 20 textos y las tipograficas habituales): una entidad numerica o con nombre fuera de la lista
    -- (&#x202E;, &rlm;, &#1;...) colaria por la puerta de atras los caracteres que arriba se rechazan en crudo
    r := regexp_replace(p_txt, '&(nbsp|quot|amp|gt|apos|ldquo|rdquo|lsquo|rsquo|ndash|mdash|hellip|laquo|raquo|middot|euro|#x27|#39);', '', 'g');
    if r ~ '&([^ \t\r\n]|$)' then e := e || ('entidad no permitida o "&" mal formado (solo &nbsp; &quot; &amp; &gt; &apos; &ldquo; &rdquo; &lsquo; &rsquo; &ndash; &mdash; &hellip; &laquo; &raquo; &middot; &euro; &#x27; &#39;): ' || left(substring(r from '&[^ \t\r\n&<]{0,20}'), 30)); end if;
  end if;
  return jsonb_build_object('e', to_jsonb(e), 'm', m);
end $f$;

-- ======================================================================= valor de un atributo style (gramatica de CSS minima)
create or replace function public._plantilla_style_valido(p_v text) returns text
language plpgsql immutable parallel safe set search_path = ''
as $f$
declare
  d text; prop text; val text;
  c_props constant text[] := array['margin','margin-top','margin-bottom','margin-left','margin-right','padding','padding-top','padding-bottom','padding-left',
    'padding-right','font-size','font-weight','font-style','color','text-align','height','max-height','min-height','max-width','width','display','align-items',
    'justify-content','border','border-top','border-bottom','border-left','border-right','clear','break-inside','break-before','break-after','page-break-inside',
    'page-break-before','page-break-after','line-height','vertical-align','text-transform','letter-spacing'];
begin
  if length(p_v) > 400 then return 'style demasiado largo'; end if;
  if p_v !~ '^[A-Za-z0-9 .,%#()_:;-]*$' then return 'style con caracteres no permitidos (solo letras, cifras y . , % # ( ) _ : ; -)'; end if;
  if p_v ~* 'url|expression|javascript|import|behavio|binding|image|attr\(|env\(|var\([^)]*var\(' then return 'style con url()/expression/import/imagen o var() anidado'; end if;
  foreach d in array string_to_array(p_v, ';') loop
    d := btrim(d, ' ');
    if d = '' then continue; end if;
    if d !~ '^[a-z-]+ *: *[^:]+$' then return 'declaracion de style mal formada: ' || left(d, 40); end if;
    prop := btrim(split_part(d, ':', 1), ' ');
    val := btrim(substr(d, strpos(d, ':') + 1), ' ');
    if not (prop = any (c_props)) then return 'propiedad CSS no permitida: ' || left(prop, 30); end if;
    if val = '' then return 'valor vacio en style: ' || prop; end if;
  end loop;
  return null;
end $f$;

-- ======================================================================= analisis: errores + firma estructural
create or replace function public._plantilla_analiza(p_cuerpo text, p_semilla boolean)
returns jsonb language plpgsql immutable parallel safe set search_path = ''
as $f$
declare
  c_max_bytes constant int := 600000;
  c_max_chunks constant int := 80000;
  c_max_marc constant int := 600;
  c_max_com constant int := 3000;
  c_max_err constant int := 40;
  c_max_prof constant int := 120;
  c_inline constant text[] := array['b','strong','i','em','u','span','sub','sup','li','p'];
  c_estruct constant text[] := array['html','head','body','title','meta','table','thead','tbody','tfoot','tr','td','th','div','ol','ul','h1','h2','h3','h4'];
  c_otras constant text[] := array['br'];
  c_vacias constant text[] := array['br','img','meta'];
  c_pin constant text[] := array['doc-foot','doc-watermark'];   -- clases que en el CSS de los textos ocultan o desplazan: no se pueden mover
  c_simple constant text[] := array['extra-clauses','firmas-adquirientes','compradores-extra','datos-bancarios','datos-bancarios-sin-titulo','hitos','extras-construccion'];
  errs text[] := '{}';
  chunks text[]; n int; i int; ch text; rest text; body text; p int; k int;
  in_style boolean := false; sbuf text := ''; in_com boolean := false; cbuf text := '';
  stack text[] := '{}'; cstack text[] := '{}';
  estilos text[] := '{}'; imgs text[] := '{}'; coms text[] := '{}'; estr text[] := '{}'; stys text[] := '{}'; pins text[] := '{}';
  n_marc int := 0; n_com int := 0; n_notas int := 0; marc_img boolean;
  closing boolean; selfc boolean; tname text; attrstr text; a record; anames text[]; av text; chk text; tok text; tj jsonb;
  s_src text; s_alt text; s_cls text; s_sty text; sig text; top text; cm text; campo text; sc text; tmp text;
begin
  if p_cuerpo is null or p_cuerpo = '' then
    return jsonb_build_object('errores', jsonb_build_array('el cuerpo esta vacio'), 'estilos','[]'::jsonb,'imgs','[]'::jsonb,'coms','[]'::jsonb,'estr','[]'::jsonb,'stys','[]'::jsonb,'pins','[]'::jsonb,'n_marc',0,'n_notas',0);
  end if;
  if octet_length(p_cuerpo) > c_max_bytes then
    return jsonb_build_object('errores', jsonb_build_array('cuerpo demasiado grande: ' || octet_length(p_cuerpo) || ' bytes (tope ' || c_max_bytes || ')'), 'estilos','[]'::jsonb,'imgs','[]'::jsonb,'coms','[]'::jsonb,'estr','[]'::jsonb,'stys','[]'::jsonb,'pins','[]'::jsonb,'n_marc',0,'n_notas',0);
  end if;
  chunks := string_to_array(p_cuerpo, '<');
  n := cardinality(chunks);
  if n > c_max_chunks then
    return jsonb_build_object('errores', jsonb_build_array('demasiadas etiquetas y comentarios: ' || (n - 1) || ' (tope ' || c_max_chunks || ')'), 'estilos','[]'::jsonb,'imgs','[]'::jsonb,'coms','[]'::jsonb,'estr','[]'::jsonb,'stys','[]'::jsonb,'pins','[]'::jsonb,'n_marc',0,'n_notas',0);
  end if;

  i := 0;
  while i < n loop
    i := i + 1;
    exit when cardinality(errs) >= c_max_err;
    ch := chunks[i];
    rest := null;

    if i = 1 then
      rest := ch;                                   -- texto inicial (antes del primer '<')

    elsif in_style then
      if ch ~* '^/style' then
        if ch !~* '^/style[ \t\r\n]*>' then errs := errs || ('cierre de style mal formado: </' || left(substr(ch, 2), 20)); end if;
        in_style := false;
        sbuf := replace(sbuf, E'\r\n', E'\n');
        if p_semilla then
          if sbuf ~* '@import|@font-face|@namespace|@charset|url[ \t\r\n]*\(|expression|javascript|behavio|binding|image-set|[\\]' then
            errs := errs || 'el bloque <style> usa @import/@font-face/url()/expression/escapes CSS: no permitido'::text;
          end if;
        end if;
        estilos := estilos || md5(sbuf);
        p := strpos(ch, '>');
        rest := case when p > 0 then substr(ch, p + 1) else '' end;
      else
        sbuf := sbuf || '<' || ch;
        continue;
      end if;

    elsif in_com then
      -- comentario que contiene '<' (solo admisible como nota de autor)
      p := strpos(ch, '-->');
      if p = 0 then
        cbuf := cbuf || '<' || ch;
        if length(cbuf) > 20000 then errs := errs || 'comentario sin cerrar o demasiado largo'::text; cbuf := ''; in_com := false; end if;
        continue;
      end if;
      cbuf := cbuf || '<' || left(ch, p - 1);
      rest := substr(ch, p + 3);
      in_com := false;
      if not p_semilla then
        errs := errs || ('comentario no permitido (los comentarios solo pueden ser los del motor): <!--' || left(cbuf, 50));
      elsif cbuf ~ '--!>' then errs := errs || 'comentario con --!> (cierre alternativo de HTML5)'::text;
      else n_notas := n_notas + 1;
      end if;
      cbuf := '';

    elsif left(ch, 3) = '!--' then
      tmp := substr(ch, 4);
      if tmp ~ '^(>|->)' then
        errs := errs || 'comentario degenerado (<!--> o <!--->): los navegadores lo cierran al instante'::text;
        rest := '';
      else
        p := strpos(tmp, '-->');
        if p = 0 then
          in_com := true; cbuf := tmp;
          continue;
        end if;
        cm := left(tmp, p - 1);
        rest := substr(tmp, p + 3);
        n_com := n_com + 1;
        if cm ~ '--!>' then
          errs := errs || 'comentario con --!> (cierre alternativo de HTML5)'::text;
        elsif cm ~ '^if:[a-z0-9_]+=[a-z0-9_]*$' then
          campo := split_part(substr(cm, 4), '=', 1);
          if not (campo = any (public._plantilla_campos_if())) then errs := errs || ('if sobre un campo desconocido: ' || campo); end if;
          if ('if:' || campo) = any (cstack) then errs := errs || ('<!--if:' || campo || '--> anidado dentro de otro if del mismo campo: el motor cierra en el primer cierre y rompe el documento'); end if;
          cstack := cstack || ('if:' || campo); coms := coms || cm;
        elsif cm ~ '^opt:[a-z0-9_]+$' then
          campo := substr(cm, 5);
          if not (campo = any (public._plantilla_campos_if())) then errs := errs || ('opt sobre un campo desconocido: ' || campo); end if;
          if ('opt:' || campo) = any (cstack) then errs := errs || ('<!--opt:' || campo || '--> anidado dentro de otro opt del mismo campo'); end if;
          cstack := cstack || ('opt:' || campo); coms := coms || cm;
        elsif cm ~ '^/(if|opt):[a-z0-9_]+$' then
          sc := substr(cm, 2);
          if cardinality(cstack) = 0 or cstack[cardinality(cstack)] <> sc then
            errs := errs || ('cierre <!--' || cm || '--> sin su apertura (o cruzado con otro bloque): if/opt deben cerrarse en orden inverso');
          else cstack := cstack[1:cardinality(cstack) - 1]; end if;
          coms := coms || cm;
        elsif cm in ('seccion-hitos','seccion-extras-construccion') then
          cstack := cstack || cm; coms := coms || cm;
        elsif cm in ('/seccion-hitos','/seccion-extras-construccion') then
          if cardinality(cstack) = 0 or cstack[cardinality(cstack)] <> substr(cm, 2) then
            errs := errs || ('cierre <!--' || cm || '--> sin su apertura');
          else cstack := cstack[1:cardinality(cstack) - 1]; end if;
          coms := coms || cm;
        elsif cm = any (c_simple) or cm ~ '^cuenta:[a-z0-9_]+$' then
          coms := coms || cm;
        elsif p_semilla then
          n_notas := n_notas + 1;                   -- nota de autor: solo en la carga v1
        else
          errs := errs || ('comentario no permitido (los comentarios solo pueden ser los del motor): <!--' || left(cm, 50) || '-->');
        end if;
        if n_com > c_max_com then errs := errs || 'demasiados comentarios'::text; exit; end if;
      end if;

    elsif left(ch, 1) = '!' then
      if ch ~* '^!doctype html[ \t\r\n]*>' then
        estr := estr || '!doctype'::text;
        rest := substr(ch, strpos(ch, '>') + 1);
      else
        errs := errs || ('declaracion no permitida: <' || left(ch, 30));
        rest := '';
      end if;

    elsif left(ch, 1) = '?' then
      errs := errs || ('instruccion de proceso no permitida: <' || left(ch, 30));
      rest := '';

    else
      p := strpos(ch, '>');
      if p = 0 then
        errs := errs || ('"<" sin cerrar o "<" suelto en el texto: <' || left(ch, 40));
        continue;
      end if;
      body := left(ch, p - 1);
      rest := substr(ch, p + 1);
      if length(body) > 1500 or body !~ '^/?[A-Za-z][A-Za-z0-9]*([ \t\r\n]+[A-Za-z][A-Za-z0-9-]*="[^"]*")*[ \t\r\n]*/?$' then
        errs := errs || ('etiqueta mal formada (atributos siempre entre comillas dobles, sin "/" interiores): <' || left(body, 60) || '>');
        rest := '';
      else
        closing := left(body, 1) = '/';
        selfc := right(body, 1) = '/';
        tname := lower((regexp_match(body, '^/?([A-Za-z][A-Za-z0-9]*)'))[1]);
        attrstr := substr(body, length(tname) + 1 + case when closing then 1 else 0 end);
        if selfc then attrstr := left(attrstr, length(attrstr) - 1); end if;

        if not (tname = any (c_inline) or tname = any (c_estruct) or tname = any (c_otras) or tname in ('img','style')) then
          errs := errs || (case when tname in ('script','iframe','object','embed','svg','math','link','base','form','input','button','a','frame','frameset','applet','audio','video','source','textarea','select','template','noscript','xmp','plaintext','noembed','canvas','slot','portal')
                                then 'etiqueta prohibida <' else 'etiqueta fuera de la lista blanca <' end || tname || '>');
        elsif closing then
          if attrstr ~ '[^ \t\r\n]' or selfc then errs := errs || ('cierre con atributos o con "/": </' || tname || '>'); end if;
          if tname = any (c_vacias) then errs := errs || ('cierre de etiqueta vacia: </' || tname || '>');
          elsif cardinality(stack) = 0 or stack[cardinality(stack)] <> tname then
            errs := errs || ('cierre </' || tname || '> sin su apertura (esperaba ' || coalesce('</' || nullif(stack[cardinality(stack)], '') || '>', 'ninguno') || ')');
          else
            stack := stack[1:cardinality(stack) - 1];
            if tname = any (c_estruct) then estr := estr || ('/' || tname); end if;
          end if;
        else
          -- apertura: atributos
          anames := '{}'; s_src := null; s_alt := null; s_cls := null; s_sty := null; sig := tname;
          for a in select (rm)[1] as an, (rm)[2] as av from regexp_matches(attrstr, '([A-Za-z][A-Za-z0-9-]*)="([^"]*)"', 'g') as rm loop
            tok := lower(a.an); av := a.av;
            if tok = any (anames) then errs := errs || ('atributo repetido en <' || tname || '>: ' || tok); continue; end if;
            anames := anames || tok;
            if tname = 'style' then
              errs := errs || ('<style> con atributos: ' || tok);
            elsif tok ~ '^on' then
              errs := errs || ('manejador de evento prohibido (' || tok || ') en <' || tname || '>');
            elsif tname = 'img' and tok = 'src' then
              s_src := av;
              if p_semilla and av <> '{{firma_adquiriente}}' and av !~ '^assets/brand/[a-z0-9._-]+\.png$' then
                errs := errs || ('<img src> fuera de assets/brand/*.png: ' || left(av, 60));
              end if;
            elsif tname = 'img' and tok = 'alt' then
              s_alt := av; tj := public._plantilla_texto(av, true);
              if jsonb_array_length(tj->'e') > 0 then errs := errs || ('alt de <img>: ' || (tj->'e'->>0)); end if;
            elsif tok = 'style' and tname in ('img','p','div','table','td','th','h2','h3','h4','h1','span','li','ul','ol','tr') then
              s_sty := av; chk := public._plantilla_style_valido(av);
              if chk is not null then errs := errs || ('style de <' || tname || '>: ' || chk); end if;
              if tname <> 'img' then stys := stys || (tname || '|' || av); end if;
            elsif tok = 'class' and tname not in ('html','head','body','title','meta','br') then
              s_cls := av;
              if av !~ '^[a-z0-9-]+( [a-z0-9-]+)*$' then errs := errs || ('class con forma no permitida: ' || left(av, 40));
              else
                foreach tok in array string_to_array(av, ' ') loop
                  if not (tok = any (public._plantilla_clases())) then errs := errs || ('class fuera de la lista fija: ' || tok); end if;
                  if tok = any (c_pin) then pins := pins || (tname || '|' || tok); end if;
                end loop;
                tok := 'class';
              end if;
            elsif tok = 'data-lang' and tname not in ('html','head','body','title','meta','br','img') then
              if av not in ('es','en','id') then errs := errs || ('data-lang debe ser es, en o id: ' || left(av, 20)); end if;
            elsif tok = 'data-campo' and tname not in ('html','head','body','title','meta','br','img') then
              if not (av = any (public._plantilla_marcadores())) then errs := errs || ('data-campo desconocido: ' || left(av, 40)); end if;
            elsif tok = 'aria-hidden' and tname in ('div','span','p') then
              if av <> 'true' then errs := errs || 'aria-hidden solo admite "true"'::text; end if;
            elsif tok in ('colspan','rowspan') and tname in ('td','th') then
              if av !~ '^[1-9][0-9]?$' then errs := errs || (tok || ' debe ser un numero de 1 a 99'); end if;
            elsif tok = 'lang' and tname = 'html' then
              if av not in ('es','en','id') then errs := errs || ('lang de <html> debe ser es, en o id: ' || left(av, 20)); end if;
            elsif tok = 'charset' and tname = 'meta' then
              if lower(av) <> 'utf-8' then errs := errs || 'meta charset solo admite utf-8'::text; end if;
            else
              errs := errs || ('atributo no permitido en <' || tname || '>: ' || left(tok, 30) || case when av ~* 'javascript:|data:|vbscript:|url\(|@import|expression' then ' (con contenido ejecutable)' else '' end);
            end if;
            if tname = any (c_estruct) and tok not in ('style') then
              sig := sig || '|' || tok || '=' || av;
            end if;
          end loop;

          if tname = 'img' then
            if s_src is null then errs := errs || '<img> sin src'::text; end if;
            imgs := imgs || ('src=' || coalesce(s_src, '') || '|alt=' || coalesce(s_alt, '') || '|class=' || coalesce(s_cls, '') || '|style=' || coalesce(s_sty, ''));
            if s_src = '{{firma_adquiriente}}' then n_marc := n_marc + 1; end if;
          elsif tname = 'style' then
            if selfc then errs := errs || '<style/> autocerrado'::text; else in_style := true; sbuf := rest; rest := ''; end if;
          elsif tname = any (c_vacias) then
            if tname = 'meta' then estr := estr || sig; end if;
          else
            if selfc then errs := errs || ('autocierre en etiqueta no vacia <' || tname || '/>: el navegador la trata como apertura');
            else
              if cardinality(stack) >= c_max_prof then errs := errs || 'anidamiento demasiado profundo'::text; exit; end if;
              stack := stack || tname;
              if tname = any (c_estruct) then
                -- los atributos de sig ya estan en el orden del fuente; se ordenan para que reordenar atributos no cambie la firma
                estr := estr || (select string_agg(x, '|' order by x) from unnest(string_to_array(sig, '|')) as x);
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;

    -- texto que sigue al elemento reconocido
    if rest is not null and rest <> '' and rest ~ '[&{}\x01-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069\u200e\u200f\u061c\ufeff\u2028\u2029\u200b-\u200d\u2060\u00ad\u180e]' then
      tj := public._plantilla_texto(rest, false);
      n_marc := n_marc + (tj->>'m')::int;
      for tmp in select jsonb_array_elements_text(tj->'e') loop errs := errs || tmp; end loop;
    end if;
  end loop;

  if cardinality(errs) < c_max_err then
    if in_style then errs := errs || 'bloque <style> sin cerrar'::text; end if;
    if in_com then errs := errs || 'comentario sin cerrar'::text; end if;
    if cardinality(stack) > 0 then errs := errs || ('etiqueta sin cerrar: <' || stack[cardinality(stack)] || '>'); end if;
    if cardinality(cstack) > 0 then errs := errs || ('bloque if/opt/seccion sin cerrar: ' || cstack[cardinality(cstack)] || ' (if/opt desbalanceados)'); end if;
    if n_marc > c_max_marc then errs := errs || ('demasiados marcadores: ' || n_marc || ' (tope ' || c_max_marc || ')'); end if;
  end if;

  return jsonb_build_object('errores', to_jsonb(errs[1:c_max_err]), 'estilos', to_jsonb(estilos), 'imgs', to_jsonb(imgs), 'coms', to_jsonb(coms),
                            'estr', to_jsonb(estr), 'stys', to_jsonb(stys), 'pins', to_jsonb(pins), 'n_marc', n_marc, 'n_notas', n_notas);
end $f$;

-- ======================================================================= validador (comparacion con el esqueleto)
create or replace function public._plantilla_valida(p_cuerpo text, p_esqueleto text, p_semilla boolean)
returns jsonb language plpgsql immutable parallel safe set search_path = ''
as $f$
declare
  a jsonb; b jsonb; errs text[] := '{}'; clave text; rotulo text; la jsonb; lb jsonb; j int; m int;
begin
  a := public._plantilla_analiza(p_cuerpo, p_semilla);
  errs := array(select jsonb_array_elements_text(a->'errores'));
  if p_esqueleto is null then
    if not p_semilla then errs := errs || 'falta el esqueleto: una version nueva siempre parte de otra (solo la carga v1 va sin esqueleto)'::text; end if;
  else
    b := public._plantilla_analiza(p_esqueleto, true);
    if jsonb_array_length(b->'errores') > 0 then
      errs := errs || ('el esqueleto no es analizable: ' || (b->'errores'->>0));
    elsif jsonb_array_length(a->'errores') = 0 then
      foreach clave in array array['estilos','imgs','coms','estr','stys','pins'] loop
        la := a->clave; lb := b->clave;
        if la <> lb then
          rotulo := case clave when 'estilos' then 'bloques <style> (por md5)' when 'imgs' then 'imagenes <img>' when 'coms' then 'comentarios del motor if/opt/marcadores'
                               when 'stys' then 'style en linea de cada elemento (los estilos no son editables ni se pueden anadir o mover)'
                               when 'pins' then 'posicion de las clases doc-foot y doc-watermark (ocultan o desplazan texto)'
                               else 'estructura de tablas, divisiones, listas y titulos' end;
          m := least(jsonb_array_length(la), jsonb_array_length(lb)); j := 0;
          while j < m and la->j = lb->j loop j := j + 1; end loop;
          errs := errs || ('el esqueleto cambia: ' || rotulo || ' difiere desde el elemento n.' || (j + 1) || ' (esperado ' || coalesce(left(lb->>j, 70), '<fin>')
                           || ', recibido ' || coalesce(left(la->>j, 70), '<fin>') || '; ' || jsonb_array_length(lb) || ' esperados, ' || jsonb_array_length(la) || ' recibidos)');
        end if;
      end loop;
    end if;
  end if;
  errs := errs[1:40];
  return jsonb_build_object('ok', cardinality(errs) = 0, 'errores', to_jsonb(errs), 'n_marcadores', (a->>'n_marc')::int, 'n_notas', (a->>'n_notas')::int);
end $f$;

-- ======================================================================= API
create or replace function public.plantilla_cuerpo_valida(p_cuerpo text, p_esqueleto text) returns jsonb
language sql immutable parallel safe set search_path = ''
as $f$ select public._plantilla_valida(p_cuerpo, p_esqueleto, false) $f$;

create or replace function public.plantilla_cuerpo_valida_semilla(p_cuerpo text, p_esqueleto text default null) returns jsonb
language sql immutable parallel safe set search_path = ''
as $f$ select public._plantilla_valida(p_cuerpo, p_esqueleto, true) $f$;

-- ======================================================================= permisos: ninguno para el navegador
revoke all on function public._plantilla_marcadores() from public, anon, authenticated;
revoke all on function public._plantilla_campos_if() from public, anon, authenticated;
revoke all on function public._plantilla_clases() from public, anon, authenticated;
revoke all on function public._plantilla_texto(text, boolean) from public, anon, authenticated;
revoke all on function public._plantilla_style_valido(text) from public, anon, authenticated;
revoke all on function public._plantilla_analiza(text, boolean) from public, anon, authenticated;
revoke all on function public._plantilla_valida(text, text, boolean) from public, anon, authenticated;
revoke all on function public.plantilla_cuerpo_valida(text, text) from public, anon, authenticated;
revoke all on function public.plantilla_cuerpo_valida_semilla(text, text) from public, anon, authenticated;
