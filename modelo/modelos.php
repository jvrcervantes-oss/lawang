<?php
/**
 * Catálogo de modelos de villa — fuente única de las landings /modelo/<id>.
 *
 * 2-sep-2026: **pivote a mercado australiano, catálogo completo (5 modelos)**. El owner dio
 * specs y precios reales de Dali/Dune/Dream/Trinity/Temple en la misma sesión (chat CEO,
 * confirmados explícitamente tras la pregunta de revisión de Administración sobre el patrón
 * de sobreprecio del techo Bambú — "son correctas, publica tal cual"). Sustituye la fase
 * "solo Dali" del 30-jul: aquella decisión era mantener el foco de la campaña de España en un
 * único modelo; el pivote a Australia la reabre a propósito, no por descuido.
 *
 * REGLAS DE ESTE FICHERO (no son estilo, son las que evitan publicar mentiras):
 *
 * 1. `techos` (Sirap/Bambú) llevan precio real dado por el owner, resuelto a "ahora" o
 *    "2027" por `lw_techo_precio_activo()` — nunca un flag manual ni el reloj del visitante.
 * 2. `acabados`/`alcance` (qué incluye/excluye la obra) solo se rellenan con lo verificado en
 *    el anexo de obra del modelo. Hoy solo existe el de Dali — extrapolarlo a otro modelo
 *    sería inventarse un contrato, así que los otros 4 se quedan sin esas dos claves (el
 *    template las oculta si faltan) hasta que llegue su propio anexo.
 * 3. Las imágenes NO se listan aquí: se leen de assets/img/buildings/<id>/web/.
 * 4. `renders_pendientes` es la ÚNICA forma de publicar un modelo sin imágenes — ver el
 *    porqué (decisión consciente del owner, no un descuido) en `lw_modelo_get()`, lib.php.
 *    Hoy: Trinity y Temple. Quitar el flag en cuanto lleguen sus renders reales.
 * 5. Solo inglés (pivote australiano, 2-sep): `lw_i18n($es, $en)` ya solo pinta `$en` — los
 *    campos `_es`/`sub` sin `_en` que queden de la fase anterior no se borran (viven en git,
 *    barato de recuperar si se retoma el bilingüe) pero no se traducen para los modelos
 *    nuevos: se escribe directamente en inglés.
 */

return [
    'dali' => [
        'nombre'      => 'Dali',
        'dormitorios' => 1,
        'banos'       => 1,
        'villa_m2'    => 30,
        'terraza_m2'  => 17,
        'sub'         => 'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'sub_en'      => 'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'techos'      => [
            'sirap' => [
                'nombre' => 'Sirap Ulin',
                'desc'   => 'Ulin wood shingle across the whole roof. The most weather-resistant, lowest-maintenance option.',
                'now'    => 48000,
                'y2027'  => 52000,
            ],
            'bambu' => [
                'nombre' => 'Bamboo & Ulin shingle',
                'desc'   => 'Bamboo structure combined with ulin wood shingle. Handcrafted character and greater durability.',
                'now'    => 50000,
                'y2027'  => 56000,
            ],
        ],
        // Los tres acabados verificados del anexo de obra de Dali. El tercero (Alang-alang)
        // no tiene precio propio dado por el owner en esta ronda — se queda fuera de
        // `techos` (que ahora es lo que fija el precio) pero la descripción sigue viva aquí
        // por si se retoma como opción sin recargo. No se copia a los otros 4 modelos.
        'acabados'    => [
            ['n' => 'Alang-alang', 'd' => 'Traditional Balinese thatch roofing. The look most integrated into the tropical setting.',
             'n_en' => 'Alang-alang', 'd_en' => 'Traditional Balinese thatch roofing. The look most integrated into the tropical setting.'],
        ],
        'alcance'     => [
            'incluido' => [
                'Main building per the project design',
                'Roof in the finish you choose',
                'Overflow pool in sukabumi stone',
                'Exterior terrace',
                'Air conditioning and hot water',
                'PLN 3,500W electrical connection',
                'Structure, architecture and installations',
            ],
            'incluido_en' => [
                'Main building per the project design',
                'Roof in the finish you choose',
                'Overflow pool in sukabumi stone',
                'Exterior terrace',
                'Air conditioning and hot water',
                'PLN 3,500W electrical connection',
                'Structure, architecture and installations',
            ],
            'no_incluido' => [
                'Interior furniture: beds, wardrobes, kitchen, tables',
                'Decor and textiles',
            ],
            'no_incluido_en' => [
                'Interior furniture: beds, wardrobes, kitchen, tables',
                'Decor and textiles',
            ],
        ],
    ],

    'dune' => [
        'nombre'      => 'Dune',
        'dormitorios' => 1,
        'banos'       => 1,
        'villa_m2'    => 47,
        'terraza_m2'  => 30,
        'sub'         => 'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'sub_en'      => 'A 1-bedroom en-suite villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'techos'      => [
            'sirap' => ['nombre' => 'Sirap', 'now' => 68000, 'y2027' => 72000],
            'bambu' => ['nombre' => 'Bamboo', 'now' => 70000, 'y2027' => 76000],
        ],
        // Sin acabados/alcance propios todavía: sin el anexo de obra de Dune, copiar el de
        // Dali sería inventarse un contrato (regla 2 de este fichero). El template oculta
        // esas secciones cuando faltan.
    ],

    'dream' => [
        'nombre'      => 'Dream',
        'dormitorios' => 2,
        'banos'       => 2,
        'villa_m2'    => 76,
        'terraza_m2'  => 49,
        'sub'         => 'A 2-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'sub_en'      => 'A 2-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'techos'      => [
            'sirap' => ['nombre' => 'Sirap', 'now' => 101000, 'y2027' => 109000],
            'bambu' => ['nombre' => 'Bamboo', 'now' => 106000, 'y2027' => 119000],
        ],
    ],

    'trinity' => [
        'nombre'             => 'Trinity',
        'dormitorios'        => 3,
        'banos'              => 2,
        'villa_m2'           => 92,
        'terraza_m2'         => 35,
        'sub'                => 'A 3-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'sub_en'             => 'A 3-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'techos'             => [
            'sirap' => ['nombre' => 'Sirap', 'now' => 121000, 'y2027' => 129000],
            'bambu' => ['nombre' => 'Bamboo', 'now' => 127000, 'y2027' => 139000],
        ],
        // 2-sep: publicado sin render real por decisión expresa del owner ("Publícalo,
        // estamos creándola y no estamos en producción aún") — el catálogo se lanza
        // completo mientras se terminan los renders, en vez de esperar a tenerlos los 5.
        // Quitar este flag en cuanto lleguen: hoy no hay ni un render de Trinity en el repo
        // (solo el PDF de folleto del contratista, que no es un asset publicable).
        'renders_pendientes' => true,
    ],

    'temple' => [
        'nombre'             => 'Temple',
        'dormitorios'        => 4,
        'banos'              => 3,
        'villa_m2'           => 114,
        'terraza_m2'         => 46,
        'sub'                => 'A 4-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'sub_en'             => 'A 4-bedroom villa, built on the plot you choose. Finish and budget locked in writing before you sign.',
        'techos'             => [
            'sirap' => ['nombre' => 'Sirap', 'now' => 146000, 'y2027' => 159000],
            'bambu' => ['nombre' => 'Bamboo', 'now' => 155000, 'y2027' => 169000],
        ],
        // Mismo caso que Trinity — ver su comentario. Hoy no hay ni un render de Temple en
        // el repo, solo el PDF de folleto.
        'renders_pendientes' => true,
    ],
];
